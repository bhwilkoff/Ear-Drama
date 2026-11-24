/**
 * Adding a script and correcting it (WEB-DESIGN §4.21, PLAYS-DESIGN §13; Decision 088.3): the text, then
 * the parts page, and what an own script's page adds to a play's. The grammar and every change to a
 * line are OwnCore's; what is kept is OwnScripts'. The lines are drawn as the reader draws them.
 *
 * Every word on the page is the person's own; nothing here writes one.
 */
const OwnUI = (() => {
  'use strict';
  const O = OwnCore;
  const C = PlaysCore;
  const BLOCK = 50;

  const ICON = {
    close: 'M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z',
    back: 'M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z',
    undo: 'M12.5 8c-2.65 0-5.05 1-6.9 2.6L2 7v9h9l-3.62-3.62A8 8 0 0 1 20.15 15l2.37-.78A10.5 10.5 0 0 0 12.5 8z',
    paste: 'M19 3h-4.2a3 3 0 0 0-5.6 0H5a2 2 0 0 0-2 2v15a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zm-7 0a1 1 0 1 1 0 2 1 1 0 0 1 0-2zM7 8h10v2H7z',
    file: 'M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8zm-1 7V3.5L18.5 9z',
    plus: 'M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6z',
  };
  function svg(name, cls) {
    const ns = 'http://www.w3.org/2000/svg';
    const s = document.createElementNS(ns, 'svg');
    s.setAttribute('viewBox', '0 0 24 24');
    s.setAttribute('aria-hidden', 'true');
    if (cls) s.setAttribute('class', cls);
    const p = document.createElementNS(ns, 'path');
    p.setAttribute('d', ICON[name]);
    s.append(p);
    return s;
  }

  let h = null;
  let seq = 0;
  /** The page open now: `{ leave() }`. */
  let page = null;
  /** A file dropped on Record, waiting for the page that reads it. */
  let dropped = null;

  const $ = (id) => document.getElementById(id);
  const store = () => OwnScripts.shared();
  const num = new Intl.NumberFormat('en-US');
  const count = (n, one, many) => (n === 1 ? `1 ${one}` : `${num.format(n)} ${many}`);
  const partsAndLines = (parts, lines) => `${count(parts, 'part', 'parts')} · ${count(lines, 'line', 'lines')}`;
  const noPart = (n) => (n === 1 ? '1 line has no part' : `${num.format(n)} lines have no part`);
  /** Printed rows are kept for verse, as on the reader's page; a wrapped paragraph reflows. */
  const verse = (text) => (ReaderCore.isVerse([text]) ? ' os-verse' : '');
  const later = (fn, ms) => {
    let t = null;
    const go = () => { t = null; return fn(); };
    const f = () => { clearTimeout(t); t = setTimeout(go, ms); };
    f.flush = () => { if (t === null) return null; clearTimeout(t); return go(); };
    return f;
  };

  const REFUSAL = {
    too_long: 'That text is too long.', too_many_lines: 'That text is too long.', empty: 'There are no words.', bad_name: 'That name does not work.',
    line_has_take: 'This line has a take.', part_has_take: 'A line of this part has a take.', no_parts: 'No line has a part.', no_lines: 'No lines.',
    not_text: 'That is not a text file.', no_title: 'Add a title.', title_too_long: 'That title is too long.',
  };
  const say = (code) => REFUSAL[code] || 'That did not work.';
  /** Why a write failed, in essential words. */
  function notKept(err) {
    console.error(err);
    if (err && err.kind === 'blocked') return 'Close Ear Drama’s other tabs.';
    return err && err.name === 'QuotaExceededError' ? 'This browser is out of space.' : 'This browser could not save it.';
  }

  /* ---- The bar both pages wear (§4.21 item 1) ---- */

  function bar({ out, outLabel, onOut, titles, tools = [], primary }) {
    return h.el('header', { class: 'rd-bar rd-top os-bar' },
      h.el('button', { type: 'button', class: 'icon-btn rd-icon', 'aria-label': outLabel, title: outLabel, onclick: onOut }, svg(out)),
      h.el('div', { class: 'rd-titles' }, titles), tools, primary);
  }
  const goBack = (to) => { if (h.inApp()) history.back(); else h.navigate(to, true); };

  /** The plain-text file in a drop or a paste, if there is one. */
  const fileOf = (dt) => (dt && dt.files && dt.files.length ? dt.files[0] : null);
  const hasFiles = (dt) => !!dt && [...(dt.types || [])].includes('Files');
  /** Takes files dropped anywhere on `el`; without it the browser would leave the page for the file. */
  function onDrop(el, fn) {
    el.addEventListener('dragover', (e) => { if (hasFiles(e.dataTransfer)) { e.preventDefault(); e.dataTransfer.dropEffect = 'copy'; el.classList.add('os-drop'); } });
    el.addEventListener('dragleave', (e) => { if (!el.contains(e.relatedTarget)) el.classList.remove('os-drop'); });
    el.addEventListener('drop', (e) => {
      el.classList.remove('os-drop');
      const f = fileOf(e.dataTransfer);
      if (!f) return;
      e.preventDefault();
      fn(f);
    });
  }
  async function readFile(file) {
    if (file.size > 2 * O.MAX_BYTES + 2) return { refusal: 'too_long' };
    const got = OwnScripts.decode(await file.arrayBuffer());
    return got.refusal ? got : { text: got.text, title: file.name.replace(/\.[^.]*$/, '').slice(0, O.MAX_TITLE) };
  }

  /* ---- Add a script (§4.21 item 2) ---- */

  async function renderAdd(body, my) {
    h.setTitle('Add a script');
    $('own-h').textContent = 'Add a script';
    const title = h.el('input', { class: 'field-input', id: 'os-title', type: 'text', maxlength: String(O.MAX_TITLE), autocomplete: 'off', 'aria-describedby': 'os-err' });
    const text = h.el('textarea', { class: 'field-input os-text', id: 'os-text', 'aria-describedby': 'os-err' });
    const tally = h.el('span', { class: 'tabular' });
    const keptNote = h.el('span', {});
    const err = h.el('p', { class: 'caption refusal', role: 'alert', id: 'os-err' });
    const file = h.el('input', { type: 'file', id: 'os-file', class: 'sr-only', accept: '.txt,.fountain,.md,text/plain', tabindex: '-1', 'aria-hidden': 'true' });
    const next = h.el('button', { type: 'button', class: 'btn btn-primary os-next', disabled: true }, 'Next');
    let touched = false;
    let read = null;

    const refuse = (words) => { err.textContent = words; };
    const keep = later(async () => {
      try {
        await store().setDraft({ title: title.value, text: text.value });
        if (my === seq) keptNote.textContent = text.value ? 'Kept on this device' : '';
      } catch (e) { if (my === seq) { keptNote.textContent = ''; refuse(notKept(e)); } }
    }, 400);
    const tell = later(() => {
      const why = O.textRefusal(text.value);
      read = why ? null : O.parse(text.value);
      if (read && read.lines.length > O.MAX_LINES) { read = null; refuse(say('too_long')); } else refuse(why === 'too_long' ? say(why) : '');
      tally.textContent = read ? partsAndLines(read.parts.length, read.lines.length) : '';
      next.disabled = !read;
    }, 180);
    const changed = () => {
      touched = true;
      keptNote.textContent = '';
      if (!text.value.trim()) next.disabled = true;
      tell();
      keep();
    };
    const put = (t, name) => {
      text.value = t;
      if (name && !title.value.trim()) title.value = name;
      text.setSelectionRange(0, 0);
      text.scrollTop = 0;
      changed();
      tell.flush();
    };
    const open = async (f) => {
      let got;
      try { got = await readFile(f); } catch (e) { console.error(e); got = { refusal: 'not_text' }; }
      if (my !== seq) return;
      if (got.refusal) { refuse(got.refusal === 'too_long' ? 'That file is too long.' : say(got.refusal)); return; }
      // eslint-disable-next-line no-alert
      if (text.value.trim() && !confirm('Replace the text?')) return;
      put(got.text, got.title);
    };
    /** Text from the clipboard, at the insertion point, as the browser's own paste puts it. */
    const insert = (t) => {
      if (!t) return;
      text.setRangeText(t, text.selectionStart, text.selectionEnd, 'end');
      text.dispatchEvent(new Event('input'));
      text.focus();
    };

    title.addEventListener('input', () => { title.removeAttribute('aria-invalid'); changed(); });
    text.addEventListener('input', changed);
    file.addEventListener('change', () => { if (file.files[0]) open(file.files[0]); file.value = ''; });
    const onPaste = (e) => {
      const f = fileOf(e.clipboardData);
      if (f) { e.preventDefault(); open(f); return; }
      if (e.target === title || e.target === text) return;
      const t = e.clipboardData && e.clipboardData.getData('text/plain');
      if (t) { e.preventDefault(); insert(t); }
    };
    document.addEventListener('paste', onPaste);

    next.addEventListener('click', async () => {
      tell.flush();
      if (!read) return;
      if (!title.value.trim()) { title.setAttribute('aria-invalid', 'true'); refuse(say('no_title')); title.focus(); return; }
      next.disabled = true;
      try {
        const rec = await store().create({ title: title.value, text: text.value });
        if (navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(() => {});
        await store().setDraft(null).catch((e) => console.error(e));
        if (my !== seq) return;
        touched = false;
        h.navigate(`?script=${encodeURIComponent(rec.id)}&edit=parts`, true);
      } catch (e) { refuse(notKept(e)); next.disabled = false; }
    });

    const clip = navigator.clipboard && navigator.clipboard.readText;
    const view = h.el('div', { class: 'os' },
      bar({ out: 'close', outLabel: 'Close', onOut: () => goBack('?view=record'), titles: h.el('p', { class: 'body-strong rd-title' }, 'Add a script'), primary: next }),
      h.el('div', { class: 'os-add' },
        h.el('label', { class: 'caption', for: 'os-title' }, 'Title'), title,
        h.el('div', { class: 'os-text-head' }, h.el('label', { class: 'caption', for: 'os-text' }, 'Script'),
          h.el('span', { class: 'os-ways' },
            clip ? h.el('button', { type: 'button', class: 'btn btn-ghost', id: 'os-paste', onclick: async () => {
              try { insert(await navigator.clipboard.readText()); } catch (e) { console.error(e); text.focus(); refuse('This browser did not allow it.'); }
            } }, svg('paste'), 'Paste') : null,
            h.el('button', { type: 'button', class: 'btn btn-ghost', id: 'os-open', onclick: () => file.click() }, svg('file'), 'Open a file'), file)),
        text),
      h.el('footer', { class: 'os-foot' }, err, h.el('p', { class: 'caption os-count' }, tally, keptNote)));
    onDrop(view, open);
    body.replaceChildren(view);
    page = { leave() { document.removeEventListener('paste', onPaste); if (touched) keep.flush(); } };
    window.addEventListener('pagehide', keep.flush, { once: true });

    const f = dropped;
    dropped = null;
    let was = null;
    try { was = await store().draft(); } catch (e) { if (my === seq) refuse(notKept(e)); }
    if (my !== seq) return;
    if (was && !touched) { title.value = was.title || ''; text.value = was.text || ''; tell(); tell.flush(); if (text.value) keptNote.textContent = 'Kept on this device'; }
    if (f) open(f); else if (document.activeElement === $('own-h') || document.activeElement === document.body) (title.value ? text : title).focus({ preventScroll: true });
  }

  /* ---- The parts page (§4.21 items 3 to 6) ---- */

  async function renderParts(body, my, id) {
    h.setTitle('Parts');
    $('own-h').textContent = 'Parts';
    body.replaceChildren(h.stateBox('loading'));
    let rec, taken;
    try {
      rec = O.OWN_ID.test(id) ? await store().get(id) : null;
      taken = rec ? await store().takes(id) : [];
    } catch (err) {
      if (my !== seq) return;
      console.error(err);
      body.replaceChildren(h.stateBox('error', { retry: () => renderParts(body, my, id) }));
      return;
    }
    if (my !== seq) return;
    if (!rec) { body.replaceChildren(missing()); return; }
    rec.extras = rec.extras || [];
    h.setTitle(rec.title);
    $('own-h').textContent = rec.title;

    const P = { rec, takes: new Set(taken), nodes: new Map(), hues: new Map(), near: new Map(), cur: 0, more: false, edited: false };
    const env = () => ({ takes: [...P.takes] });
    const line = (k) => P.rec.doc.lines.find(l => l.k === k);
    const locked = (l) => !!(l && l.id && P.takes.has(l.id));
    const wide = () => matchMedia('(min-width: 860px)').matches;

    const titleText = h.el('span', { class: 'body-strong rd-title' });
    const where = h.el('span', { class: 'caption tabular rd-where' });
    const titleBtn = h.el('button', { type: 'button', class: 'os-title-btn', onclick: () => renameScript() }, titleText, where);
    const undoBtn = h.el('button', { type: 'button', class: 'icon-btn rd-icon', 'aria-label': 'Undo', title: 'Undo', onclick: () => undo() }, svg('undo'));
    const doneBtn = h.el('button', { type: 'button', class: 'btn btn-primary os-next', onclick: () => finish() }, 'Done');
    const problem = h.el('div', { class: 'os-problem', role: 'alert', hidden: true });
    const stripText = h.el('p', { class: 'body-strong os-strip-t' });
    const strip = h.el('div', { class: 'os-strip', hidden: true }, h.el('div', { class: 'os-strip-in' }, stripText,
      h.el('button', { type: 'button', class: 'btn btn-ghost os-strip-next', onclick: () => nextOpen() }, 'Next')));
    const chips = h.el('div', { class: 'os-chips', role: 'group', 'aria-label': 'Parts' });
    const list = h.el('div', { class: 'os-list', role: 'list', 'aria-label': 'Lines' });
    const none = h.el('div', { hidden: true }, h.stateBox('empty', { text: 'No lines.' }));
    const scroller = h.el('div', { class: 'os-scroll' }, h.el('div', { class: 'os-page' }, chips, list, none));
    const sheets = h.el('div');
    body.replaceChildren(h.el('div', { class: 'os' },
      bar({ out: 'back', outLabel: 'Back', onOut: () => goBack(rec.done ? `?play=${encodeURIComponent(id)}` : '?view=record'), titles: titleBtn, tools: [undoBtn], primary: doneBtn }),
      problem, strip, scroller, sheets));

    /* ---- What is kept ---- */

    async function write() {
      try {
        await store().keep(P.rec);
        problem.hidden = true;
        problem.replaceChildren();
        return true;
      } catch (err) {
        if (my !== seq) { console.error(err); return false; }
        problem.replaceChildren(h.el('span', { class: 'body' }, notKept(err)), h.el('button', { type: 'button', class: 'btn', onclick: () => write() }, 'Try again'));
        problem.hidden = false;
        return false;
      }
    }
    const save = later(write, 350);

    /* ---- Drawing: only what changed (item 4) ---- */

    function partsNow() {
      const at = new Map();
      const ps = O.partsOf(P.rec.doc.lines);
      ps.forEach((p, i) => at.set(p.name, i));
      ps.sort((a, b) => b.lines - a.lines || at.get(a.name) - at.get(b.name));
      return [...ps, ...P.rec.extras.filter(n => !at.has(n)).map(name => ({ name, lines: 0 }))];
    }
    const hue = (name) => P.hues.get(`role:${name}`) || 'none';
    const asScript = (l) => (l.kind === 'speech' ? { id: `os-l${l.k}`, kind: 'speech', role: l.role, parts: O.pieces(l.text) }
      : { id: `os-l${l.k}`, kind: l.kind === 'open' ? 'direction' : l.kind, source: l.text });

    function chip(name, attrs, n = null) {
      return h.el('button', { type: 'button', class: 'os-chip', dataset: { hue: hue(name) }, ...attrs }, h.el('i', { class: 'os-dot', 'aria-hidden': 'true' }),
        h.el('span', { class: 'body-strong' }, name), n === null ? null : h.el('span', { class: 'tabular os-n' }, num.format(n)));
    }
    const plain = (text, attrs) => h.el('button', { type: 'button', class: 'os-chip os-plain', ...attrs }, text);

    function fill(item, l) {
      const on = l.k === P.cur ? '0' : '-1';
      const press = h.el('div', { class: 'os-line', role: 'button', tabindex: on, dataset: { open: String(l.k) } });
      if (l.kind === 'open') {
        press.append(h.el('span', { class: 'caption os-nopart' }, 'No part'), h.el('span', { class: `os-words${verse(l.text)}` }, l.text));
        item.className = 'os-item os-open';
        item.replaceChildren(press, h.el('div', { class: 'os-acts' },
          (P.near.get(l.k) || []).map(name => chip(name, { tabindex: on, dataset: { hue: hue(name), k: String(l.k), role: name }, 'aria-label': `Give to ${name}` })),
          plain('Direction', { tabindex: on, dataset: { k: String(l.k), kind: 'direction' } }),
          plain('More', { tabindex: on, dataset: { more: String(l.k) } })));
      } else {
        press.append(Reader.drawLine(asScript(l), P.hues, []));
        item.className = 'os-item';
        item.replaceChildren(press);
      }
    }

    /** A speech whose words stand and only its part's name or hue changed: those alone are written again. */
    function rename(n, l) {
      if (l.kind !== 'speech' || !n.line || n.line.kind !== 'speech' || n.line.text !== l.text) return false;
      const sp = n.el.querySelectorAll('.rd-sp');
      const name = n.el.querySelector('.rd-name');
      if (sp.length !== 1 || !name || name.dataset.at) return false;
      name.textContent = l.role;
      for (const x of [sp[0], n.el.querySelector('.rd-line')]) { x.dataset.part = `role:${l.role}`; x.dataset.hue = hue(l.role); }
      return true;
    }

    function draw() {
      const lines = P.rec.doc.lines;
      const ps = partsNow();
      const hues = new Map(ps.filter(p => p.lines).map((p, i) => [`role:${p.name}`, C.PART_HUES[i] || 'none']));
      const moved = new Set([...hues].filter(([p, x]) => P.hues.get(p) !== x).map(([p]) => p));
      P.hues = hues;
      const near = OwnScripts.nearestAll(lines);
      const was = P.near;
      P.near = near;
      const keep = new Set(lines.map(l => l.k));
      for (const [k, n] of P.nodes) if (!keep.has(k)) { n.el.remove(); P.nodes.delete(k); }
      if (!keep.has(P.cur)) P.cur = lines.length ? lines[0].k : 0;
      let prev = null;
      let fresh = null;
      for (const l of lines) {
        let n = P.nodes.get(l.k);
        if (!n) {
          n = { el: h.el('div', { role: 'listitem', dataset: { k: String(l.k) } }), line: null };
          P.nodes.set(l.k, n);
          if (prev) {
            if (prev.el.parentNode.childElementCount >= BLOCK && prev.el === prev.el.parentNode.lastElementChild) {
              fresh = h.el('div', { class: 'os-block', role: 'presentation' }, n.el);
              prev.el.parentNode.after(fresh);
            } else prev.el.after(n.el);
          } else if (list.firstElementChild) list.firstElementChild.prepend(n.el);
          else list.append(h.el('div', { class: 'os-block', role: 'presentation' }, n.el));
        }
        const nearNow = l.kind === 'open' ? near.get(l.k).join('\n') : '';
        const stale = n.line !== l || (l.kind === 'speech' && moved.has(`role:${l.role}`))
          || (l.kind === 'open' && ((was.get(l.k) || []).join('\n') !== nearNow || near.get(l.k).some(r => moved.has(`role:${r}`))));
        if (stale) { if (!rename(n, l)) fill(n.el, l); n.line = l; }
        prev = n;
      }
      for (const b of [...list.children]) if (!b.childElementCount) b.remove();
      none.hidden = lines.length > 0;
      const open = lines.filter(l => l.kind === 'open').length;
      titleText.textContent = P.rec.title;
      where.textContent = partsAndLines(ps.filter(p => p.lines).length, lines.length);
      titleBtn.setAttribute('aria-label', `Title: ${P.rec.title}, ${where.textContent}`);
      undoBtn.disabled = !P.rec.doc.undo.length;
      strip.hidden = open === 0;
      stripText.textContent = noPart(open);
      const show = P.more ? ps.length : Math.min(ps.length, wide() ? 8 : 4);
      const hadChip = chips.contains(document.activeElement) ? document.activeElement.dataset.part || document.activeElement.dataset.act : null;
      chips.replaceChildren(...ps.slice(0, show).map(p => chip(p.name, { dataset: { hue: hue(p.name), part: p.name }, onclick: () => partSheet(p.name) }, p.lines)),
        ...(ps.length > show ? [plain(`${num.format(ps.length - show)} more`, { dataset: { act: 'more' }, onclick: () => { P.more = true; draw(); } })] : []),
        h.el('button', { type: 'button', class: 'os-chip os-plain', dataset: { act: 'part' }, onclick: () => newPart() }, svg('plus', 'i-inline'), 'Part'));
      if (hadChip) { const b = [...chips.children].find(x => x.dataset.part === hadChip || x.dataset.act === hadChip); if (b) b.focus(); }
    }

    /* ---- One line is current: the list is one tab stop (item 6) ---- */

    function setCur(k) {
      if (P.cur === k) return;
      for (const [x, t] of [[P.cur, '-1'], [k, '0']]) {
        const n = P.nodes.get(x);
        if (n) n.el.querySelectorAll('[tabindex]').forEach(b => { b.tabIndex = Number(t); });
      }
      P.cur = k;
    }
    /** Moves the page's own scroller only: scrollIntoView moves everything that can scroll above it too. */
    function reveal(el, center) {
      const s = scroller.getBoundingClientRect(), r = el.getBoundingClientRect();
      if (center) scroller.scrollTop += r.top - s.top - Math.max(8, (s.height - r.height) / 2);
      else if (r.top < s.top + 8) scroller.scrollTop += r.top - s.top - 8;
      else if (r.bottom > s.bottom - 8) scroller.scrollTop += Math.min(r.bottom - s.bottom + 8, r.top - s.top - 8);
    }
    function focusLine(k, center = false) {
      const n = P.nodes.get(k);
      if (!n) return;
      setCur(k);
      const b = n.el.querySelector('.os-line');
      b.focus({ preventScroll: true });
      reveal(n.el, center);
      // A block drawn for the first time takes its real height after this frame.
      requestAnimationFrame(() => { if (n.el.isConnected) reveal(n.el, center); });
    }
    const index = (k) => P.rec.doc.lines.findIndex(l => l.k === k);
    function nextOpen() {
      const lines = P.rec.doc.lines;
      const from = P.edited || P.cur !== (lines[0] && lines[0].k) ? index(P.cur) : -1;
      const at = [...lines.keys()].map(i => (from + 1 + i + lines.length) % lines.length).find(i => lines[i].kind === 'open');
      if (at !== undefined) focusLine(lines[at].k, true);
    }
    list.addEventListener('focusin', (e) => { const it = e.target.closest('[data-k]'); if (it && it.getAttribute('role') === 'listitem') setCur(Number(it.dataset.k)); });
    list.addEventListener('click', (e) => {
      const b = e.target.closest('button');
      if (b && b.dataset.role) { give(Number(b.dataset.k), { role: b.dataset.role }); return; }
      if (b && b.dataset.kind) { give(Number(b.dataset.k), b.dataset.kind); return; }
      if (b && b.dataset.more) { lineSheet(Number(b.dataset.more)); return; }
      const l = e.target.closest('[data-open]');
      if (!l) return;
      // A selection being made is not a tap.
      const sel = getSelection();
      if (sel && !sel.isCollapsed && l.contains(sel.anchorNode)) return;
      lineSheet(Number(l.dataset.open));
    });
    list.addEventListener('keydown', (e) => {
      const l = e.target.closest('[data-open]');
      if (!l || e.metaKey || e.ctrlKey || e.altKey) return;
      const lines = P.rec.doc.lines;
      const i = index(Number(l.dataset.open));
      const to = { ArrowDown: i + 1, ArrowUp: i - 1, Home: 0, End: lines.length - 1 }[e.key];
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); lineSheet(lines[i].k); } else if (to !== undefined) {
        e.preventDefault();
        if (lines[to]) focusLine(lines[to].k);
      }
    });
    const onKey = (e) => {
      if ((e.metaKey || e.ctrlKey) && !e.shiftKey && !e.altKey && e.key.toLowerCase() === 'z'
          && !document.querySelector('dialog[open]') && !e.target.closest('input, textarea')) { e.preventDefault(); undo(); }
    };
    document.addEventListener('keydown', onKey);

    /* ---- Changes ---- */

    /** One change: drawn, kept, announced; the refusal's words when it is not allowed. */
    function change(op, spoken) {
      const r = O.apply(P.rec.doc, op, env());
      if (r.refusal) return say(r.refusal);
      if (r.doc !== P.rec.doc) {
        P.rec.doc = r.doc;
        P.edited = true;
        draw();
        save();
        if (spoken) h.announce(spoken);
      }
      return null;
    }
    function give(k, to) {
      const why = change({ op: 'assign', line: k, to }, typeof to === 'object' ? to.role : KIND_WORD[to]);
      if (why) h.announce(why);
      focusLine(k);
    }
    const KIND_WORD = { direction: 'Direction', sound: 'Sound', music: 'Music' };
    function undo() { if (!change({ op: 'undo' }, 'Undone') && P.cur) focusLine(P.cur); }

    async function finish() {
      doneBtn.disabled = true;
      const doc = O.done(P.rec.doc);
      const why = O.refusalOf(O.toScript(doc, { id, title: P.rec.title }));
      if (why) {
        problem.replaceChildren(h.el('span', { class: 'body' }, why === 'too_long' || why === 'too_many_lines' ? 'This script is too long.' : say(why)));
        problem.hidden = false;
        doneBtn.disabled = false;
        return;
      }
      const before = P.rec.doc;
      const wasDone = P.rec.done;
      P.rec.doc = doc;
      P.rec.done = true;
      save.flush();
      if (!(await write())) { P.rec.doc = before; P.rec.done = wasDone; doneBtn.disabled = false; return; }
      if (my !== seq) return;
      if (wasDone && h.inApp()) history.back(); else h.navigate(`?play=${encodeURIComponent(id)}`, true);
    }

    /* ---- The sheets: one native dialog at a time (item 5) ---- */

    /** While a sheet is open the page behind it is inert: its far blocks rest, so opening one costs a phone 60 ms and not 300. */
    function rest(on) {
      const s = scroller.getBoundingClientRect();
      for (const b of list.children) {
        const r = on ? b.getBoundingClientRect() : null;
        b.classList.toggle('os-far', on && (r.bottom < s.top - s.height || r.top > s.bottom + s.height));
      }
    }
    function sheet(label, cls, after) {
      const d = h.el('dialog', { class: `os-sheet ${cls}`, 'aria-label': label });
      d.addEventListener('close', () => { d.remove(); rest(false); if (after) after(); });
      rest(true);
      // A tap on the backdrop closes it, as a sheet does; never over words being typed.
      d.addEventListener('click', (e) => { if (e.target === d && !d.querySelector('.os-edit')) d.close(); });
      sheets.append(d);
      return d;
    }
    const inner = (d, ...kids) => { d.replaceChildren(h.el('div', { class: 'os-sheet-in' }, ...kids)); };
    const closeBtn = (d) => h.el('button', { type: 'button', class: 'icon-btn os-sheet-x', 'aria-label': 'Close', onclick: () => d.close() }, svg('close'));

    /** A name field with one button: rename, a new part, the title. `act(value)` answers a refusal's words or null. */
    function nameForm({ label, value = '', button, max, act, hint = null }) {
      const err = h.el('p', { class: 'caption refusal', role: 'alert' });
      const field = h.el('input', { class: 'field-input', type: 'text', value, maxlength: String(max), autocomplete: 'off', 'aria-label': label, placeholder: hint });
      return h.el('form', { class: 'os-form', onsubmit: (e) => {
        e.preventDefault();
        err.textContent = act(field.value) || '';
        if (err.textContent) field.focus();
      } }, h.el('div', { class: 'os-form-row' }, field, h.el('button', { type: 'submit', class: 'btn' }, button)), err);
    }

    function renameScript() {
      const d = sheet('Title', 'os-small', () => titleBtn.focus());
      inner(d, h.el('div', { class: 'os-sheet-head' }, h.el('h2', { class: 'section-header' }, 'Title'), closeBtn(d)),
        nameForm({ label: 'Title', value: P.rec.title, button: 'Save', max: O.MAX_TITLE, act: (v) => {
          const t = O.trim(O.normalize(v));
          if (!t) return say('no_title');
          P.rec.title = t;
          h.setTitle(t);
          draw();
          save();
          d.close();
          return null;
        } }));
      d.showModal();
    }
    /** A part named before any line is given to it (it lives in the sheets' lists until one is). */
    function addExtra(v) {
      const name = O.partName(O.normalize(v));
      const why = O.partNameRefusal(name);
      if (why) return { why: why === 'too_long' ? 'That name is too long.' : why === 'empty' ? 'Add a name.' : say(why) };
      if (!partsNow().some(p => p.name === name)) P.rec.extras.push(name);
      return { name };
    }
    function newPart() {
      const d = sheet('New part', 'os-small', () => { const b = chips.querySelector('[data-act=part]'); if (b) b.focus(); });
      inner(d, h.el('div', { class: 'os-sheet-head' }, h.el('h2', { class: 'section-header' }, 'New part'), closeBtn(d)),
        nameForm({ label: 'Name', button: 'Add', max: O.MAX_PART_NAME, act: (v) => {
          const got = addExtra(v);
          if (got.why) return got.why;
          P.more = true;
          draw();
          save();
          d.close();
          return null;
        } }));
      d.showModal();
    }
    function partSheet(name) {
      const d = sheet(name, 'os-small', () => { const b = [...chips.children].find(x => x.dataset.part === name) || chips.firstElementChild; if (b) b.focus(); });
      const mine = P.rec.doc.lines.filter(l => l.kind === 'speech' && l.role === name);
      const head = h.el('div', { class: 'os-sheet-head' }, h.el('h2', { class: 'section-header os-part-h', dataset: { hue: hue(name) } }, name), closeBtn(d));
      if (mine.some(locked)) inner(d, head, h.el('p', { class: 'caption refusal' }, say('part_has_take')));
      else if (!mine.length) {
        inner(d, head, h.el('div', { class: 'actions' }, h.el('button', { type: 'button', class: 'btn', onclick: () => {
          P.rec.extras = P.rec.extras.filter(n => n !== name);
          draw();
          save();
          d.close();
        } }, 'Leave out')));
      } else {
        const err = h.el('p', { class: 'caption refusal', role: 'alert' });
        const act = (op, spoken) => { const why = change(op, spoken); if (why) err.textContent = why; else d.close(); return why; };
        const others = partsNow().filter(p => p.name !== name);
        inner(d, head,
          nameForm({ label: 'Name', value: name, button: 'Rename', max: O.MAX_PART_NAME, act: (v) => {
            const to = O.partName(O.normalize(v));
            const why = O.partNameRefusal(to);
            if (why) return why === 'too_long' ? 'That name is too long.' : why === 'empty' ? 'Add a name.' : say(why);
            return act({ op: 'rename', part: name, to: v }, to);
          } }),
          others.length ? h.el('p', { class: 'caption os-lab' }, 'Join to') : null,
          others.length ? h.el('div', { class: 'os-acts' }, others.map(p => chip(p.name, { 'aria-label': `Join to ${p.name}`, onclick: () => act({ op: 'rename', part: name, to: p.name }, p.name) }, p.lines))) : null,
          h.el('div', { class: 'actions' }, h.el('button', { type: 'button', class: 'btn', onclick: () => act({ op: 'notPart', part: name }, 'No part') }, 'Not a part')), err);
      }
      d.showModal();
    }

    function lineSheet(k) {
      const l = line(k);
      if (!l) return;
      setCur(k);
      let back = k;
      const d = sheet('Line', 'os-line-sheet', () => { if (my === seq) focusLine(back); });
      const err = h.el('p', { class: 'caption refusal', role: 'alert' });
      /** Does it and closes; a refusal stays in the sheet. `to` is the line the focus goes to. */
      const act = (op, spoken, to) => {
        const i = index(k);
        const had = new Set(P.rec.doc.lines.map(x => x.k));
        const above = i > 0 ? P.rec.doc.lines[i - 1].k : null;
        const below = P.rec.doc.lines[i + 1] ? P.rec.doc.lines[i + 1].k : null;
        const why = change(op, spoken);
        if (why) { err.textContent = why; return; }
        const made = P.rec.doc.lines.find(x => !had.has(x.k));
        back = to === 'made' && made ? made.k : to === 'above' ? above : to === 'next' ? below || above : k;
        d.close();
      };
      const edit = () => {
        const field = h.el('textarea', { class: 'field-input os-edit', 'aria-label': 'Words' });
        field.value = l.text;
        inner(d, field, h.el('div', { class: 'os-four' },
          h.el('button', { type: 'button', class: 'btn btn-primary', onclick: () => act({ op: 'words', line: k, text: field.value }, 'Words changed') }, 'Save'),
          h.el('button', { type: 'button', class: 'btn', onclick: () => d.close() }, 'Cancel')), err);
        field.focus();
        field.setSelectionRange(0, 0);
      };
      const btn = (text, onclick, attrs = {}) => h.el('button', { type: 'button', class: 'btn', onclick, ...attrs }, text);
      const top = h.el('div', { class: 'os-sheet-head os-sheet-top' }, closeBtn(d));
      if (locked(l)) {
        inner(d, top, h.el('p', { class: `os-cutline${verse(l.text)}` }, l.text), h.el('p', { class: 'caption refusal' }, say('line_has_take')), h.el('div', { class: 'os-four' }, btn('Edit words', edit)), err);
        d.showModal();
        return;
      }
      const split = btn('Split here', () => act({ op: 'split', line: k, at: cut.at() }, 'Split', 'made'), { class: 'btn btn-way', disabled: true });
      const cut = cutter(l.text, (at) => { split.disabled = at < 0; });
      const ps = partsNow();
      const near = [...new Set([l.role, ...(P.near.get(k) || O.nearestParts(P.rec.doc.lines, index(k)))].filter(Boolean))];
      const rest = ps.map(p => p.name).filter(n => !near.includes(n));
      const all = ps.length <= 6;
      const partChip = (name) => chip(name, { 'aria-pressed': l.kind === 'speech' && l.role === name ? 'true' : 'false', onclick: () => act({ op: 'assign', line: k, to: { role: name } }, name) });
      const kindChip = (kind) => plain(KIND_WORD[kind], { 'aria-pressed': l.kind === kind ? 'true' : 'false', onclick: () => act({ op: 'assign', line: k, to: kind }, KIND_WORD[kind]) });
      const field = () => nameForm({ label: 'New part', hint: 'New part', button: 'Give', max: O.MAX_PART_NAME, act: (v) => {
        const got = addExtra(v);
        if (got.why) return got.why;
        act({ op: 'assign', line: k, to: { role: got.name } }, got.name);
        return null;
      } });
      const more = h.el('div', { class: 'os-more' });
      const partsBox = h.el('div', { class: 'os-acts' }, [...near, ...(all ? rest : [])].map(partChip),
        plain('All parts', { 'aria-expanded': 'false', onclick: (e) => {
          const b = e.currentTarget;
          b.replaceWith(...(all ? [] : rest.map(partChip)));
          const f = field();
          more.append(f);
          (all ? f.querySelector('input') : partsBox.children[near.length]).focus();
        } }), ['direction', 'sound', ...(l.kind === 'music' ? ['music'] : [])].map(kindChip));
      if (all) partsBox.querySelector('[aria-expanded]').textContent = 'New part';
      inner(d, top, cut.node, partsBox, more,
        h.el('div', { class: 'os-four' },
          cut.places ? split : null,
          index(k) > 0 ? btn('Join to line above', () => act({ op: 'join', line: k }, 'Joined', 'above'), { class: 'btn btn-way' }) : null,
          btn('Edit words', edit), btn('Leave out', () => act({ op: 'leaveOut', line: k }, 'Left out', 'next'))), err);
      d.showModal();
      if (cut.places) cut.node.focus();
    }

    /** The words with a place to cut: a slider over the gaps between them (item 5). */
    function cutter(text, onMove) {
      const words = [...text.matchAll(/\S+/g)].map(m => ({ at: m.index, end: m.index + m[0].length }));
      let gap = 0;
      let at = -1;
      const places = words.length > 1;
      const node = h.el('p', { class: `os-cutline${verse(text)}`, ...(places ? { role: 'slider', tabindex: '0', 'aria-label': 'Cut', 'aria-valuemin': '0',
        'aria-valuemax': String(words.length - 1), 'aria-valuenow': '0', 'aria-valuetext': 'None' } : {}) });
      function paint() {
        const kids = [];
        words.forEach((w, i) => {
          const till = i + 1 < words.length ? words[i + 1].at : text.length;
          const span = h.el('span', { class: 'os-w', dataset: { i: String(i) } });
          if (at > w.at && at < till && at < w.end) span.append(text.slice(w.at, at), h.el('span', { class: 'os-cut', 'aria-hidden': 'true' }), text.slice(at, till));
          else span.append(...(at === w.at ? [h.el('span', { class: 'os-cut', 'aria-hidden': 'true' })] : []), text.slice(w.at, till));
          kids.push(span);
        });
        node.replaceChildren(...(words.length ? kids : [text]));
      }
      function place(g) {
        const to = Math.max(0, Math.min(words.length - 1, g));
        const p = to > 0 ? O.cutAt(text, words[to].at) : -1;
        gap = to;
        at = p;
        node.setAttribute('aria-valuenow', String(to));
        node.setAttribute('aria-valuetext', p < 0 ? 'None' : `${words.slice(Math.max(0, to - 3), to).map(w => text.slice(w.at, w.end)).join(' ')} | ${words.slice(to, to + 3).map(w => text.slice(w.at, w.end)).join(' ')}`);
        paint();
        onMove(at);
      }
      paint();
      if (places) {
        node.addEventListener('click', (e) => {
          const w = e.target.closest('.os-w');
          if (!w) return;
          const i = Number(w.dataset.i);
          const r = [...w.getClientRects()].find(x => e.clientY >= x.top && e.clientY <= x.bottom) || w.getBoundingClientRect();
          place(e.clientX > r.left + r.width / 2 ? i + 1 : i);
        });
        node.addEventListener('keydown', (e) => {
          const to = { ArrowRight: gap + 1, ArrowUp: gap + 1, ArrowLeft: gap - 1, ArrowDown: gap - 1, PageUp: gap + 10, PageDown: gap - 10, Home: 1, End: words.length - 1 }[e.key];
          if (to === undefined) return;
          e.preventDefault();
          place(to);
        });
      }
      return { node, places, at: () => at };
    }

    /* ---- Shown ---- */

    P.cur = P.rec.doc.lines.length ? P.rec.doc.lines[0].k : 0;
    draw();
    // A take recorded in another tab locks its line here too.
    const onShow = async () => { if (document.visibilityState === 'visible') try { P.takes = new Set(await store().takes(id)); } catch (e) { console.error(e); } };
    document.addEventListener('visibilitychange', onShow);
    const onHide = () => { save.flush(); };
    window.addEventListener('pagehide', onHide);
    page = { leave() {
      document.removeEventListener('keydown', onKey);
      document.removeEventListener('visibilitychange', onShow);
      window.removeEventListener('pagehide', onHide);
      sheets.querySelectorAll('dialog[open]').forEach(d => d.close());
      save.flush();
    } };
  }

  const missing = () => h.stateBox('empty', { text: 'This script is not in this browser.', action: { label: 'Record', href: '?view=record' } });

  /* ---- An own script's page (§4.21 item 7): what a play's page has and this adds ---- */

  /** A script's page before its Done: the parts page finishes it; nothing here says it is not in this browser. */
  async function notDone(body, helpers, id) {
    h = helpers;
    body.replaceChildren(h.stateBox('loading'));
    try {
      if (O.OWN_ID.test(id) && await store().get(id)) { h.navigate(`?script=${encodeURIComponent(id)}&edit=parts`, true); return; }
      body.replaceChildren(missing());
    } catch (err) {
      console.error(err);
      body.replaceChildren(h.stateBox('error', { retry: () => notDone(body, helpers, id) }));
    }
  }

  function foot(script, helpers) {
    h = helpers;
    const err = h.el('p', { class: 'caption refusal', role: 'alert' });
    const del = h.el('button', { type: 'button', class: 'btn btn-destructive', onclick: async () => {
      try {
        const made = await store().productions(script.id);
        // eslint-disable-next-line no-alert
        if (!confirm(`Delete ${script.title}?${made.length ? ' Its productions keep their copy.' : ''}`)) return;
        del.disabled = true;
        await store().remove(script.id);
        // Their productions still read in these; with none left nothing can.
        if (!made.length) {
          VoiceCast.forget(VoiceCast.scriptKey(script.id));
          try { MarksCore.save(localStorage, script, []); } catch { /* storage blocked: there were none */ }
        }
        h.announce('Deleted');
        h.navigate('?view=record', true);
      } catch (e) { console.error(e); err.textContent = 'This browser could not delete it.'; del.disabled = false; }
    } }, 'Delete');
    return h.el('section', { class: 'os-own' },
      h.el('p', { class: 'caption' }, 'Added by you · Kept on this device'),
      h.el('p', { class: 'caption' }, 'This script can’t be published.'),
      h.el('div', { class: 'actions' },
        h.el('a', { class: 'btn', href: `?script=${encodeURIComponent(script.id)}&edit=parts` }, 'Edit'),
        h.el('button', { type: 'button', class: 'btn', onclick: () => DataExport.save(OwnScripts.fileName(script.title), 'text/plain;charset=utf-8', OwnScripts.asText(script)) }, 'Save as text'),
        del), err);
  }

  /* ---- Your scripts: Record's section and Search's (§4.15 item 1a, §4.6) ---- */

  const rowFacts = (row) => (!row.done && row.open ? noPart(row.open) : partsAndLines(row.parts, row.lines));
  const rowHref = (row) => (row.done ? `?play=${encodeURIComponent(row.id)}` : `?script=${encodeURIComponent(row.id)}&edit=parts`);
  function scriptRow(row, helpers) {
    const el = helpers.el;
    return el('li', { class: 'series-row g-row ear-drama-only' }, el('a', { class: 'g-link', href: rowHref(row) },
      helpers.playWindow({ title: row.title, cast: row.cast, voices: row.voices }),
      el('span', { class: 'g-text' }, el('span', { class: 'ep-title body-strong' }, row.title), el('span', { class: 'ep-sub caption tabular' }, rowFacts(row)))));
  }
  /** Record's section, or null with none; a store that will not open says so where the rows would be. */
  async function yours(helpers) {
    h = h || helpers;
    let rows;
    try { rows = await store().list(); } catch (err) {
      console.error(err);
      if (err && err.kind === 'blocked') return helpers.el('p', { class: 'caption refusal' }, notKept(err));
      return null;
    }
    if (!rows.length) return null;
    return helpers.el('section', { class: 'block', 'aria-labelledby': 'own-list-h' }, helpers.el('h2', { class: 'section-header', id: 'own-list-h' }, 'Your scripts'),
      helpers.el('ul', { class: 'series-list' }, rows.map(r => scriptRow(r, helpers))));
  }
  const matching = async (words) => (await store().list()).filter(r => { const have = API.tokens(r.title); return words.every(w => have.some(x => x.startsWith(w))); });
  const addLink = (helpers, cls = 'btn btn-ghost') => helpers.el('a', { class: `${cls} ear-drama-only os-add-link`, href: '?view=record&add=1' }, svg('plus'), 'Add a script');
  /** A text file dropped on Record opens the page that reads it. */
  function dropOn(el, helpers) { onDrop(el, (f) => { dropped = f; helpers.navigate('?view=record&add=1'); }); }

  /* ---- The router's doors ---- */

  function leave() {
    seq += 1;
    const p = page;
    page = null;
    if (p) p.leave();
  }
  function render(r, helpers) {
    leave();
    h = helpers;
    const my = seq;
    const body = $('own-body');
    const id = r.p.get('script');
    if (id) return renderParts(body, my, id);
    return renderAdd(body, my);
  }

  return { render, leave, notDone, foot, yours, scriptRow, matching, addLink, dropOn };
})();
