// D2b-1 contact sheets: sheet.html at 375 px through an iframe (headless Chrome will not lay out
// narrower), light and dark, real waits. node shoot.mjs <repoRoot> <outDir> <port>
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, extname, normalize } from 'node:path';

const [root, out, portArg] = process.argv.slice(2);
const port = Number(portArg);
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2' };
const base = '/docs/research/design/d2b-1/sheet.html';
const SHOTS = [];
for (const view of ['tiles', 'wall']) for (const phase of ['before', 'after']) for (const theme of ['light', 'dark']) SHOTS.push({ view, phase, theme });
SHOTS.push({ view: 'tiles', phase: 'duotone', theme: 'light' });

const server = createServer(async (req, res) => {
  const u = new URL(req.url, 'http://x');
  if (u.pathname === '/__frame') {
    res.writeHead(200, { 'content-type': 'text/html' });
    res.end(`<!doctype html><html><body style="margin:0;background:#888"><iframe id="f" src="${u.searchParams.get('u')}" style="width:375px;height:812px;border:0;display:block"></iframe></body></html>`);
    return;
  }
  try {
    const p = normalize(join(root, decodeURIComponent(u.pathname)));
    if (!p.startsWith(normalize(root))) throw new Error('outside');
    const b = await readFile(p);
    res.writeHead(200, { 'content-type': TYPES[extname(p)] || 'application/octet-stream' });
    res.end(b);
  } catch { res.writeHead(404); res.end(); }
}).listen(port);

const dbg = port + 1;
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
  '--headless=new', '--disable-gpu', '--hide-scrollbars', '--mute-audio', `--remote-debugging-port=${dbg}`,
  `--user-data-dir=${mkdtempSync(join(tmpdir(), 'd2b1-shoot-'))}`, '--window-size=420,1000', 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ok = 0;
try {
  let targets;
  for (let i = 0; i < 60 && !targets; i++) {
    try { targets = await (await fetch(`http://127.0.0.1:${dbg}/json`)).json(); } catch { await sleep(250); }
  }
  const page = targets.find((t) => t.type === 'page');
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener('open', r));
  let id = 0; const pending = new Map();
  ws.addEventListener('message', (e) => { const m = JSON.parse(e.data); if (pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } });
  const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
  const evalJS = async (expr) => (await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true })).result.result.value;
  await send('Page.enable');
  await mkdir(out, { recursive: true });
  for (const s of SHOTS) {
    await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: s.theme }] });
    await send('Emulation.setDeviceMetricsOverride', { width: 420, height: 3000, deviceScaleFactor: 1, mobile: false });
    const url = `http://127.0.0.1:${port}${base}?view=${s.view}&phase=${s.phase}${s.theme === 'dark' ? '&theme=dark' : ''}`;
    await send('Page.navigate', { url: `http://127.0.0.1:${port}/__frame?u=${encodeURIComponent(url)}` });
    await sleep(800);
    let state;
    for (let i = 0; i < 120; i++) {
      state = await evalJS(`(() => { const d = document.getElementById('f') && document.getElementById('f').contentDocument; if (!d || d.readyState !== 'complete') return null; const im = [...d.images]; return { n: im.length, done: im.filter((x) => x.complete).length, broken: im.filter((x) => x.complete && !x.naturalWidth).length }; })()`);
      if (state && state.n && state.done === state.n) break;
      await sleep(500);
    }
    await sleep(800);
    const h = await evalJS(`(() => { const f = document.getElementById('f'); const h = f.contentDocument.documentElement.scrollHeight; f.style.height = h + 'px'; return h; })()`);
    await sleep(500);
    const shot = await send('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: 375, height: h, scale: 1 } });
    const name = `${s.view}-${s.phase}-375-${s.theme}.png`;
    await writeFile(join(out, name), Buffer.from(shot.result.data, 'base64'));
    console.log(name, h, JSON.stringify(state));
    ok++;
  }
} finally {
  chrome.kill();
  server.close();
  console.log(`shot ${ok} of ${SHOTS.length}`);
}
