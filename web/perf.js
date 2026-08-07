// Measure real browser framerate for the web build.
//
// Runs the game's own `fpsprobe` mode (main.lua) in a real GPU browser window
// and collects the per-second FPS lines it prints. Headless is useless here --
// it renders on the CPU through SwiftShader and would report single digits no
// matter what the build does.
//
//   node web/perf.js [seconds]      default 40
//
// Prints min / median / mean and the slowest seconds, so a stutter that only
// shows up when a wave spawns is visible rather than averaged away.

const http = require('http');
const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer-core');

const ROOT = path.join(__dirname, '..', 'dist', 'web');
const PORT = 8128;
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const SECONDS = Number(process.argv[2]) || 40;

const MIME = {
  '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm',
  '.data': 'application/octet-stream', '.css': 'text/css', '.ttf': 'font/ttf',
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const server = http.createServer((req, res) => {
    const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.html';
    const file = path.join(ROOT, rel);
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); return res.end(); }
    const body = fs.readFileSync(file);
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream', 'Content-Length': body.length });
    res.end(body);
  });
  await new Promise((ok) => server.listen(PORT, ok));

  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: false, // must be a real GPU; see above
    protocolTimeout: 180000,
    args: ['--no-sandbox', '--window-size=1300,1000', '--mute-audio'],
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 960 });

  // LOVE's own love.graphics.getStats() reports zeros under love.js, so count
  // the WebGL calls directly. Injected before any page script runs, so it is
  // in place before love.js ever touches the context.
  await page.evaluateOnNewDocument(() => {
    window.__gl = { drawArrays: 0, drawElements: 0, bindFramebuffer: 0, clear: 0, useProgram: 0,
                    getError: 0, getParameter: 0, readPixels: 0, finish: 0, flush: 0,
                    checkFramebufferStatus: 0, frames: 0 };
    const proto = WebGLRenderingContext.prototype;
    ['drawArrays', 'drawElements', 'bindFramebuffer', 'clear', 'useProgram',
     'getError', 'getParameter', 'readPixels', 'finish', 'flush',
     'checkFramebufferStatus'].forEach((name) => {
      const orig = proto[name];
      proto[name] = function () { window.__gl[name]++; return orig.apply(this, arguments); };
    });
    const raf = window.requestAnimationFrame.bind(window);
    window.requestAnimationFrame = function (cb) {
      return raf(function (t) { window.__gl.frames++; return cb(t); });
    };
  });

  const samples = [];
  page.on('console', (m) => {
    const t = m.text();
    const fps = /FPS (\d+) frametime ([\d.]+)ms(?: draws (\d+) canvasswitches (\d+) shaderswitches (\d+))?/.exec(t);
    if (fps && process.env.DEBUG) console.log("RAW:", t);
    if (fps) samples.push({ fps: +fps[1], ms: +fps[2], draws: +fps[3] || 0, canvas: +fps[4] || 0, shaders: +fps[5] || 0 });
    if (/^PROBE /.test(t)) console.log(t);
    if (/Error:|attempt to /i.test(t)) console.log('LUA:', t);
  });

  const args = encodeURIComponent('autotest,shot9999,fpsprobe');
  await page.goto(`http://localhost:${PORT}/?args=${args}`, { waitUntil: 'load', timeout: 60000 });
  await page.waitForSelector('#play', { visible: true, timeout: 120000 });
  await page.click('#play');

  console.log(`measuring ${SECONDS}s...`);
  await sleep(3000);
  const before = await page.evaluate(() => ({ ...window.__gl }));
  await sleep((SECONDS - 3) * 1000);
  const after = await page.evaluate(() => ({ ...window.__gl }));

  const frames = after.frames - before.frames;
  const perFrame = (k) => (frames ? ((after[k] - before[k]) / frames).toFixed(1) : '?');
  console.log(`\nWebGL calls per frame (${frames} frames):`);
  console.log(`  draws ${(Number(perFrame('drawArrays')) + Number(perFrame('drawElements'))).toFixed(1)}` +
              `  framebuffer binds ${perFrame('bindFramebuffer')}` +
              `  clears ${perFrame('clear')}` +
              `  program switches ${perFrame('useProgram')}`);
  // these force the GPU to catch up with the CPU; even a handful per frame can
  // cost more than every draw call combined
  console.log(`  SYNC POINTS: getError ${perFrame('getError')}` +
              `  getParameter ${perFrame('getParameter')}` +
              `  checkFramebufferStatus ${perFrame('checkFramebufferStatus')}` +
              `  readPixels ${perFrame('readPixels')}` +
              `  finish ${perFrame('finish')}  flush ${perFrame('flush')}`);

  await browser.close();
  server.close();

  if (!samples.length) {
    console.error('no FPS samples -- did the run start?');
    process.exit(1);
  }
  // the first couple of seconds are shader compiles and asset decoding
  const warm = samples.slice(2);
  const fps = warm.map((s) => s.fps).sort((a, b) => a - b);
  const median = fps[Math.floor(fps.length / 2)];
  const mean = Math.round(fps.reduce((a, b) => a + b, 0) / fps.length);
  console.log(`\n${warm.length} samples (first 2s dropped as warm-up)`);
  console.log(`  min ${fps[0]}  median ${median}  mean ${mean}  max ${fps[fps.length - 1]}`);
  console.log(`  slowest seconds: ${fps.slice(0, 5).join(', ')}`);
  const last = warm[warm.length - 1];
  if (last && last.draws) {
    console.log(`  per frame: ${last.draws} draw calls, ${last.canvas} canvas switches, ${last.shaders} shader switches`);
  }
  process.exit(0);
})();
