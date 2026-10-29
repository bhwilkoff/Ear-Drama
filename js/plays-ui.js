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
  /* ---- Start an ear drama (§2.1): a play's page and Surprise both offer it ---- */

  function startButton(script, helpers) {
    h = h || helpers;
    const box = helpers.el('span', { class: 'start-drama' });
    const error = helpers.el('span', { class: 'caption refusal', role: 'alert' });
    const start = helpers.el('button', { type: 'button', class: 'btn btn-accent', onclick: async () => {
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

  /* ---- A play: its rights and parts ---- */

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
    const author = C.authorFacts(script);
    const facts = [script.year ? String(script.year) : null, C.lengthLine(script)].filter(Boolean).join(' · ');
    body.replaceChildren(
      h.el('div', { class: 'page-head' }, author ? h.el('p', { class: 'body' }, author) : null,
        h.el('p', { class: 'caption tabular play-facts' }, facts), rightsLine(script)),
      h.el('div', { class: 'actions ear-drama-only' }, startButton(script, h)),
      h.el('section', { class: 'block' },
        h.el('h2', { class: 'section-header', id: 'play-parts-h' }, 'Parts'),
        h.el('ul', { class: 'part-list', 'aria-labelledby': 'play-parts-h' },
          C.castParts(script).map(part => h.el('li', { class: 'part-row' },
            h.el('span', { class: 'body' }, part.title),
            h.el('span', { class: 'tabular caption' }, lines(part.lineCount)))))));
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

    const rows = C.castParts(script).map(part => {
      const st = C.stateOf(p, part.id);
      const actions = h.el('div', { class: 'cast-actions' });
      if (st.status === 'recording') {
        actions.append(h.el('a', { class: 'btn btn-accent', href: partHref(part.id) }, 'Record'));
      } else if (st.status === 'open' && !recording) {
        const name = h.el('input', { class: 'field-input', type: 'text', name: 'performer', autocomplete: 'name',
                                     placeholder: 'Your name', 'aria-label': `Your name, optional, for ${part.title}` });
        const form = h.el('form', { class: 'take-form', onsubmit: (e) => {
          e.preventDefault();
          if (apply(cur => C.take(cur, script, part.id, name.value))) h.navigate(partHref(part.id));
        } }, name, h.el('button', { type: 'submit', class: part.id === next ? 'btn btn-accent' : 'btn' }, 'Take part'));
        if (!C.isSpeaking(part.id)) {
          form.append(h.el('button', { type: 'button', class: 'btn', onclick: () => {
            if (apply(cur => C.leaveSilent(cur, script, part.id))) rerender();
          } }, 'Leave silent'));
        }
        actions.append(form);
      } else if (st.status === 'done' || st.status === 'silent') {
        actions.append(h.el('button', { type: 'button', class: 'btn', disabled: !!recording, onclick: () => {
          if (apply(cur => C.reopen(cur, script, part.id))) h.navigate(partHref(part.id));
        } }, 'Open part'));
      }
      return h.el('li', { class: 'cast-row', dataset: { status: st.status } },
        h.el('a', { class: 'cast-main', href: partHref(part.id) },
          h.el('span', { class: 'body-strong' }, part.title),
          h.el('span', { class: 'caption' }, partStatus(p, script, part))),
        actions.childNodes.length ? actions : null);
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
      h.el('p', { class: 'caption cast-progress' }, progressLine(p, script)),
      h.el('ul', { class: 'cast-list', 'aria-label': 'Parts' }, rows),
      refusal,
      listenThrough(p, script, rerender),
      shareBox(p, script, rerender),
      manage);
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
    if (S.myParts(rec, me).length) {
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
      mineBox.append(h.el('div', { class: 'actions' }, ready ? up : null, done), status);
      if (!open) status.textContent = S.line({ code: 'uploads_off' });
      else if (flagged) status.textContent = S.line({ code: 'bleed_flagged' });
    }

    body.replaceChildren(
      h.el('ul', { class: 'cast-list', 'aria-label': 'Parts' }, rows),
      line, mineBox,
      sharedListen(rec, local, script, pid, me, rerender),
      peopleBox(rec, me, p, pid, rerender),
      h.el('div', { class: 'actions' }, deleteButton(p)));
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
    if (rec.archive) {
      box.append(h.el('p', { class: 'caption', role: 'status' }, 'Queued for archive.org'));
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

  async function renderPart(body, my, id, part) {
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
    if (link && canShare()) {
      let remote = null;
      try { remote = await API.plays.get(link.pid); } catch (err) { console.error(err); }
      if (my !== token) return;
      if (remote) {
        const me = API.account.state().user_id;
        const local = await S.follow(store, id, remote, me);
        if (my !== token) return;
        if (!S.isMine(remote, part, me)) { sharedReadAlong(body, back, local, script, part, remote, link.pid, my); return; }
      }
    }
    if (C.stateOf(store.production(id), part).status !== 'recording') {
      body.replaceChildren(back, h.el('ol', { class: 'read-along' },
        C.linesFor(script, part).map(l => h.el('li', {}, lineView(l)))));
      return;
    }
    rec = { key, id, part, script, s: null, index: 0, headphones: false, back };
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
    rec.index = Math.max(0, s.lines.findIndex(l => !C.usableTake(p, l.id)));
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

  function paintRecording() {
    if (!rec) return;
    const body = $('plays-body');
    const s = rec.s;
    const failed = failure(s);
    if (!s || !s.started) {
      body.replaceChildren(rec.back, startScreen(failed));
      return;
    }
    if (s.phase.kind === 'roomTone') {
      body.replaceChildren(rec.back, h.el('div', { class: 'rec-start', role: 'status' },
        h.el('p', { class: 'body-strong' }, 'Quiet, please. Recording the room.'),
        h.el('p', { class: 'view-heading tabular countdown' }, String(s.phase.secondsLeft))));
      return;
    }
    // A repaint keeps the keyboard where it was: the one record control stays focused.
    const onRecord = document.activeElement && document.activeElement.classList.contains('record-btn');
    body.replaceChildren(rec.back, prompter(s, failed));
    if (onRecord) { const b = body.querySelector('.record-btn'); if (b) b.focus({ preventScroll: true }); }
  }

  /** Headphones only (PLAYS-DESIGN §4.3): the web cannot see the audio route, so the person says. */
  function startScreen(failed) {
    const box = h.el('div', { class: 'rec-start' }, svg('headphones', 'rec-icon'));
    if (!LiveAudio.supported()) {
      box.append(h.el('p', { class: 'body' }, 'This browser cannot record.'));
      return box;
    }
    if (!API.account.signedIn()) {
      const avail = API.account.available();
      box.append(
        h.el('p', { class: 'body' }, 'Recording needs an account.'),
        h.el('button', { type: 'button', class: 'btn btn-accent', disabled: !(avail.apple || avail.google), onclick: () => {
          AccountUI.openSheet();
          const sheet = document.querySelector('dialog.account-sheet');
          if (sheet) sheet.addEventListener('close', () => paintRecording(), { once: true });
        } }, 'Sign in'));
      return box;
    }
    const start = h.el('button', { type: 'button', class: 'btn btn-record', disabled: !rec.headphones,
                                   onclick: () => startRecording() }, svg('mic', 'i-inline'), 'Start recording');
    const check = h.el('input', { type: 'checkbox', id: 'rec-headphones', checked: rec.headphones,
                                  onchange: () => { rec.headphones = check.checked; start.disabled = !check.checked; } });
    box.append(
      h.el('p', { class: 'body' }, 'Headphones only. This browser cannot tell whether they are on.'),
      h.el('label', { class: 'check', for: 'rec-headphones' }, check, h.el('span', { class: 'body' }, 'My headphones are on')),
      start);
    if (failed) box.append(h.el('p', { class: 'caption refusal', role: 'alert' }, failed));
    return box;
  }

  function prompter(s, failed) {
    const all = s.lines;
    if (!all.length) return h.stateBox('empty', { text: 'No lines in this part.' });
    rec.index = Math.min(Math.max(0, rec.index), all.length - 1);
    const line = all[rec.index];
    const busy = s.isBusy();
    const listening = s.phase.kind === 'listening' && s.phase.lineID === line.id;

    const cue = h.el('div', { class: 'cue' });
    if (s.phase.kind === 'cue') {
      const cueLine = s.script.lines.find(l => l.id === s.phase.lineID);
      if (s.phase.deviceVoice) cue.append(h.el('p', { class: 'caption device-voice' }, svg('wave', 'i-inline'), 'Device voice'));
      if (cueLine) cue.append(lineView(cueLine));
    } else if (s.phase.kind === 'listening') {
      cue.append(h.el('p', { class: 'body-strong your-line' }, svg('mic', 'i-inline'), 'Your line'));
    } else {
      const prev = C.cueLines(s.script, line.id, false).pop();
      if (prev) cue.append(lineView(prev, 'line-dim'));
    }

    const takes = C.takesFor(s.production, line.id);
    const takeList = h.el('ul', { class: 'takes', 'aria-label': 'Takes' });
    if (C.chosenTake(s.production, line.id)?.bleed) {
      takeList.append(h.el('li', { class: 'caption bleed' }, svg('warn', 'i-inline'),
        'The microphone heard the device voice. Re-take this line with headphones.'));
    }
    takes.forEach((t, i) => {
      const chosen = s.production.chosen[line.id] === t.id;
      takeList.append(h.el('li', { class: 'take-row' },
        h.el('button', { type: 'button', class: 'btn btn-ghost', disabled: busy, onclick: () => s.playTake(t) },
          svg('play', 'i-inline'), `Take ${i + 1}`),
        h.el('span', { class: 'tabular caption' }, `${(t.frames / t.sampleRate).toFixed(1)} s`),
        chosen ? h.el('span', { class: 'take-chosen', role: 'img', 'aria-label': 'Chosen' }, svg('check'))
          : h.el('button', { type: 'button', class: 'btn', disabled: busy, onclick: () => s.choose(t) }, 'Use this take')));
    });

    const recordBtn = h.el('button', {
      type: 'button', class: `record-btn${listening ? ' is-listening' : ''}`, disabled: busy && !listening,
      'aria-label': listening ? 'Stop' : 'Record', onclick: () => recordOrStop(),
    }, svg(listening ? 'stop' : 'record'));
    const speed = h.el('select', { 'aria-label': 'Device voice speed', onchange: (e) => { s.standInRate = Number(e.target.value); } },
      [['0.8', 'Slower'], ['1', 'Normal'], ['1.2', 'Faster']].map(([v, label]) =>
        h.el('option', { value: v, selected: Number(v) === s.standInRate }, label)));
    const missing = C.isSpeaking(s.part) ? C.missingLines(s.production, s.script, s.part).length : 0;
    const refusal = h.el('p', { class: 'caption refusal', role: 'alert' }, failed || '');

    return h.el('div', { class: 'prompter' },
      cue,
      h.el('div', { class: 'line-now' }, lineView(line, 'line-large')),
      rec.index + 1 < all.length ? lineView(all[rec.index + 1], 'line-dim') : null,
      takeList,
      h.el('div', { class: 'rec-controls' },
        h.el('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Previous line', disabled: rec.index === 0 || busy,
                         onclick: () => move(-1) }, svg('prev')),
        recordBtn,
        h.el('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Next line', disabled: rec.index + 1 >= all.length || busy,
                         onclick: () => move(1) }, svg('next'))),
      h.el('div', { class: 'rec-secondary' },
        h.el('button', { type: 'button', class: 'btn', disabled: busy, onclick: () => s.record(line.id, true) }, 'Run-up'),
        h.el('button', { type: 'button', class: 'btn', disabled: busy, onclick: () => s.hearItRead(line.id) }, 'Hear it read'),
        speed,
        h.el('button', { type: 'button', class: 'btn', onclick: () => move(1),
                         disabled: busy || !s.production.chosen[line.id] || rec.index + 1 >= all.length }, 'Keep')),
      h.el('div', { class: 'rec-done' },
        h.el('button', { type: 'button', class: 'btn', disabled: busy || missing > 0, onclick: () => finishPart() }, 'Done with this part'),
        missing ? h.el('p', { class: 'caption' }, missing === 1 ? '1 line to go' : `${num.format(missing)} lines to go`) : null,
        refusal));
  }

  function move(step) {
    if (!rec || !rec.s) return;
    rec.index = Math.min(Math.max(0, rec.index + step), rec.s.lines.length - 1);
    paintRecording();
  }

  function recordOrStop() {
    const s = rec && rec.s;
    if (!s || !s.started) return;
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
      const r = document.querySelector('.rec-done .refusal');
      if (r) r.textContent = err instanceof C.Refusal ? C.refusalText(err) : String(err.message || err);
      return;
    }
    leave();
    h.navigate(`?production=${encodeURIComponent(id)}`, true);
  }

  /* Space records or stops, Return keeps, the arrow keys move by line (§7). Captured
     before the player's own keys, which would otherwise start an episode. */
  window.addEventListener('keydown', (e) => {
    if (!rec || !rec.s || !rec.s.started || e.metaKey || e.ctrlKey || e.altKey) return;
    if ($('view-plays').hidden) return;
    const t = e.target;
    if (t.closest && t.closest('input, select, textarea, [contenteditable="true"]')) return;
    const s = rec.s;
    if (e.key === ' ') recordOrStop();
    else if (e.key === 'Enter' && !t.closest('button, a')) { if (!s.isBusy() && s.production.chosen[s.lines[rec.index].id]) move(1); }
    else if (e.key === 'ArrowLeft') { if (!s.isBusy()) move(-1); }
    else if (e.key === 'ArrowRight') { if (!s.isBusy()) move(1); }
    else return;
    e.preventDefault();
    e.stopPropagation();
  }, true);

  /* ---- The router's doors ---- */

  function leave() {
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
    const id = r.p.get('production');
    const part = r.p.get('part');
    if (!(id && part && rec && rec.key === `${id} ${part}`)) leave();
    if (id && part) return renderPart(body, my, id, part);
    if (id) return renderProduction(body, my, id);
    return renderScript(body, my, r.p.get('play'));
  }

  return { render, renderMine: (body, helpers) => { watchAccount(); return renderMine(body, helpers); }, startButton, leave };
})();
