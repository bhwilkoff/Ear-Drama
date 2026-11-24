// R4 frames: mock.html at 375 px (through an iframe: headless Chrome lays a page under ~500 px out wider)
// and at 1440 px, light and dark. node shoot.mjs <outDir> [port]; then quantize the PNGs (see R4).
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const out = process.argv[2] || join(HERE, 'frames');
const port = Number(process.argv[3] || 8971), dbg = port + 1;
const only = process.argv[4] ? process.argv[4].split(',') : null;
const PHONE = ['record', 'add', 'parts', 'line', 'episode', 'ear', 'earline', 'script', 'shared'];
const WIDE = ['record', 'add', 'parts', 'ear', 'script'];
const SHOTS = [];
for (const theme of ['light', 'dark']) {
  for (const s of PHONE) SHOTS.push({ s, w: 375, h: 812, theme });
  for (const s of WIDE) SHOTS.push({ s, w: 1440, h: 900, theme });
}
const server = createServer(async (req, res) => {
  const u = new URL(req.url, 'http://x');
  if (u.pathname === '/frame') {
    res.writeHead(200, { 'content-type': 'text/html' });
    res.end(`<!doctype html><body style="margin:0"><iframe id="f" src="/mock.html?${u.searchParams.get('q')}" style="width:375px;height:812px;border:0;display:block"></iframe>`);
    return;
  }
  if (u.pathname !== '/mock.html') { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
  res.end(await readFile(join(HERE, 'mock.html')));
}).listen(port);
const profile = mkdtempSync(join(tmpdir(), 'r4-shoot-'));
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
  const evalJS = async (expression) => (await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })).result.result.value;
  await send('Page.enable');
  await mkdir(out, { recursive: true });
  for (const f of SHOTS.filter((x) => !only || only.includes(x.s))) {
    const q = `s=${f.s}&theme=${f.theme}${f.w > 500 ? '&wide=1' : ''}`;
    await send('Emulation.setDeviceMetricsOverride', { width: f.w > 500 ? f.w : 520, height: f.h, deviceScaleFactor: 1, mobile: false });
    await send('Page.navigate', { url: f.w > 500 ? `http://127.0.0.1:${port}/mock.html?${q}` : `http://127.0.0.1:${port}/frame?q=${encodeURIComponent(q)}` });
    await sleep(500);
    const doc = f.w > 500 ? 'document' : "document.getElementById('f').contentDocument";
    await evalJS(`${doc}.fonts.ready.then(() => 1)`);
    await sleep(150);
    const m = await evalJS(`(() => { const d = ${doc}; return { h: d.documentElement.scrollHeight, w: d.documentElement.scrollWidth, over: [...d.querySelectorAll('.btn,.chip,.b,.c')].filter((e) => e.getBoundingClientRect().right > ${f.w} + 0.5).map((e) => e.textContent.trim()) }; })()`);
    if (m.w > f.w || m.over.length) console.log('OVERFLOW', f.s, f.w, m);
    const h = Math.max(f.h, m.h);
    if (f.w < 500) await evalJS(`document.getElementById('f').style.height = '${h}px'; 1`);
    await send('Emulation.setDeviceMetricsOverride', { width: f.w > 500 ? f.w : 520, height: h, deviceScaleFactor: 1, mobile: false });
    await sleep(120);
    const shot = await send('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: f.w, height: h, scale: 1 } });
    await writeFile(join(out, `${f.s}-${f.w}-${f.theme}.png`), Buffer.from(shot.result.data, 'base64'));
    ok++;
  }
} finally {
  chrome.kill(); server.close(); await sleep(300);
  try { rmSync(profile, { recursive: true, force: true }); } catch { /* Chrome still letting go of it */ }
  console.log(`shot ${ok}`);
}
process.exit(0);
