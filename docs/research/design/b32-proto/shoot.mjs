// B32 frames: mock.html views in headless Chrome. Phone widths go through an iframe (headless Chrome lays a page
// under ~500 px out wider, docs memory). node shoot.mjs <outDir> [port] [only,comma,list]
// Each shot: ?s=<view>&theme=<light|dark>&w=<width>. Then quantize: magick f.png -colors 256 PNG8:f.png
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, normalize, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = normalize(join(HERE, '..', '..', '..', '..'));
const out = process.argv[2] || join(HERE, '..', 'b32-frames');
const port = Number(process.argv[3] || 8991), dbg = port + 1;
const only = process.argv[4] ? process.argv[4].split(',') : null;
const SHOTS = [
  { s: 'board', w: 375, h: 812, theme: 'light' }, { s: 'board', w: 375, h: 812, theme: 'dark' },
  { s: 'page', w: 375, h: 812, theme: 'light' }, { s: 'page', w: 375, h: 812, theme: 'dark' },
  { s: 'cast', w: 375, h: 812, theme: 'light' }, { s: 'directions', w: 375, h: 812, theme: 'light' },
  { s: 'states', w: 375, h: 812, theme: 'light' },
  { s: 'ios', w: 390, h: 844, theme: 'light' }, { s: 'ios', w: 390, h: 844, theme: 'dark' },
  { s: 'ipad', w: 1180, h: 820, theme: 'light' },
  { s: 'mac', w: 1440, h: 900, theme: 'dark' },
  { s: 'android', w: 412, h: 915, theme: 'light' }, { s: 'android', w: 412, h: 915, theme: 'dark' },
  { s: 'mix', w: 1440, h: 420, theme: 'light' },
];
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.woff2': 'font/woff2', '.jpg': 'image/jpeg', '.png': 'image/png' };
const server = createServer(async (req, res) => {
  const u = new URL(req.url, 'http://x');
  if (u.pathname === '/frame') {
    const w = u.searchParams.get('w');
    res.writeHead(200, { 'content-type': 'text/html' });
    res.end(`<!doctype html><body style="margin:0"><iframe id="f" src="/docs/research/design/b32-proto/mock.html?${u.searchParams.get('q')}" style="width:${w}px;height:${u.searchParams.get('h') || 900}px;border:0;display:block"></iframe>`);
    return;
  }
  const p = normalize(join(ROOT, decodeURIComponent(u.pathname)));
  if (!p.startsWith(ROOT)) { res.writeHead(403); res.end(); return; }
  try { const b = await readFile(p); res.writeHead(200, { 'content-type': TYPES[extname(p)] || 'application/octet-stream' }); res.end(b); }
  catch { res.writeHead(404); res.end(); }
}).listen(port);
const profile = mkdtempSync(join(tmpdir(), 'b32-shoot-'));
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', ['--headless=new', '--disable-gpu', '--hide-scrollbars',
  '--mute-audio', `--remote-debugging-port=${dbg}`, `--user-data-dir=${profile}`, '--window-size=1500,1000', 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ok = 0;
try {
  let targets;
  for (let i = 0; i < 60 && !targets; i++) { try { targets = await (await fetch(`http://127.0.0.1:${dbg}/json`)).json(); } catch { await sleep(250); } }
  const ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener('open', r));
  let id = 0; const pending = new Map();
  ws.addEventListener('message', (e) => { const m = JSON.parse(e.data); if (pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } });
  const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
  const evalJS = async (expression) => (await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })).result.result?.value;
  await send('Page.enable');
  await mkdir(out, { recursive: true });
  for (const f of SHOTS.filter((x) => !only || only.includes(x.s) || only.includes(`${x.s}-${x.w}-${x.theme}`))) {
    const q = `s=${f.s}&theme=${f.theme}&w=${f.w}`;
    const narrow = f.w < 500;
    await send('Emulation.setDeviceMetricsOverride', { width: narrow ? 520 : f.w, height: f.h, deviceScaleFactor: 1, mobile: false });
    await send('Page.navigate', { url: narrow ? `http://127.0.0.1:${port}/frame?w=${f.w}&h=${f.h}&q=${encodeURIComponent(q)}` : `http://127.0.0.1:${port}/docs/research/design/b32-proto/mock.html?${q}` });
    await sleep(600);
    const doc = narrow ? "document.getElementById('f').contentDocument" : 'document';
    await evalJS(`${doc}.fonts.ready.then(() => 1)`);
    await sleep(250);
    const m = await evalJS(`(() => { const d = ${doc}; return { h: d.documentElement.scrollHeight, w: d.documentElement.scrollWidth }; })()`);
    if (m.w > f.w) console.log('OVERFLOW', f.s, f.w, m);
    const fixed = ['directions', 'board', 'page', 'ios', 'android', 'ipad', 'mac'].includes(f.s);
    const h = fixed ? f.h : f.s === 'mix' ? m.h : Math.max(f.h, m.h);
    if (narrow) await evalJS(`document.getElementById('f').style.height = '${h}px'; 1`);
    await send('Emulation.setDeviceMetricsOverride', { width: narrow ? 520 : f.w, height: h, deviceScaleFactor: 1, mobile: false });
    await sleep(150);
    const shot = await send('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: f.w, height: h, scale: 1 } });
    await writeFile(join(out, `${f.s}-${f.w}-${f.theme}.png`), Buffer.from(shot.result.data, 'base64'));
    ok++;
  }
} finally {
  chrome.kill(); server.close(); await sleep(300);
  try { rmSync(profile, { recursive: true, force: true }); } catch { /* Chrome still letting go */ }
  console.log(`shot ${ok}`);
}
process.exit(0);
