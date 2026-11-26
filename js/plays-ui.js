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
  /** The listen-through's rendered mix, kept for this page only: { id, from, url }. */
  let mix = null;
  /** The live listen-through on the production page, ended when the page changes. */
  let listen = null;
  /** The voice pickers' preview voice, and the cast sheet's voiceschanged unsubscribe (§2.8). */
  let preview = null;
  let voicesOff = null;
  /** The last page drawn, redrawn when someone signs in or out here. */
  let lastDraw = null;
  const S = PlaysShare;
  const REASONS = [['offensive', 'Offensive'], ['harassment', 'Harassment'], ['personal_information', 'Personal information'],
                   ['not_a_performance', 'Not a performance'], ['other', 'Other']];
  const SCRIPT_REASONS = [['copyright', 'Copyright'], ...REASONS];

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
  const dayFmt = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
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

  /** This person's productions on the Worker; an own share whose creation answer was lost is adopted first (§13 item 11a), and the list read again. */
  async function listed() {
    const read = async () => (await API.plays.list()).productions || [];
    let remote = await read();
    if (await S.reconcileOwed({ api: API.plays, store, remote, me: API.account.state().user_id }).catch((e) => { console.error(e); return false; })) remote = await read();
    return remote;
  }

  /** The productions list. Record passes `onEmpty` (the section goes, no sentence) and `classes: false`. */
  async function renderMine(body, helpers, opts = {}) {
    h = helpers;
    lastDraw = () => renderMine(body, helpers, opts);
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
    let remote = [];
    if (canShare()) {
      try { remote = await listed(); } catch (err) { console.error(err); }
      if (my !== token) return;
    }
    const rows = S.libraryRows(store, remote).filter(r => !opts.play || playKey(r) === opts.play);
    if (!rows.length && opts.onEmpty) { body.replaceChildren(); opts.onEmpty(); return; }
    if (!rows.length) out.push(h.stateBox('empty', { text: 'No ear dramas yet.' }));
    else {
      const ul = h.el('ul', { class: 'play-list' });
      // One play's productions (Library, Decision 087) share a title, so each says when it was made or last changed.
      const when = (r) => (opts.play ? ` · ${dayFmt.format(new Date(r.local ? (r.local.created + 978307200) * 1000 : r.remote.updated_at || 0))}` : '');
      for (const r of rows) {
        if (r.local) {
          const script = await store.script(r.local);
          if (my !== token) return;
          ul.append(h.el('li', { class: 'play-row' },
            h.el('a', { class: 'play-link', href: `?production=${encodeURIComponent(r.local.id)}` },
              h.el('span', { class: 'body-strong' }, r.local.title),
              h.el('span', { class: 'caption' }, (r.pid ? 'Shared' : progressLine(r.local, script)) + when(r)))));
        } else {
          const status = h.el('span', { class: 'caption refusal', role: 'alert' });
          ul.append(h.el('li', { class: 'play-row' },
            h.el('button', { type: 'button', class: 'play-link play-remote', onclick: () => openRemote(r.remote, status) },
              h.el('span', { class: 'body-strong' }, r.remote.title),
              h.el('span', { class: 'caption' }, `Shared${when(r)}`)), status));
        }
      }
      out.push(ul);
    }
    if (canShare() && opts.classes !== false) {
      const classes = await classesBox(my);
      if (my !== token) return;
      out.push(classes);
    }
    body.replaceChildren(...out);
  }

  /** The play a production row belongs to: its script id (a production's title is its play's). */
  const playKey = (r) => (r.local ? r.local.scriptID : r.remote.script_id) || (r.local ? r.local.title : r.remote.title);

  /** Library's Making side (WEB-DESIGN §4.7, Decision 087): the productions grouped by play, newest play first,
      each { key, title, count, state, href | remote }; the classes when signed in (null otherwise or on a failed
      read); and the class seats this browser holds. Throws only when the play store will not open. */
  async function making(helpers) {
    h = h || helpers;
    await openStore();
    let remote = [];
    if (canShare()) {
      try { remote = await listed(); } catch (err) { console.error(err); }
    }
    const groups = new Map();
    for (const r of S.libraryRows(store, remote)) {
      const k = playKey(r);
      if (!groups.has(k)) groups.set(k, []);
      groups.get(k).push(r);
    }
    const plays = [];
    for (const [key, rs] of groups) {
      const top = rs[0];
      const own = top.local ? (top.pid ? 'Shared' : progressLine(top.local, await store.script(top.local).catch(() => null))) : 'Shared';
      plays.push({
        key, title: top.local ? top.local.title : top.remote.title, count: rs.length,
        state: rs.length > 1 ? `${num.format(rs.length)} productions · newest ${own.charAt(0).toLowerCase()}${own.slice(1)}` : own,
        href: rs.length > 1 ? `?view=library&side=make&productions=${encodeURIComponent(key)}`
          : top.local ? `?production=${encodeURIComponent(top.local.id)}` : null,
        remote: rs.length === 1 && !top.local ? top.remote : null,
      });
    }
    let classes = null;
    if (canShare()) {
      try { classes = await API.plays.classes(); } catch (err) { console.error(err); }
    }
    const seats = typeof PartsUI !== 'undefined' ? PartsUI.seatKeys(store) : [];
    return { plays, classes, seats };
  }

  /** Record's class door (WEB-DESIGN §4.15 item 4, Decision 087): the classes with Make a class and Join a class; signed in only. */
  async function classDoor(body, helpers) {
    h = h || helpers;
    if (!canShare()) { body.replaceChildren(); return; }
    const my = token;
    body.replaceChildren(await classesBox(my));
  }

  /** Home's Open parts (WEB-DESIGN §4.2 item 7, owner 2026-11-14): shared productions someone else directs
      that this signed-in person belongs to, each with a speaking part still open, newest first, at most five;
      null when there are none. A person's own productions are Record's Yours, never here. */
  async function openParts(helpers) {
    h = h || helpers;
    if (!canShare()) return null;
    const me = API.account.state().user_id;
    const listed = ((await API.plays.list()).productions || []).filter(r => r.director && r.director !== me)
      .sort((a, b) => (b.updated_at || 0) - (a.updated_at || 0)).slice(0, 8);
    const rows = [];
    for (const r of listed) {
      if (rows.length >= 5) break;
      let rec = null;
      try { rec = await API.plays.get(r.id); } catch (err) { console.error(err); continue; }
      // The record's parts are the cast sheet's, so a script is read only for a catalog play's order; an own script's text is not fetched for a count.
      let script = null;
      try { script = S.isOwnId(rec.scriptID) ? null : await S.scriptOf({ api: API, id: rec.scriptID, revision: rec.scriptRevision }); } catch { script = null; }
      const state = S.ownState(rec);
      const open = state && state.state !== 'kept' ? [] : C.openSpeakingParts(rec, script);
      if (open.length) rows.push({ r, n: open.length });
    }
    if (!rows.length) return null;
    await openStore();
    const ul = helpers.el('ul', { class: 'play-list', 'aria-labelledby': 'open-parts-h' });
    for (const { r, n } of rows) {
      const status = helpers.el('span', { class: 'caption refusal', role: 'alert' });
      ul.append(helpers.el('li', { class: 'play-row' },
        helpers.el('button', { type: 'button', class: 'play-link play-remote', onclick: () => openRemote(r, status) },
          helpers.el('span', { class: 'body-strong' }, r.title),
          helpers.el('span', { class: 'caption' }, n === 1 ? '1 open part' : `${num.format(n)} open parts`)), status));
    }
    return helpers.el('section', { class: 'block home-open-parts' },
      helpers.el('h3', { class: 'section-header', id: 'open-parts-h' }, 'Open parts'), ul);
  }

  /** A shared production's script, for a member of it. */
  const memberScript = (rec) => S.scriptOf({ api: API, store, id: rec.scriptID, revision: rec.scriptRevision, who: { pid: rec.id }, fit: S.fits.record(rec) });

  /** A shared production this browser has not opened: made here from its script (§11.7 rule 11, §13 item 11). */
  async function openRemote(remote, status) {
    try {
      const rec = await API.plays.get(remote.id);
      const script = await memberScript(rec);
      const local = await S.localFor(store, rec.id, script);
      h.navigate(`?production=${encodeURIComponent(local.id)}`);
    } catch (err) { console.error(err); status.textContent = S.line(err); }
  }
  /* ---- Direction D's making pieces (WEB-DESIGN §4.10b): the board, the fingerprint, faces ---- */

  /** Every castable script is a play: it stands on the drama board (its genre is never named). */
  const BOARD = 'drama';
  const speakingParts = (script) => C.castParts(script).filter(x => C.isSpeaking(x.id));
  const hueOf = (script, part) => C.partHue(script, part) || 'none';

  /** The cast fingerprint: each speaking part's share of the play's lines, largest first (a library row's `cast`, or the script's own). */
  function fingerprint(script, cls = '') {
    const parts = C.castOf(script).map((lineCount, i) => ({ lineCount, hue: C.PART_HUES[i] || 'none' }));
    const el = (tag, attrs, ...kids) => {
      const n = document.createElement(tag);
      for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v);
      n.append(...kids);
      return n;
    };
    return el('span', { class: `pl-print ${cls}`.trim(), role: 'img', 'aria-label': parts.length === 1 ? '1 part' : `${num.format(parts.length)} parts, largest first` },
      ...parts.map(x => el('i', { 'data-hue': x.hue, style: `flex: ${x.lineCount} 1 0` })));
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

  /** The voice chip of a part no person holds; the picker's preview speaks through one muted-aware voice. */
  function voiceChip(script, cast, part, chips, onChange) {
    if (!preview) preview = StandInVoice.create({ muted });
    const c = CastUI.chip({ script, cast, voice: preview, part, onChange });
    chips.push(c);
    return c;
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

  /** The head board of a play or a production: the play's window (B31 §3.5: a picture of the play, else on its own
      page its title page or author's portrait, else its label) on the form's board, the fingerprint as its mark;
      a finished drama keeps its part-color disc. */
  function playBoard(script, name, kicker, facts, art = null, { hero = false, picture = null } = {}) {
    const genre = art && art.kind ? BOARD : script.hue || '';
    const series = art && art.kind ? { kind: 'play', name, genre, picture, ...art } : { ...h.playArt(script, hero), name, genre, picture };
    return h.headBoard({ series, kicker, name, facts,
                         mark: fingerprint(script, 'g-head-strip pl-print-head'), ...(hero ? { hero: true, picture } : {}) });
  }
  const kindOf = (script) => (script.kind === 'own' ? 'Your script' : script.kind === 'radio' ? 'Radio play' : 'Stage play');
  /** A play's kicker (B31 §3.5): its kind, then its form and One act, each only when the record says it. */
  const kickerOf = (script) => [kindOf(script), script.form && FindCore.FORM_LABEL[script.form], script.oneAct ? 'One act' : null].filter(Boolean).join(' · ');
  /** An own script or a production of one (PLAYS-DESIGN §13). */
  const isOwn = (script) => !!script && script.kind === 'own';

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
    return h.el('li', { class: `pl-part${mine ? ' mine' : ''}`, dataset: typeof status === 'string' ? { status } : {} },
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
        // A library row (WEB-DESIGN §4.15) carries no lines: the whole script is fetched to cast it.
        const whole = Array.isArray(script.lines) ? script : await API.playScript(script.id);
        if (!whole) throw new Error('script not found');
        // Signed out, a second production asks for an account here, with the reason (Decision 079).
        if (C.secondProductionNeedsAccount(store.productions, API.account.signedIn())) {
          start.disabled = false;
          if (typeof AccountUI !== 'undefined') AccountUI.openSheet({ reason: 'A second production needs an account.' });
          return;
        }
        const p = await store.create(whole);
        helpers.navigate(`?production=${encodeURIComponent(p.id)}`, $('view-plays').hidden === false);
      } catch (err) {
        console.error(err);
        error.textContent = 'This browser could not save a production.';
        start.disabled = false;
      }
    } }, 'Record this');
    box.append(start, error);
    return box;
  }

  /** Read (WEB-DESIGN §4.16, Decision 076): the reader, for anyone, no account. `icon` is the tile's corner button. */
  function readLink(id, { icon = false } = {}) {
    const a = document.createElement('a');
    a.href = `?read=${encodeURIComponent(id)}`;
    if (!icon) {
      a.className = 'btn btn-ghost ear-drama-only';
      a.textContent = 'Read';
      return a;
    }
    a.className = 'icon-btn g-tile-read ear-drama-only';
    a.setAttribute('aria-label', 'Read');
    a.title = 'Read';
    const ns = 'http://www.w3.org/2000/svg';
    const s = document.createElementNS(ns, 'svg');
    s.setAttribute('viewBox', '0 0 24 24');
    s.setAttribute('aria-hidden', 'true');
    const path = document.createElementNS(ns, 'path');
    path.setAttribute('d', BOOK);
    s.append(path);
    a.append(s);
    return a;
  }
  const BOOK = 'M21 5c-1.1-.35-2.33-.5-3.5-.5-1.95 0-4.05.4-5.5 1.5-1.45-1.1-3.55-1.5-5.5-1.5S2.45 4.9 1 6v14.65c0 .25.25.5.5.5.1 0 .15-.05.25-.05C3.1 20.45 5.05 20 6.5 20c1.95 0 4.05.4 5.5 1.5 1.35-.85 3.8-1.5 5.5-1.5 1.65 0 3.35.3 4.75 1.05.1.05.15.05.25.05.25 0 .5-.25.5-.5V6c-.6-.45-1.25-.75-2-1zm0 13.5c-1.1-.35-2.3-.5-3.5-.5-1.7 0-4.15.65-5.5 1.5V8c1.35-.85 3.8-1.5 5.5-1.5 1.2 0 2.4.15 3.5.5v11.5z';

  /* ---- A play: its head board, its parts, its rights ---- */

  async function renderScript(body, my, id) {
    body.replaceChildren(h.stateBox('loading'));
    let script;
    let frozen = false;
    try {
      script = await API.playScript(id);
      frozen = !!script && isOwn(script) && await OwnScripts.shared().frozen(id);
    } catch (err) {
      if (my === token) failBox(body, err, () => renderScript(body, my, id));
      return;
    }
    if (my !== token) return;
    if (!script) {
      $('plays-h').textContent = 'Ear drama';
      if (/^own-/.test(id)) { OwnUI.notDone(body, h, id); return; }
      body.replaceChildren(h.stateBox('missing'));
      return;
    }
    h.setTitle(script.title);
    $('plays-h').textContent = script.title;
    const parts = speakingParts(script);
    const lead = API.playLead(script);
    const voices = C.voicesOf(script), minutes = C.minutesOf(script);
    const author = C.authorFacts(script) || C.authorLine(script);
    const board = playBoard(script, script.title, kickerOf(script),
      [author ? `${script.attributed ? 'Attributed to ' : ''}${author}` : null, script.year ? String(script.year) : null,
       `${num.format(voices)}\u00a0${voices === 1 ? 'voice' : 'voices'}`, `About\u00a0${num.format(minutes)}\u00a0min`],
      null, { hero: true, picture: lead });
    body.replaceChildren(...[board, h.heroCredit ? h.heroCredit(board, lead) : null].filter(Boolean),
      h.el('div', { class: 'actions actions-one actions-start ear-drama-only' }, startButton(script, h, { primary: true }), readLink(script.id),
        typeof ReadUI !== 'undefined' ? ReadUI.startButton(script, h, isOwn(script) ? () => roomFor(script) : null) : null),
      h.el('section', { class: 'block' },
        h.el('h2', { class: 'section-header', id: 'play-parts-h' }, 'Parts'),
        h.el('ul', { class: 'pl-grid', 'aria-labelledby': 'play-parts-h' },
          C.castParts(script).map(part => partCard(script, part)))),
      isOwn(script) ? OwnUI.foot(script, h, { frozen }) : rightsLine(script));
    boardHeading(true);
    if (!isOwn(script)) playNeighbors(body, my, script).catch((e) => console.error(e));
  }

  /** Under a library play's parts (B31 §3.5): its scenes for two voices, then Same voices and length (the rule as
      the heading: within one voice and 15 minutes), then More by the author. A section with nothing is absent. */
  async function playNeighbors(body, my, script) {
    const { rows, collections } = await h.loadFinder();
    if (my !== token) return;
    const row = rows.find(r => r.id === script.id) || script;
    const at = body.querySelector('.play-rights') || null;
    const put = (sec) => (at ? at.before(sec) : body.append(sec));
    const rail = (id, title, items, href = null, count = null) => h.el('section', { class: 'shelf', 'aria-labelledby': id },
      h.railHead(id, title, count, href), h.el('ul', { class: 'rail g-rail', 'aria-labelledby': id }, ...items));
    const scenes = (Array.isArray(row.scenes) ? row.scenes : []).filter(sc => sc.voices === 2 && sc.line);
    if (scenes.length) {
      put(h.el('section', { class: 'shelf', 'aria-labelledby': 'pp-scenes-h' }, h.railHead('pp-scenes-h', 'Scenes for two voices', null, null),
        h.el('ul', { class: 'rail pl-scard-rail', 'aria-labelledby': 'pp-scenes-h' }, ...scenes.map(scene => h.sceneTile({ row, scene }, { inPlay: true })))));
    }
    const same = FindCore.sameShape(rows, row);
    if (same.length) put(rail('pp-same-h', 'Same voices and length', same.map(h.playTile)));
    const by = FindCore.byAuthor(rows, collections, row);
    if (by.plays.length) {
      const surname = LabelCore.surnameOf(C.authorLine({ authors: (row.authors || []).slice(0, 1) }));
      const name = surname ? surname.charAt(0) + surname.slice(1).toLowerCase() : '';
      put(rail('pp-by-h', name ? `More by ${name}` : 'More by the author', by.plays.map(h.playTile),
        by.id && by.total > by.plays.length ? `?view=record&collection=${encodeURIComponent(by.id)}` : null));
    }
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
    const cast = CastUI.castFor({ script, production: p.id });
    const chips = [];
    if (voicesOff) voicesOff();
    voicesOff = StandInVoice.onVoices(() => chips.forEach(c => c.isConnected && c.paint()));
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
      // A part no person holds shows the voice that reads it (PLAYS-DESIGN §2.8; WEB-DESIGN §4.10).
      const voiced = st.status === 'open' && ['Device voice', 'Open'].includes(heardAs(p, script, part.id));
      const status = st.status === 'recording' ? `${who || 'Recording'} · ${num.format(kept)} of ${num.format(part.lineCount)}`
        : st.status === 'done' ? (who ? `${who} · recorded` : 'Recorded')
          : st.status === 'silent' ? 'Left silent'
            : voiced ? voiceChip(script, cast, part.id, chips, () => {
              // A voice for directions or sound changes what the listen-through reads: plan it again.
              if (!C.isSpeaking(part.id) && !(listen && listen.playing)) rerender();
            }) : heardAs(p, script, part.id);
      return partCard(script, part, { who, voice: !held, ok: st.status === 'done', mine: st.status === 'recording',
                                      status, href: partHref(part.id), actions });
    });

    const manage = h.el('div', { class: 'actions' });
    if (chips.length) {
      manage.append(h.el('button', { type: 'button', class: 'btn', onclick: () => {
        cast.recast();
        h.announce('Recast');
        if (listen && listen.playing) chips.forEach(c => c.paint());
        else rerender();
      } }, 'Recast all'));
      const better = CastUI.offer();
      if (better) manage.append(better);
    }
    if (C.unusedTakes(p).length) {
      manage.append(h.el('button', { type: 'button', class: 'btn', onclick: async () => {
        await store.discardUnusedTakes(id);
        h.announce('Unused takes discarded');
        rerender();
      } }, 'Discard unused takes'));
    }
    manage.append(deleteButton(p));

    body.replaceChildren(...[
      playBoard(script, p.title, 'Ear drama', [progressLine(p, script)]),
      listenThrough(p, script, rerender),
      recording ? null : h.el('label', { class: 'pl-as', for: 'pl-performer' }, h.el('span', { class: 'body' }, 'Recording as'), performer),
      h.el('ul', { class: 'pl-grid', 'aria-label': 'Parts' }, cards),
      refusal,
      shareBox(p, script, rerender),
      manage].filter(Boolean));
    boardHeading(true);
  }

  function deleteButton(p) {
    return h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: async () => {
      if (!confirm(`Delete ${p.title}? Every take is removed from this browser.`)) return;
      if (mix && mix.id === p.id) { URL.revokeObjectURL(mix.url); mix = null; }
      await store.delete(p.id);
      VoiceCast.forget(VoiceCast.productionKey(p.id));
      h.navigate('?view=library&side=make', true);
    } }, 'Delete production');
  }

  /* ---- Phase 2: a production shared through the Worker (PLAYS-DESIGN §11.7) ---- */

  /** Who can read a shared own script, in the one line that says so (§13 item 11). */
  const READERS = 'Only people you invite can read this script.';
  const CLASS_READERS = 'Only this class can read this script.';

  /**
   * The production a reading of an own script carries (§13 item 13): the one this person already shared, or one
   * shared now, once they say so. null when they did not; a refusal is thrown.
   */
  async function roomFor(script) {
    if (!API.account.signedIn()) { signIn(); throw { code: 'needs_account' }; }
    if (!(await AgeGate.ask(h))) return null;
    await openStore();
    const me = API.account.state().user_id;
    for (const p of store.productions) {
      const link = store.share(p.id);
      if (p.scriptID !== script.id || !link || !link.pid || link.seat) continue;
      const rec = await API.plays.get(link.pid).catch((e) => { if (e.status === 404) return null; throw e; });
      const own = rec && rec.director === me && rec.scriptRevision === script.revision ? S.ownState(rec, me) : null;
      if (!own || own.state === 'removed' || rec.class_id) continue;
      if (own.state === 'owed') await S.sendScript({ api: API.plays, pid: link.pid, script: await store.script(p) });
      return { production_id: link.pid };
    }
    // eslint-disable-next-line no-alert
    if (!confirm(`Share ${script.title}? People who join the reading can read it.`)) return null;
    const local = await store.create(script);
    try {
      const rec = await S.share({ api: API.plays, store, local, script });
      if (rec.unsent) throw rec.unsent;
      return { production_id: rec.id };
    } catch (err) {
      await store.discardIfAbandoned(local.id).catch(() => {});
      throw err;
    }
  }

  /** Share (rule 1): signed in only; while the Worker is a placeholder it is not offered. */
  function shareBox(p, script, rerender) {
    const box = h.el('div', { class: 'share-box' });
    if (!API.plays.available()) return box;
    const line = h.el('p', { class: 'caption refusal', role: 'alert' });
    const readers = isOwn(script) ? [h.el('p', { class: 'caption' }, READERS)] : [];
    if (!API.account.signedIn()) {
      box.append(h.el('div', { class: 'actions' }, h.el('button', { type: 'button', class: 'btn', onclick: signIn }, 'Share')),
        h.el('p', { class: 'caption' }, 'Sharing needs an account.'), ...readers);
      return box;
    }
    if (notSent.has(p.id)) { line.textContent = S.line(notSent.get(p.id)); notSent.delete(p.id); }
    const name = h.el('input', { class: 'field-input', type: 'text', name: 'director', autocomplete: 'name', maxlength: '40',
                                 placeholder: 'Your name', 'aria-label': 'Your name, optional' });
    const go = h.el('button', { type: 'submit', class: 'btn' }, 'Share');
    box.append(h.el('form', { class: 'take-form', onsubmit: async (e) => {
      e.preventDefault();
      if (!(await AgeGate.ask(h))) return;
      go.disabled = true;
      line.textContent = '';
      try {
        const rec = await S.share({ api: API.plays, store, local: store.production(p.id), script, displayName: name.value });
        if (rec.unsent) notSent.set(rec.id, rec.unsent); else h.announce('Shared');
        rerender();
      } catch (err) {
        console.error(err);
        line.textContent = S.line(err);
        go.disabled = false;
      }
    } }, name, go), ...readers, line);
    return box;
  }

  /** Why a script was not sent, for this visit: the Worker keeps only that it is owed. */
  const notSent = new Map();

  /**
   * What a shared own script's cast sheet adds after its Parts (§13 items 11, 12, 13, 15): who can read it or the
   * state's refusal, the reason it has no Publish, then Read together, Edit a copy, Report script.
   */
  function ownBox(rec, script, me, p, rerender) {
    const own = S.ownState(rec, me);
    if (!own) return null;
    const directs = rec.director === me;
    const err = h.el('p', { class: 'caption refusal', role: 'alert' });
    const acts = h.el('div', { class: 'actions' });
    const box = h.el('section', { class: 'own-share', 'aria-label': 'Script' });
    if (own.state === 'owed') {
      const why = notSent.get(rec.id);
      const again = directs ? h.el('button', { type: 'button', class: 'btn', onclick: async () => {
        again.disabled = true;
        err.textContent = '';
        const e = await S.sendOrUndo({ api: API.plays, pid: rec.id, script });
        if (!e) { notSent.delete(rec.id); h.announce('Shared'); rerender(); return; }
        console.error(e);
        if (S.passes(e)) { notSent.set(rec.id, e); err.textContent = S.line(e); again.disabled = false; return; }
        await store.unshare(p.id);
        notSent.set(p.id, e);
        rerender();
      } }, 'Try again') : null;
      box.append(h.el('p', { class: 'caption refusal', role: 'alert' }, directs ? 'The script was not sent.' : S.line({ code: 'no_script' })));
      if (again) acts.append(again);
      if (why && directs) err.textContent = S.line(why);
    } else if (own.state === 'removed') {
      box.append(h.el('p', { class: 'caption refusal' }, S.line({ code: 'script_removed' })));
    } else {
      box.append(h.el('p', { class: 'caption' }, rec.class_id ? CLASS_READERS : directs ? READERS : 'Only people invited can read this script.'));
    }
    box.append(err, h.el('p', { class: 'caption' }, 'This script can’t be published.'));
    if (own.state === 'kept' && directs && !rec.class_id && typeof ReadUI !== 'undefined') {
      const b = ReadUI.startButton(script, h, () => ({ production_id: rec.id }), err);
      if (b) acts.append(b);
    }
    if (own.mine) {
      const copy = h.el('button', { type: 'button', class: 'btn', onclick: () => OwnUI.editCopy(script, h, copy, err) }, 'Edit a copy');
      acts.append(copy);
    } else if (own.state === 'kept') {
      const rep = h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => {
        acts.replaceWith(reportForm(rec.id, { script: true }, (done) => {
          if (!done) { rerender(); return; }
          sharedShown = null;
          $('plays-body').replaceChildren(h.el('p', { class: 'caption', role: 'status' }, 'Reported. This production is hidden from you.'),
            h.el('div', { class: 'actions' }, deleteButton(p)));
        }, SCRIPT_REASONS));
      } }, 'Report script');
      acts.append(rep);
    }
    if (acts.childNodes.length) box.append(acts);
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

  /** Report a take, a member, or the production's own script (rule 8, §13 item 15, guideline 1.2): a reason and an optional note. */
  function reportForm(pid, target, onDone, reasons = REASONS) {
    const line = h.el('p', { class: 'caption refusal', role: 'alert' });
    const reason = h.el('select', { class: 'field-input', 'aria-label': 'Reason' },
      reasons.map(([v, label]) => h.el('option', { value: v }, label)));
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
    const own = S.ownState(rec, me);
    const held = !!own && own.held;
    const partHref = (part) => `?production=${encodeURIComponent(id)}&part=${encodeURIComponent(part)}`;

    const rows = C.castParts(script).map(part => {
      const s = rec.parts[part.id] || { status: 'open' };
      const actions = h.el('div', { class: 'cast-actions' });
      if (S.isMine(rec, part.id, me)) {
        actions.append(h.el('a', { class: 'btn btn-accent', href: partHref(part.id) }, 'Record'),
          button('Release', () => API.plays.partAction(pid, part.id, 'release')));
      } else if (held) {
        // The owner removed the script: no part is taken or opened again (§13 item 11).
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
    if (S.ownParts(rec, me).length && !held) {
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
      const relayRows = relayList(rec, local, script, id, me);
      if (relayRows) mineBox.append(relayRows);
    }

    body.replaceChildren(
      h.el('ul', { class: 'cast-list', 'aria-label': 'Parts' }, rows),
      line, mineBox, ...[ownBox(rec, script, me, p, rerender)].filter(Boolean),
      sharedListen(rec, local, script, pid, me, rerender),
      ...[changeBox(rec, script, pid, me, id)].filter(Boolean),
      peopleBox(rec, me, p, pid, rerender),
      h.el('div', { class: 'actions' }, deleteButton(p), rec.director === me && !rec.archive ? deleteForEveryone(rec, p) : null));
  }

  /** The director deletes the production from the Worker (Decision 084); a submitted one stays, so it is not offered. */
  function deleteForEveryone(rec, p) {
    const btn = h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: async () => {
      if (!confirm(`Delete ${rec.title} for everyone in it? Its takes leave the server.`)) return;
      btn.disabled = true;
      try {
        await API.plays.deleteProduction(rec.id);
        if (mix && mix.id === p.id) { URL.revokeObjectURL(mix.url); mix = null; }
        await store.delete(p.id);
        h.navigate('?view=library&side=make', true);
      } catch (err) { console.error(err); btn.disabled = false; h.announce(S.line(err)); }
    } }, 'Delete for everyone');
    return btn;
  }

  /**
   * Relay across time (PLAYS-DESIGN §12.11): each take of this person's parts with its state on this
   * device ("On this device · sends when Dee is in Ear Drama", "Sending", "Sent"), kept current while
   * the sender works. The sender (RelayWatch) passes the takes through whenever the director's app is open.
   */
  function relayList(rec, local, script, id, me) {
    const mine = S.ownParts(rec, me).filter((part) => C.isSpeaking(part));
    if (!mine.length) return null;
    RelayWatch.flag();
    const relay = RelayWatch.shared({ api: API, store, me: () => me });
    const director = (rec.members || []).find((m) => m.user_id === rec.director);
    const ul = h.el('ul', { class: 'cast-list parts-list', 'aria-label': 'Your takes' });
    const on = new Set(rec.takes.map((t) => t.id));
    const paint = () => {
      const cur = store.production(id);
      const rows = [];
      for (const part of mine) {
        for (const l of C.linesFor(script, part)) {
          const t = cur && C.chosenTake(cur, l.id);
          if (!t) continue;
          const st = t.bleed ? { state: 'refused', code: 'bleed_flagged' } : relay.takeState(id, t.id, [...on]);
          const words = st.state === 'refused' ? S.line({ code: st.code }) : RelayCore.wording(st.state, (director && director.display_name) || st.name, 'the director');
          rows.push(h.el('li', { class: 'cast-row parts-line' }, h.el('span', { class: 'body' }, PartsUI.excerpt(l)),
            h.el('span', { class: 'caption', role: 'status' }, words)));
        }
      }
      ul.replaceChildren(...rows);
    };
    paint();
    const off = relay.subscribe((lid) => { if (!ul.isConnected) { off(); return; } if (lid === id) paint(); });
    relay.kick(id);
    return ul;
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
  /**
   * The director's pickup (Decision 082): takes pass through to this device while the cast sheet is
   * open and shown, until 30 minutes pass with none; then Keep receiving takes (RelayCore.receive).
   */
  let pickupRun = 0;
  let pickupHeld = null;
  function holdPickup(rec, local, script, pid, me, rerender, box) {
    const mine = ++pickupRun;
    if (pickupHeld) pickupHeld.stop();
    const keep = h.el('button', { type: 'button', class: 'btn', hidden: true, onclick: () => { keep.remove(); holdPickup(rec, local, script, pid, me, rerender, box); } }, 'Keep receiving takes');
    box.append(keep);
    pickupHeld = RelayCore.receive({
      inbox: async () => {
        if (mine !== pickupRun || !sharedShown) throw { left: true };
        return API.plays.inbox(pid);
      },
      onTake: async (got) => {
        if (mine !== pickupRun) return true;
        const fresh = await API.plays.get(pid);
        await S.bringHome({ store, localId: local.id, rec: fresh, script, me, delivered: new Map([[got.take.id, got.bytes]]) });
        if (mine === pickupRun) rerender();
        return true;
      },
      stopOn: (err) => !!(err && (err.left || err.status === 409 || err.status === 503 || err.status === 403 || err.kind === 'unauthorized')),
      onIdle: () => { if (mine === pickupRun) keep.hidden = false; },
    });
  }
  function sharedListen(rec, local, script, pid, me, rerender) {
    const box = listenThrough(store.production(local.id), script, rerender);
    const own = S.ownState(rec, me);
    if (rec.director === me && !(own && own.held)) holdPickup(rec, local, script, pid, me, rerender, box);
    if (rec.hidden_takes) {
      box.append(h.el('p', { class: 'caption' }, rec.hidden_takes === 1 ? '1 take is hidden from you.'
        : `${num.format(rec.hidden_takes)} takes are hidden from you.`));
    }
    const arch = S.archiveStatus(rec);
    // An own script's reason stands with its other facts (ownBox); any other that can't be published says so here.
    if (!arch && !own && S.neverPublishes(rec) && rec.director === me) box.append(h.el('p', { class: 'caption' }, S.neverPublishes(rec)));
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
            if (!(await AgeGate.ask(h))) return;
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
        const pub = h.el('button', { type: 'button', class: 'btn', disabled: waiting.length > 0, onclick: async () => (await AgeGate.ask(h)) && consentSheet(c, async () => {
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
      const own = S.ownState(rec, me);
      const tag = [m.user_id === me ? 'You' : m.director ? 'Director' : '', own && own.by === m.user_id ? 'added this script' : ''].filter(Boolean).join(' · ')
        .replace(/^added/, 'Added');
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
    const script = S.ownState(rec, me);
    if (rec.director === me && (!script || script.state === 'kept')) {
      const slot = h.el('div', { class: 'invite-slot' });
      const line = h.el('p', { class: 'caption refusal', role: 'alert' });
      const inv = h.el('button', { type: 'button', class: 'btn', onclick: async () => {
        if (!(await AgeGate.ask(h))) return;
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
        h.el('div', { class: 'cast-main' }, h.el('a', { class: 'body-strong', href: `?class=${encodeURIComponent(c.id)}` }, c.name),
          c.under13 && !c.school_consent ? h.el('span', { class: 'caption' }, 'Waits for the school’s consent') : null,
          c.deletes_on ? h.el('span', { class: 'caption refusal' }, `Deleted ${ClassUI.dateText(c.deletes_on)} unless opened`) : null),
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
    const box = h.el('section', { class: 'block listen', 'aria-label': 'Listen through' });
    const along = h.el('a', { class: 'btn btn-ghost read-along', href: `?read=${encodeURIComponent(p.scriptID || script.id)}&production=${encodeURIComponent(p.id)}&along=1` }, 'Read along');
    if (!C.isComplete(p, script)) {
      liveListen(box, p, script);
      box.append(along);
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
    box.append(along);
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
      audio: LiveAudio.create({ muted }), voice: StandInVoice.create({ muted, cast: CastUI.castFor({ script, production: p.id }) }),
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
      // On a TV the line heard comes with one before and one after, the speaker in the part's hue (PLAYS-DESIGN §2.11 rule 10).
      if (document.documentElement.classList.contains('tv')) {
        for (const x of ReaderCore.alongPanel(script, line.id)) {
          if (!x) continue;
          const v = lineView(x, x === line ? 'panel-now' : 'panel-near');
          v.dataset.hue = C.partHue(script, C.linePart(x)) || 'none';
          slot.append(v);
        }
        return;
      }
      slot.append(lineView(line));
    }
    // Every listen plays at the device's remembered speed (rule 7): a voice takes it from its next line.
    l.rate = ReaderCore.savedSpeed();
    paint();
    if (!l.plan.length) control.disabled = true;
    box.append(control, slot);
  }

  /* ---- A part: recording it, or reading along ---- */

  async function renderPart(body, my, id, part, lineId) {
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
    // Recording happens in the reader's studio (PLAYS-DESIGN §2.9, WEB-DESIGN §4.16 item 14).
    const line = lineId && C.linesFor(script, part).some(l => l.id === lineId) ? `&line=${encodeURIComponent(lineId)}` : '';
    h.navigate(`?read=${encodeURIComponent(p.scriptID || script.id)}&production=${encodeURIComponent(id)}&part=${encodeURIComponent(part)}${line}`, true);
  }

  /** Another member's part: the lines with the takes the Worker shows this person, each playable and reportable (rule 8). */
  function sharedReadAlong(body, back, local, script, part, rec, pid, my) {
    const items = C.linesFor(script, part).map(l => {
      const li = h.el('li', {}, lineView(l));
      const takeId = rec.chosen[l.id];
      if (takeId) {
        const acts = h.el('div', { class: 'take-row' });
        acts.append(h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => {
          acts.replaceWith(reportForm(pid, { take_id: takeId }, () => renderPart(body, ++token, local.id, part)));
        } }, 'Report'));
        li.append(acts);
      }
      return li;
    });
    body.replaceChildren(back, h.el('ol', { class: 'read-along' }, items));
  }

  /* ---- The router's doors ---- */

  /* ---- Open reads (owner 2026-10-29): an invitation and the finished ear dramas, no account ---- */

  /** Plays chosen takes one after another; a take is fetched when its turn comes. */
  function takePlayer(fetchBytes, onChange) {
    let run = 0;
    let audio = null;
    let url = null;
    const clear = () => {
      if (audio) { audio.pause(); audio = null; }
      if (url) { URL.revokeObjectURL(url); url = null; }
    };
    const stop = () => { run += 1; clear(); onChange(null); };
    async function play(ids, label) {
      stop();
      const mine = run;
      if (typeof Player !== 'undefined') Player.pause();
      onChange(label);
      try {
        for (const id of ids) {
          const got = await fetchBytes(id);
          if (mine !== run) return;
          if (typeof got === 'string') audio = new Audio(got);
          else { url = URL.createObjectURL(new Blob([got], { type: 'audio/wav' })); audio = new Audio(url); }
          audio.muted = muted;
          audio.defaultPlaybackRate = ReaderCore.savedSpeed();
          audio.playbackRate = audio.defaultPlaybackRate;
          audio.preservesPitch = true;
          await new Promise((done) => { audio.onended = done; audio.onerror = done; audio.play().catch(done); });
          clear();
          if (mine !== run) return;
        }
      } catch (err) { console.error(err); }
      if (mine === run) onChange(null);
    }
    return { play, stop };
  }
  let openPlayer = null;
  function stopOpen() { if (openPlayer) openPlayer.stop(); openPlayer = null; }

  const shortDate = new Intl.DateTimeFormat('en-US', { month: 'short', year: 'numeric' });
  /** The Worker stores milliseconds; a seconds value is read as seconds. */
  const publishedOn = (t) => (t ? shortDate.format(new Date(t > 1e11 ? t : t * 1000)) : null);
  /** The names performers chose, once each, in credit order. A part with no name is no performer. */
  const creditNames = (d) => {
    const out = [];
    for (const c of d.credits || []) {
      const n = (c.name || '').trim();
      if (n && !out.includes(n)) out.push(n);
    }
    return out;
  };
  const namesLine = (names, max = 3) => (names.length > max
    ? `${names.slice(0, max).join(', ')} and ${names.length - max} more`
    : names.length === 2 ? names.join(' and ') : names.join(', '));

  /** An ear drama's label (WEB-DESIGN §6.4r): its cast's part hues around the rim, each sized by the part's lines, and the month it was published. */
  function dramaArt(d, script) {
    const parts = script ? C.castOf(script).map((lines, i) => ({ lines, hue: C.PART_HUES[i] || '' })) : [];
    const t = d && d.published_at;
    return { kind: 'drama', parts, finished: t ? new Date(t > 1e11 ? t : t * 1000).toISOString().slice(0, 10) : null };
  }

  /** A finished drama as a tile in the show tile's grammar: the title on the drama board, the voice strip as its mark. */
  function dramaTile(d, scripts) {
    const script = scripts.find(s => s.id === d.script_id);
    const names = creditNames(d);
    const mark = script ? fingerprint(script) : null;
    return h.showTile({ key: d.id, name: d.title, genre: BOARD, first: null, picture: null, ...dramaArt(d, script) },
      { href: `?drama=${encodeURIComponent(d.id)}`, mark, facts: [names.length ? namesLine(names) : null, publishedOn(d.published_at)] });
  }

  /** Finished ear dramas, newest first: `{ rows, next }`. A failed read of the plays leaves the tiles without their strip. */
  async function finishedPage(cursor) {
    const [got, scripts] = await Promise.all([API.plays.finished({ limit: 24, cursor }), API.playLibrary().catch(() => [])]);
    return { rows: got.productions || [], next: got.next_cursor || null, scripts };
  }

  /** Home's shelf: null when there is nothing to show (no empty shelf on Home). */
  async function newDramas(helpers) {
    h = helpers;
    if (!API.plays.available()) return null;
    let page;
    try { page = await finishedPage(); } catch (err) { console.error(err); return null; }
    if (!page.rows.length) return null;
    const ul = h.el('ul', { class: 'rail g-rail', 'aria-labelledby': 'dramas-h' });
    page.rows.slice(0, 12).forEach(d => ul.append(dramaTile(d, page.scripts)));
    // Fewer than six lead Home under the doors (WEB-DESIGN §4.2 item 7a, Decision 079).
    const lead = C.madeHereLeads(page.rows.length, !!page.next);
    return h.el('section', { class: 'shelf', dataset: lead ? { lead: '1' } : {} },
      h.el('div', { class: 'block-head' }, h.el('h2', { class: 'section-header', id: 'dramas-h' }, 'Made here'),
        h.el('a', { class: 'caption', href: '?view=browse&scope=dramas' }, 'All')), ul);
  }

  /** Browse's third scope. */
  async function renderDramas(body, countLine, helpers) {
    h = helpers;
    const my = ++token;
    countLine.replaceChildren();
    const draw = async () => {
      body.replaceChildren(h.stateBox('loading'));
      if (!API.plays.available()) { body.replaceChildren(h.stateBox('empty', { text: 'Not available yet.' })); return; }
      let page;
      try { page = await finishedPage(); } catch (err) { if (my === token) failBox(body, err, draw); return; }
      if (my !== token) return;
      if (!page.rows.length) { body.replaceChildren(h.stateBox('empty', { text: 'No finished ear dramas yet.' })); return; }
      const ul = h.el('ul', { class: 'g-grid', 'aria-label': 'Newest first' });
      const add = (rows) => rows.forEach(d => ul.append(dramaTile(d, page.scripts)));
      add(page.rows);
      const more = h.el('div', { class: 'actions' });
      let next = page.next;
      const paintCount = (n) => countLine.replaceChildren(...[
        h.el('span', { class: 'g-count nw' }, next ? 'Newest first' : n === 1 ? '1 ear drama' : `${num.format(n)} ear dramas`),
        next ? null : h.el('span', { class: 'caption nw' }, 'Newest first')].filter(Boolean));
      let shown = page.rows.length;
      paintCount(shown);
      const button = h.el('button', { type: 'button', class: 'btn', onclick: async () => {
        button.disabled = true;
        try {
          const got = await finishedPage(next);
          if (my !== token) return;
          next = got.next;
          shown += got.rows.length;
          got.rows.forEach(d => ul.append(dramaTile(d, got.scripts)));
          paintCount(shown);
          if (!next) more.replaceChildren(); else button.disabled = false;
        } catch (err) { console.error(err); button.disabled = false; }
      } }, 'Show more');
      if (next) more.append(button);
      body.replaceChildren(ul, more);
    };
    await draw();
  }

  /** The cast as a bill: each part, the name its performer chose, a play control for a part with takes. */
  function billRows(script, parts, play) {
    return h.el('ul', { class: 'cast-list', 'aria-label': 'Cast' }, parts.map(pt => {
      const who = pt.name || null;
      return h.el('li', { class: 'cast-row' },
        script ? face(script, pt.part, { who, size: 'sm' }) : null,
        h.el('div', { class: 'cast-main' }, h.el('span', { class: 'body-strong' }, C.partTitle(pt.part)),
          who ? h.el('span', { class: 'caption' }, who) : null),
        play ? play(pt) : null);
    }));
  }

  /** The playable copy of a finished drama's archive.org item, from its metadata (cached for the page's life).
      A published item holds one file per line (`0042-HAMLET.wav`) and each has derivatives, so a numbered file is
      never mistaken for the whole play: a whole-play MP3 wins (catalog order), else the numbered files in order
      (MP3, then FLAC, then WAV for each); null while nothing is playable yet. Never a private file or an old revision. */
  const audioFiles = new Map();
  async function archiveAudio(itemUrl) {
    const id = String(itemUrl || '').split('/').filter(Boolean).pop();
    if (!id) return null;
    if (audioFiles.has(id)) return audioFiles.get(id);
    const resp = await fetch(`https://archive.org/metadata/${encodeURIComponent(id)}`, { signal: AbortSignal.timeout(20000) });
    if (!resp.ok) throw new Error(`metadata ${resp.status}`);
    const got = S.pickAudio((await resp.json()).files || [], id);
    audioFiles.set(id, got);
    return got;
  }

  /** A finished drama's read-along plan (PLAYS-DESIGN §2.11 rule 11) for `script`, or null when its audio has no
      line timeline: a whole recording, files still being made, or another revision of the script. */
  async function dramaAlong(d, script) {
    if (!script || d.script_id !== script.id) return null;
    return ReaderCore.dramaPlan(await archiveAudio(d.archive_url), script, d.script_revision);
  }
  async function dramaAlongFor(pid, script) { return dramaAlong(await API.plays.finishedOne(pid), script); }

  /** A finished ear drama's page: the board with its credits, Listen, and the bill. */
  async function renderDrama(body, helpers, pid) {
    h = helpers;
    watchAccount();
    lastDraw = null;
    stopOpen();
    const my = ++token;
    const heading = $('drama-h');
    heading.hidden = false;
    body.replaceChildren(h.stateBox('loading'));
    let d;
    let script = null;
    try {
      d = await API.plays.finishedOne(pid);
      script = await API.playScript(d.script_id).catch(() => null);
    } catch (err) {
      if (my !== token) return;
      if (err && err.status === 404) body.replaceChildren(h.stateBox('empty', { text: 'This ear drama is not listed.' }));
      else failBox(body, err, () => renderDrama(body, helpers, pid));
      return;
    }
    if (my !== token) return;
    h.setTitle(d.title);
    const names = creditNames(d);
    const facts = [publishedOn(d.published_at), names.length ? namesLine(names, 4) : null];
    const board = script ? playBoard(script, d.title, `Ear drama · ${kindOf(script)}`, facts, dramaArt(d, script), { hero: true })
      : h.headBoard({ series: { name: d.title, genre: BOARD, picture: null, ...dramaArt(d, script) }, kicker: 'Ear drama', name: d.title, facts, hero: true });
    const listen = h.el('span', { class: 'drama-listen' });
    const acts = h.el('div', { class: 'actions' }, listen,
      h.el('button', { type: 'button', class: 'btn btn-ghost', 'aria-label': `Share ${d.title}`,
                       onclick: () => h.share(d.title, `/drama/${encodeURIComponent(d.id)}`) }, h.icon('share'), 'Share'));
    const waiting = () => { if (my === token) listen.replaceChildren(h.el('span', { class: 'caption', dataset: { state: 'preparing' } }, 'The audio is still being prepared.')); };
    archiveAudio(d.archive_url).then((file) => {
      if (my !== token) return;
      if (!file) { waiting(); return; }
      const button = h.el('button', { type: 'button', class: 'btn btn-primary' });
      const paint = (on) => button.replaceChildren(svg(on ? 'stop' : 'play', 'i-inline'), on ? 'Stop' : 'Play');
      paint(false);
      if (file.whole) {
        button.addEventListener('click', () => {
          Player.load({ id: `drama|${d.id}`, title: d.title, series: 'ear-drama', seriesName: 'Ear drama', url: file.whole, length: null }, { arc: false });
        });
      } else {
        let player = null;
        button.addEventListener('click', () => {
          if (player) { player.stop(); player = null; paint(false); return; }
          player = takePlayer(async (u) => u, (label) => { if (!label && player) { player = null; } paint(!!label); });
          openPlayer = player;
          player.play(file.lines, 'drama');
        });
      }
      listen.replaceChildren(button);
      dramaAlong(d, script).then((plan) => {
        if (!plan || my !== token) return;
        listen.append(h.el('a', { class: 'btn btn-ghost read-along', href: `?read=${encodeURIComponent(script.id)}&finished=${encodeURIComponent(d.id)}&along=1` }, 'Read along'));
      }).catch((err) => console.error(err));
    }).catch((err) => { console.error(err); waiting(); });
    body.replaceChildren(...[board, acts,
      d.credits && d.credits.length ? h.el('section', { class: 'block', 'aria-labelledby': 'bill-h' },
        h.el('h2', { class: 'section-header', id: 'bill-h' }, 'Cast'), billRows(script, d.credits)) : null,
      d.archive_url ? h.el('p', { class: 'caption' }, h.el('a', { href: d.archive_url, target: '_blank', rel: 'noopener' }, 'View on archive.org')) : null,
      script ? rightsLine(script) : null].filter(Boolean));
    heading.hidden = true;
    const hd = body.querySelector('h1');
    if (hd && document.activeElement === heading) hd.focus({ preventScroll: true });
  }

  /** An invitation: everything is shown signed out; only claiming a part asks for an account. */
  async function renderInvite(body, helpers) {
    h = helpers;
    watchAccount();
    sharedShown = null;
    lastDraw = () => renderInvite(body, helpers);
    stopOpen();
    const my = ++token;
    const heading = $('invite-h');
    heading.hidden = false;
    const say = (text) => body.replaceChildren(h.stateBox('empty', { text }));
    if (!API.plays.available()) { say('Not available yet.'); return; }
    const tok = S.pendingInvite();
    if (!tok) { say('This invitation link is not complete.'); return; }
    body.replaceChildren(h.stateBox('loading'));
    let inv;
    let script = null;
    try {
      inv = await API.plays.openInvite(tok);
      await openStore().catch((e) => console.error(e));
      script = await S.scriptOf({ api: API, store, id: inv.scriptID, revision: inv.scriptRevision, who: { token: tok, pid: inv.id }, fit: S.fits.invite(inv) })
        .catch((e) => { if (S.isOwnId(inv.scriptID)) throw e; return null; });
    } catch (err) {
      if (my !== token) return;
      // What an own script's invitation is refused by is said; the sheet is never drawn over words that did not arrive.
      if (S.scriptLine(err)) body.replaceChildren(h.stateBox('error', { text: S.scriptLine(err), retry: err.code === 'script_removed' ? null : lastDraw }));
      else if (err && err.kind === 'gone') say('This invitation has ended.');
      else if (err && (err.status === 404 || err.kind === 'missing')) say('This invitation was not found.');
      else failBox(body, err, lastDraw);
      return;
    }
    if (my !== token) return;
    let member = false;
    if (API.account.signedIn()) {
      try { member = !!(await API.plays.viewInvite(tok)).member; } catch (err) { console.error(err); }
      if (my !== token) return;
    }
    h.setTitle(inv.title);
    const line = h.el('p', { class: 'caption refusal', role: 'alert' });
    const busy = inv.parts.some(pt => pt.status === 'recording');
    const taken = inv.parts.filter(pt => pt.status !== 'open').length;
    const director = (inv.members || []).find(m => m.director);
    const facts = [director && director.name ? `Directed by ${director.name}` : null,
                   `${num.format(taken)} of ${num.format(inv.parts.length)} parts taken`];
    const board = script ? playBoard(script, inv.title, 'Ear drama · in progress', facts, dramaArt(inv, script))
      : h.headBoard({ series: { name: inv.title, genre: BOARD, picture: null, ...dramaArt(inv, script) }, kicker: 'Ear drama · in progress', name: inv.title, facts });

    // An invitation shows the play and who holds what; takes pass through to the director's device and are
    // never served to anyone else (Decision 082), so there is nothing here to listen to.

    const performer = h.el('input', { class: 'field-input', type: 'text', name: 'performer', autocomplete: 'name', maxlength: '40',
                                      id: 'pl-performer', placeholder: 'Your name' });
    const signedIn = API.account.signedIn();
    const cards = (script ? C.castParts(script) : inv.parts.map(pt => ({ id: pt.id, lineCount: pt.lineCount, title: C.partTitle(pt.id) })))
      .map(part => {
        const pt = inv.parts.find(x => x.id === part.id) || { id: part.id, status: 'open', lineCount: part.lineCount };
        const who = pt.performer || null;
        const state = { recording: 'Recording', done: 'Recorded', silent: 'Left silent' }[pt.status] || 'Open';
        const status = who ? `${who} · ${state}` : state;
        const acts = h.el('div', { class: 'pl-part-acts' });
        if (pt.status === 'open' && !busy && !member) {
          acts.append(h.el('button', { type: 'button', class: part.id === inv.next ? 'btn btn-primary' : 'btn btn-way',
            'aria-label': `Take part: ${part.title}`, onclick: async (e) => {
              line.textContent = '';
              if (!signedIn) { line.textContent = 'Taking a part needs an account.'; signIn(); return; }
              if (!script) { line.textContent = S.line({ code: 'revision_mismatch' }); return; }
              const go = e.currentTarget;
              if (!(await AgeGate.ask(h))) return;
              go.disabled = true;
              try {
                await openStore();
                const { local } = await S.join({ api: API.plays, store, token: tok, part: part.id, displayName: performer.value, script });
                S.holdInvite(null);
                h.navigate(`?production=${encodeURIComponent(local.id)}`, true);
              } catch (err) { console.error(err); line.textContent = S.line(err); go.disabled = false; }
            } }, 'Take part'));
        }
        if (script) return partCard(script, part, { who, voice: !who, ok: pt.status === 'done', status, actions: acts });
        return h.el('li', { class: 'pl-part', dataset: { status } },
          h.el('span', { class: 'pl-part-name' }, part.title), h.el('span', { class: 'caption pl-part-who' }, status), acts);
      });
    const acts = h.el('div', { class: 'actions' });
    if (member && script) {
      acts.append(h.el('button', { type: 'button', class: 'btn btn-way', onclick: async () => {
        try {
          await openStore();
          const local = await S.localFor(store, inv.id, script);
          S.holdInvite(null);
          h.navigate(`?production=${encodeURIComponent(local.id)}`, true);
        } catch (err) { console.error(err); line.textContent = S.line(err); }
      } }, 'Open'));
    }
    body.replaceChildren(...[board, acts,
      signedIn && !member && inv.parts.some(pt => pt.status === 'open') && !busy
        ? h.el('label', { class: 'pl-as', for: 'pl-performer' }, h.el('span', { class: 'body' }, 'Recording as'), performer) : null,
      h.el('ul', { class: 'pl-grid', 'aria-label': 'Parts' }, cards), line,
      script ? rightsLine(script) : null].filter(Boolean));
    heading.hidden = true;
    const hd = body.querySelector('h1');
    if (hd && document.activeElement === heading) hd.focus({ preventScroll: true });
  }

  function leave() {
    stopOpen();
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
      if (listen && listen.playing) return;
      const playing = document.querySelector('.mix-audio');
      if (playing && !playing.paused) return;
      lastDraw();
    });
    let was = API.account.signedIn();
    API.account.onChange(() => {
      const now = API.account.signedIn();
      if (now === was) return;
      was = now;
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
    leave();
    if (id && part) return renderPart(body, my, id, part, r.p.get('line'));
    if (id) return renderProduction(body, my, id);
    return renderScript(body, my, r.p.get('play'));
  }

  return { openStore, render, renderInvite, renderDrama, dramaAlongFor, renderDramas, newDramas, openParts, renderMine: (body, helpers, opts) => { watchAccount(); return renderMine(body, helpers, opts); }, making, classDoor, CLASS_READERS, openShared: openRemote, startButton, readLink, leave, fingerprint, BOARD };
})();
