// Direction D: the screenshots and the fit gate.
// node shoot.mjs <repoRoot> <outDir> <port> [--dark] [--fit] [--break] [screen ...]
// Shots: 375 px through an iframe (headless Chrome will not lay out narrower) and 1440 px direct.
// --fit lays every screen out at 320, 375, 390 and 430 px (iframes) and 1440 px and FAILS (exit 1) when
//   - the page scrolls sideways;
//   - a word breaks inside itself (one word's text spans two lines);
//   - text overflows its box (past its block's edge, or clipped by an ancestor);
//   - a row of buttons (.acts, .dock, .pb-actions, .done-act, .aids, .opts) wraps to a second line;
//   - a button's label wraps;
//   - a heading or display name ends on a stray word (its last line under a quarter of its widest).
// --break loads every screen with ?break=1, the negative control: every check must fire.
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, extname, normalize } from 'node:path';

const args = process.argv.slice(2);
const dark = args.includes('--dark'), fit = args.includes('--fit'), brk = args.includes('--break');
const [root, out, portArg, ...rest] = args.filter((a) => !a.startsWith('--'));
const port = Number(portArg);
const D = '/docs/research/design/directions/d/';
const SCREENS = [
  ['home', 'index.html'], ['browse', 'index.html'], ['series-rich', 'index.html'], ['series-sparse', 'index.html'],
  ['episode-rich', 'index.html'], ['episode-bare', 'index.html'], ['now-playing', 'index.html'], ['search', 'index.html'],
  ['stations', 'index.html'], ['library', 'index.html'], ['production', 'index.html'],
  ['pick', 'record.html'], ['part', 'record.html'], ['ready', 'record.html'], ['recording', 'record.html'],
  ['review', 'record.html'], ['done', 'record.html'], ['listen', 'record.html'],
];
const names = rest.length ? SCREENS.filter(([s]) => rest.includes(s)) : SCREENS;
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.png': 'image/png', '.svg': 'image/svg+xml' };

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
  const label = (el) => (el.tagName.toLowerCase() + (typeof el.className === 'string' && el.className ? '.' + el.className.trim().split(/\\s+/)[0] : '')) + ' "' + (el.textContent || '').trim().replace(/\\s+/g, ' ').slice(0, 32) + '"';
  const shown = (el) => { for (let x = el; x && x.nodeType === 1; x = x.parentElement) { const cs = win.getComputedStyle(x); if (cs.display === 'none' || cs.visibility === 'hidden') return false; if (x.tagName === 'DETAILS' && !x.open && x !== el && !el.closest('summary')) return false; } return el.getClientRects().length > 0; };
  if (d.documentElement.scrollWidth > W + 1) bad.push('page scrolls sideways: ' + d.documentElement.scrollWidth + ' > ' + W);
  const blockOf = (el) => { let x = el; while (x && win.getComputedStyle(x).display.startsWith('inline') && x.parentElement) x = x.parentElement; return x; };
  const clippers = (el) => { const out = []; for (let x = el; x && x !== d.body; x = x.parentElement) { const cs = win.getComputedStyle(x); if ((cs.overflowX !== 'visible' || cs.overflowY !== 'visible') && cs.textOverflow !== 'ellipsis') out.push(x); } return out; };
  const tw = d.createTreeWalker(d.body, NodeFilter.SHOW_TEXT);
  let t; const seen = new Set();
  while ((t = tw.nextNode())) {
    const el = t.parentElement;
    if (!el || !t.textContent.trim() || el.closest('svg, script, style, title') || !shown(el)) continue;
    const box = blockOf(el); const br = box.getBoundingClientRect();
    const L = br.left + box.clientLeft - 1, R = br.left + box.clientLeft + box.clientWidth + 1;
    const re = /\\S+/g; let m;
    while ((m = re.exec(t.textContent))) {
      const rg = d.createRange(); rg.setStart(t, m.index); rg.setEnd(t, m.index + m[0].length);
      const rs = [...rg.getClientRects()].filter((x) => x.width > 0.5);
      if (!rs.length) continue;
      const tops = new Set(rs.map((x) => Math.round(x.top / 3)));
      if (m[0].length > 1 && tops.size > 1) bad.push('word breaks: "' + m[0] + '" in ' + label(box));
      const key = box;
      for (const x of rs) {
        let why = null;
        if (x.right > R || x.left < L) why = 'past its box';
        else for (const c of clippers(el)) { const cr = c.getBoundingClientRect(); if (x.right > cr.right + 1 || x.left < cr.left - 1 || x.bottom > cr.bottom + 1) { why = 'clipped'; break; } }
        if (!why && (x.right > W + 1)) why = 'past the page';
        if (why && !seen.has(key)) { seen.add(key); bad.push('text overflows (' + why + '): ' + label(box)); }
      }
    }
  }
  for (const row of d.querySelectorAll('.acts, .dock, .pb-actions, .done-act, .aids, .opts')) {
    if (!shown(row) || win.getComputedStyle(row).flexDirection === 'column') continue;
    const r = [...row.children].filter(shown).map((c) => c.getBoundingClientRect()).filter((x) => x.height > 0);
    if (r.length > 1 && Math.max(...r.map((x) => x.top)) >= Math.min(...r.map((x) => x.bottom)) - 1) bad.push('button row wraps: ' + label(row));
    const rr = row.getBoundingClientRect();
    if (r.some((x) => x.right > rr.right + 1)) bad.push('button row overflows: ' + label(row));
  }
  for (const b of d.querySelectorAll('.btn, .seg a, .chip, .aid, .pill')) {
    if (!shown(b)) continue;
    const w2 = d.createTreeWalker(b, NodeFilter.SHOW_TEXT); const tops = new Set(); let x;
    while ((x = w2.nextNode())) { if (!x.textContent.trim()) continue; const rg = d.createRange(); rg.selectNodeContents(x); for (const r of rg.getClientRects()) if (r.width > 1) tops.add(Math.round(r.top / 3)); }
    if (tops.size > 1) bad.push('button label wraps: ' + label(b));
  }
  for (const h of d.querySelectorAll('h1, h2, h3, .board-name, .tile-name, .chip-board, .title, .part-name, .disp')) {
    if (!shown(h)) continue;
    const rg = d.createRange(); rg.selectNodeContents(h);
    const rs = [...rg.getClientRects()].filter((x) => x.width > 1 && x.height > 1).sort((a, b) => a.top - b.top);
    const lines = []; for (const x of rs) { const l = lines.find((y) => Math.abs(y.top - x.top) < x.height / 2); if (l) { l.l = Math.min(l.l, x.left); l.r = Math.max(l.r, x.right); } else lines.push({ top: x.top, l: x.left, r: x.right }); }
    const ws = lines.map((y) => y.r - y.l);
    if (ws.length > 1 && ws[ws.length - 1] < 0.25 * Math.max(...ws)) bad.push('stray last word: ' + label(h));
  }
  return [...new Set(bad)];
})()`;

const dbg = port + 1;
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
  '--headless=new', '--disable-gpu', '--hide-scrollbars', '--mute-audio', `--remote-debugging-port=${dbg}`,
  `--user-data-dir=${mkdtempSync(join(tmpdir(), 'd2b3-shoot-'))}`, '--window-size=1440,1000', 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ok = 0, failures = 0, failedScreens = 0;
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
  const evalJS = async (expr) => { const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true }); if (r.result.exceptionDetails) throw new Error(JSON.stringify(r.result.exceptionDetails).slice(0, 400)); return r.result.result.value; };
  const settle = async (docExpr) => {
    for (let i = 0; i < 60; i++) {
      const done = await evalJS(`(() => { const d = ${docExpr}; return !!d && d.readyState === 'complete' && d.fonts.status === 'loaded' && [...d.images].every((im) => im.complete); })()`);
      if (done) break;
      await sleep(250);
    }
    await sleep(400);
  };
  await send('Page.enable');
  await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: dark ? 'dark' : 'light' }] });
  await mkdir(out, { recursive: true });
  const suffix = dark ? '-dark' : '';
  const frame = async (url, w) => {
    await send('Emulation.setDeviceMetricsOverride', { width: w + 45, height: 2400, deviceScaleFactor: 1, mobile: false });
    await send('Page.navigate', { url: `http://127.0.0.1:${port}/__frame?w=${w}&u=${encodeURIComponent(url)}` });
    await sleep(700);
    await settle(`document.getElementById('f') && document.getElementById('f').contentDocument`);
    return evalJS(`(() => { const f = document.getElementById('f'); const d = f.contentDocument; const h = Math.max(812, Math.min(2400, d.documentElement.scrollHeight)); f.style.height = h + 'px'; return h; })()`);
  };
  for (const [name, file] of names) {
    const url = `http://127.0.0.1:${port}${D}${file}?s=${name}${dark ? '&theme=dark' : '&theme=light'}${brk ? '&break=1' : ''}`;
    if (fit) {
      let screenBad = 0;
      for (const w of [320, 375, 390, 430]) {
        await frame(url, w);
        await sleep(300);
        const bad = await evalJS(CHECK);
        if (bad.length) { screenBad += bad.length; console.log(`FIT ${name} ${w}${suffix}: ${bad.join(' | ')}`); }
      }
      await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 1100, deviceScaleFactor: 1, mobile: false });
      await send('Page.navigate', { url });
      await sleep(700);
      await settle('document');
      const bad = await evalJS(CHECK);
      if (bad.length) { screenBad += bad.length; console.log(`FIT ${name} 1440${suffix}: ${bad.join(' | ')}`); }
      failures += screenBad; if (screenBad) failedScreens++;
      ok++;
      continue;
    }
    const h = await frame(url, 375);
    await sleep(300);
    let shot = await send('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: 375, height: h, scale: 1 } });
    await writeFile(join(out, `${name}-375${suffix}.png`), Buffer.from(shot.result.data, 'base64'));
    await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false });
    await send('Page.navigate', { url });
    await sleep(700);
    await settle('document');
    const fullH = await evalJS('Math.max(1000, Math.min(1800, document.documentElement.scrollHeight))');
    await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: fullH, deviceScaleFactor: 1, mobile: false });
    await sleep(400);
    shot = await send('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width: 1440, height: fullH, scale: 1 } });
    await writeFile(join(out, `${name}-1440${suffix}.png`), Buffer.from(shot.result.data, 'base64'));
    ok++;
    console.log(name, 'ok', h, fullH);
  }
  ws.close();
} finally {
  chrome.kill('SIGTERM');
  server.close();
  console.log(fit ? `fit-checked ${ok} of ${names.length} screens${dark ? ' (dark)' : ''}: ${failures} problems on ${failedScreens} screens` : `shot ${ok} of ${names.length}`);
  if (fit && failures) process.exitCode = 1;
}
