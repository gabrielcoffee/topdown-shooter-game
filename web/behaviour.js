// Browser behaviour checks for the web build.
//
// Two things the game depends on that no screenshot can show, and that broke
// silently before:
//
//   focus      -- entering or leaving fullscreen hands focus back to the
//                 document, and SDL only sees keys while the canvas has it.
//                 The game stayed alive but ignored WASD completely.
//   background -- a hidden tab gets zero requestAnimationFrame callbacks, so
//                 the run froze while its ambience kept playing. index.html
//                 drives the loop from a Web Worker timer while hidden.
//
// Needs a real window (headless has no meaningful visibility state), so it is
// not part of the pre-push smoke test:
//
//   node web/behaviour.js
//
// Exits non-zero (and says why) if either regressed.

const http = require('http');
const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer-core');

const ROOT = path.join(__dirname, '..', 'dist', 'web');
const PORT = 8129;
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const BOOT_WAIT = 6000;
const SAMPLE_VISIBLE = 2000;
const SAMPLE_HIDDEN = 3000;
// hidden is expected to run FASTER than visible (no vsync), so this only has
// to catch a total stall
const MIN_HIDDEN_RATIO = 0.2;

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
      'Content-Length': body.length,
    });
    res.end(body);
  });
  return new Promise((ok) => server.listen(PORT, () => ok(server)));
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const server = await serve();
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: false, // document.hidden is meaningless without a real window
    args: ['--window-size=1000,800'],
  });
  const fail = [];

  const page = await browser.newPage();

  // Counting real GL draws is the only honest way to tell whether LOVE's loop
  // is still turning -- love.timer's own fps counter is inside the wasm.
  await page.evaluateOnNewDocument(() => {
    window.__draws = 0;
    const proto = window.WebGLRenderingContext && WebGLRenderingContext.prototype;
    if (!proto) return;
    for (const m of ['drawArrays', 'drawElements']) {
      const orig = proto[m];
      proto[m] = function () { window.__draws++; return orig.apply(this, arguments); };
    }
  });

  await page.goto(`http://localhost:${PORT}/?args=autotest,shot99999`, { waitUntil: 'load' });
  await page.waitForFunction(
    () => {
      const l = document.getElementById('loader');
      return l && getComputedStyle(l).display === 'none';
    },
    { timeout: 120000 });
  await page.click('#canvas');
  await sleep(BOOT_WAIT);

  // ---- focus survives a fullscreen change ---------------------------------
  // Real fullscreen needs a user gesture Chrome will not synthesise, so fire
  // the event the handler listens for and see where focus lands.
  const focus = await page.evaluate(async () => {
    document.getElementById('canvas').blur();
    document.body.focus();
    const before = document.activeElement && document.activeElement.id;
    document.dispatchEvent(new Event('fullscreenchange'));
    await new Promise((r) => setTimeout(r, 400));
    return { before, after: document.activeElement && document.activeElement.id };
  });
  console.log(`focus: blurred to "${focus.before}", after fullscreenchange -> "${focus.after}"`);
  if (focus.after !== 'canvas') fail.push('canvas does not get focus back after a fullscreen change');

  // ---- the loop keeps running while hidden --------------------------------
  const visStart = await page.evaluate(() => window.__draws);
  await sleep(SAMPLE_VISIBLE);
  const visEnd = await page.evaluate(() => window.__draws);

  // a second foreground tab is what actually marks the first one hidden
  const other = await browser.newPage();
  await other.goto('about:blank');
  await other.bringToFront();
  await sleep(500);

  const isHidden = await page.evaluate(() => document.hidden);
  const hidStart = await page.evaluate(() => window.__draws);
  await sleep(SAMPLE_HIDDEN);
  const hidEnd = await page.evaluate(() => window.__draws);
  await page.bringToFront();

  const visRate = (visEnd - visStart) / (SAMPLE_VISIBLE / 1000);
  const hidRate = (hidEnd - hidStart) / (SAMPLE_HIDDEN / 1000);
  console.log(`draws/sec  visible: ${visRate.toFixed(0)}   hidden: ${hidRate.toFixed(0)}`);

  if (!isHidden) fail.push('could not get the page into a hidden state -- inconclusive');
  else if (hidRate < visRate * MIN_HIDDEN_RATIO) {
    fail.push(`loop stalls in a background tab (${hidRate.toFixed(0)} vs ${visRate.toFixed(0)} draws/sec)`);
  }

  await browser.close();
  server.close();

  if (fail.length) {
    console.log('\nBEHAVIOUR CHECKS FAILED');
    fail.forEach((f) => console.log('  - ' + f));
    process.exit(1);
  }
  console.log('\nbehaviour checks passed');
})();
