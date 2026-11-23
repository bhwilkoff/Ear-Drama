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
    pause: 'M6 19h4V5H6v14zm8-14v14h4V5h-4z',
    skipPrev: 'M6 6h2v12H6zm3.5 6 8.5 6V6z',
    skipNext: 'M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z',
    stop: 'M7 7h10v10H7z',
    wave: 'M3 10h2v4H3zm4-3h2v10H7zm4-4h2v18h-2zm4 4h2v10h-2zm4 3h2v4h-2z',
    mic: 'M12 14a3 3 0 0 0 3-3V5a3 3 0 0 0-6 0v6a3 3 0 0 0 3 3zm5-3a5 5 0 0 1-10 0H5a7 7 0 0 0 6 6.9V21h2v-3.1A7 7 0 0 0 19 11z',
    close: 'M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z',
    marks: 'M17 3H7a2 2 0 0 0-2 2v16l7-3 7 3V5a2 2 0 0 0-2-2zm0 15-5-2.18L7 18V5h10v13z',
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

  /*
   * The Ear Drama page (PLAYS-DESIGN §2.7 rule 10, WEB-DESIGN §4.16 item 3; ReaderCore.layoutOf sets
   * each line): a speech is a block, the speaker's name over the words (beside them, in a gutter, when
   * the page is wide); a printed direction inside a speech is italic in parentheses; verse keeps its
   * lines; a sound or music cue is its own row in the sound lane; a stage direction is a quieter,
   * indented paragraph with the parts it names in their hues.
   */

  /** A direction's text, a part's name in it (as printed, in capitals) drawn in that part's hue. */
  function directionRuns(parent, r, cls, namesRx, hues) {
    const tag = r.kind === 'em' ? 'em' : 'span';
    const segs = [];
    let last = 0;
    if (namesRx && r.kind !== 'em') {
      for (const m of r.text.matchAll(namesRx)) {
        if (m.index > last) segs.push([last, r.text.slice(last, m.index), null]);
        segs.push([m.index, m[0], hues.get(`role:${m[0]}`) || 'none']);
        last = m.index + m[0].length;
      }
    }
    if (last < r.text.length || !segs.length) segs.push([last, r.text.slice(last), null]);
    // The page's parentheses go on the first and last pieces only, and never double a printed one.
    const base = cls.replace(/ rd-open| rd-close/g, '');
    segs.forEach(([at, text, hue], i) => {
      let c = base;
      if (i === 0 && cls.includes('rd-open') && !/^\s*[(\[]/.test(text)) c += ' rd-open';
      if (i === segs.length - 1 && cls.includes('rd-close') && !/[)\]][.,;:!?]*\s*$/.test(text)) c += ' rd-close';
      if (hue) c += ' rd-dname';
      parent.append(el(tag, { class: c.trim(), dataset: { at: String(r.at + at), ...(hue ? { hue } : {}) } }, text));
    });
  }

  function rowNode(row, namesRx, hues) {
    const n = el('span', { class: `rd-row${row.cue ? ' rd-sfx' : ''}${row.indent ? ' rd-half' : ''}` });
    if (row.cue) n.append(el('span', { class: 'rd-sfx-mark' }, svg('cue')));
    row.runs.forEach((r, i) => {
      // A space between two printed pieces (the data keeps no spacing there), never before a period.
      if (i && r.piece !== row.runs[i - 1].piece && R.spaceBetween(row.runs[i - 1].text, r.text)) n.append(' ');
      if (row.cue) { n.append(el(r.kind === 'em' ? 'em' : 'span', { class: 'rd-sfx-text', dataset: { at: String(r.at) } }, r.text)); return; }
      // A spaced ellipsis (". . .") never breaks across lines; the no-break spaces keep every offset.
      if (r.said) { n.append(el(r.kind === 'em' ? 'em' : 'span', { class: 'rd-said', dataset: { at: String(r.at) } }, r.text.replace(/\.(?: \.)+/g, (m) => m.replace(/ /g, ' ')))); return; }
      // A printed direction inside a speech: one parenthesized aside per piece.
      const whole = row.runs.filter(x => x.piece === r.piece && !x.said).map(x => x.text).join('');
      const open = (!i || row.runs[i - 1].piece !== r.piece) && !/^\s*[(\[]/.test(whole);
      const close = (i === row.runs.length - 1 || row.runs[i + 1].piece !== r.piece) && !/[)\]][.,;:!?]*\s*$/.test(whole);
      const cls = `rd-aside${r.kind === 'plain' ? ' rd-roman' : ''}${open ? ' rd-open' : ''}${close ? ' rd-close' : ''}`;
      directionRuns(n, r, cls, namesRx, hues);
    });
    return n;
  }

  function lineNode(script, line, hues, heads, roles, namesRx) {
    const part = C.linePart(line);
    const lay = R.layoutOf(line, roles);
    const head = heads.get(line.id);
    if (line.kind === 'speech') {
      const node = el('div', { class: 'rd-line rd-speech', id: line.id, dataset: { line: line.id, part, hue: hues.get(part) || 'none' } });
      for (const sp of lay.speeches) {
        const p = `role:${sp.role}`;
        const name = sp.name
          ? el('span', { class: 'rd-name', dataset: { at: String(sp.name.at) } }, sp.name.text)
          : el('span', { class: 'rd-name' }, sp.role);
        const body = el('p', { class: `rd-body${lay.verse ? ' rd-verse' : ''}` }, ...sp.rows.map(rw => rowNode(rw, namesRx, hues)));
        node.append(el('div', { class: 'rd-sp', dataset: { part: p, hue: hues.get(p) || 'none' } }, el('p', { class: 'rd-who' }, name), body));
      }
      return node;
    }
    const cls = line.kind === 'direction' ? 'rd-dir' : 'rd-cue';
    const node = el('p', { class: `rd-line ${cls}${head ? ' rd-headline' : ''}`, id: line.id,
      dataset: { line: line.id, part, hue: hues.get(part) || 'none', ...(head ? { level: head.level } : {}) } });
    const row = lay.rows[0];
    if (head) { for (const r of R.runsOf(line)) node.append(el(r.kind === 'em' ? 'em' : 'span', { dataset: { at: String(r.at) } }, r.text)); return node; }
    if (row.cue) node.append(el('span', { class: 'rd-sfx-mark' }, svg('cue')));
    for (const r of row.runs) directionRuns(node, r, row.cue ? 'rd-sfx-text' : '', line.kind === 'direction' ? namesRx : null, hues);
    return node;
  }

  /** The front of the play: its title, its authors, and its speaking parts in their hues, largest first. */
  function frontNode(script, hues) {
    const parts = C.castParts(script).filter(x => C.isSpeaking(x.id));
    const by = C.authorLine(script);
    return el('header', { class: 'rd-front' },
      el('h1', { class: 'rd-front-title' }, script.title),
      by ? el('p', { class: 'rd-front-by' }, by) : null,
      parts.length ? el('p', { class: 'caption rd-front-lab' }, 'Parts') : null,
      parts.length ? el('ul', { class: 'rd-front-parts' }, ...parts.map(x => el('li', { dataset: { hue: hues.get(x.id) || 'none' } }, x.title))) : null);
  }

  function buildFlow(script) {
    const hues = new Map();
    C.castParts(script).filter(x => C.isSpeaking(x.id)).forEach((x, i) => hues.set(x.id, C.PART_HUES[i] || 'none'));
    const roles = (script.roles || []).map(r => r.name).filter(Boolean);
    // Parts named in capitals inside a direction (as the printed text sets them), longest first.
    const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const capRoles = roles.filter(n => n.length >= 3 && n === n.toUpperCase() && /[A-Z]/.test(n)).sort((a, b) => b.length - a.length);
    const namesRx = capRoles.length ? new RegExp(`(?<![\\p{L}])(?:${capRoles.map(esc).join('|')})(?![\\p{L}])`, 'gu') : null;
    const secs = C.sectionsOf(script);
    const before = new Map();
    const heads = new Map();
    for (const s of secs) {
      if (s.isLine) heads.set(s.line, s);
      else (before.get(s.line) || before.set(s.line, []).get(s.line)).push(s);
    }
    const frag = document.createDocumentFragment();
    frag.append(frontNode(script, hues));
    const lines = [];
    for (const line of script.lines) {
      for (const s of before.get(line.id) || []) {
        frag.append(el('h2', { class: 'rd-head', dataset: { level: s.level, line: s.line } }, s.title));
      }
      const n = lineNode(script, line, hues, heads, roles, namesRx);
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
    const cs = getComputedStyle(st.clip);
    const pad = parseFloat(cs.paddingLeft) + parseFloat(cs.paddingRight);
    const em = parseFloat(cs.fontSize) || 16;
    if (st.prefs.layout === 'pages') {
      st.per = R.perSpread(st.stage.clientWidth);
      st.root.style.setProperty('--rd-per', String(st.per));
      st.flow.style.columnCount = String(st.per);
      st.flow.style.columnGap = `${GAP}px`;
      const w = st.clip.clientWidth - pad;
      st.unit = (w - (st.per - 1) * GAP) / st.per + GAP;
      // The speaker's name goes beside the words, in a gutter, once a page holds 30 em.
      st.root.dataset.gutter = String((st.unit - GAP) / em >= R.GUTTER_MIN_EM);
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
      st.root.dataset.gutter = String((st.clip.clientWidth - pad) / em >= R.GUTTER_MIN_EM);
      st.heads.replaceChildren();
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
    paintHeads(st);
    paintWhere(st);
    if (st.marks) st.marks.turned();
    save(st);
  }

  /**
   * A speech carried over from the page before is headed with its speaker's name and "(cont’d)", as an
   * acting edition and a radio script print it, so a page never opens on words nobody is saying.
   */
  function paintHeads(st) {
    const out = [];
    const left = st.flow.getBoundingClientRect().left;
    const pageOf = (n) => { const r = n.getClientRects(); return r.length ? R.pageAt(r[0].left - left, st.unit) : -1; };
    for (let p = st.page; p < st.page + st.per && p < st.count; p++) {
      let who = null;
      const i = st.starts.findIndex((s, k) => s < p && st.ends[k] >= p);
      const n = i >= 0 ? st.lines[i] : null;
      if (n && n.classList.contains('rd-speech')) {
        let sp = null;
        for (const s of n.querySelectorAll('.rd-sp')) { const at = pageOf(s); if (at >= 0 && at < p) sp = s; }
        if (sp) {
          const body = sp.querySelector('.rd-body');
          const rects = body ? [...body.getClientRects()] : [];
          if (rects.some(r => R.pageAt(r.left - left, st.unit) >= p)) who = sp;
        }
      }
      out.push(el('span', { class: 'rd-runhead', dataset: who ? { hue: who.dataset.hue } : {} },
        who ? [el('span', { class: 'rd-runhead-name' }, who.querySelector('.rd-name').textContent), ' (cont’d)'] : ''));
    }
    st.heads.replaceChildren(...out);
  }

  function step(st, delta) {
    if (st.prefs.layout !== 'pages') return;
    away(st);
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
    if (st.prefs.layout === 'pages') st.count && paintPageLab(st, R.pageLabel(st.page, st.per, st.count));
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

  /**
   * The part's speeches (a speech another speaker's words ran into is still theirs on the page), and
   * the cue each is heard on: the last words of the speech before it, underlined in the part's hue.
   */
  function setPart(st, part) {
    if (st.marks) st.marks.undraw();
    st.part = part || null;
    st.mine = [];
    for (const n of st.root.querySelectorAll('.rd-cueword')) n.classList.remove('rd-cueword');
    let prev = null;
    st.lines.forEach((n, i) => {
      let any = false;
      for (const sp of n.querySelectorAll('.rd-sp')) {
        const me = !!st.part && sp.dataset.part === st.part;
        sp.classList.toggle('rd-mine', me);
        if (me) { any = true; if (prev && prev.dataset.part !== st.part) cueWords(prev); }
        prev = sp;
      }
      n.classList.toggle('rd-mine', any);
      if (any) st.mine.push(i);
    });
    const first = st.part ? st.root.querySelector(`.rd-sp[data-part="${CSS.escape(st.part)}"]`) : null;
    const hue = first ? first.dataset.hue : 'none';
    st.root.style.setProperty('--mine', hue === 'none' ? 'var(--color-text-muted)' : `var(--color-genre-${hue})`);
    st.nextBtn.hidden = !st.part;
    st.hideBtn.hidden = !st.part;
    st.recBtn.hidden = !st.part || !st.onRecord;
    if (!st.part) setHiding(st, false);
    else paintHidden(st);
    if (st.marks) st.marks.draw();
    save(st);
  }
  /** Marks the last sentence of a speech's last said words (splitting their run, each half keeping its offset). */
  function cueWords(sp) {
    const said = [...sp.querySelectorAll('.rd-said')];
    const last = said[said.length - 1];
    if (!last) return;
    const k = R.cueTail(last.textContent);
    if (k > 0) {
      const tail = last.cloneNode(false);
      tail.textContent = last.textContent.slice(k);
      tail.dataset.at = String(Number(last.dataset.at) + k);
      last.textContent = last.textContent.slice(0, k);
      last.after(tail);
      tail.classList.add('rd-cueword');
    } else last.classList.add('rd-cueword');
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
    const m = st.mine || [];
    let i = direction > 0 ? m.find(k => k > st.pos) : [...m].reverse().find(k => k < st.pos);
    if (i === undefined && direction > 0) i = m[0];
    if (i === undefined) i = -1;
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

  /* ---- Read along (PLAYS-DESIGN §2.11, WEB-DESIGN §4.16a): the script follows the voice ---- */

  /** The entries read: a finished drama's files, a production's listen plan, or the cast over the whole script. */
  function alongEntries(st) {
    const a = st.along;
    if (a && a.dramaPlan) return Along.dramaEntries(a.dramaPlan);
    if (a && a.store) return Along.productionEntries(a.store.production(a.production), st.script, st.voice);
    return Along.tableEntries(st.script, st.voice);
  }

  /** Starts reading at the reader's place (a production's Read along at once, Hear the cast on its press); the transport takes the bar. */
  function alongStart(st) {
    if (st.ctl && (st.ctl.playing || st.ctl.held)) return;
    if (typeof Player !== 'undefined' && Player.pause) Player.pause();
    st.fol.back();
    paintBack(st, false);
    const a = st.along;
    const read = a && a.store ? (e) => a.store.readTake(a.production, e.take.file) : null;
    const ctl = Along.create({
      script: st.script, entries: alongEntries(st), voice: st.voice, media: Along.mediaFor(read), muted,
      onLine: (id, entry) => alongLine(st, id, entry),
      onWord: (id, w) => alongWord(st, id, w),
      onChange: () => paintTransport(st),
    });
    if (!ctl.entries.length) return;
    st.ctl = ctl;
    ctl.from(Math.max(0, st.pos));
    ctl.play();
  }

  /** The line heard changed (null when the reading ended): light it, turn to it, name a device voice. */
  function alongLine(st, id, entry) {
    if (cur !== st) return;
    clearWord(st);
    st.word = null;
    st.handle.follow(id);
    paintDock(st, id && entry && entry.source === 'voice' ? st.script.lines.find(x => x.id === id) : null);
  }

  /** Whether this browser can draw a word mark on the printed words (the CSS Custom Highlight API). */
  const canMark = () => typeof CSS !== 'undefined' && CSS.highlights && typeof Highlight !== 'undefined';

  /** The printed words `w` ({ start, end } in the line's words) as Ranges over the line's printed runs, never over a speaker's name. */
  function wordRanges(lineNode, w) {
    const out = [];
    for (const n of lineNode.querySelectorAll('[data-at]')) {
      if (n.closest('.rd-who') || n.childNodes.length !== 1 || n.firstChild.nodeType !== 3) continue;
      const t = n.firstChild;
      const at = Number(n.dataset.at);
      const lo = Math.max(w.start, at), hi = Math.min(w.end, at + t.data.length);
      if (lo < hi) { const r = document.createRange(); r.setStart(t, lo - at); r.setEnd(t, hi - at); out.push(r); }
    }
    return out;
  }

  function clearWord(st) {
    if (st.wordMark) { if (canMark()) CSS.highlights.delete(st.wordMark); st.wordMark = null; }
  }

  /** The word heard (null clears it): a fill and a rule in the speaker's hue, and the page turns to it when it is not in view. */
  function alongWord(st, id, w) {
    if (cur !== st) return;
    clearWord(st);
    st.word = w && id ? { id, w } : null;
    if (!st.word || !canMark()) return;
    const index = st.script.lines.findIndex(x => x.id === id);
    const line = st.lines[index];
    if (!line) return;
    const ranges = wordRanges(line, w);
    if (!ranges.length) return;
    const host = ranges[0].startContainer.parentElement;
    const hue = ((host && host.closest('[data-hue]')) || line).dataset.hue;
    st.wordMark = `rd-w-${hue && hue !== 'none' ? hue : 'ink'}`;
    CSS.highlights.set(st.wordMark, new Highlight(...ranges));
    if (st.fol.following) bringWord(st, index, ranges[0]);
  }

  /** Turns to the page (Scroll: scrolls to the place) where the word sits, when it is not in view. */
  function bringWord(st, index, range) {
    const rect = range.getClientRects()[0];
    if (!rect) return;
    if (st.prefs.layout === 'pages') {
      const p = R.pageContaining(rect.left - st.flow.getBoundingClientRect().left, st.unit);
      if (p < st.page || p >= st.page + st.per) setPage(st, p, true, index);
      return;
    }
    const box = st.stage.getBoundingClientRect();
    if (rect.top < box.top + 24 || rect.bottom > box.bottom - 24) {
      st.stage.scrollBy({ top: rect.top - box.top - box.height / 3, behavior: reduceMotion() ? 'auto' : 'smooth' });
    }
  }

  /** Turns to line `index` when it starts on a page not in view (either page of a spread counts); Scroll brings it to the top. */
  function followTo(st, index) {
    if (st.prefs.layout === 'pages') {
      const p = st.starts[index];
      if (p >= st.page && p < st.page + st.per) { st.pos = index; paintWhere(st); save(st); return; }
      setPage(st, p, true, index);
      return;
    }
    const n = st.lines[index];
    st.pos = index;
    st.stage.scrollTo({ top: n.offsetTop - st.flow.offsetTop - 8, behavior: reduceMotion() ? 'auto' : 'smooth' });
    paintWhere(st);
  }

  /** The transport's bar (rule 6): speaker, previous line, play or pause, next line, speed, stop. */
  function transportEl(st) {
    const tool = (cls, name, label, onclick) => el('button', { type: 'button', class: `icon-btn rd-t ${cls}`, 'aria-label': label, title: label, onclick }, svg(name));
    const speaker = el('span', { class: 'body-strong rd-speaker' });
    const prev = tool('rd-t-prev', 'skipPrev', 'Previous line', () => st.ctl && st.ctl.prev());
    const playLab = el('span', { class: 'rd-tool-lab' });
    const play = el('button', { type: 'button', class: 'btn rd-tool rd-t-play', onclick: () => st.ctl && st.ctl.toggle() }, el('span', { class: 'rd-t-ico' }), playLab);
    const next = tool('rd-t-next', 'skipNext', 'Next line', () => st.ctl && st.ctl.next());
    const speed = el('select', { class: 'rd-speed', 'aria-label': 'Speed' },
      ...R.ALONG_SPEEDS.map(v => el('option', { value: String(v) }, R.speedLabel(v))));
    speed.addEventListener('change', () => { if (st.ctl) st.ctl.setSpeed(speed.value); else R.saveSpeed(speed.value); });
    const stop = tool('rd-t-stop', 'stop', 'Stop', () => st.ctl && st.ctl.stop());
    const bar = el('div', { class: 'rd-transport', role: 'group', 'aria-label': 'Read along', hidden: true }, speaker, prev, play, next, speed, stop);
    return { bar, speaker, prev, play, playLab, next, speed };
  }

  function paintTransport(st) {
    if (cur !== st) return;
    const c = st.ctl;
    const on = !!(c && (c.playing || c.held));
    st.footer.classList.toggle('rd-alonging', on);
    const t = st.tr;
    t.bar.hidden = !on;
    st.hearBtn.replaceChildren(svg('play'), el('span', { class: 'rd-tool-lab' }, st.along ? 'Read along' : 'Hear the cast'));
    st.hearBtn.setAttribute('aria-label', st.along ? 'Read along' : 'Hear the cast');
    // No voice in this browser (or not yet: Chrome fills the list late): nothing to hear.
    st.hearBtn.disabled = !st.along && !st.voice.available();
    t.speed.value = String(c ? c.speed : R.savedSpeed());
    if (!on) { paintDock(st, null); return; }
    const line = st.script.lines.find(x => x.id === c.line());
    t.speaker.textContent = line ? C.partTitle(C.linePart(line)) : '';
    const node = line && st.lines[st.script.lines.indexOf(line)];
    if (node) t.speaker.dataset.hue = node.dataset.hue || 'none';
    const word = c.playing ? 'Pause' : 'Play';
    t.play.firstChild.replaceChildren(svg(c.playing ? 'pause' : 'play'));
    t.playLab.textContent = word;
    t.play.setAttribute('aria-label', word);
    t.prev.disabled = !c.canPrev();
    t.next.disabled = !c.canNext();
  }
  /** "12 of 140": the "of" is its own span so a phone's bar can draw a slash instead (css .rd-of). */
  function paintPageLab(st, label) {
    const i = label.indexOf(' of ');
    if (i < 0) { st.pageLab.textContent = label; return; }
    st.pageLab.replaceChildren(label.slice(0, i), el('span', { class: 'rd-of' }, ' of '), label.slice(i + 4));
  }
  /** A touch on the text stops the read-along turning the page. */
  function away(st) { paintBack(st, st.fol.away().back); }
  function paintBack(st, on) { if (st.backBtn) st.backBtn.hidden = !on; }

  /** The "Device voice · PART" strip over the transport; the dock is the studio's too, so only a strip drawn here is cleared here. */
  function paintDock(st, line) {
    if (!line && !st.dockMine) return;
    st.dockMine = !!line;
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
    // Space plays and pauses a read-along where the reader holds the keyboard (PLAYS-DESIGN §2.11 rule 6).
    if ((e.key === ' ' || e.key === 'Spacebar') && st.ctl && (st.ctl.playing || st.ctl.held) && !(t && t.tagName === 'BUTTON')) {
      e.preventDefault(); st.ctl.toggle(); return;
    }
    if (st.hiding && t && t.classList && t.classList.contains('rd-mine') && (e.key === 'Enter' || e.key === ' ')) {
      e.preventDefault(); peek(st, t); return;
    }
    // A read room's leader moves the room with the keys and a pedal (WEB-DESIGN §4.17 item 4).
    if (st.room && st.room.key(e)) { e.preventDefault(); return; }
    if (st.prefs.layout !== 'pages') return;
    if (t && t.tagName === 'BUTTON' && (e.key === ' ' || e.key === 'Enter')) return;
    const k = R.keyTurn(e.key, e.shiftKey);
    if (!k) return;
    e.preventDefault();
    step(st, k);
  }

  /* J and K, captured ahead of the player's own j/k (back 10 s, play/pause) while the plain reader is open; the studio takes them itself. */
  function onMyLineKey(e) {
    const st = cur;
    const step = R.myLineStep(e.key);
    if (!step || !st || !st.part || st.studio || !st.root.isConnected || st.root.closest('[hidden]')) return;
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (st.root.querySelector('dialog[open]') || document.querySelector('dialog[open]')) return;
    const t = e.target;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'SELECT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
    e.preventDefault();
    e.stopPropagation();
    myLine(st, step);
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
      if (!drag.moved && st.marks && st.marks.selecting()) { drag = null; return; }
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
      if (turnBy) away(st);
      setPage(st, to, true);
    };
    st.clip.addEventListener('pointerup', (e) => end(e, false));
    st.clip.addEventListener('pointercancel', (e) => end(e, true));
    st.clip.addEventListener('click', (e) => {
      if (swallow) { swallow = false; return; }
      away(st);
      // A selection's own click: the mark bar has it (PLAYS-DESIGN §2.10).
      if (st.marks && st.marks.selecting()) return;
      const line = e.target.closest('.rd-line');
      // A tap on a mark opens it (§2.10 rule 6), unless the line is hidden (a tap there peeks).
      const hidden = st.hiding && line && line.classList.contains('rd-mine') && !line.classList.contains('rd-peek');
      if (!hidden && st.marks && st.marks.tap(e)) return;
      // The studio (PLAYS-DESIGN §2.9 rule 2): a tap on one of my lines makes it current, never a page turn.
      if (st.studio && st.studio.tap(e.target, line)) {
        if (st.hiding && line && line.classList.contains('rd-mine')) peek(st, line);
        return;
      }
      if (st.hiding && line && line.classList.contains('rd-mine')) { peek(st, line); return; }
      clearPeeks(st);
      if (st.prefs.layout !== 'pages') return;
      const sel = window.getSelection && window.getSelection();
      if (sel && String(sel).length) return;
      const r = st.clip.getBoundingClientRect();
      const z = R.tapZone(e.clientX - r.left, r.width);
      if (z !== 'middle') step(st, z === 'prev' ? -1 : 1);
    });
    st.stage.addEventListener('touchmove', () => away(st), { passive: true });
    st.stage.addEventListener('wheel', (e) => {
      if (st.prefs.layout !== 'pages') { away(st); return; }
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
    const { frag, lines, hues } = buildFlow(script);
    const flow = el('div', { class: 'rd-flow' });
    flow.append(frag);
    const clip = el('div', { class: 'rd-clip' }, flow);
    const heads = el('div', { class: 'rd-heads', 'aria-hidden': 'true' });
    const stage = el('div', { class: 'rd-stage', tabindex: '-1' }, el('div', { class: 'rd-heads-wrap' }, heads), clip);
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
    const markHost = el('div', { class: 'mk-host' });
    const hearBtn = el('button', { type: 'button', class: 'btn btn-ghost rd-tool rd-hear' });
    // Record (PLAYS-DESIGN §2.9 rule 1): with a part chosen, the studio opens here.
    const recBtn = el('button', { type: 'button', class: 'btn btn-ghost rd-tool rd-rec-btn', hidden: true, 'aria-label': 'Record' },
      svg('mic'), el('span', { class: 'rd-tool-lab' }, 'Record'));
    const root = el('div', { class: 'rd' });
    const side = el('aside', { class: 'st-side', 'aria-label': 'Studio', hidden: true });
    const footer = el('footer', { class: 'rd-bar rd-bottom' });
    // A production's studio reads the production's cast; the reader alone, the play's (§2.8 rule 2).
    const cast = opts.studio || (opts.along && opts.along.production) ? CastUI.castFor({ script, production: (opts.studio || opts.along).production }) : CastUI.castFor({ script });
    const st = { root, script, flow, clip, stage, heads, where, pageLab, nextBtn, hideBtn, hearBtn, recBtn, footer, side, lines, dock, prefs: prefsNow(),
                 onRecord: opts.onRecord || null, studio: null, partSel: null,
                 cast, voice: StandInVoice.create({ muted: muted(), cast }), ctl: null, tr: null, hues, word: null, wordMark: null,
                 pos: at, page: 0, per: 1, unit: 1, count: 1, starts: [], ends: [], part: null, hiding: false, peeked: null, fol: R.alongFollow(), along: null, backBtn: null, marks: null };
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
        iconBtn('voices', 'Voices', () => st.voices.showModal()),
        typeof Marks !== 'undefined' ? iconBtn('marks', 'Marks', () => st.marks && st.marks.openNotebook()) : null),
      el('div', { class: 'rd-main' }, el('div', { class: 'rd-col' }, stage, markHost, dock, footer), side),
      st.contents, st.search, st.text, st.voices);
    st.partSel = partSel;
    footer.append(el('label', { class: 'rd-part' }, partSel), hearBtn, recBtn, nextBtn, hideBtn, pageLab);
    recBtn.addEventListener('click', () => { if (st.part && st.onRecord) st.onRecord(st.part); });
    st.backBtn = el('button', { type: 'button', class: 'btn rd-back-line', hidden: true, onclick: () => st.handle.refollow() }, 'Back to the line');
    dock.after(st.backBtn);
    st.tr = transportEl(st);
    footer.append(st.tr.bar);
    if (opts.along) st.along = { production: opts.along.production, store: opts.along.store, dramaPlan: opts.along.dramaPlan || null };
    hearBtn.addEventListener('click', () => alongStart(st));
    paintTransport(st);
    st.voicesOff = StandInVoice.onVoices(() => { if (cur === st) paintTransport(st); });
    partSel.addEventListener('change', () => setPart(st, partSel.value));
    nextBtn.addEventListener('click', () => myLine(st, 1));
    hideBtn.addEventListener('click', () => setHiding(st, !st.hiding));
    container.replaceChildren(root);
    cur = st;
    applyPrefs(st);
    wire(st);
    document.addEventListener('keydown', onKey);
    window.addEventListener('keydown', onMyLineKey, true);
    const startPart = opts.studio ? opts.studio.part : opts.room ? null : saved.part;
    if (startPart && parts.some(p => p.id === startPart)) { partSel.value = startPart; setPart(st, startPart); }
    if (opts.studio && typeof Studio !== 'undefined') st.studio = Studio.attach(studioApi(st, opts), opts.studio);
    if (typeof Marks !== 'undefined') st.marks = Marks.attach(marksApi(st, markHost));
    if (st.marks) st.marks.draw();
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
    paintTransport(st);
    if (st.along) alongStart(st);
    if (opts.room) st.room = opts.room.attach(roomApi(st));
    st.key = opts.room ? `${script.id} room ${opts.room.code}` : opts.studio ? `${script.id} ${opts.studio.production} ${opts.studio.part}` : script.id;
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
        const o = st.fol.line(i < 0 ? null : id);
        paintBack(st, o.back);
        if (i < 0) return;
        st.lines[i].classList.add('rd-now');
        if (o.turn) followTo(st, i);
      },
      /** Back to following after a touch stopped it: to the line heard, and to the word. */
      refollow: () => {
        const id = st.fol.back();
        paintBack(st, false);
        const i = index(id);
        if (i < 0) return;
        followTo(st, i);
        if (st.word) alongWord(st, st.word.id, st.word.w);
      },
    };
  }

  function close() {
    if (!cur) return;
    document.removeEventListener('keydown', onKey);
    window.removeEventListener('keydown', onMyLineKey, true);
    if (cur.studio) cur.studio.detach();
    if (cur.room) cur.room.detach();
    if (cur.marks) cur.marks.detach();
    if (cur.ctl) cur.ctl.end();
    clearWord(cur);
    if (cur.voicesOff) cur.voicesOff();
    if (cur.resize) cur.resize.disconnect();
    if (document.fonts && cur.fontsDone) document.fonts.removeEventListener('loadingdone', cur.fontsDone);
    for (const d of cur.root.querySelectorAll('dialog[open]')) d.close();
    cur = null;
  }

  const openID = () => (cur ? cur.script.id : null);
  /** The open reader's script and studio, so a route to the same address does not open it again. */
  const openKey = () => (cur ? cur.key : null);

  /** What the marks (js/marks.js, PLAYS-DESIGN §2.10) may touch: the page's lines, a host for the bar, the sheets, going to a line. */
  function marksApi(st, barHost) {
    const ids = new Map(st.script.lines.map((l, i) => [l.id, i]));
    let storage = null;
    try { storage = window.localStorage; } catch { storage = null; }
    return {
      root: st.root, flow: st.flow, script: st.script, lines: st.lines, barHost, el, sheet, storage,
      index: (id) => (ids.has(id) ? ids.get(id) : -1),
      go: (id, flash = false) => { const i = ids.get(id); if (i !== undefined) goIndex(st, i, { flash }); },
      /** A point mark moves words: lay out again, keeping the first line that starts on this page on screen. */
      relayout: () => {
        if (st.prefs.layout !== 'pages') { layout(st, st.pos); return; }
        const i = st.starts.findIndex(p => p >= st.page);
        layout(st, i >= 0 ? i : st.pos);
      },
    };
  }

  /**
   * What the studio (js/studio.js, PLAYS-DESIGN §2.9) may touch: the page's lines, the dock and the
   * side column, the bottom bar, the sheets, going to and following a line. The reader keeps the page.
   */
  function studioApi(st, opts) {
    const index = (id) => st.script.lines.findIndex(l => l.id === id);
    return {
      root: st.root, script: st.script, cast: st.cast, voice: st.voice, dock: st.dock, side: st.side, footer: st.footer,
      hideBtn: st.hideBtn, pageLab: st.pageLab, el, svg, sheet, navigate: opts.navigate || null,
      line: (id) => st.lines[index(id)] || null,
      /** Goes to a line (turning the page to it) and, when asked, outlines it a moment. */
      go: (id, flash = false) => { const i = index(id); if (i >= 0) goIndex(st, i, { flash }); },
      /** The read-along: lights the line heard and keeps it in view while following; null clears it. */
      follow: (id) => st.handle && st.handle.follow(id),
      refollow: () => { st.fol.back(); paintBack(st, false); },
      relayout: () => layout(st, st.pos),
      /** In studio mode the bottom bar is the transport: I'm playing, Next line, Hear the cast and Record step aside. */
      studioMode: (on) => {
        st.root.classList.toggle('rd-studio', on);
        st.partSel.closest('.rd-part').hidden = on;
        st.hearBtn.hidden = on;
        st.recBtn.hidden = on || !st.part || !st.onRecord;
        st.nextBtn.hidden = on || !st.part;
        if (on && st.ctl) st.ctl.stop();
      },
    };
  }

  /**
   * What a read room (js/read-ui.js, WEB-DESIGN §4.17) may touch: the page's lines, the bars, the
   * dock, following the room's cursor, and which lines are mine (a room's parts, ranges included).
   */
  function roomApi(st) {
    const index = (id) => st.script.lines.findIndex(l => l.id === id);
    // No sound from a reader's device in a room (PLAYS-DESIGN §12.3): only the screen speaks.
    st.hearBtn.hidden = true;
    return {
      root: st.root, script: st.script, footer: st.footer, dock: st.dock, hideBtn: st.hideBtn, el, svg,
      follow: (id) => st.handle && st.handle.follow(id),
      refollow: () => st.handle && st.handle.refollow(),
      following: () => !st.backBtn || st.backBtn.hidden,
      line: (id) => st.lines[index(id)] || null,
      /** My lines by index (from the room, never the part select): tinted, Hide my lines offered. */
      setMine(indexes) {
        const mine = new Set(indexes);
        st.part = null;
        st.mine = [...mine].sort((a, b) => a - b);
        st.lines.forEach((n, i) => {
          const on = mine.has(i);
          n.classList.toggle('rd-mine', on);
          for (const sp of n.querySelectorAll('.rd-sp')) sp.classList.toggle('rd-mine', on);
        });
        const first = st.mine.length ? st.lines[st.mine[0]].querySelector('.rd-sp') : null;
        const hue = first ? first.dataset.hue : 'none';
        st.root.style.setProperty('--mine', !hue || hue === 'none' ? 'var(--color-text-muted)' : `var(--color-genre-${hue})`);
        st.partSel.closest('.rd-part').hidden = true;
        st.nextBtn.hidden = true;
        st.recBtn.hidden = true;
        st.hideBtn.hidden = !st.mine.length;
        if (!st.mine.length) setHiding(st, false); else paintHidden(st);
      },
      hideAllowed(on) { st.hideBtn.hidden = !on || !(st.mine || []).length; if (!on) setHiding(st, false); },
    };
  }

  return { open, close, openID, openKey };
})();
