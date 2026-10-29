// Screenshots and the fit check for the D2b-2 prototype.
// node shoot.mjs <repoRoot> <outDir> <port> [--dark] [--fit] [screen ...]
// Shots: 375 px through an iframe (headless Chrome will not lay out narrower) and
// 1440 px direct. --fit lays every screen out at 320, 375, 390 and 430 px and
// fails on a page that scrolls sideways, a box whose text overflows it (a word
// that would have to break inside itself), a control row whose items stack, a
// button whose label wraps, or a heading whose last line is a stray word.
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, extname, normalize } from 'node:path';

const args = process.argv.slice(2);
const dark = args.includes('--dark');
const fit = args.includes('--fit');
const [root, out, portArg, ...rest] = args.filter((a) => !a.startsWith('--'));
const port = Number(portArg);
const SCREENS = ['pick', 'part', 'preflight', 'denied', 'roomtone', 'ready', 'cue', 'recording', 'review', 'flagged', 'interrupted', 'done', 'listen'];
const names = rest.length ? rest : SCREENS;
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.png': 'image/png', '.svg': 'image/svg+xml' };
const base = '/docs/research/design/directions/record/index.html';

const server = createServer(async (req, res) => {
  const u = new URL(req.url, 'http://x');
  if (u.pathname === '/__frame') {
    const w = Number(u.searchParams.get('w') || 375);
    res.writeHead(200, { 'content-type': 'text/html' });
    res.end(`<!doctype html><html><body style="margin:0;background:#888"><iframe id="f" src="${u.searchParams.get('u')}" style="width:${w}px;height:812px;border:0;display:block;background:#fff"></iframe></body></html>`);
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

const CHECK = `(() => {
  const d = document.getElementById('f') ? document.getElementById('f').contentDocument : document;
  const win = d.defaultView;
  const W = d.documentElement.clientWidth;
  const bad = [];
  const name = (el) => (el.className && typeof el.className === 'string' ? el.tagName.toLowerCase() + '.' + el.className.split(' ')[0] : el.tagName.toLowerCase()) + ' "' + (el.textContent || '').trim().slice(0, 30) + '"';
  const shown = (el) => { const cs = win.getComputedStyle(el); return cs.display !== 'none' && cs.visibility !== 'hidden' && el.getClientRects().length; };
  if (d.documentElement.scrollWidth > W + 1) bad.push('page scrolls sideways: ' + d.documentElement.scrollWidth + ' > ' + W);
  for (const el of d.querySelectorAll('body *')) {
    if (el.closest('svg') || !shown(el)) continue;
    const cs = win.getComputedStyle(el);
    if (cs.display === 'inline' || el.classList.contains('opp') || el.classList.contains('lt-cast') || el.classList.contains('print-bar') || el.closest('.wave') || el.closest('.meter') || el.classList.contains('face')) continue;
    if (el.clientWidth > 0 && el.scrollWidth > el.clientWidth + 1 && (cs.textOverflow !== 'ellipsis')) bad.push('overflows: ' + name(el) + ' ' + el.scrollWidth + '>' + el.clientWidth);
  }
  for (const row of d.querySelectorAll('.dock, .pb-actions, .done-act, .aids, .facts, .pb-as, .next-part, .rec-top, .pk-head, .pk-sec, .cont .row')) {
    if (!shown(row) || win.getComputedStyle(row).flexDirection === 'column') continue;
    const r = [...row.children].filter(shown).map((c) => c.getBoundingClientRect()).filter((x) => x.height > 0);
    if (r.length > 1 && Math.max(...r.map((x) => x.top)) >= Math.min(...r.map((x) => x.bottom))) bad.push('row stacks: ' + name(row));
  }
  for (const b of d.querySelectorAll('.btn, .aid, .pill, .check')) {
    if (!shown(b)) continue;
    const tw = d.createTreeWalker(b, 4); const tops = new Set(); let n;
    while ((n = tw.nextNode())) { if (!n.textContent.trim()) continue; const rg = d.createRange(); rg.selectNodeContents(n); for (const x of rg.getClientRects()) if (x.width > 1) tops.add(Math.round(x.top)); }
    if (tops.size > 1 || b.getBoundingClientRect().height > 64) bad.push('button wraps: ' + name(b));
  }
  for (const h of d.querySelectorAll('h1, h2, .disp, .nm, .part-name, .title, .l6, .by, .st, .who, .lab')) {
    if (!shown(h)) continue;
    const rg = d.createRange(); rg.selectNodeContents(h);
    const rs = [...rg.getClientRects()].filter((x) => x.width > 1 && x.height > 1).sort((x, y) => x.top - y.top);
    const byTop = new Map(); let cur = null;
    for (const x of rs) { if (!cur || x.top >= cur.b - 2) { cur = { l: x.left, r: x.right, b: x.bottom }; byTop.set(byTop.size, cur); } else { cur.l = Math.min(cur.l, x.left); cur.r = Math.max(cur.r, x.right); cur.b = Math.max(cur.b, x.bottom); } }
    const ws = [...byTop.values()].map((e) => e.r - e.l);
    if (ws.length > 1 && ws[ws.length - 1] < 0.25 * Math.max(...ws)) bad.push('stray last word: ' + name(h));
  }
  return bad;
})()`;

const dbg = port + 1;
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
  '--headless=new', '--disable-gpu', '--hide-scrollbars', '--mute-audio', `--remote-debugging-port=${dbg}`,
  `--user-data-dir=${mkdtempSync(join(tmpdir(), 'd2b2-shoot-'))}`, '--window-size=1440,1000', 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ok = 0; let failures = 0;
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
      const done = await evalJS(`(() => { const d = ${docExpr}; return !!d && d.readyState === 'complete' && d.fonts.status === 'loaded'; })()`);
      if (done) break;
      await sleep(250);
    }
    await sleep(400);
  };
  await send('Page.enable');
  await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: dark ? 'dark' : 'light' }] });
  await mkdir(out, { recursive: true });
  const suffix = dark ? '-dark' : '';
  const frame = async (url, w, h = 2400) => {
    await send('Emulation.setDeviceMetricsOverride', { width: w + 45, height: h, deviceScaleFactor: 1, mobile: false });
    await send('Page.navigate', { url: `http://127.0.0.1:${port}/__frame?w=${w}&u=${encodeURIComponent(url)}` });
    await sleep(600);
    await settle(`document.getElementById('f') && document.getElementById('f').contentDocument`);
    return evalJS(`(() => { const f = document.getElementById('f'); const d = f.contentDocument; const h = Math.max(812, Math.min(2400, d.documentElement.scrollHeight)); f.style.height = h + 'px'; return h; })()`);
  };
  for (const name of names) {
    const url = `http://127.0.0.1:${port}${base}?s=${name}${dark ? '&theme=dark' : ''}${args.includes('--break') ? '&break=1' : ''}`;
    if (fit) {
      for (const w of [320, 375, 390, 430]) {
        await frame(url, w);
        await sleep(300);
        const bad = await evalJS(CHECK);
        if (bad.length) { failures += bad.length; console.log(`FIT ${name} ${w}: ${bad.join(' | ')}`); }
        if (w === 320) {
          const h = await evalJS(`document.getElementById('f').offsetHeight`);
          const shot = await send('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: 320, height: h, scale: 1 } });
          await writeFile(join(out, `${name}-320${suffix}.png`), Buffer.from(shot.result.data, 'base64'));
        }
      }
      await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 1100, deviceScaleFactor: 1, mobile: false });
      await send('Page.navigate', { url });
      await sleep(600);
      await settle('document');
      const bad = await evalJS(CHECK);
      if (bad.length) { failures += bad.length; console.log(`FIT ${name} 1440: ${bad.join(' | ')}`); }
      ok++;
      continue;
    }
    const h = await frame(url, 375);
    await sleep(300);
    let shot = await send('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: 375, height: h, scale: 1 } });
    await writeFile(join(out, `${name}-375${suffix}.png`), Buffer.from(shot.result.data, 'base64'));
    await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false });
    await send('Page.navigate', { url });
    await sleep(600);
    await settle('document');
    const fullH = await evalJS('Math.max(1000, Math.min(2000, document.documentElement.scrollHeight))');
    await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: fullH, deviceScaleFactor: 1, mobile: false });
    await sleep(300);
    shot = await send('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: 1440, height: fullH, scale: 1 } });
    await writeFile(join(out, `${name}-1440${suffix}.png`), Buffer.from(shot.result.data, 'base64'));
    ok++;
    console.log(name, 'ok', h, fullH);
  }
  ws.close();
} finally {
  chrome.kill('SIGTERM');
  server.close();
  console.log(`${fit ? 'fit-checked' : 'shot'} ${ok} of ${names.length}${fit ? `; ${failures} problems` : ''}`);
}
