// Pre-push smoke test for the browser build.
//
// A love.js failure is near-silent: a shader that will not compile under
// WebGL, or a Lua error at boot, leaves a black canvas and nothing else. The
// itch.io page will happily serve that to everyone. So before pushing: load
// the real build in real Chrome and prove it draws.
//
// Two passes, because they exercise different shaders:
//   menu  -- moonshine chain (crt, scanlines, chromasep, glow)
//   game  -- light_world (stencil shadow passes, the unrolled blur) + decor
//            wind shader. This is where the WebGL-only failures live.
//
//   node web/smoke.js [--keep]     --keep leaves the screenshots in dist/
//
// Exits non-zero (and says why) if the build is broken.

const http = require('http');
const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer-core');

const ROOT = path.join(__dirname, '..', 'dist', 'web');
const PORT = 8127;
const OUT = path.join(__dirname, '..', 'dist');
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

// headless Chrome renders through SwiftShader on the CPU, so this game's
// multi-pass lighting runs at single-digit fps. Every wait here is generous
// on purpose; none of these numbers say anything about real performance.
const BOOT_WAIT = 8000;
const POLL_EVERY = 3000;
const POLL_LIMIT = 90000;
const LIT_FRACTION = 0.03; // of sampled pixels that must be non-black

const MIME = {
  '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm',
  '.data': 'application/octet-stream', '.css': 'text/css', '.ttf': 'font/ttf',
  '.png': 'image/png',
};

function serve() {
  const server = http.createServer((req, res) => {
    const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.html';
    const file = path.join(ROOT, rel);
    if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      res.writeHead(404); return res.end('not found');
    }
    const body = fs.readFileSync(file);
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(file)] || 'application/octet-stream',
      'Content-Length': body.length, // the loader's progress bar reads this
    });
    res.end(body);
  });
  return new Promise((ok) => server.listen(PORT, () => ok(server)));
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Read the canvas back. WebGL discards the drawing buffer after compositing,
// so index.html turns on preserveDrawingBuffer when ?smoke=1 is present.
const readCanvas = (page) => page.evaluate(() => {
  const c = document.getElementById('canvas');
  if (!c || !c.width) return { ok: false, why: 'no canvas element' };
  const off = document.createElement('canvas');
  off.width = c.width; off.height = c.height;
  const ctx = off.getContext('2d');
  ctx.drawImage(c, 0, 0);
  const d = ctx.getImageData(0, 0, c.width, c.height).data;
  let nonBlack = 0, sampled = 0;
  for (let i = 0; i < d.length; i += 4 * 97) { // sparse sample, ~13k px
    sampled++;
    if (d[i] > 12 || d[i + 1] > 12 || d[i + 2] > 12) nonBlack++;
  }
  return { ok: true, w: c.width, h: c.height, nonBlack, sampled, png: off.toDataURL('image/png') };
});

async function runPass(browser, pass, problems) {
  const say = (m) => console.log(`[${pass.name}] ${m}`);
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 960 });

  const flag = (m) => problems.push(`${pass.name}: ${m}`);
  page.on('pageerror', (e) => flag('page error: ' + e.message));
  page.on('requestfailed', (r) => flag('request failed: ' + r.url()));
  page.on('response', (r) => {
    // the favicon is Chrome asking on its own; an itch.io embed has none
    if (r.status() >= 400 && !r.url().endsWith('/favicon.ico')) {
      flag(`HTTP ${r.status()} ${r.url()}`);
    }
  });
  page.on('console', (m) => {
    const t = m.text();
    // "Failed to load resource" duplicates the response handler above
    if (m.type() === 'error' && !/Failed to load resource/.test(t)) flag('console: ' + t);
    // LOVE's error handler and Lua errors both surface as plain logs
    if (/Error:|attempt to |stack traceback|Syntax error|Does not exist/i.test(t)) {
      flag('lua: ' + t);
    }
    if (process.env.DEBUG) console.log(`  [${m.type()}] ${t}`);
  });

  say('loading');
  await page.goto(`http://localhost:${PORT}/?smoke=1${pass.query}`, { waitUntil: 'load', timeout: 60000 });

  // The loader hides itself and the canvas becomes visible once love.wasm AND
  // game.data are fully in -- there is no PLAY button any more, the runtime
  // boots on its own and unlocks audio at the first click.
  await page.waitForFunction(
    () => {
      const l = document.getElementById('loader');
      return l && getComputedStyle(l).display === 'none';
    },
    { timeout: 120000 });
  say('downloads complete, starting');
  await page.click('#canvas'); // stands in for a player's first gesture

  await sleep(BOOT_WAIT);
  if (pass.skipIntro) await page.click('#canvas'); // the studio card is mostly black

  const deadline = Date.now() + POLL_LIMIT;
  let lit = { ok: false, why: 'never rendered' };
  while (Date.now() < deadline) {
    await sleep(POLL_EVERY);
    lit = await readCanvas(page);
    if (process.env.DEBUG) say(lit.ok ? `poll ${lit.nonBlack}/${lit.sampled} lit` : lit.why);
    if (lit.ok && lit.nonBlack > lit.sampled * LIT_FRACTION) break;
  }

  const shot = path.join(OUT, `web-smoke-${pass.name}.png`);
  if (lit.png) fs.writeFileSync(shot, Buffer.from(lit.png.split(',')[1], 'base64'));
  say(`${lit.w}x${lit.h}, ${lit.nonBlack}/${lit.sampled} lit pixels`);

  if (!lit.ok) flag(lit.why);
  else if (lit.w !== 1280 || lit.h !== 960) flag(`canvas is ${lit.w}x${lit.h}, expected 1280x960`);
  else if (lit.nonBlack < lit.sampled * LIT_FRACTION) {
    flag(`canvas never drew anything (${lit.nonBlack}/${lit.sampled} lit pixels) -- ` +
         'usually a shader that will not compile under WebGL');
  }

  await page.close();
  return shot;
}

const PASSES = [
  { name: 'menu', query: '', skipIntro: true },
  // autotest drops straight into a run; shot9999 pushes its screenshot-and-quit
  // far enough out that it never fires while we are watching
  { name: 'game', query: '&args=' + encodeURIComponent('autotest,shot9999'), skipIntro: false },
// HEADFUL=1 opens a real window on the real GPU. Headless renders through
// SwiftShader on the CPU, which is fine for "does it run" but lies about how
// anything looks -- gradients band, and it is far too slow to judge fps.
// PASS=game runs just that one.
].filter((p) => !process.env.PASS || process.env.PASS === p.name);

(async () => {
  if (!fs.existsSync(path.join(ROOT, 'index.html'))) {
    console.error('no dist/web -- run ./build.sh web first');
    process.exit(1);
  }

  const server = await serve();
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: !process.env.HEADFUL,
    protocolTimeout: 180000, // a busy wasm main loop can stall CDP replies
    args: [
      '--no-sandbox',
      // headless has no GPU; SwiftShader gives it a real WebGL context, which
      // is the point -- the shader compiles have to actually happen
      '--enable-unsafe-swiftshader',
      '--use-gl=angle',
      '--window-size=1280,960',
      '--mute-audio',
    ],
  });

  const problems = [];
  const shots = [];
  try {
    for (const pass of PASSES) shots.push(await runPass(browser, pass, problems));
  } catch (e) {
    problems.push(e.message);
  } finally {
    await browser.close();
    server.close();
  }

  if (problems.length) {
    console.error('\nSMOKE TEST FAILED');
    problems.forEach((p) => console.error('  - ' + p));
    console.error('\nscreenshots: ' + shots.join(' '));
    process.exit(1);
  }
  console.log('\nsmoke test passed');
  if (process.argv.includes('--keep')) console.log('screenshots: ' + shots.join(' '));
  else shots.forEach((s) => fs.existsSync(s) && fs.unlinkSync(s));
  process.exit(0);
})();
