// Screenshots of a D2 direction: 375 px through an iframe (headless Chrome will
// not lay out narrower) and 1440 px direct. Serves the repository root on its
// own port so the fonts resolve; real waits, no virtual time.
// node shoot.mjs <repoRoot> <direction a|b|c> <outDir> <port> [screen ...] [--dark]
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, extname, normalize } from 'node:path';

const args = process.argv.slice(2);
const dark = args.includes('--dark');
const [root, dir, out, portArg, ...rest] = args.filter((a) => a !== '--dark');
const port = Number(portArg);
const SCREENS = ['home', 'browse', 'series-rich', 'series-sparse', 'episode-rich', 'episode-bare',
  'now-playing', 'create-pick', 'create-part', 'create-record', 'production'];
const names = rest.length ? rest : SCREENS;
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.png': 'image/png', '.svg': 'image/svg+xml' };
const base = `/docs/research/design/directions/${dir}/index.html`;

const server = createServer(async (req, res) => {
  const u = new URL(req.url, 'http://x');
  if (u.pathname === '/__frame') {
    res.writeHead(200, { 'content-type': 'text/html' });
    res.end(`<!doctype html><html><body style="margin:0;background:#888"><iframe id="f" src="${u.searchParams.get('u')}" style="width:375px;height:812px;border:0;display:block;background:#fff"></iframe></body></html>`);
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
  `--user-data-dir=${mkdtempSync(join(tmpdir(), 'd2-shoot-'))}`, '--window-size=1440,1000', 'about:blank'], { stdio: 'ignore' });
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
  const settle = async (docExpr) => {
    for (let i = 0; i < 40; i++) {
      const done = await evalJS(`(() => { const d = ${docExpr}; if (!d || d.readyState !== 'complete') return false; return [...d.images].every((im) => im.complete); })()`);
      if (done) break;
      await sleep(250);
    }
    await sleep(600);
  };
  await send('Page.enable');
  await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: dark ? 'dark' : 'light' }] });
  await mkdir(out, { recursive: true });
  const suffix = dark ? '-dark' : '';
  for (const name of names) {
    const url = `http://127.0.0.1:${port}${base}?s=${name}${dark ? '&theme=dark' : ''}`;
    // 375 px, through the iframe, full height up to 2400 px
    await send('Emulation.setDeviceMetricsOverride', { width: 420, height: 2400, deviceScaleFactor: 1, mobile: false });
    await send('Page.navigate', { url: `http://127.0.0.1:${port}/__frame?u=${encodeURIComponent(url)}` });
    await sleep(800);
    await settle(`document.getElementById('f') && document.getElementById('f').contentDocument`);
    const h = await evalJS(`(() => { const f = document.getElementById('f'); const d = f.contentDocument; const h = Math.min(2400, d.documentElement.scrollHeight); f.style.height = h + 'px'; return h; })()`);
    await sleep(500);
    let shot = await send('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: 375, height: h, scale: 1 } });
    await writeFile(join(out, `${name}-375${suffix}.png`), Buffer.from(shot.result.data, 'base64'));
    // 1440 px, direct, first 1100 px
    await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 1100, deviceScaleFactor: 1, mobile: false });
    await send('Page.navigate', { url });
    await sleep(800);
    await settle('document');
    shot = await send('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: 1440, height: 1100, scale: 1 } });
    await writeFile(join(out, `${name}-1440${suffix}.png`), Buffer.from(shot.result.data, 'base64'));
    ok++;
    console.log(name, 'ok', h);
  }
  ws.close();
} finally {
  chrome.kill('SIGTERM');
  server.close();
  console.log(`shot ${ok} of ${names.length}`);
}
