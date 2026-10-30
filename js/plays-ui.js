/**
 * The Plays views (WEB-DESIGN §4.10; PLAYS-DESIGN §2, binding): the plays a
 * person can cast, a play's parts and rights, the cast sheet, and recording
 * one part line by line. app.js's router calls render() with its helpers and
 * leave() whenever it shows another view, which ends a recording session and
 * stops the microphone.
 *
 * Every word of a script is drawn as printed; nothing here writes a list or
 * a blurb (§8 rule 2). The device voice is always labeled where it plays.
 *
 * Phase 2 (PLAYS-DESIGN §11.7, WEB-DESIGN §4.10a): a shared production's
 * parts and chosen takes are the Worker's (js/plays-share.js); recording is
 * phase 1's, on this browser, then uploaded.
 */
const PlaysUI = (() => {
  'use strict';
  const C = PlaysCore;
  const muted = typeof location !== 'undefined' && new URLSearchParams(location.search).get('mute') === '1';

  let h = null;
  let store = null;
  let token = 0;
  /** The name typed on the cast sheet, kept for this visit. */
  let performerName = '';
  /** The open recording: { key, s: RecordingSession, index }. */
  let rec = null;
  /** The listen-through's rendered mix, kept for this page only: { id, from, url }. */
  let mix = null;
  /** The live listen-through on the production page, ended when the page changes. */
  let listen = null;
  /** The last page drawn, redrawn when someone signs in or out here. */
  let lastDraw = null;
  const S = PlaysShare;
  const REASONS = [['offensive', 'Offensive'], ['harassment', 'Harassment'], ['personal_information', 'Personal information'],
                   ['not_a_performance', 'Not a performance'], ['other', 'Other']];

  const $ = (id) => document.getElementById(id);
  const ICON = {
    headphones: 'M12 3a9 9 0 0 0-9 9v6a3 3 0 0 0 3 3h2v-8H5v-1a7 7 0 0 1 14 0v1h-3v8h2a3 3 0 0 0 3-3v-6a9 9 0 0 0-9-9z',
    mic: 'M12 14a3 3 0 0 0 3-3V5a3 3 0 0 0-6 0v6a3 3 0 0 0 3 3zm5-3a5 5 0 0 1-10 0H5a7 7 0 0 0 6 6.9V21h2v-3.1A7 7 0 0 0 19 11z',
    wave: 'M3 10h2v4H3zm4-3h2v10H7zm4-4h2v18h-2zm4 4h2v10h-2zm4 3h2v4h-2z',
    record: 'M12 5a7 7 0 1 0 0 14 7 7 0 0 0 0-14z',
    stop: 'M7 7h10v10H7z',
    play: 'M8 5v14l11-7z',
    prev: 'M15.4 7.4 14 6l-6 6 6 6 1.4-1.4-4.6-4.6z',
    next: 'M8.6 16.6 10 18l6-6-6-6-1.4 1.4 4.6 4.6z',
    check: 'M9 16.2 4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4z',
    pause: 'M7 5h4v14H7zm6 0h4v14h-4z',
    down: 'M12 16l6-6-1.4-1.4-4.6 4.6-4.6-4.6L6 10z',
    warn: 'M1 21h22L12 2zm12-3h-2v-2h2zm0-4h-2v-4h2z',
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

  const num = new Intl.NumberFormat('en-US');
  const lines = (n) => (n === 1 ? '1 line' : `${num.format(n)} lines`);

  async function openStore() {
    if (!store) store = PlayStore.open();
    await store.load();
    return store;
  }

  /* ---- Shared pieces ---- */

  /** The record's own evidence, verbatim and linked, then the source (§2.1). */
  function rightsLine(script) {
    const p = h.el('p', { class: 'caption play-rights' });
    const items = [];
    for (const ev of (script.rights && script.rights.evidence) || []) {
      if (!ev.claim) continue;
      items.push(ev.src ? h.el('a', { href: ev.src, rel: 'noopener' }, ev.claim) : h.el('span', {}, ev.claim));
    }
    if (script.source && script.source.url) {
      items.push(h.el('a', { href: script.source.url, rel: 'noopener' }, script.source.name));
    }
    items.forEach((n, i) => { if (i) p.append(' · '); p.append(n); });
    return p;
  }

  /** A script line with its printed directions kept apart from the words said (§3); nothing rewritten. */
  function lineView(line, cls = '') {
    const box = h.el('div', { class: `script-line ${cls}`.trim() });
    if (line.role) box.append(h.el('p', { class: 'caption line-role' }, line.role));
    const text = h.el('p', { class: 'line-text' });
    if (line.kind === 'speech') {
      (line.parts || []).forEach((piece, i) => {
        if (i) text.append(' ');
        const words = C.pieceText(piece);
        text.append(C.pieceKind(piece) === 'say' ? words : h.el('span', { class: 'line-aside' }, `(${words})`));
      });
    } else {
      text.append(h.el('span', { class: 'line-aside' }, line.source || ''));
    }
    box.append(text);
    return box;
  }

  function progressLine(p, script) {
    if (C.isFinished(p)) return 'Finished';
    if (!script) return '';
    const total = C.speechLineIDs(script).length;
    const voiced = total - C.missingSpeech(p, script).length;
    return `${num.format(voiced)} of ${lines(total)} recorded`;
  }

  function partStatus(p, script, part) {
    const st = C.stateOf(p, part.id);
    const name = st.performer ? ` · ${st.performer}` : '';
    const missing = C.missingLines(p, script, part.id).length;
    switch (st.status) {
      case 'recording': return `${num.format(part.lineCount - missing)} of ${lines(part.lineCount)} recorded${name}`;
      case 'done': return `Recorded${name}`;
      case 'silent': return 'Left silent';
      default: return lines(part.lineCount);
    }
  }

  function failBox(body, err, retry) {
    console.error(err);
    body.replaceChildren(h.stateBox(h.problem(err), { retry }));
  }

  /* ---- Library's Ear dramas (WEB-DESIGN §4.7; Decision 068): this browser's productions ---- */

  const canShare = () => API.plays.available() && API.account.signedIn();
  const signIn = () => { if (typeof AccountUI !== 'undefined') AccountUI.openSheet(); };

  async function renderMine(body, helpers) {
    h = helpers;
    lastDraw = () => renderMine(body, helpers);
    const my = ++token;
    body.replaceChildren(h.stateBox('loading'));
    try {
      await openStore();
    } catch (err) {
      if (my === token) failBox(body, err, () => renderMine(body, helpers));
      return;
    }
    if (my !== token) return;
    const out = [];
    if (S.pendingInvite()) {
      const inv = await inviteBox(my);
      if (my !== token) return;
      out.push(inv);
    }
    let remote = [];
    if (canShare()) {
      try { remote = (await API.plays.list()).productions || []; } catch (err) { console.error(err); }
      if (my !== token) return;
    }
    const rows = S.libraryRows(store, remote);
    if (!rows.length) out.push(h.stateBox('empty', { text: 'No ear dramas yet.' }));
    else {
      const ul = h.el('ul', { class: 'play-list' });
      for (const r of rows) {
        if (r.local) {
          const script = await store.script(r.local);
          if (my !== token) return;
          ul.append(h.el('li', { class: 'play-row' },
            h.el('a', { class: 'play-link', href: `?production=${encodeURIComponent(r.local.id)}` },
              h.el('span', { class: 'body-strong' }, r.local.title),
              h.el('span', { class: 'caption' }, r.pid ? 'Shared' : progressLine(r.local, script)))));
        } else {
          const status = h.el('span', { class: 'caption refusal', role: 'alert' });
          ul.append(h.el('li', { class: 'play-row' },
            h.el('button', { type: 'button', class: 'play-link play-remote', onclick: () => openRemote(r.remote, status) },
              h.el('span', { class: 'body-strong' }, r.remote.title),
              h.el('span', { class: 'caption' }, 'Shared')), status));
        }
      }
      out.push(ul);
    }
    if (canShare()) {
      const classes = await classesBox(my);
      if (my !== token) return;
      out.push(classes);
    }
    body.replaceChildren(...out);
  }

  /** A shared production this browser has not opened: made here from the bundle's script (§11.7 rule 11). */
  async function openRemote(remote, status) {
    try {
      const rec = await API.plays.get(remote.id);
      const script = S.scriptFor(await API.castableScripts(), rec.scriptID, rec.scriptRevision);
      const local = await S.localFor(store, rec.id, script);
      h.navigate(`?production=${encodeURIComponent(local.id)}`);
    } catch (err) { console.error(err); status.textContent = S.line(err); }
  }
  /* ---- Direction D's making pieces (WEB-DESIGN §4.10b): the board, the fingerprint, faces ---- */

  /** Every castable script is a play: it stands on the drama board (its genre is never named). */
  const BOARD = 'drama';
  const speakingParts = (script) => C.castParts(script).filter(x => C.isSpeaking(x.id));
  const hueOf = (script, part) => C.partHue(script, part) || 'none';

  /** The cast fingerprint: each speaking part's share of the play's lines, largest first. */
  function fingerprint(script, cls = '') {
    const parts = speakingParts(script);
    const el = (tag, attrs, ...kids) => {
      const n = document.createElement(tag);
      for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v);
      n.append(...kids);
      return n;
    };
    return el('span', { class: `pl-print ${cls}`.trim(), role: 'img', 'aria-label': parts.length === 1 ? '1 part' : `${num.format(parts.length)} parts, largest first` },
      ...parts.map(x => el('i', { 'data-hue': hueOf(script, x.id), style: `flex: ${x.lineCount} 1 0` })));
  }

  /** Where a part speaks: 24 bars across the script, each its share of the part's lines there. */
  const BINS = 24;
  function presence(script, part) {
    const counts = new Array(BINS).fill(0);
    const n = script.lines.length || 1;
    script.lines.forEach((l, i) => { if (C.linePart(l) === part) counts[Math.min(BINS - 1, Math.floor(i * BINS / n))] += 1; });
    const max = Math.max(1, ...counts);
    return h.el('span', { class: 'pl-presence', dataset: { hue: hueOf(script, part) }, 'aria-hidden': 'true' },
      counts.map(c => h.el('i', c ? { style: `height: ${Math.max(3, Math.round(18 * c / max))}px` } : { class: 'z' })));
  }

  /** Who a line or a part is heard as: its performer's name, "Recorded", or the device voice (§5 rule 3). */
  function heardAs(p, script, part, lineID = null) {
    const st = C.stateOf(p, part);
    const human = lineID ? !!C.usableTake(p, lineID) : C.linesFor(script, part).some(l => C.usableTake(p, l.id));
    if (!human) return C.isSpeaking(part) ? 'Device voice' : 'Open';
    return st.performer || 'Recorded';
  }

  /** A part's face: a performer is a filled circle on the part's mark; the device voice a dashed ring. */
  function face(script, part, { who = null, voice = false, ok = false, size = '', live = false, now = false } = {}) {
    const f = h.el('span', { class: `pl-face${voice ? ' voice' : ''}${size ? ` ${size}` : ''}${live ? ' live' : ''}${now ? ' now' : ''}`,
                             dataset: { hue: hueOf(script, part) }, 'aria-hidden': 'true' });
    if (voice) f.append(svg('wave'));
    else f.append(((who || C.partTitle(part)).trim().charAt(0) || '?').toUpperCase());
    if (ok) f.append(h.el('span', { class: 'ok' }, svg('check')));
    return f;
  }

  /** The head board of a play or a production: the title block on the drama board, the fingerprint as its mark. */
  function playBoard(script, name, kicker, facts) {
    return h.headBoard({ series: { name, genre: BOARD, picture: null }, kicker, name, facts,
                         mark: fingerprint(script, 'g-head-strip pl-print-head') });
  }
  const kindOf = (script) => (script.kind === 'radio' ? 'Radio play' : 'Stage play');

  /** The page's own heading gives way to the head board's. */
  function boardHeading(on) {
    const ph = $('plays-h');
    const had = document.activeElement === ph;
    ph.hidden = on;
    if (on && had) { const b = $('plays-body').querySelector('h1'); if (b) b.focus({ preventScroll: true }); }
  }

  /** A part card: face, name, length, where it speaks, then who holds it and its one action. */
  function partCard(script, part, { who = null, voice = false, ok = false, mine = false, status = null, href = null, actions = null } = {}) {
    const name = h.el('span', { class: 'pl-part-name' }, part.title);
    return h.el('li', { class: `pl-part${mine ? ' mine' : ''}`, dataset: status ? { status } : {} },
      h.el('span', { class: 'pl-part-head' }, face(script, part.id, { who, voice, ok, size: 'sm' }),
        href ? h.el('a', { class: 'pl-part-link', href }, name) : name),
      h.el('span', { class: 'caption tabular pl-part-len' }, lines(part.lineCount)),
      presence(script, part.id),
      status ? h.el('span', { class: 'caption pl-part-who' }, status) : h.el('span', { class: 'pl-part-who' }),
      actions && actions.childNodes.length ? actions : h.el('span', { class: 'pl-part-hold' }));
  }

  /* ---- Start an ear drama (§2.1): a play's page and Surprise both offer it ---- */

  function startButton(script, helpers, { primary = false } = {}) {
    h = h || helpers;
    const box = helpers.el('span', { class: 'start-drama' });
    const error = helpers.el('span', { class: 'caption refusal', role: 'alert' });
    const start = helpers.el('button', { type: 'button', class: primary ? 'btn btn-primary' : 'btn btn-accent', onclick: async () => {
      start.disabled = true;
      try {
        await openStore();
        if (navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(() => {});
        const p = await store.create(script);
        helpers.navigate(`?production=${encodeURIComponent(p.id)}`, $('view-plays').hidden === false);
      } catch (err) {
        console.error(err);
        error.textContent = 'This browser could not save a production.';
        start.disabled = false;
      }
    } }, 'Start an ear drama');
    box.append(start, error);
    return box;
  }

  /* ---- A play: its head board, its parts, its rights ---- */

  async function renderScript(body, my, id) {
    body.replaceChildren(h.stateBox('loading'));
    let script;
    try {
      script = (await API.castableScripts()).find(s => s.id === id);
    } catch (err) {
      if (my === token) failBox(body, err, () => renderScript(body, my, id));
      return;
    }
    if (my !== token) return;
    if (!script) {
      $('plays-h').textContent = 'Ear drama';
      body.replaceChildren(h.stateBox('missing'));
      return;
    }
    h.setTitle(script.title);
    $('plays-h').textContent = script.title;
    const parts = speakingParts(script);
    body.replaceChildren(
      playBoard(script, script.title, kindOf(script),
        [C.authorFacts(script), script.year ? String(script.year) : null, `${num.format(parts.length)}\u00a0${parts.length === 1 ? 'part' : 'parts'}`, lines(script.lines.length).replace(' ', '\u00a0')]),
      h.el('div', { class: 'actions actions-one actions-start ear-drama-only' }, startButton(script, h, { primary: true })),
      h.el('section', { class: 'block' },
        h.el('h2', { class: 'section-header', id: 'play-parts-h' }, 'Parts'),
        h.el('ul', { class: 'pl-grid', 'aria-labelledby': 'play-parts-h' },
          C.castParts(script).map(part => partCard(script, part)))),
      rightsLine(script));
    boardHeading(true);
  }

  /* ---- The cast sheet (§2.2-2.5) ---- */

  async function production(my, id) {
    await openStore();
    const p = store.production(id);
    const script = p && await store.script(p);
    return my === token ? { p, script } : null;
  }

  function notOnDevice(body) {
    $('plays-h').textContent = 'Ear drama';
    body.replaceChildren(h.stateBox('empty', { text: 'This production is not in this browser.' }));
  }

  async function renderProduction(body, my, id) {
    lastDraw = () => renderProduction(body, token, id);
    body.replaceChildren(h.stateBox('loading'));
    let got;
    try { got = await production(my, id); } catch (err) {
      if (my === token) failBox(body, err, () => renderProduction(body, my, id));
      return;
    }
    if (!got) return;
    const { p, script } = got;
    if (!p || !script) { notOnDevice(body); return; }
    h.setTitle(p.title);
    $('plays-h').textContent = p.title;
    const link = store.share(id);
    if (link) return renderShared(body, my, p, script, link);

    const refusal = h.el('p', { class: 'caption refusal', role: 'alert' });
    const apply = (change) => {
      const latest = store.production(id);
      try {
        store.update(change(latest));
        return true;
      } catch (err) {
        refusal.textContent = err instanceof C.Refusal ? C.refusalText(err) : String(err.message || err);
        return false;
      }
    };
    const rerender = () => renderProduction(body, token, id);
    const next = C.next(p, script);
    const recording = C.current(p, script);
    const partHref = (part) => `?production=${encodeURIComponent(id)}&part=${encodeURIComponent(part)}`;

    // One name for every Take part on the sheet (the prototype's "Recording as"), optional as before.
    const performer = h.el('input', { class: 'field-input', type: 'text', name: 'performer', autocomplete: 'name', id: 'pl-performer',
                                      placeholder: 'Your name', value: performerName });
    performer.addEventListener('input', () => { performerName = performer.value; });
    const cards = C.castParts(script).map(part => {
      const st = C.stateOf(p, part.id);
      const actions = h.el('div', { class: 'pl-part-acts' });
      if (st.status === 'recording') {
        actions.append(h.el('a', { class: 'btn btn-primary', href: partHref(part.id) }, 'Record'));
      } else if (st.status === 'open' && !recording) {
        const form = h.el('form', { class: 'take-form', onsubmit: (e) => {
          e.preventDefault();
          if (apply(cur => C.take(cur, script, part.id, performer.value))) h.navigate(partHref(part.id));
        } }, h.el('button', { type: 'submit', class: part.id === next ? 'btn btn-primary' : 'btn btn-way',
                              'aria-label': `Take part: ${part.title}` }, 'Take part'));
        if (!C.isSpeaking(part.id)) {
          form.append(h.el('button', { type: 'button', class: 'btn btn-way', onclick: () => {
            if (apply(cur => C.leaveSilent(cur, script, part.id))) rerender();
          } }, 'Leave silent'));
        }
        actions.append(form);
      } else if (st.status === 'done' || st.status === 'silent') {
        actions.append(h.el('button', { type: 'button', class: 'btn btn-way', disabled: !!recording, onclick: () => {
          if (apply(cur => C.reopen(cur, script, part.id))) h.navigate(partHref(part.id));
        } }, 'Open part'));
      }
      const held = st.status === 'recording' || st.status === 'done';
      const kept = part.lineCount - C.missingLines(p, script, part.id).length;
      const who = st.performer || null;
      const status = st.status === 'recording' ? `${who || 'Recording'} · ${num.format(kept)} of ${num.format(part.lineCount)}`
        : st.status === 'done' ? (who ? `${who} · recorded` : 'Recorded')
          : st.status === 'silent' ? 'Left silent' : heardAs(p, script, part.id);
      return partCard(script, part, { who, voice: !held, ok: st.status === 'done', mine: st.status === 'recording',
                                      status, href: partHref(part.id), actions });
    });

    const manage = h.el('div', { class: 'actions' });
    if (C.unusedTakes(p).length) {
      manage.append(h.el('button', { type: 'button', class: 'btn', onclick: async () => {
        await store.discardUnusedTakes(id);
        h.announce('Unused takes discarded');
        rerender();
      } }, 'Discard unused takes'));
    }
    manage.append(deleteButton(p));

    body.replaceChildren(
      playBoard(script, p.title, 'Ear drama', [progressLine(p, script)]),
      listenThrough(p, script, rerender),
      recording ? null : h.el('label', { class: 'pl-as', for: 'pl-performer' }, h.el('span', { class: 'body' }, 'Recording as'), performer),
      h.el('ul', { class: 'pl-grid', 'aria-label': 'Parts' }, cards),
      refusal,
      shareBox(p, script, rerender),
      manage);
    boardHeading(true);
  }

  function deleteButton(p) {
    return h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: async () => {
      if (!confirm(`Delete ${p.title}? Every take is removed from this browser.`)) return;
      if (mix && mix.id === p.id) { URL.revokeObjectURL(mix.url); mix = null; }
      await store.delete(p.id);
      h.navigate('?view=library&tab=dramas', true);
    } }, 'Delete production');
  }

  /* ---- Phase 2: a production shared through the Worker (PLAYS-DESIGN §11.7) ---- */

  /** Share (rule 1): signed in only; while the Worker is a placeholder it is not offered. */
  function shareBox(p, script, rerender) {
    const box = h.el('div', { class: 'share-box' });
    if (!API.plays.available()) return box;
    const line = h.el('p', { class: 'caption refusal', role: 'alert' });
    if (!API.account.signedIn()) {
      box.append(h.el('div', { class: 'actions' }, h.el('button', { type: 'button', class: 'btn', onclick: signIn }, 'Share')),
        h.el('p', { class: 'caption' }, 'Sharing needs an account.'));
      return box;
    }
    const name = h.el('input', { class: 'field-input', type: 'text', name: 'director', autocomplete: 'name', maxlength: '40',
                                 placeholder: 'Your name', 'aria-label': 'Your name, optional' });
    const go = h.el('button', { type: 'submit', class: 'btn' }, 'Share');
    box.append(h.el('form', { class: 'take-form', onsubmit: async (e) => {
      e.preventDefault();
      go.disabled = true;
      line.textContent = '';
      try {
        await S.share({ api: API.plays, store, local: store.production(p.id), script, displayName: name.value });
        h.announce('Shared');
        rerender();
      } catch (err) {
        console.error(err);
        line.textContent = S.line(err);
        go.disabled = false;
      }
    } }, name, go), line);
    return box;
  }

  function sharedStatus(rec, script, part) {
    const s = rec.parts[part.id] || { status: 'open' };
    const name = s.performer ? ` · ${s.performer}` : '';
    switch (s.status) {
      case 'recording': {
        const voiced = C.linesFor(script, part.id).filter(l => rec.chosen[l.id]).length;
        return `${num.format(voiced)} of ${lines(part.lineCount)} recorded${name}`;
      }
      case 'done': return `Recorded${name}`;
      case 'silent': return 'Left silent';
      default: return lines(part.lineCount);
    }
  }

  /** Report a take or a member (rule 8, guideline 1.2): a reason and an optional note. */
  function reportForm(pid, target, onDone) {
    const line = h.el('p', { class: 'caption refusal', role: 'alert' });
    const reason = h.el('select', { class: 'field-input', 'aria-label': 'Reason' },
      REASONS.map(([v, label]) => h.el('option', { value: v }, label)));
    const note = h.el('input', { class: 'field-input', type: 'text', maxlength: '500', placeholder: 'Note', 'aria-label': 'Note, optional' });
    const send = h.el('button', { type: 'submit', class: 'btn' }, 'Report');
    const form = h.el('form', { class: 'report-form', onsubmit: async (e) => {
      e.preventDefault();
      send.disabled = true;
      try {
        const n = note.value.trim();
        await API.plays.report({ production_id: pid, ...target, reason: reason.value, ...(n ? { note: n } : {}) });
        h.announce('Reported');
        onDone(true);
      } catch (err) {
        console.error(err);
        line.textContent = S.line(err);
        send.disabled = false;
      }
    } }, reason, note, send, h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => onDone(false) }, 'Cancel'), line);
    setTimeout(() => reason.focus(), 0);
    return form;
  }

  async function renderShared(body, my, p, script, link) {
    const id = p.id;
    sharedShown = id;
    const rerender = () => renderProduction(body, token, id);
    if (!canShare()) {
      const can = API.plays.available();
      body.replaceChildren(h.el('p', { class: 'caption' }, can ? 'Sign in to see this production.' : 'Not available yet.'),
        h.el('div', { class: 'actions' }, can ? h.el('button', { type: 'button', class: 'btn', onclick: signIn }, 'Sign in') : null,
          deleteButton(p)));
      return;
    }
    let rec;
    try { rec = await API.plays.get(link.pid); } catch (err) {
      if (my !== token) return;
      if (err.code === 'not_found') {
        body.replaceChildren(h.el('p', { class: 'caption refusal' }, S.line(err)), h.el('div', { class: 'actions' }, deleteButton(p)));
      } else failBox(body, err, () => rerender());
      return;
    }
    if (my !== token) return;
    const me = API.account.state().user_id;
    const local = await S.follow(store, id, rec, me);
    if (my !== token) return;
    const pid = link.pid;
    const line = h.el('p', { class: 'caption refusal', role: 'alert' });
    const act = async (btn, fn) => {
      btn.disabled = true;
      line.textContent = '';
      try { await fn(); rerender(); } catch (err) { console.error(err); line.textContent = S.line(err); btn.disabled = false; }
    };
    const button = (label, fn, cls = 'btn') => {
      const b = h.el('button', { type: 'button', class: cls, onclick: () => act(b, fn) }, label);
      return b;
    };
    const recording = S.recordingPart(rec);
    const partHref = (part) => `?production=${encodeURIComponent(id)}&part=${encodeURIComponent(part)}`;

    const rows = C.castParts(script).map(part => {
      const s = rec.parts[part.id] || { status: 'open' };
      const actions = h.el('div', { class: 'cast-actions' });
      if (S.isMine(rec, part.id, me)) {
        actions.append(h.el('a', { class: 'btn btn-accent', href: partHref(part.id) }, 'Record'),
          button('Release', () => API.plays.partAction(pid, part.id, 'release')));
      } else if (S.canClaim(rec, part.id)) {
        actions.append(button('Take part', () => API.plays.claim(pid, part.id), rec.next === part.id ? 'btn btn-accent' : 'btn'));
        if (!C.isSpeaking(part.id)) actions.append(button('Leave silent', () => API.plays.partAction(pid, part.id, 'silent')));
      } else if ((s.status === 'done' || s.status === 'silent') && (s.user_id === me || rec.director === me)) {
        const b = button('Open part', () => API.plays.partAction(pid, part.id, 'reopen'));
        b.disabled = !!recording;
        actions.append(b);
      }
      return h.el('li', { class: 'cast-row', dataset: { status: s.status } },
        h.el('a', { class: 'cast-main', href: partHref(part.id) },
          h.el('span', { class: 'body-strong' }, part.title),
          h.el('span', { class: 'caption' }, sharedStatus(rec, script, part))),
        actions.childNodes.length ? actions : null);
    });

    const mineBox = h.el('div', { class: 'share-box' });
    if (S.ownParts(rec, me).length) {
      const todo = S.pending(local, script, rec, me);
      const flagged = todo.filter(t => t.bleed).length;
      const ready = todo.length - flagged;
      const open = S.uploadsOpen(rec);
      const status = h.el('p', { class: 'caption refusal', role: 'alert' });
      const up = h.el('button', { type: 'button', class: 'btn', disabled: !ready || !open, onclick: async () => {
        up.disabled = true;
        status.textContent = '';
        const r = await S.upload({ api: API.plays, store, local: store.production(id), script, rec, me });
        if (my !== token) return;
        if (r.error) { console.error(r.error); status.textContent = S.line(r.error); up.disabled = false; return; }
        if (r.stopped) { if (r.stopped === 'uploads_off') status.textContent = S.line({ code: 'uploads_off' }); up.disabled = false; return; }
        h.announce(r.sent === 1 ? '1 take uploaded' : `${num.format(r.sent)} takes uploaded`);
        rerender();
      } }, ready === 1 ? 'Upload 1 take' : `Upload ${num.format(ready)} takes`);
      const voiced = S.myParts(rec, me).every(part => !C.isSpeaking(part) || C.linesFor(script, part).every(l => rec.chosen[l.id]));
      const done = h.el('button', { type: 'button', class: 'btn', disabled: ready > 0 || !voiced, onclick: () =>
        act(done, () => Promise.all(S.myParts(rec, me).map(part => API.plays.partAction(pid, part, 'done')))) }, 'Done with this part');
      mineBox.append(h.el('div', { class: 'actions' }, ready ? up : null, S.myParts(rec, me).length ? done : null), status);
      if (!open) status.textContent = S.line({ code: 'uploads_off' });
      else if (flagged) status.textContent = S.line({ code: 'bleed_flagged' });
    }

    body.replaceChildren(
      h.el('ul', { class: 'cast-list', 'aria-label': 'Parts' }, rows),
      line, mineBox,
      sharedListen(rec, local, script, pid, me, rerender),
      ...[changeBox(rec, script, pid, me, id)].filter(Boolean),
      peopleBox(rec, me, p, pid, rerender),
      h.el('div', { class: 'actions' }, deleteButton(p)));
  }

  /** The archive.org job in essential words (rule 9): quiet while waiting, the item's link, or the Worker's reason with Publish again. */
  function archiveLine(arch, rec, me, pid, rerender) {
    if (arch.kind === 'published') {
      return h.el('p', { class: 'caption', role: 'status' },
        arch.url ? h.el('a', { href: arch.url, target: '_blank', rel: 'noopener' }, arch.text) : arch.text);
    }
    if (arch.kind === 'waiting') return h.el('p', { class: 'caption', role: 'status' }, arch.text);
    const box = h.el('div', { class: 'archive-failed' }, h.el('p', { class: 'caption refusal', role: 'alert' }, arch.text));
    if (S.canPublishAgain(rec, me)) {
      const again = h.el('button', { type: 'button', class: 'btn', onclick: async () => {
        again.disabled = true;
        try { await API.plays.publish(pid); rerender(); } catch (err) {
          console.error(err);
          box.append(h.el('p', { class: 'caption refusal', role: 'alert' }, S.line(err)));
          again.disabled = false;
        }
      } }, 'Publish again');
      box.append(h.el('div', { class: 'actions' }, again));
    }
    return box;
  }

  /** Removed in this visit; the record carries no per-line archive state. */
  const removedHere = new Set();
  /** Replace or remove a line on the archive.org item (P12, rule 13). */
  function changeBox(rec, script, pid, me, id) {
    const items = S.changeableLines(rec, script, me);
    if (!items.length) return null;
    const ul = h.el('ul', { class: 'cast-list change-list' });
    for (const it of items) {
      const key = `${pid} ${it.line.id}`;
      const row = h.el('li', { class: 'change-row' }, lineView(it.line));
      if (removedHere.has(key)) {
        row.append(h.el('p', { class: 'caption', role: 'status' }, 'Removed'));
        ul.append(row);
        continue;
      }
      const acts = h.el('div', { class: 'take-row' });
      const fail = h.el('p', { class: 'caption refusal', role: 'alert' });
      let reason = null;
      if (it.replace) {
        acts.append(h.el('a', { class: 'btn', href: `?production=${encodeURIComponent(id)}&part=${encodeURIComponent(C.linePart(it.line))}&line=${encodeURIComponent(it.line.id)}` }, 'Replace'));
      }
      if (it.reason) {
        reason = h.el('select', { class: 'field-input', 'aria-label': 'Reason for removing' },
          REASONS.map(([v, label]) => h.el('option', { value: v }, label)));
        acts.append(reason);
      }
      const rm = h.el('button', { type: 'button', class: 'btn btn-destructive', onclick: async () => {
        if (!confirm('Remove this line from archive.org?')) return;
        rm.disabled = true;
        fail.textContent = '';
        try {
          await API.plays.removeLine(pid, it.line.id, reason ? reason.value : 'withdrawn');
          removedHere.add(key);
          h.announce('Line removed');
          row.replaceChildren(lineView(it.line), h.el('p', { class: 'caption', role: 'status' }, 'Removed'));
        } catch (err) { console.error(err); fail.textContent = S.line(err); rm.disabled = false; }
      } }, 'Remove');
      acts.append(rm);
      row.append(acts, fail);
      ul.append(row);
    }
    return h.el('details', { class: 'block change-lines' }, h.el('summary', { class: 'section-header' }, rec.director === me ? 'Lines' : 'Your lines'), ul);
  }

  /**
   * Listen through any time (rule 7, C5): the other members' chosen takes come
   * into this browser first, then phase 1's listen-through plays the takes and
   * reads the open lines live. Publish asks the consent first (consentSheet).
   */
  const dismissedConsent = new Set();
  function sharedListen(rec, local, script, pid, me, rerender) {
    let box;
    if (S.inStep(local, script, rec, me)) {
      box = listenThrough(store.production(local.id), script, rerender);
    } else {
      const status = h.el('p', { class: 'caption', role: 'status' });
      const go = h.el('button', { type: 'button', class: 'btn btn-primary', onclick: async () => {
        go.disabled = true;
        status.textContent = 'Getting the takes';
        try {
          await S.bringHome({ api: API.plays, store, localId: local.id, rec, script, me });
          rerender();
        } catch (err) { console.error(err); status.textContent = S.line(err); go.disabled = false; }
      } }, svg('play', 'i-inline'), 'Listen through');
      box = h.el('section', { class: 'block listen', 'aria-labelledby': 'listen-through-h' },
        h.el('h2', { class: 'section-header', id: 'listen-through-h' }, 'Listen through'), go, status);
    }
    if (rec.hidden_takes) {
      box.append(h.el('p', { class: 'caption' }, rec.hidden_takes === 1 ? '1 take is hidden from you.'
        : `${num.format(rec.hidden_takes)} takes are hidden from you.`));
    }
    const arch = S.archiveStatus(rec);
    if (arch) {
      box.append(archiveLine(arch, rec, me, pid, rerender));
    } else if (S.canPublish(rec, script, me) || S.needsMyConsent(rec, script, me)) {
      const slot = h.el('div');
      box.append(slot);
      API.plays.consent().then((c) => {
        if (c.publishes !== true) {
          if (rec.director === me) slot.append(h.el('p', { class: 'caption', role: 'status' }, S.PUBLISH_WAITS));
          return;
        }
        const line = h.el('p', { class: 'caption refusal', role: 'alert' });
        if (rec.director !== me) {
          if (dismissedConsent.has(pid)) return;
          const agree = h.el('button', { type: 'button', class: 'btn btn-primary', onclick: async () => {
            agree.disabled = true;
            line.textContent = '';
            try { await S.agreeToPublish({ api: API.plays, store, local, pid, consent: c }); rerender(); }
            catch (err) { console.error(err); line.textContent = S.line(err); agree.disabled = false; }
          } }, 'I agree to publish my recording under CC0.');
          const later = h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => { dismissedConsent.add(pid); slot.remove(); } }, 'Not now');
          slot.append(consentView(c.text), h.el('div', { class: 'actions' }, agree), h.el('div', { class: 'actions' }, later), line);
          return;
        }
        const waiting = S.waitingOn(rec);
        const pub = h.el('button', { type: 'button', class: 'btn', disabled: waiting.length > 0, onclick: () => consentSheet(c, async () => {
          pub.disabled = true;
          line.textContent = '';
          try { await S.publishPlay({ api: API.plays, store, local, pid, consent: c }); rerender(); }
          catch (err) { console.error(err); line.textContent = S.line(err); pub.disabled = false; }
        }) }, 'Publish');
        const agreed = h.el('ul', { class: 'cast-list agreed-list', 'aria-label': 'Agreed to publish' },
          S.performers(rec).map(m => h.el('li', { class: 'cast-row' },
            h.el('span', { class: 'body-strong' }, m.display_name || 'No name'),
            h.el('span', { class: m.consented ? 'take-chosen' : 'caption', role: 'img', 'aria-label': m.consented ? 'Agreed' : 'Not yet' },
              m.consented ? svg('check') : '\u25CB'))));
        slot.append(agreed, h.el('div', { class: 'actions' }, pub), line);
      }).catch((err) => console.error(err));
    }
    return box;
  }

  /** The served consent words as a lead and a list, none changed. */
  function consentView(text) {
    const wrap = h.el('div', { class: 'consent-text' });
    let ul = null;
    for (const b of S.consentBlocks(text)) {
      if (b.kind === 'item') {
        if (!ul) { ul = h.el('ul', { class: 'consent-list' }); wrap.append(ul); }
        ul.append(h.el('li', {}, b.text));
      } else {
        ul = null;
        wrap.append(h.el('p', { class: b.kind === 'lead' ? 'body-strong' : '' }, b.text));
      }
    }
    return wrap;
  }

  /** The CC0 consent (rule 6): the Worker's words exactly as served, then I agree or Not now. */
  function consentSheet(c, onAgree) {
    const d = h.el('dialog', { class: 'account-sheet consent-sheet', 'aria-labelledby': 'consent-h' });
    d.addEventListener('close', () => d.remove());
    d.append(
      h.el('h2', { id: 'consent-h', class: 'section-header' }, 'Publish'),
      consentView(c.text),
      h.el('div', { class: 'actions' },
        h.el('button', { type: 'button', class: 'btn btn-primary', onclick: () => { d.close(); onAgree(); } }, 'I agree to publish my recording under CC0.')),
      h.el('div', { class: 'actions' },
        h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => d.close() }, 'Not now')));
    document.body.append(d);
    d.showModal();
  }

  /** The people in a production, by display name only: Invite for the director; Report and Block for everyone else (rules 2, 8). */
  function peopleBox(rec, me, p, pid, rerender) {
    const ul = h.el('ul', { class: 'cast-list', 'aria-labelledby': 'people-h' });
    for (const m of rec.members) {
      const row = h.el('li', { class: 'cast-row' });
      const who = m.display_name || 'No name';
      const tag = m.user_id === me ? 'You' : m.director ? 'Director' : '';
      row.append(h.el('div', { class: 'cast-main' }, h.el('span', { class: 'body-strong' }, who),
        tag ? h.el('span', { class: 'caption' }, tag) : null));
      if (m.user_id !== me) {
        const acts = h.el('div', { class: 'cast-actions' });
        const report = h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => {
          acts.replaceWith(reportForm(pid, { user_id: m.user_id }, () => rerender()));
        } }, 'Report');
        const block = h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: async () => {
          if (!confirm(`Block ${who}? You will no longer hear their takes.`)) return;
          block.disabled = true;
          try { await API.plays.block(m.user_id); h.announce(`${who} blocked`); rerender(); } catch (err) { console.error(err); block.disabled = false; }
        } }, 'Block');
        acts.append(report, block);
        row.append(acts);
      }
      ul.append(row);
    }
    const box = h.el('section', { class: 'block', 'aria-labelledby': 'people-h' },
      h.el('h2', { class: 'section-header', id: 'people-h' }, 'People'), ul);
    if (rec.director === me) {
      const slot = h.el('div', { class: 'invite-slot' });
      const line = h.el('p', { class: 'caption refusal', role: 'alert' });
      const inv = h.el('button', { type: 'button', class: 'btn', onclick: async () => {
        inv.disabled = true;
        line.textContent = '';
        try {
          const made = await API.plays.invite(pid);
          const url = S.inviteLink(made.token, location.origin);
          const field = h.el('input', { class: 'field-input', type: 'text', readonly: true, value: url, 'aria-label': 'Invite link' });
          const days = Math.max(1, Math.round((made.expires_at - Date.now()) / 86400000));
          slot.replaceChildren(h.el('div', { class: 'take-form' }, field,
            h.el('button', { type: 'button', class: 'btn', onclick: async () => {
              try { if ((await shareTarget({ title: p.title, text: p.title, url })) === 'copied') h.announce('Link copied'); } catch { field.select(); }
            } }, 'Share link')),
            h.el('p', { class: 'caption' }, days === 1 ? 'Works for 1 day.' : `Works for ${num.format(days)} days.`));
          inv.disabled = false;
        } catch (err) { console.error(err); line.textContent = S.line(err); inv.disabled = false; }
      } }, 'Invite');
      box.append(h.el('div', { class: 'actions' }, inv), slot, line);
    }
    return box;
  }

  /* ---- An invite link (rule 3, DEEP_LINKS.md): joining takes the person's tap, signed in ---- */

  const inviteStatus = (pt) => ({ recording: 'Recording', done: 'Recorded', silent: 'Left silent' })[pt.status] || lines(pt.lineCount);

  async function inviteBox(my) {
    const tok = S.pendingInvite();
    const box = h.el('section', { class: 'block invite', 'aria-labelledby': 'invite-h' },
      h.el('h2', { class: 'section-header', id: 'invite-h' }, 'Invitation'));
    const line = h.el('p', { class: 'caption refusal', role: 'alert' });
    const dismiss = h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => {
      S.holdInvite(null);
      box.remove();
    } }, 'Not now');
    if (!API.plays.available()) {
      box.append(h.el('p', { class: 'caption' }, 'Not available yet.'), h.el('div', { class: 'actions' }, dismiss));
      return box;
    }
    if (!API.account.signedIn()) {
      box.append(h.el('div', { class: 'actions' },
        h.el('button', { type: 'button', class: 'btn btn-primary', onclick: signIn }, 'Sign in to join'), dismiss));
      return box;
    }
    let inv;
    try { inv = await API.plays.viewInvite(tok); } catch (err) {
      console.error(err);
      line.textContent = S.line(err);
      box.append(line, h.el('div', { class: 'actions' }, dismiss));
      return box;
    }
    if (my !== token) return box;
    const script = S.scriptFor(await API.castableScripts().catch(() => []), inv.scriptID, inv.scriptRevision);
    box.append(h.el('p', { class: 'body-strong' }, inv.title));
    const busy = inv.parts.some(pt => pt.status === 'recording');
    const ul = h.el('ul', { class: 'cast-list', 'aria-label': 'Parts' });
    for (const pt of inv.parts) {
      const row = h.el('li', { class: 'cast-row', dataset: { status: pt.status } },
        h.el('div', { class: 'cast-main' }, h.el('span', { class: 'body-strong' }, C.partTitle(pt.id)),
          h.el('span', { class: 'caption' }, inviteStatus(pt))));
      if (pt.status === 'open' && !busy && script && !inv.member) {
        const name = h.el('input', { class: 'field-input', type: 'text', name: 'performer', autocomplete: 'name', maxlength: '40',
                                     placeholder: 'Your name', 'aria-label': `Your name, optional, for ${C.partTitle(pt.id)}` });
        const go = h.el('button', { type: 'submit', class: pt.id === inv.next ? 'btn btn-accent' : 'btn' }, 'Take part');
        row.append(h.el('div', { class: 'cast-actions' }, h.el('form', { class: 'take-form', onsubmit: async (e) => {
          e.preventDefault();
          go.disabled = true;
          line.textContent = '';
          try {
            const { local } = await S.join({ api: API.plays, store, token: tok, part: pt.id, displayName: name.value, script });
            S.holdInvite(null);
            h.navigate(`?production=${encodeURIComponent(local.id)}`, true);
          } catch (err) { console.error(err); line.textContent = S.line(err); go.disabled = false; }
        } }, name, go)));
      }
      ul.append(row);
    }
    box.append(ul, line);
    if (!script) line.textContent = S.line({ code: 'revision_mismatch' });
    const acts = h.el('div', { class: 'actions' });
    if (inv.member && script) {
      acts.append(h.el('button', { type: 'button', class: 'btn', onclick: async () => {
        try {
          const local = await S.localFor(store, inv.id, script);
          S.holdInvite(null);
          h.navigate(`?production=${encodeURIComponent(local.id)}`, true);
        } catch (err) { console.error(err); line.textContent = S.line(err); }
      } }, 'Open'));
    }
    acts.append(dismiss);
    box.append(acts);
    return box;
  }

  /* ---- Classes (rule 10, Decision 059): a teacher makes one and shares its code; a student joins with it ---- */

  async function classesBox(my) {
    const box = h.el('section', { class: 'block', 'aria-labelledby': 'classes-h' },
      h.el('h2', { class: 'section-header', id: 'classes-h' }, 'Classes'));
    const line = h.el('p', { class: 'caption refusal', role: 'alert' });
    const redraw = async () => { const b = await classesBox(my); box.replaceWith(b); };
    let list = { teaching: [], member_of: [] };
    try { list = await API.plays.classes(); } catch (err) { console.error(err); line.textContent = S.line(err); }
    const rows = [
      ...list.teaching.map(c => h.el('li', { class: 'cast-row' },
        h.el('div', { class: 'cast-main' }, h.el('span', { class: 'body-strong' }, c.name),
          c.under13 && !c.school_consent ? h.el('span', { class: 'caption' }, 'Waits for the school’s consent') : null),
        h.el('span', { class: 'class-code tabular body-strong', 'aria-label': `Code ${c.code.split('').join(' ')}` },
          `${c.code.slice(0, 4)} ${c.code.slice(4)}`))),
      ...list.member_of.map(c => h.el('li', { class: 'cast-row' },
        h.el('div', { class: 'cast-main' }, h.el('span', { class: 'body-strong' }, c.name)))),
    ];
    if (rows.length) box.append(h.el('ul', { class: 'cast-list', 'aria-label': 'Classes' }, rows));

    const cname = h.el('input', { class: 'field-input', type: 'text', maxlength: '40', placeholder: 'Class name',
                                  'aria-label': 'Class name', required: true });
    const under = h.el('input', { type: 'checkbox', id: 'class-under13' });
    const make = h.el('button', { type: 'submit', class: 'btn' }, 'Make a class');
    const code = h.el('input', { class: 'field-input class-code-input', type: 'text', maxlength: '12', placeholder: 'Class code',
                                 'aria-label': 'Class code', autocomplete: 'off', autocapitalize: 'characters', spellcheck: 'false', required: true });
    const sname = h.el('input', { class: 'field-input', type: 'text', maxlength: '40', autocomplete: 'name', placeholder: 'Your name',
                                  'aria-label': 'Your name, optional' });
    const join = h.el('button', { type: 'submit', class: 'btn' }, 'Join a class');
    const submit = (btn, fn) => async (e) => {
      e.preventDefault();
      btn.disabled = true;
      line.textContent = '';
      try { await fn(); await redraw(); } catch (err) { console.error(err); line.textContent = S.line(err); btn.disabled = false; }
    };
    box.append(
      h.el('form', { class: 'take-form class-form', onsubmit: submit(make, () => API.plays.createClass(cname.value, under.checked)) },
        cname, h.el('label', { class: 'check', for: 'class-under13' }, under, h.el('span', { class: 'body' }, 'Under 13')), make),
      h.el('form', { class: 'take-form class-form', onsubmit: submit(join, () => API.plays.joinClass(code.value, sname.value)) },
        code, sname, join),
      line);
    return box;
  }
  /**
   * Listen through any time (C5, owner 2026-10-23). Until every speaking line is
   * human, the takes play and the open lines are read live by the device voice,
   * labeled (ListenThrough); then the rendered mix plays, hearing it to the end
   * without seeking ahead finishes the play, and Export is offered.
   */
  function listenThrough(p, script, rerender) {
    const box = h.el('section', { class: 'block listen', 'aria-labelledby': 'listen-through-h' },
      h.el('h2', { class: 'section-header', id: 'listen-through-h' }, 'Listen through'));
    if (!C.isComplete(p, script)) {
      liveListen(box, p, script);
      return box;
    }
    const from = C.fingerprint(p);
    const status = h.el('p', { class: 'caption', role: 'status' });
    const slot = h.el('div', { class: 'listen-slot' });
    const finished = C.isFinished(p);
    const play = h.el('button', { type: 'button', class: 'btn btn-primary', onclick: () => prepare(true) },
      svg('play', 'i-inline'), finished ? 'Play' : 'Listen through');

    function attach(autoplay) {
      const audio = h.el('audio', { class: 'mix-audio', controls: true, preload: 'auto', src: mix.url,
                                    'aria-label': `${p.title}, the mix` });
      audio.muted = muted;
      let last = 0;
      let skipped = false;
      audio.addEventListener('timeupdate', () => { if (!audio.seeking) last = audio.currentTime; });
      audio.addEventListener('seeking', () => { if (audio.currentTime > last + 1) skipped = true; });
      audio.addEventListener('play', () => { if (typeof Player !== 'undefined') Player.pause(); });
      audio.addEventListener('ended', async () => {
        if (skipped || C.isFinished(store.production(p.id))) return;
        await store.markListenedThrough(p.id, from);
        h.announce('Finished');
        rerender();
      });
      slot.replaceChildren(audio);
      play.remove();
      if (autoplay) audio.play().catch(() => {});
    }

    async function prepare(autoplay) {
      play.disabled = true;
      status.textContent = 'Mixing';
      try {
        const blob = await store.renderMix(p.id, LiveAudio.offlineContext);
        if (mix) URL.revokeObjectURL(mix.url);
        mix = { id: p.id, from, url: URL.createObjectURL(blob) };
        status.textContent = '';
        attach(autoplay);
      } catch (err) {
        console.error(err);
        status.textContent = 'The mix did not render.';
        play.disabled = false;
      }
    }

    box.append(play, slot, status);
    if (mix && mix.id === p.id && mix.from === from) attach(false);
    box.append(h.el('div', { class: 'actions' }, h.el('button', { type: 'button', class: 'btn', onclick: async () => {
      try { await store.exportMix(p.id, LiveAudio.offlineContext); } catch (err) { console.error(err); status.textContent = 'The mix did not export.'; }
    } }, 'Export')));
    return box;
  }

  /** The live listen-through of a play not yet fully voiced. Writes nothing (§5). */
  function liveListen(box, p, script) {
    if (listen) listen.end();
    const slot = h.el('div', { class: 'listen-now', 'aria-live': 'polite' });
    const control = h.el('button', { type: 'button', class: 'btn btn-primary' });
    const l = ListenThrough.create({
      production: p, script, store,
      audio: LiveAudio.create({ muted }), voice: StandInVoice.create({ muted }),
      onChange: () => paint(),
    });
    listen = l;
    control.addEventListener('click', () => {
      if (l.playing) { l.stop(); return; }
      if (typeof Player !== 'undefined') Player.pause();
      l.play();
    });
    function paint() {
      if (listen !== l) return;
      control.replaceChildren(svg(l.playing ? 'stop' : 'play', 'i-inline'), l.playing ? 'Stop' : 'Listen through');
      const entry = l.playing ? l.current() : null;
      const line = entry && script.lines.find(x => x.id === entry.lineID);
      slot.replaceChildren();
      if (!line) return;
      if (entry.source === 'voice') slot.append(h.el('p', { class: 'caption device-voice' }, svg('wave', 'i-inline'), 'Device voice'));
      slot.append(lineView(line));
    }
    paint();
    if (!l.plan.length) control.disabled = true;
    box.append(control, slot);
  }

  /* ---- A part: recording it, or reading along ---- */

  async function renderPart(body, my, id, part, lineId) {
    const key = `${id} ${part}`;
    if (rec && rec.key === key) { paintRecording(); return; }
    body.replaceChildren(h.stateBox('loading'));
    let got;
    try { got = await production(my, id); } catch (err) {
      if (my === token) failBox(body, err, () => renderPart(body, my, id, part));
      return;
    }
    if (!got) return;
    const { p, script } = got;
    if (!p || !script || !C.castParts(script).some(x => x.id === part)) { notOnDevice(body); return; }
    const title = C.partTitle(part);
    h.setTitle(title, p.title);
    $('plays-h').textContent = title;
    const back = h.el('a', { class: 'eyebrow-link section-header', href: `?production=${encodeURIComponent(id)}` }, p.title);
    const link = store.share(id);
    let replacing = false;
    if (link && canShare()) {
      let remote = null;
      try { remote = await API.plays.get(link.pid); } catch (err) { console.error(err); }
      if (my !== token) return;
      if (remote) {
        const me = API.account.state().user_id;
        const local = await S.follow(store, id, remote, me);
        if (my !== token) return;
        replacing = !!lineId && S.ownParts(remote, me).includes(part) && S.published(remote)
          && C.linesFor(script, part).some(l => l.id === lineId);
        if (!S.isMine(remote, part, me) && !replacing) { sharedReadAlong(body, back, local, script, part, remote, link.pid, my); return; }
      }
    }
    if (!replacing && C.stateOf(store.production(id), part).status !== 'recording') {
      body.replaceChildren(back, h.el('ol', { class: 'read-along' },
        C.linesFor(script, part).map(l => h.el('li', {}, lineView(l)))));
      return;
    }
    rec = { key, id, part, script, s: null, index: 0, headphones: false, back, line: replacing ? lineId : null };
    paintRecording();
  }

  /** Another member's part: the lines with the takes the Worker shows this person, each playable and reportable (rule 8). */
  function sharedReadAlong(body, back, local, script, part, rec, pid, my) {
    let player = null;
    const play = async (btn, takeId) => {
      btn.disabled = true;
      try {
        const bytes = await API.plays.audio(pid, takeId);
        if (my !== token) return;
        if (player) { player.pause(); URL.revokeObjectURL(player.src); }
        player = new Audio(URL.createObjectURL(new Blob([bytes], { type: 'audio/wav' })));
        player.muted = muted;
        if (typeof Player !== 'undefined') Player.pause();
        await player.play().catch(() => {});
      } catch (err) { console.error(err); h.announce(S.line(err)); }
      btn.disabled = false;
    };
    const items = C.linesFor(script, part).map(l => {
      const li = h.el('li', {}, lineView(l));
      const takeId = rec.chosen[l.id];
      if (takeId) {
        const acts = h.el('div', { class: 'take-row' });
        const b = h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => play(b, takeId) }, svg('play', 'i-inline'), 'Take');
        acts.append(b, h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => {
          acts.replaceWith(reportForm(pid, { take_id: takeId }, () => renderPart(body, ++token, local.id, part)));
        } }, 'Report'));
        li.append(acts);
      }
      return li;
    });
    body.replaceChildren(back, h.el('ol', { class: 'read-along' }, items));
  }
  function startRecording() {
    if (!API.account.signedIn()) { paintRecording(); return; }
    const p = store.production(rec.id);
    if (typeof Player !== 'undefined') Player.pause();
    const audio = LiveAudio.create({ muted });
    const voice = StandInVoice.create({ muted });
    const r = rec;
    const s = RecordingSession.create({
      production: p, script: rec.script, part: rec.part, store, audio, voice,
      announce: async () => h.announce('Your line'),
      onChange: () => { if (rec === r) paintRecording(); },
    });
    rec.s = s;
    rec.index = Math.max(0, s.lines.findIndex(l => rec.line ? l.id === rec.line : !C.usableTake(p, l.id)));
    s.begin();
    paintRecording();
  }

  function failure(s) {
    if (!s || s.phase.kind !== 'failed') return null;
    const reason = s.phase.reason;
    if (reason === 'NotAllowedError' || reason === 'SecurityError') return 'Ear Drama needs the microphone to record your part. Allow it for this site in the browser\'s settings.';
    if (reason === 'NotFoundError' || reason === 'OverconstrainedError') return 'No microphone found.';
    if (reason === 'save') return 'This take was not saved.';
    return 'Recording did not start.';
  }

  /** The recorder's top slot: close, the part over the play, and the lines kept. */
  function recTop(title, sub, count) {
    return h.el('div', { class: 'pl-top' },
      h.el('a', { class: 'icon-btn', href: rec.back.getAttribute('href'), 'aria-label': `Close, back to ${sub}` }, svg('down')),
      h.el('div', { class: 'pl-top-t' }, h.el('h1', { class: 'pl-top-part', tabindex: '-1' }, title), h.el('p', { class: 'caption pl-top-play' }, sub)),
      count ? h.el('span', { class: 'pl-top-count tabular' }, count) : h.el('span'));
  }

  function paintRecording() {
    if (!rec) return;
    const body = $('plays-body');
    const s = rec.s;
    const failed = failure(s);
    const title = C.partTitle(rec.part);
    const play = rec.back.textContent;
    boardHeading(true);
    clearInterval(rec.clock);
    if (!s || !s.started) {
      body.replaceChildren(h.el('div', { class: 'pl-rec pl-rec-pre' }, recTop(title, play, ''), startScreen(failed)));
      return;
    }
    if (s.phase.kind === 'roomTone') {
      body.replaceChildren(h.el('div', { class: 'pl-rec pl-rec-pre' }, recTop(title, play, ''),
        h.el('div', { class: 'pl-pre', role: 'status' },
          h.el('p', { class: 'body-strong' }, 'Quiet, please. Recording the room.'),
          h.el('p', { class: 'pl-countdown tabular' }, String(s.phase.secondsLeft)))));
      return;
    }
    // A repaint keeps the keyboard where it was: the control that had focus keeps it.
    const had = document.activeElement && document.activeElement.dataset ? document.activeElement.dataset.act : null;
    follow(s);
    body.replaceChildren(recorder(s, failed, title, play));
    if (had) { const b = body.querySelector(`[data-act="${had}"]:not(:disabled)`); if (b) b.focus({ preventScroll: true }); }
    if (s.phase.kind === 'listening') {
      const t0 = Date.now();
      const out = body.querySelector('.pl-rec-time');
      rec.clock = setInterval(() => {
        const sec = Math.floor((Date.now() - t0) / 1000);
        if (out) out.textContent = `Recording ${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}`;
      }, 500);
    }
  }

  /** During a run the recorder follows the play: the line on screen is the part's next line. */
  function follow(s) {
    const id = s.phase.lineID;
    if (!id || !(s.run || s.phase.kind === 'listening')) return;
    const at = s.script.lines.findIndex(l => l.id === id);
    const next = s.lines.findIndex(l => s.script.lines.findIndex(x => x.id === l.id) >= at);
    if (next >= 0) rec.index = next;
  }

  /** Headphones only (PLAYS-DESIGN §4.3): the web cannot see the audio route, so the person says. */
  function startScreen(failed) {
    const box = h.el('div', { class: 'pl-pre' }, svg('headphones', 'pl-pre-icon'));
    if (!LiveAudio.supported()) {
      box.append(h.el('p', { class: 'body' }, 'This browser cannot record.'));
      return box;
    }
    if (!API.account.signedIn()) {
      const avail = API.account.available();
      box.append(
        h.el('p', { class: 'body' }, 'Recording needs an account.'),
        h.el('button', { type: 'button', class: 'btn btn-primary', disabled: !(avail.apple || avail.google), onclick: () => {
          AccountUI.openSheet();
          const sheet = document.querySelector('dialog.account-sheet');
          if (sheet) sheet.addEventListener('close', () => paintRecording(), { once: true });
        } }, 'Sign in'));
      return box;
    }
    const start = h.el('button', { type: 'button', class: 'btn btn-record pl-go', disabled: !rec.headphones,
                                   onclick: () => startRecording() }, svg('mic', 'i-inline'), 'Start recording');
    const check = h.el('input', { type: 'checkbox', id: 'rec-headphones', checked: rec.headphones,
                                  onchange: () => { rec.headphones = check.checked; start.disabled = !check.checked; } });
    box.append(
      h.el('h2', { class: 'pl-pre-h' }, 'Headphones on'),
      h.el('p', { class: 'body pl-pre-why' }, 'This browser cannot tell whether they are on.'),
      h.el('label', { class: 'pl-check', for: 'rec-headphones' }, check, h.el('span', { class: 'body-strong' }, 'My headphones are on')),
      start);
    if (failed) box.append(h.el('p', { class: 'caption refusal', role: 'alert' }, failed));
    return box;
  }

  const MODE_LABEL = { run: 'Run through', lines: 'Line by line', step: 'Step' };
  const secs = (t) => `${(t.frames / t.sampleRate).toFixed(1)} s`;

  /** A script line in the scene: the speaker's face, name and who it is heard as, then the words. */
  function sceneLine(s, line, cls, playing = false) {
    const part = C.linePart(line);
    const heard = heardAs(s.production, s.script, part, line.id);
    const voice = heard === 'Device voice';
    return h.el('div', { class: `pl-ln ${cls}`.trim(), dataset: { hue: hueOf(s.script, part) } },
      face(s.script, part, { who: C.stateOf(s.production, part).performer, voice, size: 'sm', now: playing }),
      h.el('div', { class: 'pl-ln-body' },
        h.el('p', { class: 'pl-ln-who' }, h.el('span', {}, line.role || C.partTitle(part)), h.el('span', { class: 'pl-tag' }, heard)),
        lineWords(line, 'pl-say')));
  }

  /** The words of a line, its printed directions apart (§3); nothing rewritten. */
  function lineWords(line, cls) {
    const text = h.el('p', { class: cls });
    if (line.kind === 'speech') {
      (line.parts || []).forEach((piece, i) => {
        if (i) text.append(' ');
        const words = C.pieceText(piece);
        text.append(C.pieceKind(piece) === 'say' ? words : h.el('span', { class: 'line-aside' }, `(${words})`));
      });
    } else text.append(h.el('span', { class: 'line-aside' }, line.source || ''));
    return text;
  }

  /** The takes of a line as numbered choices: the chosen one filled; choosing never deletes (§8 rule 5). */
  function takeChoices(s, line, busy) {
    const takes = C.takesFor(s.production, line.id);
    if (!takes.length) return null;
    return h.el('span', { class: 'pl-takes', role: 'group', 'aria-label': 'Takes' }, takes.map((t, i) => {
      const on = s.production.chosen[line.id] === t.id;
      return h.el('button', { type: 'button', class: `pl-take-n${on ? ' on' : ''}`, 'aria-pressed': String(on), disabled: busy,
                              'aria-label': `Take ${i + 1}`, onclick: () => s.choose(t) }, String(i + 1));
    }));
  }

  /** Your line's box: your part's board; dashed red while armed, solid red while the microphone is open. */
  function mineBox(s, line, head, busy) {
    const ph = s.phase;
    const listening = ph.kind === 'listening' && ph.lineID === line.id;
    const armed = ph.kind === 'cue' && !listening && (s.run || C.cueLines(s.script, line.id, true).some(c => c.id === ph.lineID));
    const review = ph.kind === 'review' && ph.lineID === line.id;
    const chosen = C.chosenTake(s.production, line.id);
    let pill = takeChoices(s, line, busy);
    if (armed) pill = h.el('span', { class: 'pl-pill redo' }, h.el('span', { class: 'dot' }), 'Next');
    if (listening) pill = h.el('span', { class: 'pl-pill red pl-rec-time', role: 'status' }, h.el('span', { class: 'dot' }), 'Recording 0:00');
    const box = h.el('div', { class: `pl-mine${armed ? ' armed' : ''}${listening ? ' on' : ''}`, dataset: { hue: hueOf(s.script, s.part) } },
      h.el('p', { class: 'pl-mine-who' }, h.el('span', {}, head), pill),
      lineWords(line, 'pl-mine-say'));
    if (chosen && (review || ph.kind === 'idle')) {
      box.append(h.el('div', { class: 'pl-take' },
        h.el('button', { type: 'button', class: 'pl-play-dot', disabled: busy, 'aria-label': 'Play the take', onclick: () => s.playTake(chosen) }, svg('play')),
        h.el('span', { class: 'pl-take-len tabular' }, secs(chosen))));
    }
    if (chosen && chosen.bleed) {
      box.append(h.el('p', { class: 'pl-warn', role: 'alert' }, svg('warn'),
        'The microphone heard the device voice. Re-take this line with headphones.'));
    }
    return box;
  }

  /** Step and Run through: the line before, the cue card, your line, the next line. */
  function stage(s, line, busy) {
    const all = s.script.lines;
    const k = all.findIndex(l => l.id === line.id);
    const ph = s.phase;
    const playingID = ph.kind === 'cue' ? ph.lineID : null;
    let cue = C.cueLines(s.script, line.id)[0] || null;
    if (playingID && playingID !== line.id && (!cue || playingID !== cue.id)) cue = all.find(l => l.id === playingID) || cue;
    const out = [];
    const ci = cue ? all.findIndex(l => l.id === cue.id) : k;
    const before = all.slice(0, ci).filter(l => l.kind === 'speech').pop();
    if (before) out.push(sceneLine(s, before, 'past'));
    if (cue) out.push(h.el('div', { class: `pl-cue${playingID === cue.id ? ' on' : ''}` }, sceneLine(s, cue, '', playingID === cue.id)));
    out.push(mineBox(s, line, `${C.partTitle(s.part)} · You`, busy));
    const after = all.slice(k + 1).find(l => l.kind === 'speech');
    if (after) out.push(sceneLine(s, after, 'next'));
    return out;
  }

  /** Line by line: every line of the part; the one selected opens in place with its cue. */
  function lineList(s, busy) {
    return h.el('ol', { class: 'pl-lx-list' }, s.lines.map((line, i) => {
      if (i === rec.index) {
        const listening = s.phase.kind === 'listening' && s.phase.lineID === line.id;
        const cue = C.cueLines(s.script, line.id)[0];
        return h.el('li', { class: 'pl-lx sel' },
          cue ? h.el('div', { class: `pl-cue${s.phase.kind === 'cue' && s.phase.lineID === cue.id ? ' on' : ''}` }, sceneLine(s, cue, '')) : null,
          mineBox(s, line, `Line ${num.format(i + 1)}`, busy),
          h.el('div', { class: 'pl-lx-acts' },
            listening
              ? h.el('button', { type: 'button', class: 'btn btn-record', dataset: { act: 'stop' }, onclick: () => s.stopListening() }, svg('stop', 'i-inline'), 'Stop')
              : h.el('button', { type: 'button', class: 'btn btn-record', dataset: { act: 'record' }, disabled: busy, onclick: () => s.record(line.id) }, svg('mic', 'i-inline'), 'Record'),
            cue ? h.el('button', { type: 'button', class: 'btn btn-way', dataset: { act: 'cue' }, disabled: busy, onclick: () => s.playCue(line.id) }, svg('play', 'i-inline'), 'Cue') : null));
      }
      const t = C.chosenTake(s.production, line.id);
      const n = t ? C.takesFor(s.production, line.id).findIndex(x => x.id === t.id) + 1 : 0;
      const st = !t ? h.el('span', { class: 'pl-lx-st' }, 'Not yet')
        : t.bleed ? h.el('span', { class: 'pl-lx-st warn' }, svg('warn'), 'Re-take')
          : h.el('span', { class: 'pl-lx-st kept' }, svg('check'), `Take ${n}`);
      return h.el('li', {}, h.el('button', { type: 'button', class: 'pl-lx', disabled: busy, onclick: () => { rec.index = i; paintRecording(); } },
        h.el('span', { class: 'pl-lx-n tabular' }, String(i + 1)), lineWords(line, 'pl-lx-say'), st));
    }));
  }

  /** After a run: the takes it made, each heard with its cue; keep them all, or record any again. */
  function runReview(s) {
    const takes = s.runTakes();
    return [
      h.el('h2', { class: 'section-header' }, `This run · ${takes.length === 1 ? '1 take' : `${num.format(takes.length)} takes`}`),
      h.el('ol', { class: 'pl-rv-list' }, takes.map(t => {
        const line = s.script.lines.find(l => l.id === t.lineID);
        const n = s.lines.findIndex(l => l.id === t.lineID) + 1;
        return h.el('li', { class: 'pl-rv' },
          h.el('p', { class: 'caption tabular' }, `Line ${num.format(n)}`),
          lineWords(line, 'pl-say'),
          t.bleed ? h.el('p', { class: 'pl-warn', role: 'alert' }, svg('warn'), 'The microphone heard the device voice. Re-take this line with headphones.') : null,
          h.el('div', { class: 'pl-take' },
            h.el('button', { type: 'button', class: 'pl-play-dot', 'aria-label': `Play line ${n} with its cue`, onclick: () => s.playWithCue(t) }, svg('play')),
            h.el('span', { class: 'pl-take-len tabular' }, secs(t)),
            h.el('button', { type: 'button', class: 'btn btn-again', dataset: { act: 'again' }, onclick: () => s.record(t.lineID) },
              h.el('span', { class: 'dot' }), 'Again')));
      })),
    ];
  }

  function aids(s, line, busy) {
    const speed = h.el('select', { class: 'pl-aid', 'aria-label': 'Device voice speed', disabled: busy, onchange: (e) => { s.standInRate = Number(e.target.value); } },
      [['0.8', 'Slower'], ['1', 'Normal'], ['1.2', 'Faster']].map(([v, label]) =>
        h.el('option', { value: v, selected: Number(v) === s.standInRate }, label)));
    return [
      h.el('button', { type: 'button', class: 'pl-aid', disabled: busy, onclick: () => s.record(line.id, true) }, 'Run-up'),
      h.el('button', { type: 'button', class: 'pl-aid', disabled: busy, onclick: () => s.hearItRead(line.id) }, 'Hear it read'),
      speed,
    ];
  }

  const KEYS = {
    step: [['Space', 'Record or stop'], ['Return', 'Keep'], ['R', 'Again'], ['← →', 'Line']],
    run: [['Space', 'Start or pause'], ['Return', 'Keep the run']],
    lines: [['↑ ↓', 'Line'], ['Space', 'Record or stop']],
  };

  function dock(s, line, busy) {
    const ph = s.phase;
    const keep = () => { if (rec.index + 1 < s.lines.length) move(1); else paintRecording(); };
    if (s.mode === 'step' && ph.kind === 'review') {
      const t = C.chosenTake(s.production, line.id);
      return h.el('div', { class: 'pl-dock three' },
        h.el('button', { type: 'button', class: 'btn btn-again', dataset: { act: 'again' }, onclick: () => s.record(line.id) }, h.el('span', { class: 'dot' }), 'Again'),
        h.el('button', { type: 'button', class: 'btn btn-way', dataset: { act: 'with-cue' }, disabled: !t, onclick: () => s.playWithCue(t) }, svg('play', 'i-inline'), 'With cue'),
        h.el('button', { type: 'button', class: 'btn btn-primary', dataset: { act: 'keep' }, onclick: () => { s.phase = { kind: 'idle' }; keep(); } }, svg('check', 'i-inline'), 'Keep'));
    }
    if (s.mode === 'run' && ph.kind === 'runReview') {
      const n = s.runTakes().length;
      return h.el('div', { class: 'pl-dock two' },
        h.el('button', { type: 'button', class: 'btn btn-way', dataset: { act: 'discard' }, onclick: () => s.discardRun() }, 'Discard the run'),
        h.el('button', { type: 'button', class: 'btn btn-primary', dataset: { act: 'keep' }, onclick: () => s.keepRun() },
          svg('check', 'i-inline'), n === 1 ? 'Keep 1 take' : `Keep ${num.format(n)} takes`));
    }
    const round = (act, cls, icon, label, onclick, disabled = false) => h.el('div', { class: 'pl-ctr' },
      h.el('button', { type: 'button', class: `pl-recbtn ${cls}`.trim(), dataset: { act }, 'aria-label': label, disabled, onclick }, svg(icon)),
      h.el('span', { class: 'pl-lab', 'aria-hidden': 'true' }, label));
    const listening = ph.kind === 'listening';
    if (s.mode === 'run') {
      const taken = s.run ? s.run.takes.length : 0;
      const center = !s.run ? round('record', '', 'mic', 'From here', () => s.runThrough(line.id), busy)
        : listening ? round('pause', 'stop', 'stop', 'Stop', () => s.pause())
          : round('pause', 'ink', 'pause', 'Pause', () => s.pause());
      return h.el('div', { class: 'pl-dock' },
        h.el('div', { class: 'pl-side caption tabular' }, s.run ? (taken === 1 ? '1 taken' : `${num.format(taken)} taken`) : ''),
        center, h.el('div', { class: 'pl-side' }));
    }
    const center = listening ? round('stop', 'stop', 'stop', 'Stop', () => s.stopListening())
      : ph.kind === 'cue' ? round('record', 'armed', 'mic', 'Next', null, true)
        : round('record', '', 'mic', 'Record', () => s.record(line.id), busy);
    return h.el('div', { class: 'pl-dock' },
      h.el('div', { class: 'pl-side' }, h.el('button', { type: 'button', class: 'icon-btn', dataset: { act: 'prev' }, 'aria-label': 'Previous line',
        disabled: rec.index === 0 || busy, onclick: () => move(-1) }, svg('prev'))),
      center,
      h.el('div', { class: 'pl-side' }, h.el('button', { type: 'button', class: 'icon-btn', dataset: { act: 'next' }, 'aria-label': 'Next line',
        disabled: rec.index + 1 >= s.lines.length || busy, onclick: () => move(1) }, svg('next'))));
  }

  /** The parts near the line, with who each is heard as: the strip under the mode on a phone, the left rail on a desktop. */
  function partnersNear(s, line) {
    const all = s.script.lines;
    const k = all.findIndex(l => l.id === line.id);
    const seen = [];
    const near = all.map((l, i) => [l, Math.abs(i - k)]).filter(([, d]) => d <= 24).sort((a, b) => a[1] - b[1]);
    for (const [l] of near) {
      const part = C.linePart(l);
      if (l.kind === 'speech' && part !== s.part && !seen.includes(part)) seen.push(part);
    }
    return seen.slice(0, 6);
  }

  function recorder(s, failed, title, play) {
    const all = s.lines;
    if (!all.length) return h.stateBox('empty', { text: 'No lines in this part.' });
    rec.index = Math.min(Math.max(0, rec.index), all.length - 1);
    const line = all[rec.index];
    const busy = s.isBusy();
    const locked = busy || !!s.run;
    const missing = C.missingLines(s.production, s.script, s.part).length;
    const kept = all.length - missing;
    const listeningID = s.phase.kind === 'listening' ? s.phase.lineID : null;

    const strip = h.el('div', { class: 'pl-strip', dataset: { hue: hueOf(s.script, s.part) }, role: 'img',
                                'aria-label': `${num.format(kept)} of ${lines(all.length)} kept`,
                                style: `gap: ${all.length > 150 ? 0 : all.length > 60 ? 1 : 2}px` },
      all.map((l, i) => {
        const t = C.chosenTake(s.production, l.id);
        const cls = i === rec.index ? `c${listeningID === l.id ? ' rec-on' : ''}` : t && !t.bleed ? 'k' : t ? 'f' : '';
        return h.el('i', cls ? { class: cls } : {});
      }));

    const mode = h.el('div', { class: 'pl-mode', role: 'radiogroup', 'aria-label': 'Recording mode' },
      C.MODES.map(m => h.el('label', { class: s.mode === m ? 'on' : '' },
        h.el('input', { type: 'radio', name: 'rec-mode', value: m, checked: s.mode === m, disabled: locked,
                        onchange: () => { if (s.setMode(m)) h.announce(MODE_LABEL[m]); } }),
        MODE_LABEL[m])));

    const partners = partnersNear(s, line);
    const who = (part) => heardAs(s.production, s.script, part);
    const opp = h.el('div', { class: 'pl-opp', 'aria-label': 'Opposite you' }, partners.slice(0, 2).map(part =>
      h.el('span', { class: 'pl-opp-p' }, face(s.script, part, { who: C.stateOf(s.production, part).performer, voice: who(part) === 'Device voice', size: 'xs' }),
        h.el('b', {}, C.partTitle(part)), h.el('span', { class: 'pl-muted' }, who(part)))));

    const scene = h.el('div', { class: 'pl-scene', 'aria-live': 'polite' });
    if (s.mode === 'run' && s.phase.kind === 'runReview') scene.append(...runReview(s));
    else if (s.mode === 'lines') scene.append(lineList(s, busy));
    else scene.append(...stage(s, line, busy));

    const rail = h.el('aside', { class: 'pl-rail l', 'aria-label': 'In this scene' },
      h.el('h2', { class: 'pl-rail-h' }, 'In this scene'),
      h.el('div', { class: 'pl-r1' }, face(s.script, s.part, { who: C.stateOf(s.production, s.part).performer, size: 'lg', live: !!listeningID }),
        h.el('span', {}, h.el('span', { class: 'pl-r1-nm' }, C.partTitle(s.part)), h.el('span', { class: 'caption pl-muted' }, 'You'))),
      partners.map(part => h.el('div', { class: 'pl-r1' }, face(s.script, part, { who: C.stateOf(s.production, part).performer, voice: who(part) === 'Device voice', size: 'lg' }),
        h.el('span', {}, h.el('span', { class: 'pl-r1-nm' }, C.partTitle(part)), h.el('span', { class: 'caption pl-muted' }, who(part))))));

    const side = h.el('div', { class: 'pl-aside' },
      s.mode === 'run' ? null : h.el('div', { class: 'pl-aids' }, aids(s, line, busy)),
      h.el('dl', { class: 'pl-keys' }, KEYS[s.mode].flatMap(([k, v]) => [h.el('dt', {}, h.el('kbd', {}, k)), h.el('dd', {}, v)])));

    const refusal = h.el('p', { class: 'caption refusal', role: 'alert' }, failed || '');
    const done = h.el('div', { class: 'pl-done' },
      h.el('button', { type: 'button', class: 'btn', disabled: locked || missing > 0, onclick: () => finishPart() }, 'Done with this part'),
      missing ? h.el('p', { class: 'caption' }, missing === 1 ? '1 line to go' : `${num.format(missing)} lines to go`) : null,
      refusal);

    return h.el('div', { class: 'pl-rec', dataset: { mode: s.mode } },
      recTop(title, play, `${num.format(kept)} of ${num.format(all.length)}`),
      strip,
      h.el('div', { class: 'pl-mode-row' }, mode),
      opp, rail, scene, side,
      s.mode === 'lines' ? h.el('div', { class: 'pl-dock-none' }) : dock(s, line, busy),
      done);
  }

  function move(step) {
    if (!rec || !rec.s) return;
    rec.index = Math.min(Math.max(0, rec.index + step), rec.s.lines.length - 1);
    paintRecording();
  }

  /** Space: the mode's one control (record or stop; in a run, start or pause). */
  function recordOrStop() {
    const s = rec && rec.s;
    if (!s || !s.started) return;
    if (s.mode === 'run') {
      if (s.phase.kind === 'runReview') return;
      if (s.run) s.pause();
      else if (!s.isBusy()) s.runThrough(s.lines[rec.index].id);
      return;
    }
    if (s.phase.kind === 'listening') s.stopListening();
    else if (!s.isBusy()) s.record(s.lines[rec.index].id);
  }

  /** "Done with this part" hands the device on (§2.5). */
  function finishPart() {
    const { id, part, script } = rec;
    // Shared: the takes are uploaded and the part finished on the Worker, from the cast sheet (rule 5).
    if (store.share(id)) {
      leave();
      h.navigate(`?production=${encodeURIComponent(id)}`, true);
      return;
    }
    try {
      store.update(C.finish(store.production(id), script, part));
    } catch (err) {
      const r = document.querySelector('.pl-done .refusal');
      if (r) r.textContent = err instanceof C.Refusal ? C.refusalText(err) : String(err.message || err);
      return;
    }
    leave();
    h.navigate(`?production=${encodeURIComponent(id)}`, true);
  }

  /* Space records, stops, or pauses; Return keeps; R records again; the arrow keys move by line (§7).
     Captured before the player's own keys, which would otherwise start an episode. */
  window.addEventListener('keydown', (e) => {
    if (!rec || !rec.s || !rec.s.started || e.metaKey || e.ctrlKey || e.altKey) return;
    if ($('view-plays').hidden) return;
    const t = e.target;
    if (t.closest && t.closest('input:not([type="radio"]), select, textarea, [contenteditable="true"]')) return;
    const s = rec.s;
    const press = (act) => { const b = document.querySelector(`.pl-rec [data-act="${act}"]`); if (b && !b.disabled) b.click(); };
    if (e.key === ' ') recordOrStop();
    else if (e.key === 'Enter' && !t.closest('button, a')) press('keep');
    else if (e.key === 'r' || e.key === 'R') press('again');
    else if (e.key === 'ArrowLeft' && s.mode === 'step') { if (!s.isBusy()) move(-1); }
    else if (e.key === 'ArrowRight' && s.mode === 'step') { if (!s.isBusy()) move(1); }
    else if (e.key === 'ArrowUp' && s.mode === 'lines' && !t.closest('[role="radiogroup"]')) { if (!s.isBusy()) move(-1); }
    else if (e.key === 'ArrowDown' && s.mode === 'lines' && !t.closest('[role="radiogroup"]')) { if (!s.isBusy()) move(1); }
    else return;
    e.preventDefault();
    e.stopPropagation();
  }, true);

  /* ---- The router's doors ---- */

  function leave() {
    if (rec) clearInterval(rec.clock);
    if (rec && rec.s) rec.s.end();
    rec = null;
    if (listen) listen.end();
    listen = null;
  }

  let watching = false;
  /** The shared production on screen, re-read when the tab is shown again (§11.7 rule 7). */
  let sharedShown = null;
  /** A sign-in or sign-out redraws a shared page, never a live recording. */
  function watchAccount() {
    if (watching || !API.account || !API.account.onChange) return;
    watching = true;
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState !== 'visible' || !sharedShown || !lastDraw) return;
      if ((rec && rec.s && rec.s.started) || (listen && listen.playing)) return;
      const playing = document.querySelector('.mix-audio');
      if (playing && !playing.paused) return;
      lastDraw();
    });
    let was = API.account.signedIn();
    API.account.onChange(() => {
      const now = API.account.signedIn();
      if (now === was) return;
      was = now;
      if (rec && rec.s && rec.s.started) return;
      if (lastDraw) lastDraw();
    });
  }

  function render(r, helpers) {
    h = helpers;
    watchAccount();
    lastDraw = null;
    sharedShown = null;
    const my = ++token;

    const body = $('plays-body');
    $('plays-h').hidden = false;
    const id = r.p.get('production');
    const part = r.p.get('part');
    if (!(id && part && rec && rec.key === `${id} ${part}`)) leave();
    if (id && part) return renderPart(body, my, id, part, r.p.get('line'));
    if (id) return renderProduction(body, my, id);
    return renderScript(body, my, r.p.get('play'));
  }

  return { render, renderMine: (body, helpers) => { watchAccount(); return renderMine(body, helpers); }, startButton, leave, fingerprint, BOARD };
})();
