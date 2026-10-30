// Direction D: the screenshots and the fit gate.
// node shoot.mjs <repoRoot> <outDir> <port> [--dark] [--fit] [--break] [screen ...]
// Shots: 375 px through an iframe (headless Chrome will not lay out narrower) and 1440 px direct.
// --fit lays every screen out at 320, 375, 390 and 430 px (iframes) and 1440 px and FAILS (exit 1) when
//   - the page scrolls sideways;
//   - a word breaks inside itself (one word's text spans two lines);
//   - text overflows its box (past its block's edge, or clipped by an ancestor);
//   - a row of buttons (.acts, .dock, .pb-actions, .done-act, .aids, .opts) wraps to a second line;
//   - a button's label wraps;
//   - a heading or display name ends on a stray word (its last line under a quarter of its widest);
//   - (D2c-3) a card-edge stripe: one border side 3 px or more, or an offset inset shadow (Human Shaped D6);
//   - (D2c-3) a slot that jumps, goes missing or changes its window's size among the tiles or faces of one
//     grid row; a list row without its 48 px visual or under 64 px;
//   - (D2c-3) a slot jump between a rich and a bare variant of one skeleton (PAIRS below): every slot both
//     carry must keep its left, its width, its gap above (to the slot before it), and, for fixed slots, its
//     height. Run with --fit over all screens; pairs whose screens were not named are skipped.
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
  ['stations', 'index.html'], ['library', 'index.html'], ['production', 'index.html'], ['shelf', 'index.html'],
  ['invite', 'index.html'], ['invite-join', 'index.html'], ['dramas', 'index.html'], ['drama', 'index.html'],
  ['pick', 'record.html'], ['part', 'record.html'], ['preflight', 'record.html'], ['ready', 'record.html'],
  ['recording', 'record.html'], ['review', 'record.html'], ['run', 'record.html'], ['run-recording', 'record.html'],
  ['run-review', 'record.html'], ['lines', 'record.html'], ['lines-recording', 'record.html'], ['done', 'record.html'],
  ['listen', 'record.html'],
];
// The rich and bare variants of one skeleton, and the recorder's three modes.
const PAIRS = [['episode-rich', 'episode-bare'], ['series-rich', 'series-sparse'], ['production', 'invite'], ['production', 'drama'],
  ['ready', 'run'], ['ready', 'lines'], ['ready', 'run-review']];
const FIXED = new Set(['window', 'mark', 'acts', 'top', 'strip', 'mode']);
const SLOTS = `(() => {
  const d = document.getElementById('f') ? document.getElementById('f').contentDocument : document;
  const out = [];
  for (const s of d.querySelectorAll('[data-slot]')) {
    if (s.closest('.tiles, .wall, .rows, .bill, .tile, .face, .ed-mini, .cr, .guest, .lx-list') && !s.matches('.bill')) continue;
    if (!s.getClientRects().length) continue;
    const r = s.getBoundingClientRect();
    out.push({ slot: s.dataset.slot, left: r.left, width: r.width, top: r.top + d.defaultView.scrollY, height: r.height });
  }
  return out;
})()`;
function compare(a, b) {
  const bad = [];
  const gapAbove = (list, i) => {
    // The gap to the lowest slot above it that shares its columns: what it closes up to.
    const x = list[i];
    let floor = null;
    for (let j = i - 1; j >= 0; j--) {
      const y = list[j];
      if (y.left < x.left + x.width && x.left < y.left + y.width && y.top + y.height <= x.top + 1) floor = Math.max(floor ?? -Infinity, y.top + y.height);
    }
    return floor === null ? x.top : x.top - floor;
  };
  const by = (list) => new Map(list.map((x, i) => [x.slot, { ...x, gap: gapAbove(list, i) }]));
  const A = by(a), B = by(b);
  for (const [k, x] of A) {
    const y = B.get(k);
    if (!y) continue;
    const off = [];
    if (Math.abs(x.left - y.left) > 1.5) off.push('left');
    if (Math.abs(x.width - y.width) > 1.5) off.push('width');
    if (Math.abs(x.gap - y.gap) > 2) off.push(`gap above ${Math.round(x.gap)} vs ${Math.round(y.gap)}`);
    if (FIXED.has(k) && Math.abs(x.height - y.height) > 1.5) off.push(`height ${Math.round(x.height)} vs ${Math.round(y.height)}`);
    if (off.length) bad.push(`slot ${k}: ${off.join(', ')}`);
  }
  return bad;
}
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
    // A word is what lies between spaces and hyphens: "true-born" may turn its line at the hyphen.
    const re = /[^\\s\\-‐–]+/g; let m;
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
  for (const b of d.querySelectorAll('.btn, .seg a, .seg label, .chip, .aid, .pill')) {
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
  // A separator dot that opens a line ("· Roma Wines"): the owner's "poor word wrapping".
  const tw2 = d.createTreeWalker(d.body, NodeFilter.SHOW_TEXT); let t2;
  while ((t2 = tw2.nextNode())) {
    const el = t2.parentElement;
    if (!el || !shown(el) || el.closest('svg, script, style, title')) continue;
    const box = blockOf(el); const bl = box.getBoundingClientRect().left + box.clientLeft;
    for (let i = t2.textContent.indexOf('·'); i >= 0; i = t2.textContent.indexOf('·', i + 1)) {
      const rg = d.createRange(); rg.setStart(t2, i); rg.setEnd(t2, i + 1);
      const x = [...rg.getClientRects()].find((r) => r.width > 0.5);
      if (x && x.left - bl < 2) { bad.push('line opens on a separator: ' + label(box)); break; }
    }
  }
  // D2c-3: a card-edge stripe (one thick border, or an offset inset shadow) says a hue by decoration (Human Shaped D6).
  for (const el of d.querySelectorAll('body *')) {
    if (el.closest('svg') || !shown(el)) continue;
    const cs = win.getComputedStyle(el);
    const sides = ['Top', 'Right', 'Bottom', 'Left'].map((s) => ({ w: parseFloat(cs['border' + s + 'Width']) || 0, st: cs['border' + s + 'Style'] }));
    const thick = sides.filter((x) => x.w >= 3 && x.st !== 'none'), thin = sides.filter((x) => x.w < 1 || x.st === 'none');
    if (thick.length === 1 && thin.length === 3) { bad.push('card-edge stripe: ' + label(el)); continue; }
    if (cs.boxShadow && cs.boxShadow !== 'none') for (const part of cs.boxShadow.split(/,(?![^(]*\\))/)) {
      if (!/inset/.test(part)) continue;
      const [x, y, b] = (part.replace(/rgba?\\([^)]*\\)/, '').match(/-?[\\d.]+px/g) || []).map(parseFloat);
      if ((Math.abs(x) >= 3 || Math.abs(y) >= 3) && !b) { bad.push('card-edge stripe (shadow): ' + label(el)); break; }
    }
  }
  // D2c-3: objects in one grid row share their slots: every tile or face in a row has each slot, at one top,
  // and windows of one size (catalog-experience-design rule 11).
  for (const g of d.querySelectorAll('.tiles, .wall')) {
    if (!shown(g)) continue;
    const rows = new Map();
    for (const t of g.children) { if (!shown(t)) continue; const k = Math.round(t.getBoundingClientRect().top); if (!rows.has(k)) rows.set(k, []); rows.get(k).push(t); }
    for (const ts of rows.values()) {
      const names = new Set(); ts.forEach((t) => t.querySelectorAll(':scope > [data-slot]').forEach((s) => names.add(s.dataset.slot)));
      for (const nm of names) {
        const rs = ts.map((t) => t.querySelector(':scope > [data-slot="' + nm + '"]')).map((s) => (s && shown(s) ? s.getBoundingClientRect() : null));
        if (rs.some((x) => !x)) { bad.push('a slot missing in a row: ' + nm + ' in ' + label(g)); continue; }
        if (Math.max(...rs.map((x) => x.top)) - Math.min(...rs.map((x) => x.top)) > 1.5) bad.push('a slot jumps in a row: ' + nm + ' in ' + label(g));
        if (nm === 'window' && Math.max(...rs.map((x) => x.height)) - Math.min(...rs.map((x) => x.height)) > 1.5) bad.push('windows differ in a row: ' + label(g));
      }
    }
  }
  // Every list row keeps its 48 px visual and its 64 px height, whatever it carries.
  for (const r of d.querySelectorAll('.rows > li > .row')) {
    if (!shown(r)) continue;
    const v = r.querySelector(':scope > [data-slot="visual"]');
    const vr = v && shown(v) ? v.getBoundingClientRect() : null;
    if (!vr || Math.abs(vr.width - 48) > 1 || Math.abs(vr.height - 48) > 1) bad.push('a row without its 48 px visual: ' + label(r));
    if (r.getBoundingClientRect().height < 63.5) bad.push('a row under 64 px: ' + label(r));
  }
  // One Share per screen: the owner saw a second one fall onto its own line.
  const shares = [...d.querySelectorAll('[aria-label="Share"]')].filter(shown);
  if (shares.length > 1) bad.push(shares.length + ' Share controls on one screen');
  return [...new Set(bad)];
})()`;

const dbg = port + 1;
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
  '--headless=new', '--disable-gpu', '--hide-scrollbars', '--mute-audio', `--remote-debugging-port=${dbg}`,
  `--user-data-dir=${mkdtempSync(join(tmpdir(), 'd2b3-shoot-'))}`, '--window-size=1440,1000', 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ok = 0, failures = 0, failedScreens = 0, pairsChecked = 0;
const slotsOf = {};
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
        (slotsOf[name] = slotsOf[name] || {})[w] = await evalJS(SLOTS);
      }
      await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 1100, deviceScaleFactor: 1, mobile: false });
      await send('Page.navigate', { url });
      await sleep(700);
      await settle('document');
      const bad = await evalJS(CHECK);
      if (bad.length) { screenBad += bad.length; console.log(`FIT ${name} 1440${suffix}: ${bad.join(' | ')}`); }
      (slotsOf[name] = slotsOf[name] || {})[1440] = await evalJS(SLOTS);
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
  if (fit) for (const [a, b] of PAIRS) {
    if (!slotsOf[a] || !slotsOf[b]) continue;
    pairsChecked++;
    for (const w of [320, 375, 390, 430, 1440]) {
      const bad = compare(slotsOf[a][w], slotsOf[b][w]);
      if (bad.length) { failures += bad.length; console.log(`SLOTS ${a} vs ${b} ${w}${suffix}: ${bad.join(' | ')}`); }
    }
  }
  ws.close();
} finally {
  chrome.kill('SIGTERM');
  server.close();
  console.log(fit ? `fit-checked ${ok} of ${names.length} screens${dark ? ' (dark)' : ''}: ${failures} problems on ${failedScreens} screens; ${pairsChecked} rich and bare pairs compared` : `shot ${ok} of ${names.length}`);
  if (fit && failures) process.exitCode = 1;
}
