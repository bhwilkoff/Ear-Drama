/**
 * The teacher's class page and casting board (WEB-DESIGN §4.19; PLAYS-DESIGN §12.4; R3c §4).
 * Ordered by what needs the teacher now (learner-experience-design §2-§3): start a reading,
 * takes waiting for review, seats, plays with their counts. Counts and links, never a ranking;
 * the casting board shows facts and proposes nothing about who should read what.
 *
 * Every call is API.plays (bearer, the JWT refreshed first); takes pass through to this device
 * while the page is open (Decision 082, the pickup) and are kept in this tab only.
 */
const ClassUI = (() => {
  'use strict';
  const C = PlaysCore;
  const R = ReadCore;
  const num = new Intl.NumberFormat('en-US');
  let h = null;
  let token = 0;
  /** Takes that reached this device in this tab: take id to bytes. Never stored (nothing at rest). */
  const heard = new Map();
  let pickups = [];
  let player = null;

  const lines = (n) => (n === 1 ? '1 line' : `${num.format(n)} lines`);
  const words = (n) => (n === 1 ? '1 word' : `${num.format(n)} words`);
  const wordCount = (line) => (C.spokenText(line) || '').split(/\s+/).filter(Boolean).length;
  const castOf = (script) => script.lines.map((l) => [l.id, C.linePart(l)]);
  const starts = (script) => C.sectionsOf(script).map((s) => s.index);
  const codeOf = (err) => (err && (err.code || err.kind)) || 'error';
  const WORDS = {
    bad_assignments: 'Two seats hold one line.',
    too_many_seats: 'A class holds at most 64 names.',
    name_not_allowed: 'That name is not allowed.',
    offline: 'You are offline.',
    unauthorized: 'Classes need an account.',
    not_castable: 'This play cannot be cast.',
    revision_mismatch: 'This play has changed since it was cast.',
  };
  const say = (err) => WORDS[codeOf(err)] || R.refusal(codeOf(err));
  /** A class's YYYY-MM-DD as the person's own date words; the date is a day, never shifted by a zone. */
  const dateText = (ymd) => {
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(ymd || '');
    return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' }) : '';
  };
  const today = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; };
  const plusDays = (n) => { const d = new Date(Date.now() + n * 86400000); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; };

  function stopPickups() { pickups.forEach((p) => p.stop()); pickups = []; if (player) { player.pause(); player = null; } }

  /**
   * The director's pickup for one production: takes pass through to this tab while the page is open
   * and shown, until 30 minutes pass with none (RelayCore.receive; WEB-DESIGN §4.19 item 7).
   */
  function pickup(pid, onTake, onIdle) {
    pickups.push(RelayCore.receive({
      inbox: () => API.plays.inbox(pid),
      onTake: (got) => { heard.set(got.take.id, got.bytes); onTake(got.take); return false; },
      stopOn: (err) => ['unauthorized', 'not_configured'].includes(codeOf(err)) || err.status === 409 || err.status === 503 || err.status === 403,
      onIdle,
    }));
  }

  function render(r, helpers) {
    h = helpers;
    stopPickups();
    const my = ++token;
    const body = document.getElementById('class-body');
    const id = r.p.get('class');
    const cast = r.p.get('cast');
    if (!API.account.signedIn()) {
      h.setTitle('Class');
      body.replaceChildren(h.el('div', { class: 'state' }, h.el('p', { class: 'caption' }, WORDS.unauthorized),
        h.el('button', { type: 'button', class: 'btn', onclick: () => typeof AccountUI !== 'undefined' && AccountUI.openSheet() }, 'Sign in')));
      return;
    }
    if (cast) return board(body, my, id, cast);
    return classPage(body, my, id);
  }

  /* ---- The class page ---- */

  async function classPage(body, my, id) {
    body.replaceChildren(h.stateBox('loading'));
    let cls, prog;
    try {
      [cls, prog] = await Promise.all([API.plays.klass(id), API.plays.progress(id)]);
    } catch (err) {
      if (my !== token) return;
      console.error(err);
      body.replaceChildren(h.stateBox(h.problem(err), { retry: () => classPage(body, my, id) }));
      return;
    }
    if (my !== token) return;
    h.setTitle(cls.name);
    const recs = await Promise.all((prog.productions || []).map((p) => API.plays.get(p.id).catch(() => null)));
    if (my !== token) return;
    const productions = (prog.productions || []).map((p, i) => ({ ...p, rec: recs[i] }));
    const offline = API.isOffline();
    const redraw = () => classPage(body, my, id);

    const code = cls.code || '';
    const codeText = `${code.slice(0, 4)} ${code.slice(4)}`;
    const showCode = h.el('dialog', { class: 'rd-sheet cl-code-sheet', 'aria-label': 'Class code' },
      h.el('p', { class: 'cl-code-big tabular', 'aria-label': `Code ${code.split('').join(' ')}` }, codeText),
      h.el('button', { type: 'button', class: 'btn', onclick: () => showCode.close() }, 'Done'));
    const head = h.el('header', { class: 'cl-head' },
      h.el('h1', { class: 'view-heading', tabindex: '-1' }, cls.name),
      h.el('p', { class: 'cl-code tabular body-strong', 'aria-label': `Code ${code.split('').join(' ')}` }, codeText),
      h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => showCode.showModal() }, 'Show code'),
      cls.under13 && !cls.school_consent ? h.el('p', { class: 'caption' }, 'Waits for the school’s consent') : null,
      showCode);

    const out = [head];
    if (cls.under13 && !cls.school_consent) out.push(authorizationBox(cls, offline, redraw));
    if (productions.length) out.push(startBox(cls, productions, offline));
    const reviewBox = h.el('section', { class: 'block', id: 'cl-review', 'aria-labelledby': 'cl-review-h' });
    const waitingRow = h.el('p', { class: 'cl-waiting' });
    out.push(waitingRow);
    out.push(seatsBox(cls, offline, redraw));
    out.push(playsBox(cls, productions, offline, redraw));
    out.push(reviewBox);
    out.push(classBox(cls, offline, redraw));
    body.replaceChildren(...out);
    const paintReview = () => reviewQueue(reviewBox, waitingRow, cls, productions, offline);
    paintReview();
    const keep = h.el('button', { type: 'button', class: 'btn', hidden: true, onclick: () => { keep.hidden = true; receiveAll(); } }, 'Keep receiving takes');
    reviewBox.before(keep);
    const idle = () => { if (my !== token) return; stopPickups(); keep.hidden = false; };
    const receiveAll = () => { for (const p of productions) if (p.rec) receiveFor(p); };
    receiveAll();
    function receiveFor(p) {
      pickup(p.id, async (take) => {
        if (my !== token) return;
        try { p.rec = await API.plays.get(p.id); } catch { p.rec.takes = [...(p.rec.takes || []), take]; }
        if (my === token) paintReview();
        try {
          const fresh = await API.plays.progress(id);
          if (my !== token) return;
          for (const q of productions) { const f = (fresh.productions || []).find((x) => x.id === q.id); if (f) q.seats = f.seats; }
          const old = body.querySelector('#cl-plays');
          if (old) old.replaceWith(playsBox(cls, productions, offline, redraw));
        } catch { /* the next arrival or a reload shows the counts */ }
      }, idle);
    }
  }

  /**
   * An under-13 class: the school or district decides (FTC COPPA FAQ N.3; Decision 084). The teacher
   * confirms it and names who approved; until then no student's voice leaves their device.
   */
  function authorizationBox(cls, offline, redraw) {
    const line = h.el('p', { class: 'caption refusal', role: 'alert' });
    const ref = h.el('input', { class: 'field-input', type: 'text', maxlength: '120', id: 'cl-auth-ref', placeholder: 'School or district, and the approval',
      'aria-label': 'Approved by', required: true });
    const ok = h.el('input', { type: 'checkbox', id: 'cl-auth-ok' });
    const go = h.el('button', { type: 'submit', class: 'btn btn-primary', disabled: offline }, 'Record');
    const form = h.el('form', { class: 'cl-auth', onsubmit: async (e) => {
      e.preventDefault();
      line.textContent = '';
      if (!ok.checked) { line.textContent = R.refusal('confirmations_required'); return; }
      if (!ref.value.trim()) { line.textContent = R.refusal('reference_required'); return; }
      go.disabled = true;
      try { await API.plays.schoolConsent(cls.id, ref.value.trim()); redraw(); }
      catch (err) { console.error(err); line.textContent = say(err); go.disabled = false; }
    } },
    h.el('label', { class: 'check', for: 'cl-auth-ok' }, ok, h.el('span', { class: 'body' }, 'My school or district approved Ear Drama for this class.')),
    h.el('label', { class: 'field', for: 'cl-auth-ref' }, h.el('span', { class: 'caption' }, 'Approved by'), ref),
    h.el('div', { class: 'actions' }, go));
    return h.el('section', { class: 'block', 'aria-labelledby': 'cl-auth-h' },
      h.el('h2', { class: 'section-header', id: 'cl-auth-h' }, 'School approval'), form, line);
  }

  /** The class itself (Decision 084): when it ends, Change date, Export class, Delete class. */
  function classBox(cls, offline, redraw) {
    const line = h.el('p', { class: 'caption refusal', role: 'alert' });
    const ends = h.el('p', { class: 'body cl-ends' }, cls.ends_on ? `Ends ${dateText(cls.ends_on)}` : '');
    const date = h.el('input', { class: 'field-input', type: 'date', id: 'cl-end', value: cls.ends_on || '', min: today(), max: plusDays(400), 'aria-label': 'End date' });
    const set = h.el('button', { type: 'submit', class: 'btn', disabled: offline }, 'Change date');
    const dateForm = h.el('form', { class: 'take-form cl-end-form', onsubmit: async (e) => {
      e.preventDefault();
      if (!date.value || date.value === cls.ends_on) return;
      set.disabled = true; line.textContent = '';
      try { await API.plays.setClassEnd(cls.id, date.value); h.announce(`Ends ${dateText(date.value)}`); redraw(); }
      catch (err) { console.error(err); line.textContent = say(err); set.disabled = false; }
    } }, date, set);
    const exp = h.el('button', { type: 'button', class: 'btn', disabled: offline }, 'Export class');
    exp.addEventListener('click', async () => {
      exp.disabled = true; line.textContent = '';
      try {
        const data = await API.plays.exportClass(cls.id);
        const name = `${(cls.name || 'Class').replace(/[\\/:*?"<>|]+/g, '').trim() || 'Class'} export.json`;
        DataExport.save(name, 'application/json', `${JSON.stringify(data, null, 2)}\n`);
      } catch (err) { console.error(err); line.textContent = say(err); }
      exp.disabled = offline;
    });
    const del = h.el('button', { type: 'button', class: 'btn btn-ghost cl-remove', disabled: offline }, 'Delete class');
    del.addEventListener('click', async () => {
      if (!confirm(`Delete ${cls.name}? Its names, casting and notes are deleted. Published plays stay.`)) return;
      del.disabled = true; line.textContent = '';
      try { await API.plays.deleteClass(cls.id); h.navigate('?view=record', true); }
      catch (err) { console.error(err); line.textContent = say(err); del.disabled = false; }
    });
    return h.el('section', { class: 'block', id: 'cl-class', 'aria-labelledby': 'cl-class-h' },
      h.el('h2', { class: 'section-header', id: 'cl-class-h' }, 'Class'),
      ends, dateForm, h.el('div', { class: 'actions' }, exp, del), line);
  }

  function startBox(cls, productions, offline) {
    const line = h.el('p', { class: 'caption refusal', role: 'alert' });
    const sel = productions.length > 1 ? h.el('select', { class: 'field-input', 'aria-label': 'Play' },
      productions.map((p) => h.el('option', { value: p.id }, p.title))) : null;
    const radio = (value, label, on) => h.el('label', { class: 'check' },
      h.el('input', { type: 'radio', name: 'cl-mode', value, checked: on }), h.el('span', { class: 'body' }, label));
    const modes = h.el('fieldset', { class: 'rd-choice cl-modes' }, h.el('legend', { class: 'caption' }, 'Mode'),
      radio('read', 'Table read', true), radio('rehearse', 'Rehearse', false));
    const go = h.el('button', { type: 'button', class: 'btn btn-primary', disabled: offline }, 'Start a reading');
    go.addEventListener('click', async () => {
      go.disabled = true; line.textContent = '';
      const p = sel ? productions.find((x) => x.id === sel.value) : productions[0];
      try {
        const script = await API.playScript(p.rec ? p.rec.scriptID : null);
        if (!script) throw { code: 'not_castable' };
        const mode = modes.querySelector('input:checked').value;
        await ReadUI.start(script, mode, { kind: 'class', class_id: cls.id, production_id: p.id }, h);
      } catch (err) { console.error(err); line.textContent = R.refusal(codeOf(err)); go.disabled = false; }
    });
    return h.el('section', { class: 'block', 'aria-labelledby': 'cl-now-h' },
      h.el('h2', { class: 'section-header', id: 'cl-now-h' }, 'Now'),
      h.el('div', { class: 'take-form cl-start' }, sel, modes, go), line);
  }

  function seatsBox(cls, offline, redraw) {
    const line = h.el('p', { class: 'caption refusal', role: 'alert' });
    const act = (btn, fn) => async () => {
      btn.disabled = true; line.textContent = '';
      try { await fn(); redraw(); } catch (err) { console.error(err); line.textContent = say(err); btn.disabled = false; }
    };
    const rows = (cls.seats || []).map((s) => {
      const tools = h.el('div', { class: 'cl-seat-tools' });
      if (s.claimed) {
        const rel = h.el('button', { type: 'button', class: 'btn btn-ghost', disabled: offline }, 'Release');
        rel.addEventListener('click', act(rel, () => API.plays.releaseSeat(cls.id, s.id)));
        tools.append(rel);
      }
      const rm = h.el('button', { type: 'button', class: 'btn btn-ghost cl-remove', disabled: offline }, 'Remove');
      rm.addEventListener('click', () => { if (confirm(`Remove ${s.label}? Their casting goes; their takes stay.`)) act(rm, () => API.plays.removeSeat(cls.id, s.id))(); });
      tools.append(rm);
      return h.el('li', { class: 'cast-row' }, h.el('div', { class: 'cast-main' }, h.el('span', { class: 'body-strong' }, s.label),
        s.claimed ? h.el('span', { class: 'caption' }, 'On a device') : null), tools);
    });
    const area = h.el('textarea', { class: 'field-input cl-names', rows: '4', 'aria-label': 'Names, one a line', placeholder: 'Names, one a line' });
    const add = h.el('button', { type: 'submit', class: rows.length ? 'btn' : 'btn btn-primary', disabled: offline }, 'Add');
    const refused = h.el('ul', { class: 'cl-refused' });
    const form = h.el('form', { class: 'cl-add', onsubmit: async (e) => {
      e.preventDefault();
      if (!area.value.trim()) return;
      add.disabled = true; line.textContent = ''; refused.replaceChildren();
      try {
        const r = await API.plays.addSeats(cls.id, area.value);
        if ((r.refused || []).length) {
          refused.replaceChildren(...r.refused.map((x) => h.el('li', { class: 'caption refusal' }, `${x.label}: ${WORDS[x.error] || 'not added'}`)));
          add.disabled = false;
          area.value = r.refused.map((x) => x.label).join('\n');
          if (!(r.seats || []).length) return;
        }
        redraw();
      } catch (err) { console.error(err); line.textContent = say(err); add.disabled = false; }
    } }, area, h.el('div', { class: 'actions' }, add), refused);
    return h.el('section', { class: 'block', 'aria-labelledby': 'cl-seats-h' },
      h.el('h2', { class: 'section-header', id: 'cl-seats-h' }, 'Seats'),
      rows.length ? h.el('ul', { class: 'cast-list', 'aria-label': 'Seats' }, rows) : h.el('p', { class: 'caption' }, 'No names yet.'),
      form, line);
  }

  function playsBox(cls, productions, offline, redraw) {
    const line = h.el('p', { class: 'caption refusal', role: 'alert' });
    const rows = productions.map((p) => {
      const per = (p.seats || []).map((s) => {
        const t = s.parts.reduce((a, x) => ({ lines: a.lines + x.lines, recorded: a.recorded + x.recorded, approved: a.approved + x.approved, again: a.again + x.again }),
          { lines: 0, recorded: 0, approved: 0, again: 0 });
        const facts = [`${num.format(t.recorded)} of ${lines(t.lines)} recorded`, t.approved ? `${num.format(t.approved)} approved` : null, t.again ? `${num.format(t.again)} again` : null].filter(Boolean);
        return h.el('li', { class: 'cl-prog-row' }, h.el('span', { class: 'body' }, s.label), h.el('span', { class: 'caption tabular' }, facts.join(' · ')));
      });
      return h.el('li', { class: 'cl-play' },
        h.el('div', { class: 'cast-row' }, h.el('span', { class: 'body-strong' }, p.title),
          h.el('a', { class: 'btn', href: `?class=${encodeURIComponent(cls.id)}&cast=${encodeURIComponent(p.id)}` }, 'Cast')),
        per.length ? h.el('ul', { class: 'cl-prog', 'aria-label': `${p.title}: recorded by seat` }, per) : h.el('p', { class: 'caption' }, 'Nobody cast yet.'));
    });
    const sel = h.el('select', { class: 'field-input', 'aria-label': 'Pick a play' }, h.el('option', { value: '' }, 'Pick a play'));
    const make = h.el('button', { type: 'submit', class: productions.length ? 'btn' : 'btn btn-primary', disabled: true }, 'Make');
    API.playLibrary().then((rows) => {
      sel.append(...C.pickList(rows).map((x) => h.el('option', { value: x.id }, x.label)));
    }).catch((err) => { console.error(err); line.textContent = say(err); });
    sel.addEventListener('change', () => { make.disabled = offline || !sel.value; });
    const form = h.el('form', { class: 'take-form', onsubmit: async (e) => {
      e.preventDefault();
      if (!sel.value) return;
      make.disabled = true; line.textContent = '';
      try {
        const script = await API.playScript(sel.value);
        if (!script) throw { code: 'not_castable' };
        await API.plays.classProduction(cls.id, { script_id: script.id, script_revision: script.revision, cast: script.lines.map((l) => ({ id: l.id, part: C.linePart(l) })) });
        redraw();
      } catch (err) { console.error(err); line.textContent = say(err); make.disabled = false; }
    } }, sel, make);
    return h.el('section', { class: 'block', id: 'cl-plays', 'aria-labelledby': 'cl-plays-h' },
      h.el('h2', { class: 'section-header', id: 'cl-plays-h' }, 'Plays'),
      rows.length ? h.el('ul', { class: 'cl-plays' }, rows) : h.el('p', { class: 'caption' }, 'No play yet.'), form, line);
  }

  /** The seats' chosen takes with no review yet, in script order (PLAYS-DESIGN §12.4 Review). */
  async function reviewQueue(box, waitingRow, cls, productions, offline) {
    const label = (id) => { const s = (cls.seats || []).find((x) => x.id === id); return s ? s.label : 'A seat'; };
    const items = [];
    for (const p of productions) {
      const rec = p.rec;
      if (!rec) continue;
      const reviews = rec.reviews || {};
      for (const t of rec.takes || []) {
        if (!t.seat || (rec.chosen || {})[t.lineID] !== t.id || reviews[t.id]) continue;
        items.push({ p, t });
      }
    }
    waitingRow.replaceChildren(...(items.length ? [h.el('a', { class: 'body-strong', href: '#cl-review' }, items.length === 1 ? '1 take to review' : `${num.format(items.length)} takes to review`)] : []));
    if (!items.length) { box.replaceChildren(); box.hidden = true; return; }
    box.hidden = false;
    const scripts = new Map();
    for (const { p } of items) {
      if (!scripts.has(p.rec.scriptID)) scripts.set(p.rec.scriptID, await API.playScript(p.rec.scriptID).catch(() => null));
    }
    const order = (x) => { const s = scripts.get(x.p.rec.scriptID); return s ? s.lines.findIndex((l) => l.id === x.t.lineID) : 0; };
    items.sort((a, b) => (a.p.title < b.p.title ? -1 : a.p.title > b.p.title ? 1 : order(a) - order(b)));
    const ul = h.el('ul', { class: 'cl-review-list' });
    for (const { p, t } of items) {
      const script = scripts.get(p.rec.scriptID);
      const ln = script ? script.lines.find((l) => l.id === t.lineID) : null;
      const status = h.el('p', { class: 'caption refusal', role: 'alert' });
      const note = h.el('textarea', { class: 'field-input', rows: '2', maxlength: '500', 'aria-label': `Note to ${label(t.seat)}`, placeholder: `Note to ${label(t.seat)}` });
      const decide = (state, btn) => async () => {
        btn.disabled = true; status.textContent = '';
        try { await API.plays.review(p.id, t.id, state, note.value.trim()); li.remove(); } catch (err) { console.error(err); status.textContent = say(err); btn.disabled = false; }
      };
      const play = heard.has(t.id)
        ? h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => {
          if (player) player.pause();
          player = new Audio(URL.createObjectURL(new Blob([heard.get(t.id)], { type: 'audio/wav' })));
          player.muted = new URLSearchParams(location.search).get('mute') === '1';
          player.play().catch(() => {});
        } }, h.icon('play'), 'Play')
        : h.el('span', { class: 'caption' }, 'On another device');
      const ok = h.el('button', { type: 'button', class: 'btn', disabled: offline }, 'Approve');
      const again = h.el('button', { type: 'button', class: 'btn btn-way', disabled: offline }, 'Again');
      ok.addEventListener('click', decide('approved', ok));
      again.addEventListener('click', decide('again', again));
      const li = h.el('li', { class: 'cl-review-row' },
        h.el('p', { class: 'caption' }, `${label(t.seat)} · ${C.partTitle(t.part)} · ${p.title}`),
        h.el('p', { class: 'body cl-review-line' }, ln ? C.spokenText(ln) : ''),
        h.el('div', { class: 'actions cl-review-acts' }, play, ok, again), note, status);
      ul.append(li);
    }
    box.replaceChildren(h.el('h2', { class: 'section-header', id: 'cl-review-h' }, 'Review'), ul);
  }

  /* ---- The casting board (§4.19 item 6) ---- */

  async function board(body, my, id, pid) {
    body.replaceChildren(h.stateBox('loading'));
    let cls, rec, script;
    try {
      [cls, rec] = await Promise.all([API.plays.klass(id), API.plays.get(pid)]);
      script = await API.playScript(rec.scriptID);
    } catch (err) {
      if (my !== token) return;
      console.error(err);
      body.replaceChildren(h.stateBox(h.problem(err), { retry: () => board(body, my, id, pid) }));
      return;
    }
    if (my !== token) return;
    if (!script) { body.replaceChildren(h.stateBox('missing')); return; }
    h.setTitle(rec.title || script.title, cls.name);
    const cast = castOf(script);
    const w = script.lines.map(wordCount);
    const st = starts(script);
    const seats = (cls.seats || []).map((s) => ({ id: s.id, label: s.label }));
    const facts = R.partFacts(cast, w, st);
    const ordered = C.castParts(script).map((p) => ({ ...p, f: facts.find((x) => x.part === p.id) }));
    let assignments = (rec.assignments || []).map((a) => ({ part: a.part, seat: a.seat, from: a.from || null, to: a.to || null }));
    let dirty = false;
    const line = h.el('p', { class: 'caption refusal', role: 'alert' });
    const chips = h.el('ul', { class: 'cb-seats', 'aria-label': 'Seats' });
    const rows = h.el('ul', { class: 'cb-parts', 'aria-label': 'Parts' });
    const save = h.el('button', { type: 'button', class: 'btn btn-primary', disabled: true }, 'Save');
    const label = (sid) => { const s = seats.find((x) => x.id === sid); return s ? s.label : ''; };

    const set = (next) => { assignments = next; dirty = true; paint(); };
    const assignWhole = (part, seat) => set([...assignments.filter((a) => a.part !== part), ...(seat ? [{ part, seat, from: null, to: null }] : [])]);

    function paint() {
      const totals = R.seatTotals(cast, w, assignments, seats);
      chips.replaceChildren(...seats.map((s) => {
        const t = totals.find((x) => x.seat === s.id);
        return h.el('li', { class: 'cb-chip', draggable: 'true', dataset: { seat: s.id },
          ondragstart: (e) => { e.dataTransfer.setData('text/plain', s.id); e.dataTransfer.effectAllowed = 'move'; } },
          h.el('span', { class: 'body-strong' }, s.label), h.el('span', { class: 'caption tabular' }, `${lines(t.lines)} · ${words(t.words)}`));
      }));
      rows.replaceChildren(...ordered.map((p) => {
        const mine = assignments.filter((a) => a.part === p.id);
        const splitUp = mine.length > 1 || (mine.length === 1 && (mine[0].from || mine[0].to));
        const sel = h.el('select', { class: 'field-input cb-sel', 'aria-label': `Seat for ${p.title}` },
          h.el('option', { value: '' }, 'Open'),
          splitUp ? h.el('option', { value: '__split', selected: true, disabled: true }, `Split · ${mine.map((a) => label(a.seat)).join(', ')}`) : null,
          ...seats.map((s) => h.el('option', { value: s.id, selected: !splitUp && mine[0] && mine[0].seat === s.id }, s.label)));
        sel.addEventListener('change', () => assignWhole(p.id, sel.value));
        const f = p.f;
        const factLine = [lines(f.lines), words(f.words), st.length > 1 ? (f.scenes === 1 ? '1 scene' : `${num.format(f.scenes)} scenes`) : null, f.longest ? `longest ${words(f.longest)}` : null].filter(Boolean).join(' · ');
        const splitBtn = f.scenes > 1 ? h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => splitSheet(p) }, 'Split by scene') : null;
        return h.el('li', { class: 'cb-part', dataset: { part: p.id },
          ondragover: (e) => { e.preventDefault(); e.currentTarget.classList.add('cb-over'); },
          ondragleave: (e) => e.currentTarget.classList.remove('cb-over'),
          ondrop: (e) => { e.preventDefault(); e.currentTarget.classList.remove('cb-over'); const sid = e.dataTransfer.getData('text/plain'); if (seats.some((s) => s.id === sid)) assignWhole(p.id, sid); } },
          h.el('div', { class: 'cb-part-main' },
            h.el('span', { class: 'body-strong cb-name', dataset: { hue: C.partHue(script, p.id) || 'none' } }, p.title),
            h.el('span', { class: 'caption tabular' }, factLine)),
          h.el('div', { class: 'cb-part-acts' }, sel, splitBtn));
      }));
      save.disabled = !dirty || API.isOffline();
    }

    function splitSheet(p) {
      const ranges = R.sceneRanges(cast, p.id, st);
      const places = new Map(C.sectionsOf(script).map((s) => [s.index, s.title]));
      const sels = ranges.map((rg) => {
        const cur = assignments.find((a) => a.part === p.id && ((a.from === rg.from && a.to === rg.to) || (!a.from && !a.to)));
        return h.el('select', { class: 'field-input', 'aria-label': `${places.get(rg.scene) || 'Start'}: seat` },
          h.el('option', { value: '' }, 'Open'), ...seats.map((s) => h.el('option', { value: s.id, selected: cur && cur.seat === s.id }, s.label)));
      });
      const dlg = h.el('dialog', { class: 'rd-sheet', 'aria-label': `Split ${p.title} by scene` },
        h.el('div', { class: 'rd-sheet-head' }, h.el('h2', { class: 'section-header' }, p.title)),
        h.el('ul', { class: 'cast-list' }, ranges.map((rg, i) => h.el('li', { class: 'cast-row' },
          h.el('div', { class: 'cast-main' }, h.el('span', { class: 'body' }, places.get(rg.scene) || 'Opening'), h.el('span', { class: 'caption tabular' }, lines(rg.lines))), sels[i]))),
        h.el('div', { class: 'actions' },
          h.el('button', { type: 'button', class: 'btn btn-primary', onclick: () => {
            const picked = ranges.map((rg, i) => ({ part: p.id, seat: sels[i].value, from: rg.from, to: rg.to })).filter((a) => a.seat);
            const allOne = picked.length === ranges.length && picked.every((a) => a.seat === picked[0].seat);
            set([...assignments.filter((a) => a.part !== p.id), ...(allOne ? [{ part: p.id, seat: picked[0].seat, from: null, to: null }] : picked)]);
            dlg.close();
          } }, 'Done'),
          h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => dlg.close() }, 'Cancel')));
      dlg.addEventListener('close', () => dlg.remove());
      body.append(dlg);
      dlg.showModal();
    }

    save.addEventListener('click', async () => {
      save.disabled = true; line.textContent = '';
      try { const r = await API.plays.assign(pid, R.toWire(assignments)); assignments = (r.assignments || []).map((a) => ({ part: a.part, seat: a.seat, from: a.from || null, to: a.to || null })); dirty = false; h.announce('Saved'); paint(); }
      catch (err) { console.error(err); line.textContent = say(err); save.disabled = false; }
    });
    const fill = h.el('button', { type: 'button', class: 'btn', disabled: !seats.length, onclick: () => set(R.fillEvenly(ordered.map((p) => p.f).filter((f) => C.isSpeaking(f.part)), seats, assignments, cast, w)) }, 'Fill evenly');
    const clear = h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => set([]) }, 'Clear');
    body.replaceChildren(
      h.el('header', { class: 'cl-head' },
        h.el('a', { class: 'caption', href: `?class=${encodeURIComponent(id)}` }, cls.name),
        h.el('h1', { class: 'view-heading', tabindex: '-1' }, rec.title || script.title)),
      seats.length ? chips : h.el('div', { class: 'state' }, h.el('p', { class: 'caption' }, 'No names yet.'),
        h.el('a', { class: 'btn', href: `?class=${encodeURIComponent(id)}` }, 'Add names')),
      h.el('div', { class: 'actions cb-tools' }, fill, clear, save), line, rows);
    paint();
  }

  function leave() { stopPickups(); token += 1; }

  return { render, leave, dateText };
})();
