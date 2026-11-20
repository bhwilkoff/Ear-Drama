/**
 * Reading together on the web: the join page, the room bar on the reader, and the shared screen
 * (WEB-DESIGN §4.17, §4.18; PLAYS-DESIGN §12). The rules are ReadCore's (the protocol's port);
 * the transport is ReadSession's; every call is API.read or API.plays. Every word drawn is a
 * label, a fact, a warning or a refusal (AGENTS.md "Only essential words on screen").
 */
const ReadUI = (() => {
  'use strict';
  const C = PlaysCore;
  const R = ReadCore;
  const SEATS_KEY = 'ed.seats';
  const num = new Intl.NumberFormat('en-US');
  let h = null;
  let token = 0;
  const params = () => new URLSearchParams(typeof location !== 'undefined' ? location.search : '');
  const muted = () => params().get('mute') === '1';
  const storage = (() => { try { return window.sessionStorage; } catch { return null; } })();

  const session = ReadSession.make({
    api: API, core: R, storage, diag: params().get('readdiag') === '1',
  });

  /* ---- Seat keys: this tab only (a shared iPad cart picks a name each session, R3c §4.2) ---- */
  function seats() { try { return JSON.parse(storage.getItem(SEATS_KEY) || '[]'); } catch { return []; } }
  function keepSeat(s) {
    const rest = seats().filter((x) => x.class_id !== s.class_id);
    try { storage.setItem(SEATS_KEY, JSON.stringify([...rest, s])); } catch { /* the seat lasts as long as the page */ }
  }
  function dropSeat(classId) {
    try { storage.setItem(SEATS_KEY, JSON.stringify(seats().filter((x) => x.class_id !== classId))); } catch { /* none */ }
  }

  const split = (code) => `${code.slice(0, 3)} ${code.slice(3)}`;
  const spoken = (code) => `Code ${code.split('').join(' ')}`;
  const castOf = (script) => R.castOf(script.lines.map((l) => ({ id: l.id, part: C.linePart(l) })));
  const sceneStarts = (script) => C.sectionsOf(script).map((s) => s.index);
  const seatLabel = (snap, id) => { const s = (snap.seats || []).find((x) => x.id === id); return s ? s.label : null; };
  const codeOf = (err) => (err && (err.code || err.kind)) || 'error';
  const NAME_KEY = 'ed.readName';
  /** The name an adult reads under: the account's chosen name when signed in, else the last one typed here. */
  function chosenName() {
    const a = API.account && API.account.state ? API.account.state() : null;
    if (a && a.display_name) return a.display_name;
    try { return localStorage.getItem(NAME_KEY) || ''; } catch { return ''; }
  }
  function keepName(v) { try { if (v) localStorage.setItem(NAME_KEY, v); } catch { /* a convenience only */ } }

  function codeBlock(code, cls = '') {
    return h.el('p', { class: `rr-code tabular ${cls}`.trim(), 'aria-label': spoken(code) }, split(code));
  }

  /* ---- Opening a room (a play's Read together; the class page's Start a reading) ---- */

  /** Opens a room as leader and goes to it. `extra` carries a class room's `kind`, `class_id`, `production_id`. */
  async function start(script, mode = 'read', extra = {}, helpers = null) {
    if (helpers) h = helpers;
    if (!Array.isArray(script.lines)) script = await API.playScript(script.id);
    const body = { script_id: script.id, script_revision: script.revision, cast: script.lines.map((l) => ({ id: l.id, part: C.linePart(l) })), mode, ...extra };
    const snap = await session.open(body);
    h.navigate(`?read-room=${snap.code}`);
    return snap;
  }

  /** A play page's door: Read together, opening an adult room. Null where reading together is not offered. */
  function startButton(script, helpers) {
    h = helpers;
    if (!API.read.available() || document.documentElement.classList.contains('tv')) return null;
    const line = h.el('span', { class: 'caption refusal', role: 'alert' });
    const b = h.el('button', { type: 'button', class: 'btn btn-way', onclick: async () => {
      b.disabled = true; line.textContent = '';
      try { await start(script, 'read', {}, helpers); } catch (err) { console.error(err); line.textContent = R.refusal(codeOf(err)); b.disabled = false; }
    } }, 'Read together');
    return h.el('span', { class: 'start-drama' }, b, line);
  }

  /* ---- The join page ---- */

  function render(r, helpers) {
    h = helpers;
    const my = ++token;
    const body = document.getElementById('readroom-body');
    const raw = r.p.get('read-room') || '';
    const code = R.normalizeCode(raw);
    const screen = r.p.has('screen');
    document.body.classList.remove('reading');
    document.body.classList.toggle('read-screen', screen);
    h.setTitle(screen ? 'Screen' : 'Read together');
    if (screen && raw.toLowerCase() === 'pair') { pairScreen(body, my); return; }
    if (raw.toLowerCase() === 'parts') { PartsUI.render(body, h); return; }
    if (!code) { body.replaceChildren(page(h.el('p', { class: 'body refusal', role: 'alert' }, R.refusal('bad_code')))); return; }
    body.replaceChildren(h.stateBox('loading'));
    session.resume(code).then((back) => {
      if (my !== token) return;
      if (back && (session.state().role === 'screen') === screen) follow(body, my, screen);
      else joinPage(body, my, code, screen);
    });
  }

  function page(...kids) {
    return h.el('div', { class: 'rr-page' }, ...kids);
  }

  function joinPage(body, my, code, screen) {
    const line = h.el('p', { class: 'caption refusal', role: 'alert' });
    const slot = h.el('div', { class: 'rr-slot' });
    const offline = API.isOffline();
    const go = h.el('button', { type: 'button', class: 'btn btn-primary rr-go', disabled: offline || !API.read.available() }, screen ? 'Show here' : 'Join');
    // An adult reads under an optional name ("Waiting for Ann", "Ann is reading"); a class's names are its seats.
    const name = h.el('input', { class: 'field-input rr-name-input', type: 'text', maxlength: String(R.NAME_MAX), autocomplete: 'nickname',
      placeholder: 'Your name', 'aria-label': 'Your name, optional', value: chosenName() });
    const nameRow = screen ? null : h.el('label', { class: 'rr-name-field' }, name);
    if (offline) line.textContent = R.refusal('offline');
    else if (!API.read.available()) line.textContent = R.refusal('not_configured');
    go.addEventListener('click', async () => {
      go.disabled = true; line.textContent = '';
      try {
        if (screen) { await session.join(code, { role: 'screen' }); return done(); }
        for (const s of seats()) {
          try { await session.join(code, { seat: s.seat, seat_key: s.seat_key }); return done(); } catch (err) {
            if (codeOf(err) === 'seat_key_required') dropSeat(s.class_id);
            else if (!['seat_required', 'seat_in_use'].includes(codeOf(err))) throw err;
          }
        }
        const typed = name.value.trim();
        await session.join(code, typed ? { name: typed } : {});
        keepName(typed);
        return done();
      } catch (err) {
        if (my !== token) return;
        if (codeOf(err) === 'seat_required') { classStep(slot, my, code, line); go.hidden = true; if (nameRow) nameRow.hidden = true; return; }
        console.error(err);
        line.textContent = R.refusal(codeOf(err));
        go.disabled = false;
      }
    });
    const done = () => { if (my === token) follow(body, my, screen); };
    body.replaceChildren(page(
      h.el('h1', { class: 'section-header rr-h', tabindex: '-1' }, screen ? 'Screen' : 'Read together'),
      codeBlock(code), nameRow, h.el('div', { class: 'actions' }, go), slot, line,
      screen ? null : h.el('a', { class: 'btn btn-ghost', href: '?read-room=parts' }, 'Your parts')));
  }

  /** A class room: the class code, then the class's names (no account, no typing a name). */
  function classStep(slot, my, code, line) {
    const input = h.el('input', { class: 'field-input class-code-input', type: 'text', maxlength: '12', autocomplete: 'off',
      autocapitalize: 'characters', spellcheck: 'false', 'aria-label': 'Class code', placeholder: 'Class code', required: true });
    const next = h.el('button', { type: 'submit', class: 'btn btn-primary' }, 'Next');
    const names = h.el('div', { class: 'rr-names' });
    const form = h.el('form', { class: 'take-form', onsubmit: async (e) => {
      e.preventDefault(); next.disabled = true; line.textContent = '';
      try {
        const list = await API.plays.seatList(input.value);
        if (my !== token) return;
        form.hidden = true;
        pickName(names, my, code, input.value, list, line);
      } catch (err) { console.error(err); line.textContent = R.refusal(err.status === 404 ? 'class_not_found' : codeOf(err)); next.disabled = false; }
    } }, input, next);
    slot.replaceChildren(form, names);
    input.focus();
    const door = seatDoor();
    if (door) { input.value = door.classCode; form.requestSubmit(); }
  }

  /** DEBUG doors `?read-part=<role name>` (claim it once in the room) and `?read-record=1` (then arm Record; the bench's stub microphone), local pages only. */
  function roomDoor() {
    if (typeof location === 'undefined' || !/^(localhost|127\.0\.0\.1)$/.test(location.hostname)) return {};
    const p = params();
    return { part: p.get('read-part') || null, record: p.get('read-record') === '1' };
  }

  /** The `?seat=<class code>:<seat id or label>` door picks that name without a person at the form; local pages only, so no shared link carries one. */
  function seatDoor() {
    if (typeof location === 'undefined' || !/^(localhost|127\.0\.0\.1)$/.test(location.hostname)) return null;
    const v = new URLSearchParams(location.search).get('seat') || '';
    const i = v.indexOf(':');
    return i > 0 ? { classCode: v.slice(0, i), seat: v.slice(i + 1) } : null;
  }

  function pickName(box, my, roomCode, classCode, list, line) {
    const ul = h.el('ul', { class: 'rr-name-list', 'aria-label': 'Names' });
    const claim = async (s, move, btn) => {
      btn.disabled = true; line.textContent = '';
      try {
        const got = await API.plays.seatClaim(classCode, s.id, move);
        keepSeat({ class_id: got.class.id, seat: got.seat.id || s.id, seat_key: got.seat_key, label: s.label });
        await session.join(roomCode, { seat: got.seat.id || s.id, seat_key: got.seat_key });
        if (my === token) follow(document.getElementById('readroom-body'), my, false);
      } catch (err) {
        if (my !== token) return;
        btn.disabled = false;
        if (codeOf(err) === 'seat_in_use') {
          line.replaceChildren(R.refusal('seat_in_use'), ' ',
            h.el('button', { type: 'button', class: 'btn btn-way', onclick: (e) => claim(s, true, e.currentTarget) }, 'Move here'));
          return;
        }
        console.error(err);
        line.textContent = R.refusal(codeOf(err));
      }
    };
    const door = seatDoor();
    for (const s of list.seats || []) {
      const b = h.el('button', { type: 'button', class: 'btn rr-name' }, s.label);
      b.addEventListener('click', () => claim(s, false, b));
      ul.append(h.el('li', {}, b));
      if (door && (s.id === door.seat || s.label === door.seat)) setTimeout(() => claim(s, true, b), 0);
    }
    box.replaceChildren(h.el('h2', { class: 'section-header' }, list.class ? list.class.name : 'Names'),
      (list.seats || []).length ? ul : h.el('p', { class: 'caption' }, 'No names yet.'));
  }

  /* ---- Following: the reader with a room attached ---- */

  async function follow(body, my, screen) {
    const snap = session.state().snap;
    body.replaceChildren(h.stateBox('loading'));
    let script = null;
    try { script = await API.playScript(snap.script_id); } catch (err) {
      if (my !== token) return;
      body.replaceChildren(h.stateBox(h.problem(err), { retry: () => follow(body, my, screen) }));
      return;
    }
    if (my !== token) return;
    if (!script || script.revision !== snap.script_revision) {
      body.replaceChildren(page(h.el('p', { class: 'body refusal', role: 'alert' }, R.refusal('revision_mismatch'))));
      return;
    }
    h.setTitle(script.title);
    if (screen) { screenView(body, my, script); return; }
    document.body.classList.add('reading');
    Reader.open(body, script, { onClose: leave, navigate: h.navigate, room: { code: snap.code, attach: (api) => roomBar(api, script) } });
  }

  function leave() {
    session.leave();
    Reader.close();
    h.navigate(history.state && history.state.i > 0 ? '?view=record' : '?view=record', true);
  }

  /** The room bar (§4.17 items 3-6): one fact, presence, and for the leader Back, Next and the Reading disclosure. */
  function roomBar(api, script) {
    const cast = castOf(script);
    const starts = sceneStarts(script);
    const el = api.el;
    const fact = el('p', { class: 'caption rr-fact', role: 'status', 'aria-live': 'polite' });
    const here = el('span', { class: 'caption tabular rr-here' });
    const warn = el('p', { class: 'caption rr-warn', role: 'alert' });
    const back = el('button', { type: 'button', class: 'btn rr-back' }, 'Back');
    const next = el('button', { type: 'button', class: 'btn btn-primary rr-next' }, 'Next');
    const again = el('button', { type: 'button', class: 'btn btn-way rr-again', hidden: true }, 'Again');
    const skip = el('button', { type: 'button', class: 'btn btn-way', hidden: true }, 'Skip');
    const parts = el('button', { type: 'button', class: 'btn btn-way rr-parts', hidden: true }, 'Parts');
    const lead = el('div', { class: 'rr-lead', hidden: true }, back, again, next);
    const menu = el('details', { class: 'rr-menu', hidden: true });
    const recRow = el('div', { class: 'rr-row rr-rec', hidden: true });
    const bar = el('div', { class: 'rr-bar', role: 'region', 'aria-label': 'Reading together' },
      el('div', { class: 'rr-row' }, fact, skip, parts, here), recRow, warn, el('div', { class: 'rr-row rr-row-lead' }, lead, menu));
    api.footer.before(bar);
    let lastCursor = null;
    let lastMine = null;
    let lastMode = null;
    // Record in the room (PLAYS-DESIGN §12.10): the take machinery on this device, made once the store is open.
    let rr = null;
    let litRec = null;
    PlaysUI.openStore().then((store) => {
      if (!bar.isConnected) return;
      rr = ReadRecord.make({
        api: API, store, session, script, cast,
        engine: (o) => RecordingSession.create({ ...o, audio: LiveAudio.create({ muted: muted() }), voice: StandInVoice.create({ muted: true }),
          announce: async () => { const live = document.getElementById('live'); if (live) live.textContent = 'Your line'; } }),
        onChange: () => paint('rec'),
        diag: (line) => { if (params().get('readdiag') === '1') console.log('[readdiag]', 'rec', line, 'at', Date.now(), 'offset', session.state().offset); },
        trace: (...words) => { if (params().get('readdiag') === '1') console.log('[readdiag]', ...words); },
      });
      rr.resume();
      const door = roomDoor();
      if (door.part) send({ type: 'claim', part: door.part.startsWith('role:') ? door.part : `role:${door.part}` });
      if (door.record) setTimeout(() => rr.arm(), door.part ? 1000 : 0);
      // One microphone is the default for an under-13 class (§12.10 item 6): no child's voice leaves a device.
      const s0 = session.state().snap;
      if (s0 && s0.kind === 'class' && s0.class_id && s0.you && s0.you.receives) {
        API.plays.klass(s0.class_id).then((c) => { if (c && c.under13 && rr) rr.setOneMic(true); }).catch(() => {});
      }
      paint('snapshot');
    }).catch((e) => console.error('room store', e));

    const send = (msg) => session.send(msg).catch((err) => { if (codeOf(err) !== 'stale') warn.textContent = R.refusal(codeOf(err)); });
    const move = (delta) => {
      const s = session.state().snap;
      if (!s || !s.you || !s.you.leads) return;
      const line = R.step(cast, s.cursor, delta);
      if (line) send({ type: 'cursor', line, base: s.cursor_gen });
    };
    back.addEventListener('click', () => move(-1));
    next.addEventListener('click', () => move(1));
    skip.addEventListener('click', () => move(1));
    again.addEventListener('click', () => {
      const s = session.state().snap;
      const line = R.sceneStart(cast, s.cursor, starts);
      if (line && line !== s.cursor) send({ type: 'cursor', line, base: s.cursor_gen });
    });
    parts.addEventListener('click', () => partsSheet(api, script, cast).showModal());

    function paintMenu(s) {
      const radio = (value, label) => el('label', { class: 'check' },
        el('input', { type: 'radio', name: 'rr-mode', value, checked: s.mode === value, onchange: () => send({ type: 'mode', mode: value }) }),
        el('span', { class: 'body' }, label));
      const lock = el('input', { type: 'checkbox', checked: !!s.locked, onchange: (e) => send({ type: 'lock', locked: e.currentTarget.checked }) });
      const openParts = el('input', { type: 'checkbox', checked: !!s.read_open, onchange: (e) => send({ type: 'read-open', open: e.currentTarget.checked }) });
      menu.replaceChildren(el('summary', { class: 'btn btn-ghost' }, 'Reading'),
        el('div', { class: 'rr-menu-body' },
          el('fieldset', { class: 'rd-choice' }, el('legend', { class: 'caption' }, 'Mode'), radio('read', 'Table read'), radio('rehearse', 'Rehearse'), radio('record', 'Record')),
          s.mode === 'record' && rr ? el('label', { class: 'check' },
            el('input', { type: 'checkbox', checked: rr.state().oneMic, onchange: (e) => rr.setOneMic(e.currentTarget.checked) }),
            el('span', { class: 'body' }, 'Record every line here')) : null,
          el('label', { class: 'check' }, lock, el('span', { class: 'body' }, 'Lock joining')),
          el('label', { class: 'check' }, openParts, el('span', { class: 'body' }, 'Read open parts')),
          el('a', { class: 'btn btn-ghost', href: `?read-room=${s.code}&screen=1`, target: '_blank', rel: 'noopener' }, 'Open the screen'),
          addScreen(el, s),
          el('button', { type: 'button', class: 'btn btn-ghost rr-end', onclick: () => { if (confirm('End the reading for everyone?')) send({ type: 'end' }); } }, 'End the reading')));
    }

    /** The Record row (§12.10 items 1-4): Start recording, Recording with Stop, who is reading, waiting takes, Takes. */
    function paintRec(s) {
      const on = s.mode === 'record' && !!rr && !!s.you && s.you.role === 'reader';
      recRow.hidden = !on;
      const r = rr ? rr.state() : null;
      const node = r && r.recording ? api.line(r.recording) : null;
      if (litRec && litRec !== node) litRec.classList.remove('rd-rec');
      if (node) node.classList.add('rd-rec');
      litRec = node;
      if (!on) return;
      const room = R.roomOf(s);
      const receives = !!s.you.receives;
      const holdsAny = R.mineIndexes(room, cast, s.you).length > 0;
      const records = (holdsAny && !receives) || (receives && r.oneMic);
      const kids = [];
      if (r.recording) {
        kids.push(el('span', { class: 'rr-rec-dot', 'aria-hidden': 'true' }), el('p', { class: 'body-strong rr-fact', role: 'status' }, 'Recording'),
          el('button', { type: 'button', class: 'btn', onclick: () => rr.stop() }, 'Stop'));
      } else if (records && !r.armed) {
        kids.push(el('button', { type: 'button', class: 'btn btn-record', onclick: () => { if (typeof Player !== 'undefined' && Player.pause) Player.pause(); rr.arm(); } }, 'Start recording'));
        if (r.failed) kids.push(el('p', { class: 'caption refusal', role: 'alert' }, r.failed === 'NotAllowedError' || r.failed === 'SecurityError' ? 'Allow the microphone for this site.' : 'Recording did not start.'));
      } else {
        const reads = s.reads_now;
        const held = reads && (s.kind === 'class' ? !!reads.seat : !!reads.holder);
        const mineNow = s.next_mine && s.next_mine.in === 0;
        if (held && !mineNow && !(s.done || []).includes(s.cursor)) kids.push(el('p', { class: 'caption rr-quiet' }, 'Quiet while others record'));
      }
      if (r.outbox.length) kids.push(el('span', { class: 'caption tabular' }, r.outbox.length === 1 ? '1 take on this device' : `${num.format(r.outbox.length)} takes on this device`));
      if (receives) kids.push(el('button', { type: 'button', class: 'btn btn-way rr-takes', onclick: () => takesSheet(api, script, cast, rr).showModal() }, 'Takes'));
      recRow.replaceChildren(...kids);
    }

    function paint(kind) {
      const st = session.state();
      const s = st.snap;
      if (st.ended) {
        bar.replaceChildren(el('div', { class: 'rr-row' }, el('p', { class: 'body rr-fact', role: 'alert' }, R.refusal(st.ended === 'room_ended' ? 'room_ended' : st.ended)),
          el('button', { type: 'button', class: 'btn', onclick: leave }, 'Close')));
        return;
      }
      if (!s) return;
      const room = R.roomOf(s);
      const mine = R.mineIndexes(room, cast, s.you);
      const key = mine.join(',');
      if (key !== lastMine || s.mode !== lastMode) {
        if (key !== lastMine) api.setMine(mine);
        api.hideAllowed(s.mode === 'rehearse');
        lastMine = key; lastMode = s.mode;
      }
      if (s.cursor !== lastCursor) { api.follow(s.cursor); lastCursor = s.cursor; }
      const leads = !!(s.you && s.you.leads);
      const reads = s.reads_now;
      const away = leads && reads && reads.seat && !reads.members.length && (!s.you || s.you.seat !== reads.seat);
      if (s.waiting_for_leader && !leads) {
        const who = s.kind === 'class' ? R.waitingFor(s) : null;
        fact.textContent = who ? `Waiting for ${who}` : s.kind === 'class' ? 'Waiting for the teacher' : 'Waiting for the leader';
      } else if (away) {
        fact.textContent = `${seatLabel(s, reads.seat) || 'A reader'}’s device is away`;
      } else {
        const n = R.nextLine(s.next_mine);
        const who = reads && (s.kind === 'class' ? (reads.seat ? seatLabel(s, reads.seat) : null) : null);
        const open = reads && (s.kind === 'class' ? !reads.seat : !reads.holder);
        const mineNow = s.next_mine && s.next_mine.in === 0;
        const named = s.mode === 'record' && !mineNow ? R.readerName(s, reads) : null;
        fact.textContent = named ? [`${named} is reading`, n].filter(Boolean).join(' · ')
          : n || (reads ? [C.partTitle(reads.part), who, open ? 'Open' : null].filter(Boolean).join(' · ') : '');
      }
      paintRec(s);
      skip.hidden = !away;
      here.textContent = `${num.format(s.present)} here`;
      parts.hidden = s.kind !== 'adult' || !s.you || s.you.role !== 'reader';
      lead.hidden = !leads;
      menu.hidden = !leads;
      again.hidden = !leads || s.mode !== 'rehearse';
      back.disabled = !R.step(cast, s.cursor, -1);
      next.disabled = !R.step(cast, s.cursor, 1);
      if (leads && (kind === 'snapshot' || !menu.firstChild) && !menu.open) paintMenu(s);
      const w = st.slow ? 'Slow connection' : st.error === 'offline' ? R.refusal('offline') : '';
      if (kind !== 'refused') warn.textContent = w;
    }

    const off = session.onChange((kind, detail) => {
      if (kind === 'refused') { if (detail.code !== 'stale') warn.textContent = R.refusal(detail.code); return; }
      paint(kind);
    });
    paint('snapshot');

    return {
      /** The leader's keys and a pedal: forward and back, never while typing or on a focused button. */
      key(e) {
        const s = session.state().snap;
        if (!s || !s.you || !s.you.leads || session.state().ended) return false;
        const t = e.target;
        if (t && t.closest && t.closest('button, a, summary, details[open]') && (e.key === ' ' || e.key === 'Enter')) return false;
        if (['ArrowRight', 'ArrowDown', 'PageDown', ' ', 'Enter'].includes(e.key)) { move(1); return true; }
        if (['ArrowLeft', 'ArrowUp', 'PageUp'].includes(e.key)) { move(-1); return true; }
        return false;
      },
      detach() { off(); if (rr) rr.detach(); if (litRec) litRec.classList.remove('rd-rec'); bar.remove(); },
    };
  }

  /** The leader's Add a screen (§12.10 item 9): the code a TV shows, typed here. */
  function addScreen(el, s) {
    const input = el('input', { class: 'field-input rr-pair-input', type: 'text', maxlength: '9', autocomplete: 'off', autocapitalize: 'characters',
      spellcheck: 'false', placeholder: 'Code on the TV', 'aria-label': 'Code on the TV' });
    const line = el('p', { class: 'caption refusal', role: 'alert' });
    const add = el('button', { type: 'submit', class: 'btn' }, 'Add a screen');
    return el('form', { class: 'rr-pair', onsubmit: async (e) => {
      e.preventDefault(); add.disabled = true; line.textContent = '';
      try {
        await API.read.attachScreen(s.code, session.state().key, input.value);
        input.value = '';
        line.className = 'caption'; line.textContent = 'Screen added.';
      } catch (err) { line.className = 'caption refusal'; line.textContent = R.refusal(codeOf(err)); }
      add.disabled = false;
    } }, input, add, line);
  }

  /**
   * The receiver's Takes (§12.10 items 4-5): counts per reader, each speaking line's state with Play
   * and Again (and Approve / Again, with an optional note, in a class production), then Listen through, Export,
   * and, in a class of 13 and over, Publish under my name. Counts, never a ranking.
   */
  function takesSheet(api, script, cast, rr) {
    const el = api.el;
    const lines = el('ol', { class: 'rr-take-list' });
    const counts = el('p', { class: 'caption tabular rr-counts' });
    const foot = el('div', { class: 'rr-take-foot' });
    const line = el('p', { class: 'caption refusal', role: 'alert' });
    let player = null;
    let listen = null;
    let klass = null;
    const dlg = el('dialog', { class: 'rd-sheet rr-takes-sheet', 'aria-label': 'Takes' },
      el('div', { class: 'rd-sheet-head' }, el('h2', { class: 'section-header' }, 'Takes'),
        el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => dlg.close() }, 'Done')), counts, lines, foot, line);
    const byId = new Map(script.lines.map((l) => [l.id, l]));
    const label = (snap, c) => (c.seat ? seatLabel(snap, c.seat) : ((snap.members || []).find((m) => m.id === c.holder) || {}).name) || null;
    const send = (msg) => session.send(msg).catch((e) => { line.textContent = R.refusal(codeOf(e)); });
    const STATE = { recorded: 'Recorded', waiting: 'Waiting', open: 'Open' };
    async function hear(t) {
      if (player) { player.pause(); player = null; }
      const bytes = await rr.ensureProduction().then((p) => PlaysUI.openStore().then((store) => store.readTake(p.id, t.file)));
      player = new Audio(URL.createObjectURL(new Blob([bytes], { type: 'audio/wav' })));
      player.muted = muted();
      player.play().catch(() => {});
    }
    function paint() {
      const s = session.state().snap;
      if (!s) return;
      const p = rr.production();
      const arrived = rr.arrivedLines();
      const { rows, counts: per } = R.takeRows(s, cast, arrived, C.isSpeaking);
      counts.textContent = per.map((c) => `${label(s, c) || 'A reader'} ${num.format(c.recorded)} of ${num.format(c.lines)}`).join(' · ');
      lines.replaceChildren(...rows.map((r) => {
        const l = byId.get(r.line);
        const words = (C.spokenText(l) || '').slice(0, 80);
        const who = r.seat ? seatLabel(s, r.seat) : ((s.members || []).find((m) => m.id === r.holder) || {}).name;
        const state = r.state === 'away' ? `On ${who || 'a reader'}’s device` : STATE[r.state];
        const take = p && p.chosen[r.line] ? p.takes.find((t) => t.id === p.chosen[r.line]) : null;
        const acts = [];
        if (take) acts.push(el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => hear(take) }, 'Play'));
        const again = () => send({ type: 'again', line: r.line, base: session.state().snap.cursor_gen });
        const reviewable = take && s.production_id && s.kind === 'class';
        if (reviewable) {
          const note = el('input', { class: 'field-input', type: 'text', maxlength: '500', placeholder: 'Note (optional)', 'aria-label': 'Note to the reader' });
          const fail = (er) => { line.textContent = R.refusal(codeOf(er)); };
          acts.push(el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => API.plays.review(s.production_id, take.id, 'approved').then(() => { line.textContent = ''; }).catch(fail) }, 'Approve'),
            el('details', { class: 'rr-again-note' }, el('summary', { class: 'btn btn-ghost' }, 'Again'),
              el('form', { onsubmit: (e) => {
                e.preventDefault();
                const said = note.value.trim();
                (said ? API.plays.review(s.production_id, take.id, 'again', said) : Promise.resolve()).then(again).catch(fail);
              } }, note, el('button', { type: 'submit', class: 'btn' }, 'Send'))));
        } else if (r.state === 'recorded' || r.state === 'away') {
          acts.push(el('button', { type: 'button', class: 'btn btn-ghost', onclick: again }, 'Again'));
        }
        return el('li', { class: 'rr-take-row', dataset: { state: r.state, line: r.line } },
          el('div', { class: 'cast-main' }, el('span', { class: 'body-strong' }, C.partTitle(r.part)), el('span', { class: 'caption rr-take-words' }, words)),
          el('span', { class: 'caption rr-take-state' }, state), el('div', { class: 'rr-take-acts' }, ...acts));
      }));
      paintFoot(s, p);
    }
    function paintFoot(s, p) {
      const kids = [];
      if (p) {
        const lis = el('button', { type: 'button', class: 'btn btn-primary', onclick: () => {
          if (listen && listen.playing) { listen.stop(); return; }
          PlaysUI.openStore().then((store) => {
            listen = ListenThrough.create({ production: store.production(p.id), script, store, audio: LiveAudio.create({ muted: muted() }),
              voice: StandInVoice.create({ muted: muted() }), onChange: () => { lis.textContent = listen.playing ? 'Stop' : 'Listen through'; } });
            listen.play();
          });
        } }, listen && listen.playing ? 'Stop' : 'Listen through');
        kids.push(lis);
        if (C.isComplete(p, script)) {
          kids.push(el('button', { type: 'button', class: 'btn', onclick: () => PlaysUI.openStore().then((store) => store.exportMix(p.id, LiveAudio.offlineContext)).catch(() => { line.textContent = 'The mix did not export.'; }) }, 'Export'));
        }
      }
      if (s.kind === 'class' && s.production_id) {
        if (klass && klass.under13) kids.push(el('p', { class: 'caption refusal' }, 'An under-13 class never publishes.'));
        else if (klass && p && C.isComplete(p, script)) kids.push(publishForm(el, s, line));
      }
      foot.replaceChildren(...kids);
    }
    if (session.state().snap.kind === 'class' && session.state().snap.class_id) {
      API.plays.klass(session.state().snap.class_id).then((c) => { klass = c; paint(); }).catch(() => {});
    }
    const off = session.onChange(paint);
    const offRec = setInterval(paint, 2000);
    // Open at the line the room is on, so the leader starts where the reading is.
    requestAnimationFrame(() => { const at = lines.querySelector(`[data-line="${CSS.escape(session.state().snap.cursor)}"]`); if (at) at.scrollIntoView({ block: 'center' }); });
    dlg.addEventListener('close', () => { off(); clearInterval(offRec); if (player) player.pause(); if (listen) listen.stop(); dlg.remove(); });
    api.root.append(dlg);
    paint();
    return dlg;
  }

  /** Publish under my name (§12.10 item 5): the credit name, the CC0 consent, then each line's file from this device. */
  function publishForm(el, s, line) {
    const credit = el('input', { class: 'field-input', type: 'text', maxlength: '40', value: chosenName(), placeholder: 'Credit name', 'aria-label': 'Credit name' });
    const agree = el('input', { type: 'checkbox' });
    const terms = el('p', { class: 'caption' });
    const go = el('button', { type: 'submit', class: 'btn btn-primary', disabled: true }, 'Publish under my name');
    let consent = null;
    API.plays.consent().then((c) => { consent = c; terms.textContent = c.publishes === true ? c.text : 'Publishing opens when the Ear Drama archive account is connected.'; go.disabled = c.publishes !== true; }).catch(() => {});
    return el('form', { class: 'rr-publish', onsubmit: async (e) => {
      e.preventDefault();
      if (!agree.checked || !consent) return;
      go.disabled = true; line.textContent = '';
      try {
        await API.plays.agree(s.production_id, consent.version);
        await API.plays.publish(s.production_id, { credit_name: credit.value.trim() });
        keepName(credit.value.trim());
        line.className = 'caption'; line.textContent = 'Queued for archive.org';
        sendFiles(s.production_id, line);
      } catch (err) { line.className = 'caption refusal'; line.textContent = R.refusal(codeOf(err)); go.disabled = false; }
    } }, credit, terms, el('label', { class: 'check' }, agree, el('span', { class: 'body' }, 'I agree')), go);
  }

  /** The director's device sends each line's chosen take to archive.org, one at a time; not laid out yet waits for the cron. */
  async function sendFiles(pid, line) {
    const store = await PlaysUI.openStore();
    const p = store.productions.find((x) => x.roomPid === pid);
    if (!p) return;
    for (const l of (await store.script(p)).lines) {
      const t = p.chosen[l.id] && p.takes.find((x) => x.id === p.chosen[l.id]);
      if (!t) continue;
      for (let tries = 0; tries < 30; tries++) {
        try { await API.plays.sendFile(pid, l.id, await store.readTake(p.id, t.file)); break; } catch (err) {
          if (codeOf(err) === 'already_sent') break;
          if (codeOf(err) === 'not_ready' || err.status === 503) { await new Promise((r) => setTimeout(r, 60000)); continue; }
          line.className = 'caption refusal'; line.textContent = R.refusal(codeOf(err)); return;
        }
      }
    }
    line.className = 'caption'; line.textContent = 'On archive.org';
  }

  /** An adult room's parts: Take (first claim wins) or Release; a taken part says so. */
  function partsSheet(api, script, cast) {
    const el = api.el;
    const list = el('ul', { class: 'cast-list' });
    const line = el('p', { class: 'caption refusal', role: 'alert' });
    const dlg = el('dialog', { class: 'rd-sheet', 'aria-label': 'Parts' },
      el('div', { class: 'rd-sheet-head' }, el('h2', { class: 'section-header' }, 'Parts'),
        el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => dlg.close() }, 'Done')), list, line);
    const paint = () => {
      const s = session.state().snap;
      if (!s) return;
      list.replaceChildren(...C.castParts(script).map((p) => {
        const holder = s.claims[p.id];
        const mine = holder && s.you && holder === s.you.id;
        const act = mine
          ? el('button', { type: 'button', class: 'btn btn-way', onclick: () => session.send({ type: 'release', part: p.id }).catch((e) => { line.textContent = R.refusal(codeOf(e)); }) }, 'Release')
          : holder ? el('span', { class: 'caption' }, 'Taken')
            : el('button', { type: 'button', class: 'btn', onclick: () => session.send({ type: 'claim', part: p.id }).catch((e) => { line.textContent = R.refusal(codeOf(e)); }) }, 'Take');
        return el('li', { class: 'cast-row' }, el('div', { class: 'cast-main' }, el('span', { class: 'body-strong' }, p.title),
          el('span', { class: 'caption tabular' }, p.lineCount === 1 ? '1 line' : `${num.format(p.lineCount)} lines`)), act);
      }));
    };
    const off = session.onChange(paint);
    dlg.addEventListener('close', () => { off(); dlg.remove(); });
    api.root.append(dlg);
    paint();
    void cast;
    return dlg;
  }

  /* ---- The shared screen (§4.18) ---- */

  function screenView(body, my, script) {
    const lines = script.lines;
    const cast = castOf(script);
    const voice = StandInVoice.create({ muted: muted() });
    let spokenAt = null;
    const before = h.el('div', { class: 'rs-before' });
    const now = h.el('div', { class: 'rs-now' });
    const after = h.el('div', { class: 'rs-after' });
    const status = h.el('p', { class: 'caption rs-status', role: 'status' });
    const here = h.el('span', { class: 'caption tabular' });
    const codeEl = h.el('span', { class: 'rs-code tabular' });
    const full = h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => document.documentElement.requestFullscreen && document.documentElement.requestFullscreen().catch(() => {}) }, 'Full screen');
    const root = h.el('div', { class: 'rs' },
      h.el('div', { class: 'rs-page' }, before, now, after),
      h.el('div', { class: 'rs-foot' }, status,
        full,
        h.el('span', { class: 'rs-corner' }, codeEl, here)));
    const speech = (line, cls) => {
      if (!line) return h.el('p', { class: cls });
      const part = C.linePart(line);
      const hue = C.partHue(script, part) || 'none';
      return h.el('div', { class: `rs-line ${cls}` },
        line.kind === 'speech' ? h.el('p', { class: 'rs-who', dataset: { hue } }, C.partTitle(part)) : null,
        h.el('p', { class: 'rs-words' }, C.spokenText(line) || line.source || ''));
    };
    function paint() {
      if (my !== token) return;
      const st = session.state();
      if (st.ended) { status.textContent = R.refusal('room_ended'); return; }
      const s = st.snap;
      if (!s) return;
      const i = Math.max(0, lines.findIndex((l) => l.id === s.cursor));
      before.replaceChildren(speech(lines[i - 1], 'rs-near'));
      now.replaceChildren(speech(lines[i], 'rs-current'));
      after.replaceChildren(speech(lines[i + 1], 'rs-near'), speech(lines[i + 2], 'rs-near'));
      codeEl.textContent = split(s.code);
      codeEl.setAttribute('aria-label', spoken(s.code));
      here.textContent = `${num.format(s.present)} here`;
      status.textContent = s.waiting_for_leader ? (R.waitingFor(s) ? `Waiting for ${R.waitingFor(s)}` : s.kind === 'class' ? 'Waiting for the teacher' : 'Waiting for the leader')
        : st.slow ? 'Slow connection' : '';
      // Read open parts: only a line nobody holds, only on the screen, only live (PLAYS-DESIGN §5).
      const reads = s.reads_now;
      const open = reads && (s.kind === 'class' ? !reads.seat : !reads.holder);
      // The voice stops the moment the cursor moves, so it never sounds during a take (§12.10 item 10).
      if (spokenAt && spokenAt !== s.cursor) { voice.cancel(); if (!open || !s.read_open) spokenAt = null; }
      if (s.read_open && voice.available() && open && spokenAt !== s.cursor && lines[i] && lines[i].kind === 'speech') {
        spokenAt = s.cursor;
        voice.speak(C.spokenText(lines[i]), C.linePart(lines[i]));
      }
      void cast;
    }
    const off = session.onChange(paint);
    body.replaceChildren(root);
    paint();
    const stop = () => { off(); };
    window.addEventListener('popstate', stop, { once: true });
  }

  /**
   * A TV or projector with no code yet (`?read-room=pair&screen=1`, `/read/pair?screen`; §12.10 item 9):
   * it shows a pairing code and waits; the leader types it under Reading, Add a screen. A code lasts
   * 10 minutes and is replaced without a word.
   */
  function pairScreen(body, my) {
    document.body.classList.add('read-screen');
    h.setTitle('Show a reading');
    const codeEl = h.el('p', { class: 'rs-pair-code tabular' });
    const status = h.el('p', { class: 'caption rs-status', role: 'status' });
    body.replaceChildren(h.el('div', { class: 'rs rs-pair' }, h.el('div', { class: 'rs-page' },
      h.el('h1', { class: 'section-header' }, 'Show a reading'), codeEl,
      h.el('p', { class: 'body' }, 'On the leader’s device: Reading, then Add a screen.'), status)));
    let pair = null;
    const fresh = async () => {
      try {
        pair = await API.read.pair();
        codeEl.textContent = split(pair.pair_code);
        codeEl.setAttribute('aria-label', spoken(pair.pair_code));
        status.textContent = '';
      } catch (err) { status.textContent = R.refusal(codeOf(err)); pair = null; }
    };
    const wait = async () => {
      if (my !== token) return;
      if (!pair) await fresh();
      else {
        try {
          const r = await API.read.pairWait(pair.pair_code, pair.pair_key);
          if (my !== token) return;
          if (r && r.type === 'snapshot') { session.adopt(r, 'screen'); follow(body, my, true); return; }
        } catch (err) {
          if (['pair_expired', 'no_such_pair'].includes(codeOf(err))) pair = null;
          else status.textContent = R.refusal(codeOf(err));
        }
      }
      setTimeout(wait, 2000);
    };
    wait();
  }

  /** Leaving the page pauses the room on this device; its key stays for coming back. */
  function pause() { token += 1; session.pause(); document.body.classList.remove('read-screen'); }

  return { render, start, startButton, session, pause, keepSeat, seats };
})();
