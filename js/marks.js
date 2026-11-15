/**
 * Marks on the reader's page (WEB-DESIGN §4.16 item 15, PLAYS-DESIGN §2.10; Decision 076 S5). The
 * owner, 2026-11-14: "You should be able to read a script and turn pages and mark them up..."
 *
 * The reader keeps the page; this file draws the person's marks on it and offers the mark bar and the
 * notebook. What a selection makes, how marks merge, and where a revision puts them are MarksCore's
 * (js/marks-core.js, tested without a DOM). Highlights, underlines and a note's rule are painted with
 * the CSS Custom Highlight API, so the page's text and layout never change for them; a breath, pause,
 * beat or a note's glyph is an empty inline element whose glyph is drawn by CSS, so no character ever
 * joins the script's words and every run's data-at offset stays true.
 */
const Marks = (() => {
  'use strict';
  const MC = MarksCore;
  const HL = typeof CSS !== 'undefined' && !!CSS.highlights && typeof Highlight === 'function';
  const NAMES = [...MC.HUES.map(h => `ed-mk-${h}`), 'ed-mk-under', 'ed-mk-note'];
  const KEYS = { h: 'highlight', u: 'underline', '/': 'breath', p: 'pause', b: 'beat', n: 'note' };
  const LABEL = { highlight: 'Highlight', underline: 'Underline', breath: 'Breath', pause: 'Pause', beat: 'Beat', note: 'Note' };
  const KEY_OF = { highlight: 'H', underline: 'U', breath: '/', pause: 'P', beat: 'B', note: 'N' };
  const ICON = {
    underline: 'M12 17a6 6 0 0 0 6-6V3h-2.5v8a3.5 3.5 0 0 1-7 0V3H6v8a6 6 0 0 0 6 6zm-7 2v2h14v-2H5z',
    breath: 'M14.6 3h2.2L9.4 21H7.2z',
    pause: 'M10.1 3h2.2L4.9 21H2.7zm9 0h2.2l-7.4 18h-2.2z',
    beat: 'M7.1 3h2.2L3.9 17H1.7zm6 0h2.2L9.9 17H7.7zM13 19h9v2h-9z',
    note: 'M19 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10l6-6V5a2 2 0 0 0-2-2zM7 8h10v2H7V8zm0 4h7v2H7v-2zm7 7v-5h5l-5 5z',
    trash: 'M6 19a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z',
    edit: 'M3 17.25V21h3.75L17.8 9.94l-3.75-3.75L3 17.25zM20.7 7.04a1 1 0 0 0 0-1.41l-2.34-2.34a1 1 0 0 0-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z',
    warn: 'M1 21h22L12 2zm12-3h-2v-2h2zm0-4h-2v-4h2z',
  };

  function icon(name) {
    const ns = 'http://www.w3.org/2000/svg';
    const s = document.createElementNS(ns, 'svg');
    s.setAttribute('viewBox', '0 0 24 24');
    s.setAttribute('aria-hidden', 'true');
    const p = document.createElementNS(ns, 'path');
    p.setAttribute('d', ICON[name]);
    s.append(p);
    return s;
  }
  /** Words as printed: the `_italic_` marks are never shown. */
  const shown = (s) => String(s || '').replace(/_/g, '').replace(/\s+/g, ' ');

  /* ---- The page: (line, offset) <-> the DOM, through each run's data-at ---- */

  const runsIn = (lineNode) => [...lineNode.querySelectorAll('[data-at]')];
  const runLen = (span) => span.textContent.length;
  function textNodes(node) {
    const out = [];
    const w = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
    for (let n = w.nextNode(); n; n = w.nextNode()) out.push(n);
    return out;
  }
  function textBefore(span, node) {
    let n = 0;
    for (const t of textNodes(span)) { if (t === node) return n; n += t.length; }
    return n;
  }

  /** The DOM point for an offset into a line's words; `side` 'start' or 'end' picks the run at a boundary. */
  function domPoint(lineNode, off, side) {
    const runs = runsIn(lineNode);
    let span = null;
    for (const r of runs) {
      const at = Number(r.dataset.at), len = runLen(r);
      if (side === 'start' ? (off >= at && off < at + len) : (off > at && off <= at + len)) { span = r; break; }
    }
    if (!span) {
      // An offset on a character the page leaves undrawn (a bracket, a label's period): the nearest run.
      if (side === 'start') span = runs.find(r => Number(r.dataset.at) >= off) || runs[runs.length - 1];
      else span = [...runs].reverse().find(r => Number(r.dataset.at) + runLen(r) <= off) || runs[0];
      if (!span) return null;
      const ts = textNodes(span);
      if (!ts.length) return null;
      const before = side === 'start' ? Number(span.dataset.at) >= off : false;
      return before ? { node: ts[0], offset: 0 } : (side === 'start' ? { node: ts[0], offset: 0 } : { node: ts[ts.length - 1], offset: ts[ts.length - 1].length });
    }
    let rem = off - Number(span.dataset.at);
    const ts = textNodes(span);
    for (const t of ts) {
      if (side === 'start' ? rem < t.length : rem <= t.length) return { node: t, offset: rem };
      rem -= t.length;
    }
    const last = ts[ts.length - 1];
    return last ? { node: last, offset: last.length } : null;
  }

  /** A DOM boundary as (line node, offset into its words), snapping to the nearest run of the line when it falls outside one. */
  function pointOf(node, offset, side) {
    if (!node) return null;
    if (node.nodeType !== 3) {
      const kids = node.childNodes;
      if (offset < kids.length) {
        const ts = textNodes(kids[offset]);
        if (kids[offset].nodeType === 3) { node = kids[offset]; offset = 0; }
        else if (ts.length) { node = ts[0]; offset = 0; }
        else return pointNear(kids[offset], side);
      } else {
        const ts = textNodes(node);
        if (!ts.length) return pointNear(node, side);
        node = ts[ts.length - 1]; offset = node.length;
      }
    }
    const parent = node.parentElement;
    const line = parent && parent.closest('.rd-line');
    if (!line) return null;
    const span = parent.closest('[data-at]');
    if (span && line.contains(span) && !parent.closest('.mk')) return { line, off: Number(span.dataset.at) + textBefore(span, node) + offset };
    return pointNear(node, side);
  }
  function pointNear(node, side) {
    const line = (node.nodeType === 1 ? node : node.parentElement).closest('.rd-line');
    if (!line) return null;
    const runs = runsIn(line);
    if (side === 'start') {
      const r = runs.find(x => node.compareDocumentPosition(x) & Node.DOCUMENT_POSITION_FOLLOWING);
      return r ? { line, off: Number(r.dataset.at) } : { line, off: Infinity };
    }
    const r = [...runs].reverse().find(x => node.compareDocumentPosition(x) & Node.DOCUMENT_POSITION_PRECEDING);
    return r ? { line, off: Number(r.dataset.at) + runLen(r) } : { line, off: 0 };
  }

  function caretAt(x, y) {
    if (document.caretPositionFromPoint) { const c = document.caretPositionFromPoint(x, y); return c ? { node: c.offsetNode, offset: c.offset } : null; }
    if (document.caretRangeFromPoint) { const r = document.caretRangeFromPoint(x, y); return r ? { node: r.startContainer, offset: r.startOffset } : null; }
    return null;
  }

  /**
   * Attaches marks to an open reader. `api`: { root, flow, script, lines (line nodes, script order),
   * index(id), go(id, flash), relayout(), sheet(title, ...body), el, barHost, storage }. Returns the
   * reader's handle: { draw, undraw, tap(event), selecting(), dismiss(), openNotebook(), detach() }.
   */
  function attach(api) {
    const { el, script } = api;
    const storage = api.storage;
    const prefs = MC.prefs(storage);
    const st = { all: [], lost: new Set(), show: prefs.show, hue: prefs.hue, failed: false, sel: null, editing: null, undo: null, detached: false };

    /* ---- Load: re-anchor to this revision, keep what moved ---- */
    {
      const stored = MC.load(storage, script.id);
      const r = MC.place(script, stored);
      st.all = [...r.placed, ...r.lost];
      for (const m of r.lost) st.lost.add(m.id);
      if (r.changed) st.failed = !MC.save(storage, script, st.all);
    }
    const placed = () => st.all.filter(m => !st.lost.has(m.id));
    const lineOf = (id) => api.lines[api.index(id)] || null;
    const persist = () => { st.failed = !MC.save(storage, script, st.all); };

    /* ---- Drawing ---- */

    function undraw() {
      const spans = new Set();
      for (const n of api.flow.querySelectorAll('.mk')) { if (n.parentElement) spans.add(n.parentElement); n.remove(); }
      for (const s of spans) s.normalize();
      if (HL) for (const n of NAMES) CSS.highlights.delete(n);
    }

    /** A point element set into the words at `off` (never adding text). */
    function setPoint(lineNode, off, node) {
      const p = domPoint(lineNode, off, 'end') || domPoint(lineNode, off, 'start');
      if (!p) return false;
      const t = p.node;
      if (p.offset >= t.length) t.after(node);
      else if (p.offset <= 0) t.before(node);
      else t.splitText(p.offset).before(node);
      return true;
    }

    function draw() {
      undraw();
      if (!st.show || st.detached) return;
      const ms = placed();
      // Point elements first: a split text node would otherwise move a range's ends.
      for (const m of ms) {
        const ln = lineOf(m.line);
        if (!ln) continue;
        if (m.kind === 'breath' || m.kind === 'pause' || m.kind === 'beat') {
          const label = m.kind === 'beat' ? `Beat${m.label ? `: ${m.label}` : ''}` : LABEL[m.kind];
          setPoint(ln, m.start, el('span', { class: `mk mk-${m.kind}`, dataset: { mark: m.id, ...(m.kind === 'beat' ? { label: m.label || '' } : {}) }, role: 'img', 'aria-label': label }));
        } else if (m.kind === 'note') {
          const pin = el('span', { class: 'mk mk-pin', dataset: { mark: m.id }, role: 'img', 'aria-label': 'Note' });
          pin.append(icon('note'));
          setPoint(ln, m.end, pin);
        }
      }
      if (!HL) return;
      const sets = new Map(NAMES.map(n => [n, []]));
      for (const m of ms) {
        if (!MC.SPAN.has(m.kind)) continue;
        const ln = lineOf(m.line);
        if (!ln) continue;
        const a = domPoint(ln, m.start, 'start'), b = domPoint(ln, m.end, 'end');
        if (!a || !b) continue;
        const r = document.createRange();
        try { r.setStart(a.node, a.offset); r.setEnd(b.node, b.offset); } catch { continue; }
        if (r.collapsed) continue;
        sets.get(m.kind === 'highlight' ? `ed-mk-${m.hue || 'yellow'}` : m.kind === 'underline' ? 'ed-mk-under' : 'ed-mk-note').push(r);
      }
      for (const [n, rs] of sets) if (rs.length) CSS.highlights.set(n, new Highlight(...rs));
    }

    /* ---- The selection ---- */

    function piecesOf(range) {
      if (!range || range.collapsed) return null;
      if (!api.flow.contains(range.commonAncestorContainer) && !range.commonAncestorContainer.contains(api.flow)) return null;
      const a = pointOf(range.startContainer, range.startOffset, 'start');
      const b = pointOf(range.endContainer, range.endOffset, 'end');
      const out = [];
      for (const n of api.lines) {
        if (!range.intersectsNode(n)) continue;
        const line = script.lines[api.index(n.dataset.line)];
        if (!line) continue;
        const len = PlaysCore.lineText(line).length;
        const s = a && a.line === n ? Math.min(a.off, len) : 0;
        const e = b && b.line === n ? Math.min(b.off, len) : len;
        if (e > s) out.push({ line: n.dataset.line, start: s, end: e });
      }
      return out.length ? out : null;
    }

    function onSelection() {
      if (st.detached) return;
      const sel = window.getSelection();
      const pieces = sel && sel.rangeCount ? piecesOf(sel.getRangeAt(0)) : null;
      if (pieces) { st.sel = pieces; st.editing = null; st.undo = null; paintBar(); return; }
      st.sel = null;
      if (!st.editing && !st.undo) hideBar();
    }

    /* ---- The mark bar ---- */

    const bar = el('div', { class: 'mk-bar', role: 'toolbar', 'aria-label': 'Mark', hidden: true });
    const wrap = el('div', { class: 'mk-wrap' }, bar);
    api.barHost.append(wrap);
    // A press on the bar never lets go of the selection it acts on.
    bar.addEventListener('pointerdown', (e) => { if (!e.target.closest('input, textarea')) e.preventDefault(); });
    bar.addEventListener('mousedown', (e) => e.preventDefault());

    const btn = (attrs, ...kids) => el('button', { type: 'button', class: 'mk-btn', ...attrs }, ...kids);
    const warnRow = () => (st.failed ? el('p', { class: 'caption mk-warn', role: 'alert' }, icon('warn'), 'Marks are not being saved on this device.') : null);

    function paintBar() {
      const row = el('div', { class: 'mk-row' });
      if (st.sel) {
        row.append(
          btn({ 'aria-label': `${LABEL.highlight} (H)`, title: `${LABEL.highlight} (H)`, onclick: () => make('highlight') }, el('span', { class: 'mk-swatch', dataset: { hue: st.hue } })),
          ...['underline', 'breath', 'pause', 'beat', 'note'].map(k => btn({ 'aria-label': `${LABEL[k]} (${KEY_OF[k]})`, title: `${LABEL[k]} (${KEY_OF[k]})`, onclick: () => make(k) }, icon(k))));
      } else if (st.undo) {
        row.append(btn({ class: 'mk-btn mk-text', onclick: undo }, 'Undo'));
      } else if (st.editing) {
        const m = st.all.find(x => x.id === st.editing);
        if (!m) { hideBar(); return; }
        if (m.kind === 'highlight') {
          for (const h of MC.HUES) {
            row.append(btn({ 'aria-label': h[0].toUpperCase() + h.slice(1), 'aria-pressed': m.hue === h ? 'true' : 'false', onclick: () => recolor(m.id, h) },
              el('span', { class: 'mk-swatch', dataset: { hue: h } })));
          }
        } else {
          row.append(el('span', { class: 'mk-kind', 'aria-hidden': 'true' }, icon(m.kind)), el('span', { class: 'mk-kind-lab caption' }, LABEL[m.kind]));
        }
        if (m.kind === 'beat' || m.kind === 'note') row.append(btn({ 'aria-label': m.kind === 'beat' ? 'Edit label' : 'Edit note', title: 'Edit', onclick: () => fieldSheet(m) }, icon('edit')));
        row.append(btn({ 'aria-label': 'Delete', title: 'Delete', onclick: () => del(m.id) }, icon('trash')));
      } else { hideBar(); return; }
      bar.replaceChildren(...[warnRow(), row].filter(Boolean));
      bar.hidden = false;
    }
    function hideBar() { bar.hidden = true; bar.replaceChildren(); }

    /* ---- Making, changing, deleting ---- */

    function commit(made) {
      if (!made.length) return;
      for (const m of made) st.all = MC.add(script, st.all, m);
      if (!st.show) { st.show = true; MC.savePrefs(storage, { show: true, hue: st.hue }); }
      persist();
      const sel = window.getSelection();
      if (sel) sel.removeAllRanges();
      st.sel = null; st.undo = null; st.editing = null;
      redraw(made.some(m => !MC.SPAN.has(m.kind) || m.kind === 'note'));
      if (st.failed) paintBar(); else hideBar();
    }
    function make(kind) {
      if (!st.sel) return;
      const made = MC.fromSelection(script, st.sel, kind, { hue: st.hue }).filter(Boolean);
      if (!made.length) return;
      if (kind === 'highlight') MC.savePrefs(storage, { show: st.show, hue: st.hue });
      if (kind === 'beat' || kind === 'note') { fieldSheet(made[0], true); return; }
      commit(made);
    }
    function recolor(id, hue) {
      st.all = MC.update(st.all, id, { hue });
      st.hue = hue;
      MC.savePrefs(storage, { show: st.show, hue });
      persist();
      redraw(false);
      paintBar();
    }
    function del(id) {
      const r = MC.remove(st.all, id);
      st.all = r.marks;
      for (const m of r.removed) st.lost.delete(m.id);
      st.undo = r.removed;
      st.editing = null;
      persist();
      redraw(r.removed.some(m => !MC.SPAN.has(m.kind) || m.kind === 'note'));
      paintBar();
      if (notebook.open) paintNotebook();
    }
    function undo() {
      if (!st.undo) return;
      st.all = [...st.all, ...st.undo];
      const point = st.undo.some(m => !MC.SPAN.has(m.kind) || m.kind === 'note');
      st.undo = null;
      persist();
      redraw(point);
      hideBar();
    }
    function redraw(relayout) {
      draw();
      if (relayout) { st.relaying = true; try { api.relayout(); } finally { st.relaying = false; } }
    }

    /** A beat's label or a note's words, in the reader's sheet; `fresh` when the mark is not yet made. */
    function fieldSheet(m, fresh = false) {
      const line = script.lines[api.index(m.line)];
      const lt = line ? PlaysCore.lineText(line) : '';
      const words = m.kind === 'note' ? shown(m.text)
        : `${shown(lt.slice(Math.max(0, m.start - 40), m.start)).replace(/^\S*\s/, '…')} // ${shown(lt.slice(m.start, m.start + 40)).replace(/\s\S*$/, '…')}`;
      const field = m.kind === 'beat'
        ? el('input', { type: 'text', class: 'field-input mk-field', maxlength: String(MC.LABEL_MAX), 'aria-label': 'Beat label', autocomplete: 'off', enterkeyhint: 'done' })
        : el('textarea', { class: 'field-input mk-field mk-note-field', rows: '5', 'aria-label': 'Note' });
      field.value = m.kind === 'beat' ? (m.label || '') : (m.note || '');
      const save = el('button', { type: 'button', class: 'btn btn-primary' }, 'Save');
      const remove = fresh ? null : el('button', { type: 'button', class: 'btn btn-ghost mk-del' }, icon('trash'), 'Delete');
      const d = api.sheet(LABEL[m.kind], el('p', { class: 'caption mk-quote' }, words), field, el('div', { class: 'mk-sheet-acts' }, remove, save));
      d.classList.add('mk-sheet');
      const paintSave = () => { save.disabled = m.kind === 'note' && !field.value.trim(); };
      field.addEventListener('input', paintSave);
      paintSave();
      const finish = () => { d.close(); };
      save.addEventListener('click', () => {
        if (save.disabled) return;
        if (fresh) {
          const made = { ...m, ...(m.kind === 'beat' ? { label: field.value.trim().slice(0, MC.LABEL_MAX) } : { note: field.value }) };
          finish();
          commit([made]);
          return;
        }
        st.all = MC.update(st.all, m.id, m.kind === 'beat' ? { label: field.value } : { note: field.value });
        persist();
        finish();
        redraw(m.kind === 'beat');
        st.editing = null; hideBar();
        if (notebook.open) paintNotebook();
      });
      if (m.kind === 'beat') field.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); save.click(); } });
      if (remove) remove.addEventListener('click', () => { finish(); del(m.id); });
      d.addEventListener('close', () => d.remove());
      api.root.append(d);
      d.showModal();
      field.focus();
    }

    /* ---- The notebook ---- */

    const showBox = el('input', { type: 'checkbox', role: 'switch', class: 'mk-show-box' });
    const nbList = el('div', { class: 'mk-nb' });
    const notebook = api.sheet('Marks', el('label', { class: 'mk-show' }, el('span', {}, 'Show marks'), showBox), nbList);
    notebook.classList.add('mk-notebook');
    api.root.append(notebook);
    showBox.addEventListener('change', () => {
      st.show = showBox.checked;
      MC.savePrefs(storage, { show: st.show, hue: st.hue });
      api.root.classList.toggle('mk-hidden', !st.show);
      redraw(true);
    });

    function glyph(m) {
      if (m.kind === 'highlight') return el('span', { class: 'mk-swatch', dataset: { hue: m.hue || 'yellow' }, 'aria-hidden': 'true' });
      return el('span', { class: 'mk-glyph', 'aria-hidden': 'true' }, icon(m.kind));
    }
    function rowWords(m, lt) {
      if (MC.SPAN.has(m.kind)) return el('span', { class: 'mk-nb-words' }, shown(m.text) || '…');
      const before = shown(lt.slice(Math.max(0, m.start - 32), m.start)).replace(/^\S*\s/, '…');
      const after = shown(lt.slice(m.start, m.start + 32)).replace(/\s\S*$/, '…');
      return el('span', { class: 'mk-nb-words' }, before, el('span', { class: 'mk-nb-point' }, m.kind === 'breath' ? ' / ' : ' // '), after);
    }
    function paintNotebook() {
      showBox.checked = st.show;
      const ms = MC.order(script, placed());
      const lost = st.all.filter(m => st.lost.has(m.id));
      const kids = [];
      if (st.failed) kids.push(warnRow());
      if (!ms.length && !lost.length) kids.push(el('p', { class: 'caption rd-empty' }, 'Select words on the page to mark them.'));
      if (ms.length) {
        kids.push(el('ol', { class: 'mk-nb-list' }, ...ms.map(m => {
          const line = script.lines[api.index(m.line)];
          const lt = line ? PlaysCore.lineText(line) : '';
          const who = line && line.kind === 'speech' ? line.role : null;
          const extra = m.kind === 'beat' && m.label ? m.label : m.kind === 'note' ? m.note : null;
          return el('li', {}, el('button', { type: 'button', class: 'mk-nb-row', 'aria-label': `${LABEL[m.kind]}${who ? `, ${who}` : ''}: ${shown(m.text) || ''}`,
            onclick: () => { notebook.close(); api.go(m.line, true); } },
          glyph(m),
          el('span', { class: 'mk-nb-body' },
            who ? el('span', { class: 'caption mk-nb-who' }, who) : null,
            rowWords(m, lt),
            extra ? el('span', { class: `mk-nb-extra${m.kind === 'beat' ? ' mk-nb-label' : ''}` }, extra) : null)));
        })));
      }
      if (lost.length) {
        kids.push(el('h3', { class: 'caption mk-nb-h' }, 'Not placed'));
        kids.push(el('ol', { class: 'mk-nb-list' }, ...lost.map(m => el('li', { class: 'mk-nb-lost' },
          glyph(m),
          el('span', { class: 'mk-nb-body' }, el('span', { class: 'mk-nb-words' }, shown(m.text) || shown(`${m.prefix || ''} / ${m.suffix || ''}`)),
            m.note ? el('span', { class: 'mk-nb-extra' }, m.note) : null, m.label ? el('span', { class: 'mk-nb-extra mk-nb-label' }, m.label) : null),
          el('button', { type: 'button', class: 'icon-btn mk-nb-del', 'aria-label': 'Delete', title: 'Delete', onclick: () => del(m.id) }, icon('trash'))))));
      }
      nbList.replaceChildren(...kids);
    }
    notebook.addEventListener('toggle', () => { if (notebook.open) paintNotebook(); });

    /* ---- Taps and keys ---- */

    function tap(e) {
      const pin = e.target.closest && e.target.closest('.mk');
      let id = pin ? pin.dataset.mark : null;
      if (!id && st.show && HL) {
        const c = caretAt(e.clientX, e.clientY);
        const p = c && pointOf(c.node, c.offset, 'start');
        if (p && p.off !== Infinity) {
          const hit = MC.at(placed(), p.line.dataset.line, p.off);
          if (hit.length) id = hit[0].id;
        }
      }
      if (!id) { dismiss(); return false; }
      st.editing = id; st.undo = null; st.sel = null;
      paintBar();
      return true;
    }
    /** A selection is on the page: a tap there neither turns nor makes a line current. */
    const selecting = () => !!st.sel;
    function dismiss() { if (st.editing || st.undo) { st.editing = null; st.undo = null; if (!st.sel) hideBar(); } }

    function onKey(e) {
      if (st.detached || e.metaKey || e.ctrlKey || e.altKey || !api.root.isConnected) return;
      if (document.querySelector('dialog[open]')) return;
      const t = e.target;
      if (t && t.closest && t.closest('input, select, textarea, [contenteditable="true"]')) return;
      if (e.key === 'Escape' && (st.sel || st.editing || st.undo)) {
        const sel = window.getSelection();
        if (sel) sel.removeAllRanges();
        st.sel = null; st.editing = null; st.undo = null; hideBar();
        e.preventDefault();
        return;
      }
      const kind = KEYS[e.key.length === 1 ? e.key.toLowerCase() : ''];
      if (!kind || !st.sel) return;
      e.preventDefault();
      e.stopPropagation();
      make(kind);
    }
    document.addEventListener('selectionchange', onSelection);
    window.addEventListener('keydown', onKey, true);
    api.root.classList.toggle('mk-hidden', !st.show);

    return {
      draw, undraw, tap, selecting, dismiss,
      openNotebook: () => notebook.showModal(),
      /** A page turn closes the bar for a mark (a selection keeps its own). */
      turned: () => { if (!st.relaying) dismiss(); },
      detach() {
        st.detached = true;
        document.removeEventListener('selectionchange', onSelection);
        window.removeEventListener('keydown', onKey, true);
        if (HL) for (const n of NAMES) CSS.highlights.delete(n);
        wrap.remove();
      },
      /** For the frames and tests: the marks as stored and which are lost. */
      state: () => ({ all: st.all.slice(), lost: [...st.lost], show: st.show, failed: st.failed }),
    };
  }

  return { attach, HL };
})();
