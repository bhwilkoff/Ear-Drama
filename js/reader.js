/**
 * The script reader (WEB-DESIGN §4.16, PLAYS-DESIGN §2.7; Decision 076 S1): any castable play,
 * read in pages (the default; a slide, two facing pages when wide) or in one scroll, with its
 * contents by act and scene, search, text settings, and "I'm playing" (highlight my lines, my
 * next line, hide them to rehearse). The read-along and the studio will use this same view:
 * go(lineID) and follow(lineID) are the read-along's seam, and the dock under the page is the
 * studio's.
 *
 * Every word drawn is the script's (§9 rule 9). A page is never stored: the position is a line
 * id (ReaderCore), and a page is wherever that line falls in this layout.
 */
const Reader = (() => {
  'use strict';
  const C = PlaysCore;
  const R = ReaderCore;
  const PREFS_KEY = 'ed.reader.prefs';
  const POS_KEY = 'ed.reader.pos';
  const GAP = 48;

  const ICON = {
    back: 'M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z',
    contents: 'M3 9h14V7H3v2zm0 4h14v-2H3v2zm0 4h14v-2H3v2zm16 0h2v-2h-2v2zm0-10v2h2V7h-2zm0 6h2v-2h-2v2z',
    search: 'M10 3a7 7 0 0 1 5.6 11.2l5.1 5.1-1.4 1.4-5.1-5.1A7 7 0 1 1 10 3zm0 2a5 5 0 1 0 0 10 5 5 0 0 0 0-10z',
    text: 'M9 4v3h5v12h3V7h5V4H9zm-6 8h3v7h3v-7h3V9H3v3z',
    next: 'M20 12l-1.41-1.41L13 16.17V4h-2v12.17l-5.58-5.59L4 12l8 8 8-8z',
    hide: 'M12 7a5 5 0 0 1 4.64 6.83l2.92 2.92A11.8 11.8 0 0 0 23 12c-1.73-4.39-6-7.5-11-7.5-1.4 0-2.74.25-3.98.7l2.16 2.16A4.9 4.9 0 0 1 12 7zM2 4.27l2.74 2.74A11.8 11.8 0 0 0 1 12c1.73 4.39 6 7.5 11 7.5 1.55 0 3.03-.3 4.38-.84L19.73 22 21 20.73 3.27 3 2 4.27zm5.53 5.53 1.55 1.55A3 3 0 0 0 12 15c.22 0 .44-.03.65-.08l1.55 1.55A5 5 0 0 1 7.53 9.8z',
    cue: 'M3 9v6h4l5 5V4L7 9H3zm13.5 3A4.5 4.5 0 0 0 14 7.97v8.05A4.5 4.5 0 0 0 16.5 12z',
    voices: 'M9 13c2.67 0 8 1.34 8 4v3H1v-3c0-2.66 5.33-4 8-4zm0-2a4 4 0 1 1 0-8 4 4 0 0 1 0 8zm7.76-7.64C18.78 5.12 18.78 9 16.76 11l-1.68-1.69a3 3 0 0 0 0-3.27zM20.07 1C24 5.05 23.97 11.11 20.07 15l-1.63-1.63c2.77-3.18 2.77-7.72 0-10.74z',
    play: 'M8 5v14l11-7z',
    stop: 'M7 7h10v10H7z',
    wave: 'M3 10h2v4H3zm4-3h2v10H7zm4-4h2v18h-2zm4 4h2v10h-2zm4 3h2v4h-2z',
    close: 'M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z',
  };
  function svg(name) {
    const ns = 'http://www.w3.org/2000/svg';
    const s = document.createElementNS(ns, 'svg');
    s.setAttribute('viewBox', '0 0 24 24');
    s.setAttribute('aria-hidden', 'true');
    const p = document.createElementNS(ns, 'path');
    p.setAttribute('d', ICON[name]);
    s.append(p);
    return s;
  }
  function el(tag, attrs, ...kids) {
    const n = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (v === null || v === undefined || v === false) continue;
      if (k === 'class') n.className = v;
      else if (k === 'dataset') Object.assign(n.dataset, v);
      else if (k.startsWith('on')) n.addEventListener(k.slice(2), v);
      else n.setAttribute(k, v === true ? '' : v);
    }
    for (const k of kids.flat()) if (k !== null && k !== undefined && k !== false) n.append(k);
    return n;
  }
  const num = new Intl.NumberFormat('en-US');
  const readJSON = (key) => { try { return JSON.parse(localStorage.getItem(key) || 'null'); } catch { return null; } };
  const writeJSON = (key, v) => { try { localStorage.setItem(key, JSON.stringify(v)); } catch { /* private window */ } };
  const muted = () => typeof location !== 'undefined' && new URLSearchParams(location.search).get('mute') === '1';
  const reduceMotion = () => typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;

  /** The open reader, or null. */
  let cur = null;

  /* ---- The page: one element per line, each printed run knowing its offset (§4.16 item 11) ---- */

  function lineNode(script, line, hues, heads) {
    const part = C.linePart(line);
    const runs = R.runsOf(line);
    const cls = line.kind === 'speech' ? 'rd-speech' : line.kind === 'direction' ? 'rd-dir' : 'rd-cue';
    const head = heads.get(line.id);
    const node = el('p', { class: `rd-line ${cls}${head ? ' rd-headline' : ''}`, id: line.id,
      dataset: { line: line.id, part, hue: hues.get(part) || 'none', ...(head ? { level: head.level } : {}) } });
    if (line.kind === 'speech') {
      node.append(el('span', { class: 'rd-who' }, line.role || ''), ' ');
      runs.forEach((r, i) => {
        // A space between two printed pieces (the data keeps no spacing there), never before a period.
        if (i && r.piece !== runs[i - 1].piece && R.spaceBetween(runs[i - 1].text, r.text)) node.append(' ');
        const cls = r.said ? 'rd-said' : r.kind === 'plain' ? 'rd-aside rd-roman' : 'rd-aside';
        node.append(el(r.kind === 'em' ? 'em' : 'span', { class: cls, dataset: { at: String(r.at) } }, r.text));
      });
    } else {
      if (line.kind !== 'direction') node.append(el('span', { class: 'rd-cue-mark' }, svg('cue')));
      for (const r of runs) node.append(el(r.kind === 'em' ? 'em' : 'span', { dataset: { at: String(r.at) } }, r.text));
    }
    return node;
  }

  function buildFlow(script) {
    const hues = new Map();
    C.castParts(script).filter(x => C.isSpeaking(x.id)).forEach((x, i) => hues.set(x.id, C.PART_HUES[i] || 'none'));
    const secs = C.sectionsOf(script);
    const before = new Map();
    const heads = new Map();
    for (const s of secs) {
      if (s.isLine) heads.set(s.line, s);
      else (before.get(s.line) || before.set(s.line, []).get(s.line)).push(s);
    }
    const frag = document.createDocumentFragment();
    const lines = [];
    for (const line of script.lines) {
      for (const s of before.get(line.id) || []) {
        frag.append(el('h2', { class: 'rd-head', dataset: { level: s.level, line: s.line } }, s.title));
      }
      const n = lineNode(script, line, hues, heads);
      lines.push(n);
      frag.append(n);
    }
    return { frag, lines, hues };
  }

  /* ---- Layout and turning ---- */

  function prefsNow() { return R.normalizePrefs(readJSON(PREFS_KEY)); }

  function applyPrefs(st) {
    st.root.dataset.layout = st.prefs.layout;
    st.root.style.setProperty('--rd-scale', String(R.SIZES[st.prefs.size]));
    st.root.style.setProperty('--rd-leading', String(R.SPACING[st.prefs.spacing]));
  }

  /** Lays the script out at the current size and returns to `keep` (a line index), else the saved position. */
  function layout(st, keep) {
    const at = keep !== undefined ? keep : st.pos;
    st.flow.classList.add('rd-still');
    if (st.prefs.layout === 'pages') {
      st.per = R.perSpread(st.stage.clientWidth);
      st.root.style.setProperty('--rd-per', String(st.per));
      st.flow.style.columnCount = String(st.per);
      st.flow.style.columnGap = `${GAP}px`;
      const w = st.clip.clientWidth;
      st.unit = (w - (st.per - 1) * GAP) / st.per + GAP;
      st.flow.style.transform = 'translateX(0px)';
      const left = st.flow.getBoundingClientRect().left;
      const starts = new Array(st.lines.length);
      const ends = new Array(st.lines.length);
      st.lines.forEach((n, i) => {
        const rects = n.getClientRects();
        if (!rects.length) { starts[i] = ends[i] = i ? ends[i - 1] : 0; return; }
        starts[i] = R.pageAt(rects[0].left - left, st.unit);
        ends[i] = R.pageAt(rects[rects.length - 1].left - left, st.unit);
      });
      st.starts = starts; st.ends = ends;
      st.count = ends.length ? ends[ends.length - 1] + 1 : 1;
      // A re-layout keeps the line it was asked to keep, so repeated changes never drift backward.
      setPage(st, at >= 0 && at < starts.length ? starts[at] : 0, false, at >= 0 && at < starts.length ? at : undefined);
    } else {
      st.flow.style.columnCount = '';
      st.flow.style.columnGap = '';
      st.flow.style.transform = '';
      const n = st.lines[Math.max(0, at)];
      st.stage.scrollTop = n ? n.offsetTop - st.flow.offsetTop : 0;
      st.pos = Math.max(0, at);
      paintWhere(st);
    }
    requestAnimationFrame(() => st.flow.classList.remove('rd-still'));
  }

  function setPage(st, page, animate, keep) {
    st.page = R.spreadStart(Math.max(0, Math.min(page, st.count - 1)), st.per);
    st.flow.classList.toggle('rd-still', !animate || reduceMotion());
    st.flow.style.transform = `translateX(${-st.page * st.unit}px)`;
    st.pos = keep !== undefined ? keep : R.lineAtPage(st.starts, st.ends, st.page);
    clearPeeks(st);
    paintWhere(st);
    save(st);
  }

  function step(st, delta) {
    if (st.prefs.layout !== 'pages') return;
    const to = delta === 'first' ? 0 : delta === 'last' ? st.count - 1 : R.turn(st.page, delta, st.per, st.count);
    if (R.spreadStart(to, st.per) !== st.page) setPage(st, to, true);
  }

  /** Goes to a line (by index) and, when asked, outlines it a moment. */
  function goIndex(st, index, { flash = false } = {}) {
    const n = st.lines[index];
    if (!n) return;
    if (st.prefs.layout === 'pages') {
      const p = st.starts[index];
      if (R.spreadStart(p, st.per) !== st.page) setPage(st, p, false, index);
      else { st.pos = index; paintWhere(st); save(st); }
    } else {
      st.stage.scrollTop = n.offsetTop - st.flow.offsetTop - 8;
      st.pos = index;
      paintWhere(st);
      save(st);
    }
    if (flash) {
      n.classList.remove('rd-flash');
      void n.offsetWidth;
      n.classList.add('rd-flash');
      setTimeout(() => n.classList.remove('rd-flash'), 1600);
    }
  }

  /** In Scroll, the reading position is the first line still showing at the top of the scroller. */
  function scrollPos(st) {
    const top = st.stage.scrollTop + st.flow.offsetTop;
    let lo = 0, hi = st.lines.length - 1, ans = 0;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      const n = st.lines[mid];
      if (n.offsetTop + n.offsetHeight > top + 2) { ans = mid; hi = mid - 1; } else lo = mid + 1;
    }
    return ans;
  }

  function paintWhere(st) {
    const { act, scene } = C.placeOf(st.script, Math.max(0, st.pos));
    st.where.textContent = [act && act.title, scene && scene.title].filter(Boolean).join(' · ');
    if (st.prefs.layout === 'pages') st.count && (st.pageLab.textContent = R.pageLabel(st.page, st.per, st.count));
    else {
      const max = st.stage.scrollHeight - st.stage.clientHeight;
      st.pageLab.textContent = `${Math.round(100 * (max > 0 ? st.stage.scrollTop / max : 1))}%`;
    }
  }

  let saveTimer = null;
  function save(st) {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      const line = st.script.lines[Math.max(0, st.pos)];
      writeJSON(POS_KEY, R.remember(readJSON(POS_KEY), st.script.id, { line: line ? line.id : null, part: st.part || null }));
    }, 300);
  }

  /* ---- I'm playing (§4.16 item 10) ---- */

  function setPart(st, part) {
    st.part = part || null;
    const mine = new Set(st.part ? C.lineIndexesOf(st.script, st.part) : []);
    st.lines.forEach((n, i) => n.classList.toggle('rd-mine', mine.has(i)));
    st.nextBtn.hidden = !st.part;
    st.hideBtn.hidden = !st.part;
    if (!st.part) setHiding(st, false);
    else paintHidden(st);
    save(st);
  }
  function setHiding(st, on) {
    st.hiding = on;
    st.root.classList.toggle('rd-hiding', on);
    st.hideBtn.setAttribute('aria-pressed', on ? 'true' : 'false');
    paintHidden(st);
  }
  function paintHidden(st) {
    for (const n of st.lines) {
      const hidden = st.hiding && n.classList.contains('rd-mine');
      if (hidden) { n.setAttribute('tabindex', '0'); n.setAttribute('role', 'button'); n.setAttribute('aria-label', 'Show line'); }
      else if (n.hasAttribute('role')) { n.removeAttribute('tabindex'); n.removeAttribute('role'); n.removeAttribute('aria-label'); }
    }
    clearPeeks(st);
  }
  function peek(st, n) {
    clearPeeks(st);
    n.classList.add('rd-peek');
    n.removeAttribute('aria-label');
    st.peeked = n;
  }
  function clearPeeks(st) {
    if (!st.peeked) return;
    st.peeked.classList.remove('rd-peek');
    if (st.hiding && st.peeked.classList.contains('rd-mine')) st.peeked.setAttribute('aria-label', 'Show line');
    st.peeked = null;
  }
  function myLine(st, direction) {
    if (!st.part) return;
    let i = C.nextLineOf(st.script, st.part, st.pos, direction);
    if (i < 0 && direction > 0) i = C.nextLineOf(st.script, st.part, -1, 1);
    if (i >= 0) goIndex(st, i, { flash: true });
  }

  /* ---- The sheets: Contents, Search, Text ---- */

  function sheet(title, ...body) {
    const d = el('dialog', { class: 'rd-sheet', 'aria-label': title },
      el('div', { class: 'rd-sheet-head' }, el('h2', { class: 'section-header' }, title),
        el('button', { type: 'button', class: 'icon-btn rd-icon', 'aria-label': 'Close', onclick: () => d.close() }, svg('close'))),
      ...body);
    d.addEventListener('click', (e) => { if (e.target === d) d.close(); });
    return d;
  }

  function contentsSheet(st) {
    const toc = C.contentsOf(st.script);
    const list = el('ol', { class: 'rd-toc' });
    const row = (s, cls) => el('li', { class: cls }, el('button', { type: 'button', class: 'rd-toc-btn', dataset: { index: String(s.index) },
      onclick: () => { st.contents.close(); goIndex(st, s.index); } }, s.title));
    for (const t of toc) {
      list.append(row(t, 'rd-toc-top'));
      for (const s of t.scenes) list.append(row(s, 'rd-toc-scene'));
    }
    const d = sheet('Contents', toc.length ? list : el('p', { class: 'caption rd-empty' }, 'This script prints no acts or scenes.'));
    d.addEventListener('toggle', () => {
      if (!d.open) return;
      const btns = [...list.querySelectorAll('.rd-toc-btn')];
      let here = null;
      for (const b of btns) { b.removeAttribute('aria-current'); if (Number(b.dataset.index) <= st.pos) here = b; }
      if (here) { here.setAttribute('aria-current', 'true'); here.scrollIntoView({ block: 'center' }); }
    });
    return d;
  }

  /** A hit's words as printed: italic marks dropped, no space before closing punctuation (display only). */
  const shown = (s) => s.replace(/_/g, '').replace(/ ([.,;:!?])/g, '$1');

  function searchSheet(st) {
    const input = el('input', { type: 'search', class: 'field-input rd-q', 'aria-label': 'Search in the script', enterkeyhint: 'search', autocomplete: 'off' });
    const count = el('p', { class: 'caption rd-count', role: 'status' });
    const list = el('ul', { class: 'rd-hits' });
    let timer = null;
    const run = () => {
      const r = C.searchScript(st.script, input.value);
      list.replaceChildren(...r.hits.map(h => el('li', {}, el('button', { type: 'button', class: 'rd-hit', onclick: () => { st.search.close(); goIndex(st, h.index, { flash: true }); } },
        h.role ? el('span', { class: 'rd-hit-who caption' }, h.role) : null,
        el('span', { class: 'rd-hit-text' }, shown(h.before), el('mark', {}, shown(h.match)), shown(h.after))))));
      const q = input.value.trim();
      count.textContent = q.length < 2 ? '' : !r.total ? 'No line has these words.'
        : r.total > r.hits.length ? `${num.format(r.total)} lines · ${num.format(r.total - r.hits.length)} more` : (r.total === 1 ? '1 line' : `${num.format(r.total)} lines`);
    };
    input.addEventListener('input', () => { clearTimeout(timer); timer = setTimeout(run, 150); });
    const d = sheet('Search', input, count, list);
    d.addEventListener('toggle', () => { if (d.open) { input.focus(); input.select(); } });
    return d;
  }

  function textSheet(st) {
    const sizeLab = el('span', { class: 'tabular rd-size-lab', 'aria-live': 'polite' });
    const smaller = el('button', { type: 'button', class: 'btn rd-size-btn', 'aria-label': 'Smaller text', onclick: () => change({ size: st.prefs.size - 1 }) }, 'A−');
    const larger = el('button', { type: 'button', class: 'btn rd-size-btn rd-size-big', 'aria-label': 'Larger text', onclick: () => change({ size: st.prefs.size + 1 }) }, 'A+');
    const radios = (name, label, opts) => el('fieldset', { class: 'rd-choice' }, el('legend', { class: 'caption' }, label),
      el('div', { class: 'rd-seg' }, ...opts.map(([v, l]) => el('label', {},
        el('input', { type: 'radio', name: `rd-${name}`, value: v, onchange: () => change({ [name]: v }) }), el('span', {}, l)))));
    const spacing = radios('spacing', 'Line spacing', [['tight', 'Tight'], ['normal', 'Normal'], ['loose', 'Loose']]);
    const lay = radios('layout', 'Layout', [['pages', 'Pages'], ['scroll', 'Scroll']]);
    const paint = () => {
      sizeLab.textContent = `${Math.round(R.SIZES[st.prefs.size] * 100)}%`;
      smaller.disabled = st.prefs.size <= 0;
      larger.disabled = st.prefs.size >= R.SIZES.length - 1;
      for (const i of spacing.querySelectorAll('input')) i.checked = i.value === st.prefs.spacing;
      for (const i of lay.querySelectorAll('input')) i.checked = i.value === st.prefs.layout;
    };
    function change(delta) {
      const keep = st.pos;
      st.prefs = R.normalizePrefs({ ...st.prefs, ...delta, size: delta.size !== undefined ? Math.max(0, Math.min(R.SIZES.length - 1, delta.size)) : st.prefs.size });
      writeJSON(PREFS_KEY, st.prefs);
      applyPrefs(st);
      layout(st, keep);
      paint();
    }
    const d = sheet('Text',
      el('div', { class: 'rd-size' }, el('span', { class: 'caption' }, 'Size'), smaller, sizeLab, larger), spacing, lay);
    d.addEventListener('toggle', () => { if (d.open) paint(); });
    return d;
  }

  /* ---- Voices and Hear the cast (§4.16 item 13, PLAYS-DESIGN §2.8) ---- */

  function voicesSheet(st) {
    const list = CastUI.list({ script: st.script, cast: st.cast, voice: st.voice });
    const d = sheet('Voices', list);
    d.addEventListener('toggle', () => { if (d.open) list.paint(); });
    return d;
  }

  /** Reads from the first line on the page to the end; the reader follows each line, the dock labels it. */
  function hearCast(st) {
    if (st.table && st.table.playing) { st.table.stop(); return; }
    if (typeof Player !== 'undefined' && Player.pause) Player.pause();
    st.following = true;
    st.table = TableRead.create({
      script: st.script, voice: st.voice,
      onLine: (line) => { st.handle.follow(line ? line.id : null); paintDock(st, line); },
      onChange: () => paintHear(st),
    });
    st.table.play(Math.max(0, st.pos));
  }
  function paintHear(st) {
    const on = !!(st.table && st.table.playing);
    st.hearBtn.replaceChildren(svg(on ? 'stop' : 'play'), el('span', { class: 'rd-tool-lab' }, on ? 'Stop' : 'Hear the cast'));
    st.hearBtn.setAttribute('aria-label', on ? 'Stop' : 'Hear the cast');
    // No voice in this browser (or not yet: Chrome fills the list late): nothing to hear.
    st.hearBtn.disabled = !on && !st.voice.available();
    if (!on) paintDock(st, null);
  }
  function paintDock(st, line) {
    st.dock.hidden = !line;
    st.dock.replaceChildren(...(line ? [el('p', { class: 'caption device-voice rd-voice-now' }, svg('wave'), 'Device voice · ', C.partTitle(C.linePart(line)))] : []));
  }

  /* ---- Input: keys, taps, swipes, wheels ---- */

  function onKey(e) {
    const st = cur;
    if (!st || !st.root.isConnected || st.root.closest('[hidden]')) return;
    if (e.defaultPrevented || e.metaKey || e.ctrlKey || e.altKey) return;
    if (st.root.querySelector('dialog[open]') || document.querySelector('dialog[open]')) return;
    const t = e.target;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'SELECT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
    if (st.hiding && t && t.classList && t.classList.contains('rd-mine') && (e.key === 'Enter' || e.key === ' ')) {
      e.preventDefault(); peek(st, t); return;
    }
    if (st.part && (e.key === 'j' || e.key === 'k')) { e.preventDefault(); myLine(st, e.key === 'j' ? 1 : -1); return; }
    if (st.prefs.layout !== 'pages') return;
    if (t && t.tagName === 'BUTTON' && (e.key === ' ' || e.key === 'Enter')) return;
    const k = R.keyTurn(e.key, e.shiftKey);
    if (!k) return;
    e.preventDefault();
    step(st, k);
  }

  function wire(st) {
    let drag = null;
    let swallow = false;
    let wheel = 0, wheelAt = 0;
    st.clip.addEventListener('pointerdown', (e) => {
      if (e.button || st.prefs.layout !== 'pages') return;
      drag = { x: e.clientX, y: e.clientY, t: e.timeStamp, dx: 0, moved: false, touch: e.pointerType !== 'mouse' };
    });
    st.clip.addEventListener('pointermove', (e) => {
      if (!drag || !drag.touch) return;
      const dx = e.clientX - drag.x;
      if (!drag.moved && Math.abs(dx) > 8 && Math.abs(dx) > Math.abs(e.clientY - drag.y)) {
        drag.moved = true;
        st.clip.setPointerCapture(e.pointerId);
        st.flow.classList.add('rd-still');
      }
      if (drag.moved) { drag.dx = dx; st.flow.style.transform = `translateX(${-st.page * st.unit + dx}px)`; }
    });
    const end = (e, cancel) => {
      if (!drag) return;
      const d = drag;
      drag = null;
      if (!d.moved) return;
      swallow = true;
      const turnBy = cancel ? 0 : R.swipeTurn(d.dx, e.timeStamp - d.t, st.clip.clientWidth);
      const to = turnBy ? R.turn(st.page, turnBy, st.per, st.count) : st.page;
      setPage(st, to, true);
    };
    st.clip.addEventListener('pointerup', (e) => end(e, false));
    st.clip.addEventListener('pointercancel', (e) => end(e, true));
    st.clip.addEventListener('click', (e) => {
      if (swallow) { swallow = false; return; }
      st.following = false;
      const line = e.target.closest('.rd-line');
      if (st.hiding && line && line.classList.contains('rd-mine')) { peek(st, line); return; }
      clearPeeks(st);
      if (st.prefs.layout !== 'pages') return;
      const sel = window.getSelection && window.getSelection();
      if (sel && String(sel).length) return;
      const r = st.clip.getBoundingClientRect();
      const z = R.tapZone(e.clientX - r.left, r.width);
      if (z !== 'middle') step(st, z === 'prev' ? -1 : 1);
    });
    st.stage.addEventListener('wheel', (e) => {
      if (st.prefs.layout !== 'pages') return;
      e.preventDefault();
      const d = Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
      if (e.timeStamp - wheelAt > 350) wheel = 0;
      wheel += d;
      if (Math.abs(wheel) > 60 && e.timeStamp - wheelAt > 350) { step(st, wheel > 0 ? 1 : -1); wheel = 0; wheelAt = e.timeStamp; }
    }, { passive: false });
    let scrollTimer = null;
    st.stage.addEventListener('scroll', () => {
      if (st.prefs.layout !== 'scroll') return;
      clearTimeout(scrollTimer);
      scrollTimer = setTimeout(() => { st.pos = scrollPos(st); paintWhere(st); save(st); }, 120);
    }, { passive: true });
    let raf = 0, lastW = 0, lastH = 0;
    st.resize = new ResizeObserver(() => {
      const w = st.stage.clientWidth, hgt = st.stage.clientHeight;
      if (!w || (w === lastW && hgt === lastH)) return;
      lastW = w; lastH = hgt;
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => layout(st, st.pos));
    });
    st.resize.observe(st.stage);
  }

  /* ---- Open, close, and the seams ---- */

  /**
   * Opens `script` in `container`. opts: `line` (a line id to open at), `onClose`.
   * Returns the reader's handle: { go(lineID), follow(lineID), dock } (the read-along and studio seams).
   */
  function open(container, script, opts = {}) {
    close();
    const saved = (readJSON(POS_KEY) || {})[script.id] || {};
    const at = Math.max(0, script.lines.findIndex(l => l.id === (opts.line || saved.line)));
    const { frag, lines } = buildFlow(script);
    const flow = el('div', { class: 'rd-flow' });
    flow.append(frag);
    const clip = el('div', { class: 'rd-clip' }, flow);
    const stage = el('div', { class: 'rd-stage', tabindex: '-1' }, clip);
    const where = el('p', { class: 'caption rd-where' });
    const pageLab = el('span', { class: 'caption tabular rd-page', 'aria-live': 'polite' });
    const parts = C.castParts(script).filter(x => C.isSpeaking(x.id));
    const partSel = el('select', { class: 'rd-part-sel', 'aria-label': 'I’m playing' },
      el('option', { value: '' }, 'I’m playing…'),
      ...parts.map(p => el('option', { value: p.id }, `${p.title} · ${num.format(p.lineCount)}`)));
    const nextBtn = el('button', { type: 'button', class: 'btn btn-ghost rd-tool', hidden: true }, svg('next'), el('span', { class: 'rd-tool-lab' }, 'Next line'));
    const hideBtn = el('button', { type: 'button', class: 'btn btn-ghost rd-tool', 'aria-pressed': 'false', hidden: true }, svg('hide'), el('span', { class: 'rd-tool-lab' }, 'Hide my lines'));
    const iconBtn = (name, label, onclick) => el('button', { type: 'button', class: 'icon-btn rd-icon', 'aria-label': label, title: label, onclick }, svg(name));
    const dock = el('div', { class: 'rd-dock', hidden: true });
    const hearBtn = el('button', { type: 'button', class: 'btn btn-ghost rd-tool rd-hear' });
    const root = el('div', { class: 'rd' });
    const cast = CastUI.castFor({ script });
    const st = { root, script, flow, clip, stage, where, pageLab, nextBtn, hideBtn, hearBtn, lines, dock, prefs: prefsNow(),
                 cast, voice: StandInVoice.create({ muted: muted(), cast }), table: null,
                 pos: at, page: 0, per: 1, unit: 1, count: 1, starts: [], ends: [], part: null, hiding: false, peeked: null, following: true };
    st.contents = contentsSheet(st);
    st.search = searchSheet(st);
    st.text = textSheet(st);
    st.voices = voicesSheet(st);
    root.append(
      el('header', { class: 'rd-bar rd-top' },
        iconBtn('back', 'Close', () => (opts.onClose ? opts.onClose() : history.back())),
        el('div', { class: 'rd-titles' }, el('p', { class: 'body-strong rd-title' }, script.title), where),
        iconBtn('contents', 'Contents', () => st.contents.showModal()),
        iconBtn('search', 'Search', () => st.search.showModal()),
        iconBtn('text', 'Text', () => st.text.showModal()),
        iconBtn('voices', 'Voices', () => st.voices.showModal())),
      stage, dock,
      el('footer', { class: 'rd-bar rd-bottom' }, el('label', { class: 'rd-part' }, partSel), hearBtn, nextBtn, hideBtn, pageLab),
      st.contents, st.search, st.text, st.voices);
    hearBtn.addEventListener('click', () => hearCast(st));
    paintHear(st);
    st.voicesOff = StandInVoice.onVoices(() => { if (cur === st) paintHear(st); });
    partSel.addEventListener('change', () => setPart(st, partSel.value));
    nextBtn.addEventListener('click', () => myLine(st, 1));
    hideBtn.addEventListener('click', () => setHiding(st, !st.hiding));
    container.replaceChildren(root);
    cur = st;
    applyPrefs(st);
    wire(st);
    document.addEventListener('keydown', onKey);
    if (saved.part && parts.some(p => p.id === saved.part)) { partSel.value = saved.part; setPart(st, saved.part); }
    layout(st, at);
    // A face that arrives late (the heading face loads when a heading first shows) moves every line:
    // lay out again, keeping the position.
    st.fontsDone = () => { if (cur === st) layout(st, st.pos); };
    if (document.fonts) {
      document.fonts.ready.then(st.fontsDone);
      document.fonts.addEventListener('loadingdone', st.fontsDone);
    }
    stage.focus({ preventScroll: true });
    st.handle = handle(st);
    return st.handle;
  }

  function handle(st) {
    const index = (id) => st.script.lines.findIndex(l => l.id === id);
    return {
      dock: st.dock,
      go: (id) => { const i = index(id); if (i >= 0) goIndex(st, i); },
      /** The read-along: light the line and keep it in view until the person touches the text. */
      follow: (id) => {
        const i = index(id);
        st.lines.forEach(n => n.classList.remove('rd-now'));
        if (i < 0) return;
        st.lines[i].classList.add('rd-now');
        if (st.following) goIndex(st, i);
      },
      /** Back to following after a touch stopped it. */
      refollow: () => { st.following = true; const n = st.root.querySelector('.rd-now'); if (n) goIndex(st, st.lines.indexOf(n)); },
    };
  }

  function close() {
    if (!cur) return;
    document.removeEventListener('keydown', onKey);
    if (cur.table) cur.table.stop();
    if (cur.voicesOff) cur.voicesOff();
    if (cur.resize) cur.resize.disconnect();
    if (document.fonts && cur.fontsDone) document.fonts.removeEventListener('loadingdone', cur.fontsDone);
    for (const d of cur.root.querySelectorAll('dialog[open]')) d.close();
    cur = null;
  }

  const openID = () => (cur ? cur.script.id : null);

  return { open, close, openID };
})();
