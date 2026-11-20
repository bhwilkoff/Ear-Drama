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
        await session.join(code, {});
        return done();
      } catch (err) {
        if (my !== token) return;
        if (codeOf(err) === 'seat_required') { classStep(slot, my, code, line); go.hidden = true; return; }
        console.error(err);
        line.textContent = R.refusal(codeOf(err));
        go.disabled = false;
      }
    });
    const done = () => { if (my === token) follow(body, my, screen); };
    body.replaceChildren(page(
      h.el('h1', { class: 'section-header rr-h', tabindex: '-1' }, screen ? 'Screen' : 'Read together'),
      codeBlock(code), h.el('div', { class: 'actions' }, go), slot, line));
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
    const bar = el('div', { class: 'rr-bar', role: 'region', 'aria-label': 'Reading together' },
      el('div', { class: 'rr-row' }, fact, skip, parts, here), warn, el('div', { class: 'rr-row rr-row-lead' }, lead, menu));
    api.footer.before(bar);
    let lastCursor = null;
    let lastMine = null;
    let lastMode = null;

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
          el('fieldset', { class: 'rd-choice' }, el('legend', { class: 'caption' }, 'Mode'), radio('read', 'Table read'), radio('rehearse', 'Rehearse')),
          el('label', { class: 'check' }, lock, el('span', { class: 'body' }, 'Lock joining')),
          el('label', { class: 'check' }, openParts, el('span', { class: 'body' }, 'Read open parts')),
          el('a', { class: 'btn btn-ghost', href: `?read-room=${s.code}&screen=1`, target: '_blank', rel: 'noopener' }, 'Open the screen'),
          el('button', { type: 'button', class: 'btn btn-ghost rr-end', onclick: () => { if (confirm('End the reading for everyone?')) send({ type: 'end' }); } }, 'End the reading')));
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
        fact.textContent = n || (reads ? [C.partTitle(reads.part), who, open ? 'Open' : null].filter(Boolean).join(' · ') : '');
      }
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
      detach() { off(); bar.remove(); },
    };
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

  /** Leaving the page pauses the room on this device; its key stays for coming back. */
  function pause() { token += 1; session.pause(); document.body.classList.remove('read-screen'); }

  return { render, start, startButton, session, pause, keepSeat, seats };
})();
