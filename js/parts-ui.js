/**
 * Your parts (PLAYS-DESIGN §12.11, WEB-DESIGN §4.20): a class seat at home. The seat's parts from
 * its class, each line with its take's state on this device ("On this device · sends when Ms.
 * Ortiz is in Ear Drama", "Sending", "Sent") and the teacher's review. Every word is a label, a
 * fact, a warning or a refusal (AGENTS.md "Only essential words on screen"). The takes are the
 * studio's own, recorded in a production on this device; the sender is RelayWatch.
 * Reached at `?read-room=parts`.
 */
const PartsUI = (() => {
  'use strict';
  const C = PlaysCore;
  const R = RelayCore;
  let h = null;
  let token = 0;
  let offs = [];
  const codeOf = (err) => (err && (err.code || err.kind)) || 'error';
  const plural = (n, one, many) => (n === 1 ? one : many);

  /** A line's first words, for a row (a label from the script's own data). */
  function excerpt(line) {
    const words = (line.parts || []).filter((p) => C.pieceKind(p) === 'say').map((p) => C.pieceText(p)).join(' ').split(/\s+/).filter(Boolean);
    return words.length > 7 ? `${words.slice(0, 7).join(' ')}…` : words.join(' ');
  }

  async function ensureLocal(store, script, prod, seat) {
    let local = store.findShared(prod.id);
    if (!local) {
      local = await store.create(script);
      await store.setShare(local.id, { pid: prod.id, seat: { key: seat.seat_key, class_id: seat.class_id, label: seat.label }, assignments: prod.assignments || [] });
    } else {
      const link = store.share(local.id) || {};
      await store.setShare(local.id, { ...link, pid: prod.id, seat: { key: seat.seat_key, class_id: seat.class_id, label: seat.label }, assignments: prod.assignments || [] });
    }
    RelayWatch.flag();
    return local;
  }

  function render(body, helpers) {
    h = helpers;
    const my = ++token;
    offs.forEach((f) => f());
    offs = [];
    h.setTitle('Your parts');
    body.replaceChildren(h.stateBox('loading'));
    (async () => {
      const store = await PlaysUI.openStore();
      if (my !== token) return;
      const relay = RelayWatch.shared({ api: API, store, me: () => null });
      const keys = seatKeys(store);
      if (!keys.length) { classStep(body, my); return; }
      const out = [h.el('h1', { class: 'view-heading', tabindex: '-1' }, 'Your parts')];
      for (const k of keys) out.push(await seatBlock(store, relay, k, my));
      if (my === token) body.replaceChildren(h.el('div', { class: 'rr-page' }, ...out));
    })().catch((err) => {
      if (my !== token) return;
      console.error(err);
      body.replaceChildren(h.stateBox(h.problem(err), { retry: () => render(body, helpers) }));
    });
  }

  /** Every seat this device holds: the ones a studio production was linked to, and the ones just claimed in this tab. */
  function seatKeys(store) {
    const seen = new Map();
    for (const p of store.productions) {
      const l = store.share(p.id);
      if (l && l.seat) seen.set(l.seat.key, { seat_key: l.seat.key, class_id: l.seat.class_id, label: l.seat.label });
    }
    for (const s of ReadUI.seats()) if (!seen.has(s.seat_key)) seen.set(s.seat_key, s);
    return [...seen.values()];
  }

  /** No seat yet: the class code, then the names (no account, no typing a name). */
  function classStep(body, my) {
    const line = h.el('p', { class: 'caption refusal', role: 'alert' });
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
        const ul = h.el('ul', { class: 'rr-name-list', 'aria-label': 'Names' });
        for (const s of list.seats || []) {
          const b = h.el('button', { type: 'button', class: 'btn rr-name' }, s.label);
          b.addEventListener('click', async () => {
            b.disabled = true; line.textContent = '';
            try {
              const got = await API.plays.seatClaim(input.value, s.id, false);
              ReadUI.keepSeat({ class_id: got.class.id, seat: got.seat.id || s.id, seat_key: got.seat_key, label: s.label });
              render(document.getElementById('readroom-body'), h);
            } catch (err) {
              if (my !== token) return;
              console.error(err);
              b.disabled = false;
              line.textContent = codeOf(err) === 'seat_in_use' ? ReadCore.refusal('seat_in_use') : ReadCore.refusal(codeOf(err));
            }
          });
          ul.append(h.el('li', {}, b));
        }
        names.replaceChildren(h.el('h2', { class: 'section-header' }, list.class ? list.class.name : 'Names'),
          (list.seats || []).length ? ul : h.el('p', { class: 'caption' }, 'No names yet.'));
      } catch (err) { console.error(err); line.textContent = ReadCore.refusal(err.status === 404 ? 'class_not_found' : codeOf(err)); next.disabled = false; }
    } }, input, next);
    body.replaceChildren(h.el('div', { class: 'rr-page' }, h.el('h1', { class: 'view-heading', tabindex: '-1' }, 'Your parts'), form, names, line));
    input.focus();
  }

  async function seatBlock(store, relay, seat, my) {
    const box = h.el('section', { class: 'block', 'aria-label': seat.label });
    let home;
    try { home = await API.plays.seatHome(seat.seat_key); } catch (err) {
      box.append(h.el('h2', { class: 'section-header' }, seat.label),
        h.el('p', { class: 'caption refusal', role: 'alert' }, codeOf(err) === 'seat_key_required' ? ReadCore.refusal('seat_key_required') : ReadCore.refusal(codeOf(err))));
      return box;
    }
    box.append(h.el('h2', { class: 'section-header' }, `${home.seat.label} · ${home.class.name}`));
    const mine = (home.productions || []).filter((p) => (p.assignments || []).length);
    if (!mine.length) { box.append(h.el('p', { class: 'caption' }, 'No parts yet.')); return box; }
    for (const prod of mine) {
      let script = null;
      try {
        script = await PlaysShare.scriptOf({ api: API, store, id: prod.scriptID, revision: prod.scriptRevision,
          who: { seat: seat.seat_key, pid: prod.id }, fit: PlaysShare.fits.seat(prod) });
      } catch (err) {
        if (my !== token) return box;
        console.error(err);
        const own = PlaysShare.isOwnId(prod.scriptID);
        const words = codeOf(err) === 'no_script' ? 'Your teacher has not sent this script yet.' : own ? PlaysShare.line(err) : ReadCore.refusal('revision_mismatch');
        box.append(h.el('div', { class: 'parts-prod' }, h.el('h3', { class: 'body-strong' }, prod.title), h.el('p', { class: 'caption refusal', role: 'alert' }, words),
          own && !['script_removed'].includes(codeOf(err)) ? h.el('div', { class: 'actions' }, h.el('button', { type: 'button', class: 'btn', onclick: () => render(document.getElementById('readroom-body'), h) }, 'Try again')) : null));
        continue;
      }
      if (my !== token) return box;
      box.append(await productionBlock(store, relay, seat, home, prod, script));
    }
    return box;
  }

  async function productionBlock(store, relay, seat, home, prod, script) {
    const cast = script.lines.map((l) => [l.id, C.linePart(l)]);
    const mineLines = new Set(R.assignedLines(cast, prod.assignments));
    const parts = [...new Set(prod.assignments.map((a) => a.part))];
    const remote = new Map((prod.takes || []).map((t) => [t.lineID, t]));
    const local = store.findShared(prod.id);
    let name = null;
    const sec = h.el('div', { class: 'parts-prod' }, h.el('h3', { class: 'body-strong' }, prod.title));
    const paint = () => {
      const lists = parts.map((part) => {
        const lines = script.lines.filter((l) => mineLines.has(l.id) && C.linePart(l) === part);
        const rows = lines.map((l) => {
          const t = local ? C.chosenTake(store.production(local.id), l.id) : null;
          const r = remote.get(l.id);
          let state = null;
          let review = null;
          if (r && r.chosen) {
            state = R.wording('sent');
            if (r.review) review = r.review.state === 'approved' ? 'Approved' : `Again${r.review.note ? ` · ${r.review.note}` : ''}`;
          } else if (t && !t.bleed) {
            const st = local ? relay.takeState(local.id, t.id, [...remote.values()].map((x) => x.id)) : { state: 'waiting' };
            state = st.state === 'refused' ? PlaysShare.line({ code: st.code }) : R.wording(st.state, name || st.name, 'your teacher');
          } else if (t && t.bleed) {
            state = PlaysShare.line({ code: 'bleed_flagged' });
          }
          return h.el('li', { class: 'cast-row parts-line' },
            h.el('span', { class: 'body' }, excerpt(l)),
            state ? h.el('span', { class: 'caption', role: 'status' }, state) : null,
            review ? h.el('span', { class: review.startsWith('Again') ? 'caption refusal' : 'caption' }, review) : null);
        });
        const record = h.el('button', { type: 'button', class: 'btn btn-accent', onclick: async (e) => {
          e.currentTarget.disabled = true;
          const lp = await ensureLocal(store, script, prod, seat);
          relay.kick(lp.id);
          // A seat holds its parts by the class's casting, never by a claim, so Record goes to the studio itself (§4.20 item 1).
          const p = store.production(lp.id);
          if (C.stateOf(p, part).status === 'open' && !C.current(p, script)) await store.save(C.take(p, script, part, seat.label));
          h.navigate(`?read=${encodeURIComponent(script.id)}&production=${encodeURIComponent(lp.id)}&part=${encodeURIComponent(part)}`);
        } }, 'Record');
        return h.el('div', { class: 'parts-part' },
          h.el('div', { class: 'cast-row' },
            h.el('span', { class: 'body-strong' }, `${C.partTitle(part)} · ${lines.length} ${plural(lines.length, 'line', 'lines')}`), record),
          h.el('ul', { class: 'cast-list', 'aria-label': `${C.partTitle(part)}: your takes` }, rows));
      });
      sec.replaceChildren(h.el('h3', { class: 'body-strong' }, prod.title), ...lists);
    };
    paint();
    API.plays.seatReceiver(seat.seat_key, prod.id).then((r) => { if (r && r.name) { name = r.name; paint(); } }).catch(() => {});
    offs.push(relay.subscribe((id) => { if (local && id === local.id && sec.isConnected) paint(); }));
    if (local) relay.kick(local.id);
    return sec;
  }

  return { render, excerpt, seatKeys };
})();
