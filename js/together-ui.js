/**
 * Listen Together's face on the web (WEB-DESIGN §4.12): the button in Now
 * Playing, Library's "Join a room" row, and the one sheet both open. The
 * session (js/together.js) does the work; this file only draws and asks.
 */
const TogetherUI = (() => {
  'use strict';

  function el(tag, attrs, ...children) {
    const n = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (v === null || v === undefined || v === false) continue;
      if (k === 'class') n.className = v;
      else if (k.startsWith('on')) n.addEventListener(k.slice(2), v);
      else n.setAttribute(k, v === true ? '' : v);
    }
    for (const c of children.flat()) {
      if (c === null || c === undefined || c === false) continue;
      n.append(c instanceof Node ? c : document.createTextNode(String(c)));
    }
    return n;
  }
  function svg(d, cls = 'i-inline') {
    const ns = 'http://www.w3.org/2000/svg';
    const s = document.createElementNS(ns, 'svg');
    s.setAttribute('viewBox', '0 0 24 24');
    s.setAttribute('aria-hidden', 'true');
    if (cls) s.setAttribute('class', cls);
    const p = document.createElementNS(ns, 'path');
    p.setAttribute('d', d);
    s.append(p);
    return s;
  }
  const GROUP = 'M16 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6zm-8 0a3 3 0 1 0 0-6 3 3 0 0 0 0 6zm0 2c-2.3 0-7 1.2-7 3.5V19h14v-2.5C15 14.2 10.3 13 8 13zm8 0c-.3 0-.6 0-1 .1 1.2.8 2 1.9 2 3.4V19h6v-2.5c0-2.3-4.7-3.5-7-3.5z';
  const CLOSE = 'M6.4 5 5 6.4 10.6 12 5 17.6 6.4 19l5.6-5.6 5.6 5.6 1.4-1.4-5.6-5.6L19 6.4 17.6 5 12 10.6z';
  const PLAY = 'M8 5v14l11-7z';
  const SHARE = 'M18 16a3 3 0 0 0-2.4 1.2l-7-3.5a3 3 0 0 0 0-1.4l7-3.5A3 3 0 1 0 15 7l-7 3.5a3 3 0 1 0 0 3l7 3.5A3 3 0 1 0 18 16z';

  const NOTICE = {
    bad_code: 'That is not a room code.',
    no_such_room: 'No room has that code.',
    room_ended: 'This room has ended.',
    room_full: 'This room is full.',
    not_a_member: 'You are no longer in this room.',
    rate_limited: 'Too many tries. Try again in a minute.',
    offline: 'You are offline.',
  };
  const noticeText = (k) => NOTICE[k] || 'Ear Drama could not be reached.';
  /** Six characters read aloud as two threes; the normalizer drops the space. */
  const spaced = (code) => `${code.slice(0, 3)} ${code.slice(3)}`;
  const listening = (n) => `${n} listening`;

  let session = null;
  let share = null;
  let sheet = null;
  let rowBox = null;
  let typed = '';

  function ensureSheet() {
    if (sheet) return sheet;
    sheet = el('dialog', { class: 'account-sheet together-sheet', 'aria-labelledby': 'together-h' });
    sheet.addEventListener('close', () => { sheet.replaceChildren(); if (session) session.clearNotice(); });
    document.body.append(sheet);
    return sheet;
  }

  /** Opens the sheet; a code from a `?room=` link is filled in, and Join takes the person's tap. */
  function open(code) {
    if (typeof code === 'string') typed = code;
    const d = ensureSheet();
    paintSheet();
    if (!d.open) d.showModal();
    const join = d.querySelector('.together-join');
    if (typeof code === 'string' && join) join.focus();
  }

  /** replaceChildren would draw a null as the text "null". */
  function fill(...nodes) { sheet.replaceChildren(...nodes.filter(Boolean)); }

  function paintSheet() {
    if (!sheet) return;
    const i = session.info();
    const head = [
      el('button', { type: 'button', class: 'icon-btn account-close', 'aria-label': 'Close', onclick: () => sheet.close() }, svg(CLOSE, '')),
      el('h2', { id: 'together-h', class: 'section-header' }, 'Listen together'),
    ];
    if (!i.available) {
      sheet.replaceChildren(...head, el('p', { class: 'body' }, 'Not available yet.'));
      return;
    }
    if (i.inRoom) {
      const guest = i.role === 'guest';
      fill(...head,
        el('p', { class: 'view-heading room-code', 'aria-label': `Room code ${i.code.split('').join(' ')}` }, spaced(i.code)),
        el('p', { class: 'caption', 'aria-live': 'polite' }, [listening(i.members), guest ? 'Following the host' : null].filter(Boolean).join(' · ')),
        i.blocked ? el('div', { class: 'actions' },
          el('button', { type: 'button', class: 'btn btn-primary', onclick: () => session.tap() }, svg(PLAY), 'Play')) : null,
        el('div', { class: 'actions' },
          el('button', { type: 'button', class: 'btn btn-accent', onclick: () => share(i.code) }, svg(SHARE), 'Share link'),
          el('button', { type: 'button', class: 'btn', disabled: i.busy, onclick: () => session.leave() }, 'Leave'),
          guest ? null : el('button', { type: 'button', class: 'btn', disabled: i.busy, onclick: () => session.end() }, 'End room')));
      return;
    }
    const input = el('input', { id: 'together-code', class: 'field-input', type: 'text', name: 'code', value: typed,
                                autocomplete: 'off', autocapitalize: 'characters', spellcheck: 'false', maxlength: '12',
                                enterkeyhint: 'go', 'aria-describedby': i.notice ? 'together-notice' : null });
    input.value = typed;
    input.addEventListener('input', () => { typed = input.value; });
    const form = el('form', { class: 'together-form', onsubmit: (e) => { e.preventDefault(); session.join(input.value); } },
      el('label', { for: 'together-code', class: 'caption' }, 'Room code'),
      el('div', { class: 'together-field' }, input,
        el('button', { type: 'submit', class: 'btn together-join', disabled: i.busy }, 'Join')));
    fill(...head,
      i.canStart ? el('div', { class: 'actions together-start' },
        el('button', { type: 'button', class: 'btn btn-accent', disabled: i.busy, onclick: () => session.start() }, svg(GROUP), 'Start a room')) : null,
      form,
      i.notice ? el('p', { id: 'together-notice', class: 'body account-warn', role: 'alert' }, noticeText(i.notice)) : null);
  }

  /** Library's row (§4.12): the way in with nothing playing. */
  function paintRow(box = rowBox) {
    if (!box || !session) return;
    rowBox = box;
    const i = session.info();
    box.replaceChildren(
      el('button', { type: 'button', class: 'btn btn-ghost account-open', disabled: !i.available, onclick: () => open() },
        svg(GROUP), i.inRoom ? `Room ${spaced(i.code)}` : 'Join a room'),
      !i.available ? el('span', { class: 'caption' }, 'Not available yet')
        : i.inRoom ? el('span', { class: 'caption' }, listening(i.members)) : null);
  }

  /** Now Playing's button. */
  function paintButton() {
    const b = document.getElementById('np-together');
    if (!b || !session) return;
    const i = session.info();
    b.disabled = !i.available;
    b.setAttribute('aria-pressed', String(i.inRoom));
    b.querySelector('.together-label').textContent = i.inRoom ? `Room ${spaced(i.code)}` : 'Listen together';
    const note = document.getElementById('np-together-note');
    if (note) note.hidden = i.available;
  }

  let lastSig = '';
  function repaint() {
    // A read every 2 s emits; only a change worth drawing redraws, so focus and a screen reader are left alone.
    const i = session.info();
    const sig = JSON.stringify([i.available, i.busy, i.notice, i.blocked, i.inRoom, i.code, i.role, i.members, i.canStart]);
    if (sig === lastSig) return;
    lastSig = sig;
    paintButton();
    paintRow();
    if (sheet && sheet.open) {
      const focused = document.activeElement && document.activeElement.id;
      paintSheet();
      if (focused) { const f = document.getElementById(focused); if (f) f.focus(); }
    }
  }

  function mount(s, opts) {
    session = s;
    share = opts.share;
    const b = document.getElementById('np-together');
    if (b) b.addEventListener('click', () => open());
    session.onChange(repaint);
    paintButton();
  }

  return { mount, open, paintRow, noticeText };
})();
