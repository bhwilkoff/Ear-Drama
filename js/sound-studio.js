/**
 * The Sound part's studio and the sound board (B32 §3; WEB-DESIGN §4.16 item 14a). The owner, 2026-11-26:
 * "I'd like to add the ability to record both stage direction (as a character) and foley sounds within a
 * well-designed foley (or sound effects, depending on the need of the play) soundboard/interface that would
 * allow someone to add sounds in the backgrounds of a recording."
 *
 * The reader keeps the page; this file draws what the Sound part adds to it: each slot's state and chosen sounds,
 * the current slot, a bed's rule, the dock and transport, and the board (a sheet below the spread width, the
 * studio's panel from it). What a slot holds is SoundCore (js/sound-core.js); where a sound's audio comes from is
 * SoundStore (js/sound-store.js). A performed cue records through the shipped RecordingSession as a take.
 */
const SoundStudio = (() => {
  'use strict';
  const C = PlaysCore;
  const S = SoundCore;
  const WIDE = ReaderCore.SPREAD_MIN;
  const ICON = {
    record: 'M12 5a7 7 0 1 0 0 14 7 7 0 0 0 0-14z',
    stop: 'M7 7h10v10H7z',
    play: 'M8 5v14l11-7z',
    prev: 'M15.4 7.4 14 6l-6 6 6 6 1.4-1.4-4.6-4.6z',
    next: 'M8.6 16.6 10 18l6-6-6-6-1.4 1.4 4.6 4.6z',
    board: 'M4 4h7v7H4zm9 0h7v7h-7zM4 13h7v7H4zm9 0h7v7h-7z',
    speaker: 'M3 9v6h4l5 5V4L7 9H3zm13.5 3A4.5 4.5 0 0 0 14 8v8a4.5 4.5 0 0 0 2.5-4z',
    note: 'M12 3v10.55A4 4 0 1 0 14 17V7h4V3h-6z',
    wave: 'M7 9h2v6H7zm4-3h2v12h-2zm4 3h2v6h-2z',
    plus: 'M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z',
    check: 'M9 16.2 4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4z',
    trash: 'M6 19a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z',
    down: 'M5 20h14v-2H5v2zM19 9h-4V3H9v6H5l7 7 7-7z',
    file: 'M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6zm4 18H6V4h7v5h5v11z',
    mic: 'M12 14a3 3 0 0 0 3-3V5a3 3 0 0 0-6 0v6a3 3 0 0 0 3 3zm5-3a5 5 0 0 1-10 0H5a7 7 0 0 0 6 6.92V21h2v-3.08A7 7 0 0 0 19 11h-2z',
    headphones: 'M12 3a9 9 0 0 0-9 9v6a3 3 0 0 0 3 3h2v-8H5v-1a7 7 0 0 1 14 0v1h-3v8h2a3 3 0 0 0 3-3v-6a9 9 0 0 0-9-9z',
    warn: 'M1 21h22L12 2zm12-3h-2v-2h2zm0-4h-2v-4h2z',
    chev: 'M8.6 16.6 10 18l6-6-6-6-1.4 1.4 4.6 4.6z',
  };
  const num = new Intl.NumberFormat('en-US');
  const muted = () => typeof location !== 'undefined' && new URLSearchParams(location.search).get('mute') === '1';
  const DUCKS = [null, -3, -6, -9, -12, -18, 0];

  function icon(name, cls) {
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

  /* ---- One sound store and one player for the page ---- */

  let shared = null;
  let thePlayer = null;
  /** The sounds over the plays database the cast sheet and studio share (PlaysUI's store). */
  function soundsFor(store) {
    if (!shared || shared.owner !== store.backend) { shared = SoundStore.create({ backend: store.backend }); shared.owner = store.backend; }
    return shared;
  }
  const player = () => (thePlayer || (thePlayer = SoundStore.player()));

  /** A line's number as the page knows it ("191" from L0191), and its speaker. */
  function lineLabel(script, lineID) {
    const i = script.lines.findIndex(l => l.id === lineID);
    const line = script.lines[i];
    const m = /^L0*(\d+)$/.exec(lineID || '');
    const n = m ? m[1] : String(i + 1);
    const who = line ? (line.kind === 'speech' ? line.role : line.kind === 'direction' ? 'Directions' : 'Sound') : '';
    return { n, who, text: `Line ${n}${who ? ` · ${who}` : ''}` };
  }

  /**
   * The live listen's cues (B32 §4.4) for ListenThrough's `cues`: each slot's sounds started as their line comes,
   * ducked while a voice entry sounds. A sound this device lacks plays nothing.
   */
  function liveCues(store, p, script) {
    const sounds = soundsFor(store);
    const ready = Promise.all([sounds.mine(), sounds.loadPack()]).catch(() => {});
    const P = player();
    if (P.warm) P.warm();
    return (plan) => {
      const sched = S.listenCues(script, p, plan);
      return {
        at: (i) => sched[i],
        async start({ sound: x }) {
          await ready;
          const data = await sounds.samplesOf(x.src, p, store);
          if (!data) return null;
          const d = sounds.describe(x.src, p);
          const lane = x.at === 'bed' || d.kind === 'music' ? 'music' : 'effects';
          const laneDb = (((p.sound || {}).lanes || {})[lane] || {}).duckDb;
          const duckDb = typeof x.duckDb === 'number' ? x.duckDb : (typeof laneDb === 'number' ? laneDb : (lane === 'music' ? C.SOUND_DEFAULTS.musicDuckDb : C.SOUND_DEFAULTS.effectsDuckDb));
          const src = d.cue || d.own || {};
          const h = await P.play(data, { gainDb: x.gainDb || 0, loop: !!x.loop, fadeInMs: x.fadeInMs || 0, fadeOutMs: x.fadeOutMs || 0, duckDb,
                                         loudness: src.lufs ?? src.loudness ?? (d.take ? d.take.loudness : null), peak: src.peak || (d.take ? d.take.peak : 0), lane });
          h.soundID = x.id;
          h.bed = !!x.loop;
          return h;
        },
        stopAll: () => P.stopAll(),
      };
    };
  }

  /**
   * What a mix with sound needs (Decision 091): the resolver and loader over this device's pack and own sounds,
   * the categories it needs downloaded first. Rejects with MixFailure('missingSounds', names) when a sound is not
   * here and `without` is not set; with it, the mix leaves those out (and is never recorded as current).
   */
  async function mixOptions(store, p, { without = false } = {}) {
    if (!C.hasSound(p)) return {};
    const got = await soundsFor(store).prepare(p);
    if (got.missing.length && !without) throw new C.MixFailure('missingSounds', got.missing.map(m => m.title));
    return { resolveSound: got.resolveSound, loadSound: got.loadSound, withoutMissing: without };
  }

  /** "2 sounds are on another device: Owl at night, Gate creak." (B32 §7) */
  function missingLine(names) {
    // A timeline names a sound by its id; only a person's own words for it are shown.
    const known = names.filter(n => n && !/^[0-9A-F]{8}-[0-9A-F]{4}-/i.test(n));
    const n = names.length;
    return `${n === 1 ? '1 sound is' : `${num.format(n)} sounds are`} on another device${known.length ? `: ${known.join(', ')}` : ''}.`;
  }

  /* ---- The studio ---- */

  function attach(api, { production: id, store, line = null }) {
    const { el, script } = api;
    const sounds = soundsFor(store);
    const P = player();
    const prod = () => store.production(id);
    const ss = {
      cur: null, sel: null, wide: false, detached: false, listen: null, picking: null, q: null, cat: undefined,
      open: null, rec: null, gate: false, headphones: false, clock: null, menu: null, sig: '', audition: null, err: '',
    };
    let session = null;
    let sessionReady = false;

    /* ---- Slots ---- */

    const slots = () => S.slotsOf(script, prod());
    const same = (a, b) => !!a && !!b && a.line === b.line && (a.piece ?? null) === (b.piece ?? null) && !!a.added === !!b.added;
    const current = () => slots().find(s => same(s, ss.cur)) || null;
    function setCur(slot, { reveal = true } = {}) {
      const was = current();
      ss.cur = slot ? { line: slot.line, piece: slot.piece, added: slot.added } : null;
      ss.sel = slot && slot.sounds.length ? slot.sounds[0].id : null;
      ss.q = null;
      if (was && was.id && !same(was, slot)) {
        const n = S.prune(prod(), slot && slot.id);
        if (n !== prod()) store.update(n);
      }
      paint();
      if (reveal && slot) api.go(slot.line);
    }
    function apply(change) {
      const n = change(prod());
      if (n && n !== prod()) store.update(n);
      paint();
    }
    /** The current slot's record id, writing it on first touch. */
    function ensureCur() {
      const v = current();
      if (!v) return null;
      if (v.id) return v.id;
      const { production, id: sid } = S.ensure(prod(), v);
      store.update(production);
      return sid;
    }
    {
      const all = slots();
      const want = line ? all.find(s => s.line === line) : null;
      const first = want || all.find(s => !s.sounds.length && !s.silent) || all[0] || null;
      ss.cur = first ? { line: first.line, piece: first.piece, added: first.added } : null;
      ss.sel = first && first.sounds.length ? first.sounds[0].id : null;
    }

    const titleOf = (x) => sounds.describe(x.src, prod()).title;
    const placeShort = (x) => (x.at === 'bed' ? `Bed to line ${lineLabel(script, x.until || '').n}` : S.placementWords(x));

    /* ---- The page: each slot's state, its sounds, the current slot, a bed's rule ---- */

    let decorated = [];
    function hostOf(slot) {
      const node = api.line(slot.line);
      if (!node) return null;
      if (slot.added) {
        let h = node.querySelector(':scope > .sb-added');
        if (!h) { h = el('span', { class: 'sb-added' }, el('span', { class: 'rd-sfx-mark' }, icon('speaker'))); node.append(h); }
        return h;
      }
      if (slot.piece === null) return node;
      return node.querySelector(`.rd-sfx[data-piece="${slot.piece}"]`);
    }
    function paintPage() {
      for (const n of decorated) n.remove();
      decorated = [];
      api.root.querySelectorAll('.sb-cur, .sb-bed, .sb-host').forEach(n => n.classList.remove('sb-cur', 'sb-bed', 'sb-host', 'sb-rec'));
      api.root.querySelectorAll('.sb-added').forEach(n => n.remove());
      const cur = current();
      const all = slots();
      const at = new Map(script.lines.map((l, i) => [l.id, i]));
      let sig = '';
      all.forEach((slot, k) => {
        if (slot.added && !slot.sounds.length && !same(slot, cur)) return;
        const host = hostOf(slot);
        if (!host) return;
        host.classList.add('sb-host');
        const n = slot.sounds.length;
        const ring = el('button', { type: 'button', class: 'rd-take sb-ring', dataset: { slot: String(k), state: slot.silent ? 'silent' : n ? 'chosen' : 'none' },
                                    'aria-label': slot.silent ? 'Left silent' : n ? `${n === 1 ? '1 sound' : `${num.format(n)} sounds`}` : 'No sound' },
          el('span', { class: 'rd-take-dot' }), n ? el('span', { class: 'rd-take-n tabular' }, String(n)) : '');
        host.append(ring);
        decorated.push(ring);
        if (n) {
          const list = el('span', { class: 'sb-list' }, slot.sounds.map(x => el('span', { class: 'sb-snd caption' },
            icon(x.at === 'bed' || sounds.describe(x.src, prod()).kind === 'music' ? 'note' : 'speaker'),
            el('span', { class: 'sb-snd-t' }, titleOf(x)), el('span', { class: 'st-muted' }, ` · ${placeShort(x)}`))));
          host.append(list);
          decorated.push(list);
        }
        if (same(slot, cur)) {
          host.classList.add('sb-cur');
          host.classList.toggle('sb-rec', !!(session && session.phase.kind === 'listening'));
        }
        sig += `${k}:${n}:${slot.silent ? 1 : 0};`;
        for (const x of slot.sounds) {
          if (x.at !== 'bed') continue;
          const a = at.get(slot.line), b = at.has(x.until) ? at.get(x.until) : a;
          for (let i = a; i <= Math.max(a, b); i++) { const ln = api.line(script.lines[i].id); if (ln) ln.classList.add('sb-bed'); }
        }
      });
      if (sig !== ss.sig) { ss.sig = sig; api.relayout(); }
    }

    /* ---- The dock and the transport ---- */

    const dock = el('div', { class: 'st-dock sb-dock' });
    const transport = el('div', { class: 'st-transport' });
    const boardBtn = el('button', { type: 'button', class: 'icon-btn rd-icon st-open', 'aria-label': 'Sounds', title: 'Sounds', onclick: () => openBoard() }, icon('board'));
    const panel = el('div', { class: 'st-panel sb-panel' });
    const sheet = api.sheet('Sounds', panel);
    sheet.classList.add('st-sheet', 'sb-sheet');
    api.root.append(sheet);
    api.dock.hidden = false;
    api.dock.replaceChildren(dock);
    api.footer.insertBefore(transport, api.hideBtn);
    api.footer.insertBefore(boardBtn, api.footer.firstChild);
    api.studioMode(true);
    api.hideBtn.hidden = true;

    function ensureSession() {
      if (session) return session;
      session = RecordingSession.create({
        production: prod(), script, part: C.SOUND, store,
        audio: LiveAudio.create({ muted: muted() }),
        voice: StandInVoice.create({ muted: muted(), cast: api.cast }),
        onChange: () => { if (sessionReady) paint(); },
      });
      session.onLevel = (levels) => { const m = dock.querySelector('.st-meter'); if (m) drawMeter(m, levels); };
      sessionReady = true;
      return session;
    }
    const busy = () => !!(session && session.isBusy());

    function drawMeter(m, levels) {
      const bars = m.children;
      const shown = levels.slice(-bars.length);
      for (let i = 0; i < bars.length; i++) { const v = shown[i - (bars.length - shown.length)]; bars[i].style.height = `${Math.max(3, Math.round(22 * (v || 0)))}px`; }
    }

    function gate() {
      const box = el('div', { class: 'st-gate' });
      if (!LiveAudio.supported()) { box.append(el('p', { class: 'body' }, 'This browser cannot record.')); return box; }
      const start = el('button', { type: 'button', class: 'btn btn-record st-go', disabled: !ss.headphones, onclick: async () => {
        if (typeof Player !== 'undefined' && Player.pause) Player.pause();
        ss.gate = false;
        await ensureSession().begin();
        paint();
      } }, icon('record', 'i-inline'), 'Start recording');
      const check = el('input', { type: 'checkbox', id: 'sb-headphones', checked: ss.headphones,
                                  onchange: () => { ss.headphones = check.checked; start.disabled = !check.checked; } });
      const r = session && session.phase.kind === 'failed' ? session.phase.reason : null;
      const failed = !r ? null : (r === 'NotAllowedError' || r === 'SecurityError') ? 'Ear Drama needs the microphone to record your part. Allow it for this site in the browser\'s settings.'
        : (r === 'NotFoundError' || r === 'OverconstrainedError') ? 'No microphone found.' : r === 'save' ? 'This take was not saved.' : 'Recording did not start.';
      box.append(...[
        el('div', { class: 'st-gate-h' }, icon('headphones', 'st-gate-icon'),
          el('span', {}, el('span', { class: 'body-strong' }, 'Headphones on'), el('span', { class: 'caption st-why' }, 'This browser cannot tell whether they are on.'))),
        el('div', { class: 'st-gate-go' }, el('label', { class: 'pl-check', for: 'sb-headphones' }, check, el('span', { class: 'body-strong' }, 'My headphones are on')), start),
        failed ? el('p', { class: 'caption refusal', role: 'alert' }, failed) : null].filter(Boolean));
      return box;
    }

    function paintDock() {
      clearInterval(ss.clock);
      const ph = session ? session.phase : { kind: 'idle' };
      if (ss.picking) {
        dock.replaceChildren(el('div', { class: 'st-status', role: 'status' }, el('span', { class: 'body-strong' }, 'Tap the last line it sits under.'),
          el('button', { type: 'button', class: 'btn btn-way', onclick: () => { ss.picking = null; paint(); openBoard(); } }, 'Cancel')));
        return;
      }
      if (ss.gate || (session && !session.started && ph.kind === 'failed')) { dock.replaceChildren(gate()); return; }
      if (ph.kind === 'roomTone') {
        dock.replaceChildren(el('div', { class: 'st-status', role: 'status' },
          el('span', { class: 'body-strong' }, 'Quiet, please. Recording the room.'), el('span', { class: 'st-count tabular' }, String(ph.secondsLeft))));
        return;
      }
      const row = el('div', { class: 'st-status', role: 'status' });
      if (ph.kind === 'listening') {
        const bars = Array.from({ length: 40 }, () => el('i'));
        row.append(el('span', { class: 'st-rec tabular' }, el('span', { class: 'dot' }), 'Recording 0:00'), el('div', { class: 'pl-meter st-meter', 'aria-hidden': 'true' }, bars));
        dock.replaceChildren(row);
        const t0 = Date.now();
        ss.clock = setInterval(() => {
          const sec = Math.floor((Date.now() - t0) / 1000);
          const out = dock.querySelector('.st-rec');
          if (out) out.lastChild.textContent = `Recording ${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}`;
        }, 500);
        return;
      }
      if (ph.kind === 'cue') {
        const ln = script.lines.find(l => l.id === ph.lineID);
        const lp = ln ? C.linePart(ln) : null;
        row.append(el('span', { class: 'st-who', dataset: { hue: C.partHue(script, lp) || 'none' } }, ln ? (ln.role || C.partTitle(lp)) : ''),
          el('span', { class: 'caption st-muted' }, ph.deviceVoice ? 'Device voice' : 'Take'));
        dock.replaceChildren(row);
        return;
      }
      const all = slots();
      const cur = current();
      const i = cur ? all.findIndex(s => same(s, cur)) : -1;
      if (!all.length) row.append(el('span', { class: 'caption st-muted' }, 'Right-click or hold a line to add a sound.'));
      else {
        row.append(el('span', { class: 'tabular' }, `Cue ${num.format(i + 1)} of ${num.format(all.length)}`));
        const x = cur && cur.sounds.find(y => y.id === ss.sel) || (cur && cur.sounds[0]);
        if (x) row.append(el('span', { class: 'body-strong sb-dock-t' }, titleOf(x)), el('span', { class: 'caption st-muted' }, placeShort(x)));
        else if (cur && cur.silent) row.append(el('span', { class: 'caption st-muted' }, 'Silent'));
      }
      if (ss.err) row.append(el('span', { class: 'caption refusal', role: 'alert' }, ss.err));
      dock.replaceChildren(row);
    }

    function round(act, cls, name, label, onclick, disabled = false) {
      return el('button', { type: 'button', class: `pl-recbtn st-recbtn ${cls}`.trim(), dataset: { act }, 'aria-label': label, title: label, disabled, onclick }, icon(name));
    }
    function paintTransport() {
      const ph = session ? session.phase : { kind: 'idle' };
      const all = slots();
      const i = all.findIndex(s => same(s, current()));
      const hearing = !!(ss.listen && ss.listen.playing);
      const center = ph.kind === 'listening' ? round('stop', 'stop', 'stop', 'Stop', () => session.stopListening())
        : ph.kind === 'cue' ? round('cancel', 'ink', 'stop', 'Cancel', () => session.cancel())
          : round('record', '', 'record', 'Record this cue', () => recordCue(), !current() || ph.kind === 'roomTone');
      transport.replaceChildren(
        el('button', { type: 'button', class: 'icon-btn', dataset: { act: 'prev' }, 'aria-label': 'Previous cue', title: 'Previous cue',
                       disabled: busy() || i <= 0, onclick: () => move(-1) }, icon('prev')),
        center,
        el('button', { type: 'button', class: 'icon-btn', dataset: { act: 'next' }, 'aria-label': 'Next cue', title: 'Next cue',
                       disabled: busy() || i < 0 || i + 1 >= all.length, onclick: () => move(1) }, icon('next')),
        el('button', { type: 'button', class: 'icon-btn st-hear', dataset: { act: 'listen' }, 'aria-label': hearing ? 'Stop' : 'Listen from here',
                       title: hearing ? 'Stop' : 'Listen from here', 'aria-pressed': hearing ? 'true' : 'false', disabled: !hearing && busy(),
                       onclick: () => listen() }, icon(hearing ? 'stop' : 'play')));
    }

    function move(delta) {
      if (busy()) return false;
      const all = slots();
      const i = all.findIndex(s => same(s, current()));
      const to = all[Math.max(0, Math.min(all.length - 1, i + delta))];
      if (!to || same(to, current())) return false;
      setCur(to);
      return true;
    }

    /** The round control: a performed cue on the current slot, a take like any line (§3.1 item 6). */
    async function recordCue() {
      quiet();
      const s = ensureSession();
      if (!s.started) { ss.gate = true; paint(); return; }
      if (s.isBusy()) return;
      const v = current();
      if (!v) return;
      const sid = ensureCur();
      const t = await s.recordCue(v.line, (p, take) => S.addPerformed(p, script, sid, take));
      if (t) {
        const slot = slots().find(x => x.id === sid);
        const x = slot && slot.sounds.find(y => y.src && y.src.take === t.id);
        if (x) ss.sel = x.id;
      }
      paint();
    }

    /* ---- Listening: Listen from here, Hear it in place ---- */

    function quiet() {
      if (ss.listen && ss.listen.playing) ss.listen.stop();
      if (ss.audition) { ss.audition.stop(); ss.audition = null; }
    }
    function listen(range = false) {
      if (ss.listen && ss.listen.playing) { ss.listen.stop(); return; }
      if (busy()) return;
      quiet();
      const cur = current();
      if (typeof Player !== 'undefined' && Player.pause) Player.pause();
      const p = prod();
      api.refollow();
      const lt = ListenThrough.create({
        production: p, script, store, audio: LiveAudio.create({ muted: muted() }),
        voice: StandInVoice.create({ muted: muted(), cast: api.cast }), cues: liveCues(store, p, script),
        onChange: (x) => { const e = x.playing ? x.current() : null; api.follow(e ? e.lineID : null); paintTransport(); paintBoardListen(); },
      });
      const lineID = cur ? cur.line : script.lines[0].id;
      if (range) {
        const r = S.inPlace(script, lt.plan, lineID);
        lt.index = r.from;
        lt.until = r.to;
      } else {
        const k = script.lines.findIndex(l => l.id === lineID);
        lt.index = Math.max(0, lt.plan.findIndex(e => script.lines.findIndex(l => l.id === e.lineID) >= k));
      }
      ss.listen = lt;
      lt.play();
    }

    async function audition(src, key) {
      if (ss.audition && ss.audition.key === key) { ss.audition.stop(); ss.audition = null; paintBoard(); return; }
      if (busy()) return;
      quiet();
      if (P.warm) P.warm();
      if (typeof Player !== 'undefined' && Player.pause) Player.pause();
      const data = await sounds.samplesOf(src, prod(), store);
      if (!data) return;
      const d = sounds.describe(src, prod());
      const h = await P.play(data, { loudness: (d.cue && d.cue.lufs) ?? (d.own && d.own.loudness) ?? null, peak: (d.cue && d.cue.peak) || (d.own && d.own.peak) || 0,
                                     lane: d.kind === 'music' ? 'music' : 'effects' });
      h.key = key;
      ss.audition = h;
      paintBoard();
      h.done.then(() => { if (ss.audition === h) { ss.audition = null; paintBoard(); } });
    }

    /* ---- The board ---- */

    function openBoard() {
      if (ss.wide) { panel.scrollIntoView({ block: 'nearest' }); return; }
      if (!sheet.open) sheet.showModal();
    }

    const search = el('input', { type: 'search', class: 'field-input sb-q', 'aria-label': 'Search sounds', placeholder: 'Search sounds', enterkeyhint: 'search', autocomplete: 'off' });
    search.addEventListener('input', () => { ss.q = search.value; ss.typed = true; paintResults(); });
    const results = el('div', { class: 'sb-results' });
    const chipsRow = el('div', { class: 'segmented segmented-scroll sb-chips', role: 'group', 'aria-label': 'Categories' });
    const listenBtn = el('button', { type: 'button', class: 'btn btn-way sb-inplace', dataset: { act: 'in-place' }, onclick: () => listen(true) });
    function paintBoardListen() {
      const on = !!(ss.listen && ss.listen.playing);
      listenBtn.replaceChildren(icon(on ? 'stop' : 'play', 'i-inline'), on ? 'Stop' : 'Hear it in place');
    }

    function slotHead(slot) {
      const all = slots();
      const i = all.findIndex(s => same(s, slot));
      const ln = script.lines.find(l => l.id === slot.line);
      const who = ln && ln.kind === 'speech' ? ln.role : '';
      const head = el('div', { class: 'sb-head' },
        el('span', { class: 'st-h sb-cuenum tabular' }, `Cue ${num.format(i + 1)} of ${num.format(all.length)}${who ? ` · ${who}` : ''}`),
        el('button', { type: 'button', class: 'btn btn-way sb-done', onclick: () => sheet.close() }, 'Done'));
      const words = slot.text
        ? el('p', { class: 'sb-words' }, el('span', { class: 'rd-sfx-mark' }, icon('speaker')), el('span', { class: 'rd-sfx-text' }, slot.text))
        : el('p', { class: 'sb-words sb-line' }, ln ? C.spokenText(ln) : '');
      const silent = !slot.sounds.length
        ? el('button', { type: 'button', class: 'btn sb-silent', 'aria-pressed': slot.silent ? 'true' : 'false', onclick: () => {
          const sid = ensureCur();
          apply(p => S.setSilent(p, sid, !slot.silent));
        } }, slot.silent ? 'Left silent' : 'Leave silent') : null;
      return el('section', { class: 'st-sec sb-slot' }, head, words, silent);
    }

    function soundRow(slot, x) {
      const d = sounds.describe(x.src, prod());
      const on = x.id === ss.sel;
      const key = `s:${x.id}`;
      const playing = ss.audition && ss.audition.key === key;
      const meta = d.missing === 'own' ? 'On another device' : `${S.clock(d.ms)} · ${S.placeLine(x, x.at === 'bed' ? `line ${lineLabel(script, x.until || slot.line).n}` : null)}`;
      return el('li', { class: `sb-row sb-in${on ? ' on' : ''}` },
        el('button', { type: 'button', class: 'pl-play-dot', 'aria-label': playing ? 'Stop' : `Play ${d.title}`, disabled: !!d.missing, onclick: () => audition(x.src, key) }, icon(playing ? 'stop' : 'play')),
        el('button', { type: 'button', class: 'sb-row-t', 'aria-pressed': on ? 'true' : 'false', onclick: () => { ss.sel = x.id; paintBoard(); paintDock(); } },
          el('span', { class: 'body-strong' }, d.title), el('span', { class: 'caption st-muted tabular' }, meta)),
        el('button', { type: 'button', class: 'btn btn-way sb-remove', onclick: () => {
          quiet();
          apply(p => S.removeSound(p, slot.id, x.id));
          const left = current();
          ss.sel = left && left.sounds.length ? left.sounds[0].id : null;
          paint();
        } }, 'Remove'));
    }

    function controls(slot, x) {
      const set = (patch) => apply(p => S.updateSound(p, slot.id, x.id, patch));
      const box = el('div', { class: 'sb-ctl' });
      box.append(el('div', { class: 'pl-mode sb-place', role: 'radiogroup', 'aria-label': 'Placement' },
        S.PLACEMENTS.map(m => el('label', { class: x.at === m ? 'on' : '' },
          el('input', { type: 'radio', name: `sb-at-${x.id}`, value: m, checked: x.at === m, onchange: () => set({ at: m }) }), S.PLACEMENT_LABEL[m]))));
      if (x.at === 'bed') {
        box.append(el('div', { class: 'sb-set' }, el('span', { class: 'body' }, 'Until'),
          el('button', { type: 'button', class: 'sb-until', onclick: () => { ss.picking = { slot: slot.id, sound: x.id }; sheet.close(); paint(); } },
            el('span', { class: 'tabular' }, lineLabel(script, x.until || slot.line).text), icon('chev'))));
      } else {
        const sec = `${x.startMs < 0 ? '−' : '+'}${(Math.abs(x.startMs) / 1000).toFixed(1)} s`;
        box.append(el('div', { class: 'sb-set' }, el('span', { class: 'body' }, 'Start'),
          el('span', { class: 'sb-step' }, el('output', { class: 'tabular' }, sec),
            el('button', { type: 'button', class: 'btn sb-pm', 'aria-label': 'Earlier by 0.1 second', disabled: x.startMs <= C.SOUND_DEFAULTS.startMinMs, onclick: () => set({ startMs: x.startMs - S.START_STEP_MS }) }, '−'),
            el('button', { type: 'button', class: 'btn sb-pm', 'aria-label': 'Later by 0.1 second', onclick: () => set({ startMs: x.startMs + S.START_STEP_MS }) }, '+'))));
      }
      const lane = x.at === 'bed' || sounds.describe(x.src, prod()).kind === 'music' ? 'music' : 'effects';
      const laneDb = (((prod().sound || {}).lanes || {})[lane] || {}).duckDb ?? (lane === 'music' ? C.SOUND_DEFAULTS.musicDuckDb : C.SOUND_DEFAULTS.effectsDuckDb);
      const duck = typeof x.duckDb === 'number' ? x.duckDb : laneDb;
      const dB = (v) => (v === 0 ? 'Off' : `${v < 0 ? '−' : '+'}${Math.abs(v)} dB`);
      const details = el('details', { class: 'sb-more' }, el('summary', { class: 'sb-set' }, el('span', { class: 'body' }, 'Level and fades'),
        el('span', { class: 'caption st-muted' }, `Under voices ${dB(duck)}`)));
      const fades = (v, list) => list.map(ms => el('option', { value: String(ms), selected: ms === v }, ms ? `${ms / 1000} s` : 'None'));
      const level = el('input', { type: 'range', min: String(C.SOUND_DEFAULTS.gainMinDb), max: String(C.SOUND_DEFAULTS.gainMaxDb), step: '1', value: String(x.gainDb), 'aria-label': 'Level',
                                  onchange: (e) => set({ gainDb: Number(e.target.value) }) });
      details.append(...[
        el('label', { class: 'sb-set' }, el('span', { class: 'body' }, 'Level'), el('span', { class: 'sb-level' }, level, el('output', { class: 'tabular caption' }, dB(x.gainDb).replace('Off', '0 dB')))),
        el('label', { class: 'sb-set' }, el('span', { class: 'body' }, 'Fade in'), el('select', { class: 'field-input sb-sel', onchange: (e) => set({ fadeInMs: Number(e.target.value) }) },
          fades(x.fadeInMs, x.at === 'bed' ? [...new Set([...S.FADES_MS, 1500])].sort((a, b) => a - b) : S.FADES_MS))),
        el('label', { class: 'sb-set' }, el('span', { class: 'body' }, 'Fade out'), el('select', { class: 'field-input sb-sel', onchange: (e) => set({ fadeOutMs: Number(e.target.value) }) }, fades(x.fadeOutMs, S.FADES_MS))),
        x.at === 'under' ? el('label', { class: 'sb-set' }, el('span', { class: 'body' }, 'Length'), el('select', { class: 'field-input sb-sel', onchange: (e) => set({ loop: e.target.value === 'loop' }) },
          el('option', { value: 'whole', selected: !x.loop }, 'Whole'), el('option', { value: 'loop', selected: !!x.loop }, 'Loop to the end of the line'))) : null,
        el('label', { class: 'sb-set' }, el('span', { class: 'body' }, 'Under voices'), el('select', { class: 'field-input sb-sel', onchange: (e) => set({ duckDb: e.target.value === '' ? null : Number(e.target.value) }) },
          DUCKS.map(v => el('option', { value: v === null ? '' : String(v), selected: v === null ? x.duckDb === null : x.duckDb === v }, v === null ? `As the lane (${dB(laneDb)})` : dB(v)))))].filter(Boolean));
      box.append(details);
      return box;
    }

    function cueSection(slot) {
      const sec = el('section', { class: 'st-sec sb-cue', 'aria-label': 'In this cue' }, el('h3', { class: 'st-h' }, 'In this cue'));
      if (!slot.sounds.length) return null;
      sec.append(el('ul', { class: 'sb-list-rows' }, slot.sounds.map(x => soundRow(slot, x))));
      const x = slot.sounds.find(y => y.id === ss.sel) || slot.sounds[0];
      if (x) sec.append(controls(slot, x));
      paintBoardListen();
      sec.append(listenBtn);
      return sec;
    }

    function inCue(src) {
      const slot = current();
      if (!slot) return false;
      return slot.sounds.some(x => (src.pack && x.src.pack && x.src.cue === src.cue) || (src.own && x.src.own === src.own));
    }
    function add(src, meta) {
      quiet();
      const sid = ensureCur();
      if (!sid) return;
      const anchor = C.usableTake(prod(), current().line);
      let newID = null;
      apply(p => { const r = S.addSound(p, script, sid, src, { kind: meta.kind, take: anchor }); newID = r.id; return r.production; });
      if (newID) { ss.sel = newID; paint(); }
    }

    function packCats() { return sounds.pack.status === 'ready' ? sounds.pack.manifest.categories : []; }
    function paintChips() {
      const cats = [...packCats().map(c => ({ id: c.id, title: c.title })), { id: 'mine', title: 'Mine' }];
      chipsRow.replaceChildren(...cats.map(c => el('button', { type: 'button', 'aria-pressed': String(ss.cat === c.id), onclick: () => {
        ss.cat = ss.cat === c.id && packCats().length ? null : c.id;
        ss.catChosen = true;
        paintChips();
        paintResults();
      } }, c.title)));
    }

    function catHeader(cat) {
      const cs = sounds.categoryState(cat.id);
      const head = el('div', { class: 'sb-cat' }, el('span', { class: 'st-h' }, `${cat.title} · ${S.megabytes(cat.bytes)}`));
      const offline = typeof navigator !== 'undefined' && navigator.onLine === false;
      if (cs.state === 'here') head.append(el('span', { class: 'caption sb-here' }, icon('check', 'i-inline'), 'Downloaded'));
      else if (cs.state === 'loading') head.append(el('span', { class: 'caption tabular sb-loading', role: 'status' }, el('span', { class: 'sb-ring-p', style: `--p: ${Math.round(cs.done * 100)}` }), `${Math.round(cs.done * 100)}%`));
      else if (offline) head.append(el('span', { class: 'caption st-muted' }, 'Offline'));
      else {
        if (cs.state === 'failed') head.append(el('span', { class: 'caption refusal' }, 'Did not download.'));
        head.append(el('button', { type: 'button', class: 'btn btn-way sb-dl', onclick: () => sounds.download(cat.id) }, icon('down', 'i-inline'), cs.state === 'failed' ? 'Try again' : 'Download'));
      }
      return head;
    }

    function cueRow(cue) {
      const here = sounds.isHere(cue);
      const key = `c:${cue.id}`;
      const playing = ss.audition && ss.audition.key === key;
      const has = inCue({ pack: true, cue: cue.id });
      const row = el('li', { class: `sb-row${here ? '' : ' sb-dim'}` },
        el('button', { type: 'button', class: 'pl-play-dot', 'aria-label': playing ? 'Stop' : `Play ${cue.title}`, disabled: !here, onclick: () => audition({ pack: sounds.pack.manifest.pack, cue: cue.id }, key) },
          icon(here ? (playing ? 'stop' : 'play') : 'down')),
        el('button', { type: 'button', class: 'sb-row-t', 'aria-expanded': ss.open === cue.id ? 'true' : 'false', onclick: () => { ss.open = ss.open === cue.id ? null : cue.id; paintResults(); } },
          el('span', { class: 'body-strong' }, cue.title), el('span', { class: 'caption st-muted tabular' }, S.cueLine(cue))),
        has ? el('span', { class: 'btn sb-add on' }, icon('check', 'i-inline'), 'In cue')
          : el('button', { type: 'button', class: 'btn sb-add', disabled: !current(), onclick: () => add({ pack: sounds.pack.manifest.pack, cue: cue.id }, cue) }, icon('plus', 'i-inline'), 'Add'));
      if (ss.open !== cue.id) return row;
      const link = (href, text) => el('a', { href, target: '_blank', rel: 'noopener' }, text);
      return [row, el('li', { class: 'sb-record caption' },
        el('span', {}, 'Source: ', link(cue.source.page, cue.source.name), cue.source.maker ? ` · ${cue.source.maker}` : ''),
        el('span', {}, 'License: ', cue.license.url ? link(cue.license.url, cue.license.id) : cue.license.id, ' · ', link(cue.license.evidence, 'Evidence'), ` · checked ${cue.license.checked}`))];
    }

    function mineRow(row) {
      const key = `o:${row.id}`;
      const playing = ss.audition && ss.audition.key === key;
      const has = inCue({ own: row.id });
      return el('li', { class: 'sb-row' },
        el('button', { type: 'button', class: 'pl-play-dot', 'aria-label': playing ? 'Stop' : `Play ${row.name}`, onclick: () => audition({ own: row.id }, key) }, icon(playing ? 'stop' : 'play')),
        el('span', { class: 'sb-row-t' }, el('span', { class: 'body-strong' }, row.name), el('span', { class: 'caption st-muted tabular' }, `${S.clock((row.frames / row.sampleRate) * 1000)} · Mine`)),
        has ? el('span', { class: 'btn sb-add on' }, icon('check', 'i-inline'), 'In cue')
          : el('button', { type: 'button', class: 'btn sb-add', disabled: !current(), onclick: () => add({ own: row.id, name: row.name }, { kind: 'effect' }) }, icon('plus', 'i-inline'), 'Add'),
        el('button', { type: 'button', class: 'icon-btn sb-del', 'aria-label': `Delete ${row.name}`, title: `Delete ${row.name}`, onclick: async () => {
          // eslint-disable-next-line no-alert
          if (!confirm(`Delete ${row.name} from this device?`)) return;
          await sounds.removeOwn(row.id);
        } }, icon('trash')));
    }

    /* Own sounds: Record a sound (no cue plays, so no headphones gate) and Bring a file. */
    const fileInput = el('input', { type: 'file', accept: 'audio/*', hidden: true, onchange: () => bring(fileInput.files && fileInput.files[0]) });
    async function bring(file) {
      fileInput.value = '';
      if (!file) return;
      ss.err = '';
      if (file.size > S.OWN_FILE_MAX_BYTES) { ss.mineErr = 'This file is larger than 50 MB.'; paintResults(); return; }
      try {
        const got = await SoundStore.decodeFile(await file.arrayBuffer());
        if (got.samples.length / got.sampleRate > S.OWN_FILE_MAX_S) { ss.mineErr = 'This file is longer than 10 minutes.'; paintResults(); return; }
        ss.mineErr = '';
        await sounds.saveOwn({ name: file.name.replace(/\.[^.]+$/, ''), samples: got.samples, sampleRate: got.sampleRate, from: 'file' });
        ss.cat = 'mine';
      } catch (e) {
        console.error('own sound', e);
        ss.mineErr = 'This file could not be read as audio.';
      }
      paint();
    }
    async function recordOwn(name = '') {
      if (ss.rec) { ss.rec.stop(); return; }
      if (busy()) return;
      quiet();
      const audio = LiveAudio.create({ muted: muted() });
      const r = { name, t0: 0, timer: null, stop: null };
      ss.rec = r;
      try { await audio.start(); } catch (e) {
        audio.stop();
        ss.rec = null;
        ss.mineErr = e && e.name === 'NotAllowedError' ? 'Ear Drama needs the microphone to record a sound. Allow it for this site in the browser\'s settings.' : 'No microphone found.';
        paintResults();
        return;
      }
      audio.beginCapture(() => {});
      r.t0 = Date.now();
      const done = new Promise((resolve) => { r.stop = resolve; });
      r.timer = setInterval(() => { if (Date.now() - r.t0 >= S.OWN_RECORD_MAX_S * 1000) r.stop(); else paintResults(); }, 500);
      paintResults();
      await done;
      clearInterval(r.timer);
      const cap = audio.endCapture();
      const at = await audio.toTakeRate(cap);
      audio.stop();
      ss.rec = null;
      ss.mineErr = '';
      if (at.samples.length) {
        const n = (await sounds.mine()).length + 1;
        await sounds.saveOwn({ name: r.name || `My sound ${n}`, samples: at.samples, sampleRate: at.sampleRate, from: 'recorded' });
      }
      ss.cat = 'mine';
      paint();
    }
    function mineTools() {
      if (ss.rec) {
        const sec = Math.floor((Date.now() - ss.rec.t0) / 1000);
        return el('div', { class: 'sb-mine-acts' }, el('span', { class: 'st-rec tabular' }, el('span', { class: 'dot' }), `Recording 0:${String(sec).padStart(2, '0')}`),
          el('button', { type: 'button', class: 'btn', dataset: { act: 'own-stop' }, onclick: () => ss.rec.stop() }, icon('stop', 'i-inline'), 'Stop'));
      }
      return el('div', { class: 'sb-mine-acts' },
        el('button', { type: 'button', class: 'btn btn-again sb-rec-own', onclick: () => recordOwn() }, icon('mic', 'i-inline'), 'Record a sound'),
        el('button', { type: 'button', class: 'btn sb-bring', onclick: () => fileInput.click() }, icon('file', 'i-inline'), 'Bring a file'),
        fileInput);
    }

    function skeleton() {
      return el('ul', { class: 'sb-list-rows sb-skel', 'aria-busy': 'true', 'aria-label': 'Loading' },
        [0, 1, 2].map(() => el('li', { class: 'sb-row' }, el('span', { class: 'sb-skel-dot' }), el('span', { class: 'sb-skel-t' }, el('i'), el('i')))));
    }

    function paintResults() {
      if (ss.detached) return;
      const q = (ss.q ?? search.value).trim();
      if (search.value !== (ss.q ?? search.value)) search.value = ss.q;
      const out = [];
      const pk = sounds.pack;
      const mine = sounds.mineNow();
      if (pk.status === 'error') {
        out.push(el('div', { class: 'sb-state' }, el('p', { class: 'body' }, 'The sounds are not downloaded yet.'),
          el('button', { type: 'button', class: 'btn', onclick: () => { sounds.pack.status = 'none'; sounds.loadPack(); } }, 'Try again')));
      }
      if (ss.cat !== 'mine' && pk.status === 'loading') out.push(skeleton());
      if (ss.cat !== 'mine' && pk.status === 'ready') {
        const hits = S.search(pk.manifest.cues, q, ss.cat || null);
        for (const cat of pk.manifest.categories) {
          const rows = hits.filter(c => c.category === cat.id);
          if (!rows.length) continue;
          out.push(catHeader(cat), el('ul', { class: 'sb-list-rows' }, rows.flatMap(cueRow)));
        }
        const own = q ? S.searchMine(mine, q) : [];
        if (own.length && !ss.cat) out.push(el('div', { class: 'sb-cat' }, el('span', { class: 'st-h' }, 'Mine')), el('ul', { class: 'sb-list-rows' }, own.map(mineRow)));
        if (!hits.length && !own.length && q) {
          out.push(el('div', { class: 'sb-state' }, el('p', { class: 'body' }, `No sound called “${q}”.`),
            el('button', { type: 'button', class: 'btn btn-again', onclick: () => { ss.cat = 'mine'; ss.catChosen = true; paintChips(); recordOwn(q); } }, icon('mic', 'i-inline'), 'Record it')));
        }
      }
      if (ss.cat === 'mine') {
        const rows = q ? S.searchMine(mine, q) : mine;
        if (rows.length) out.push(el('ul', { class: 'sb-list-rows' }, rows.map(mineRow)));
        else if (q && mine.length) out.push(el('p', { class: 'body sb-state' }, `No sound called “${q}”.`));
        else out.push(el('p', { class: 'body sb-state' }, 'No sounds of your own yet.'));
        if (ss.mineErr) out.push(el('p', { class: 'caption refusal', role: 'alert' }, ss.mineErr));
        out.push(mineTools());
      }
      results.replaceChildren(...out);
    }

    function paintBoard() {
      if (ss.detached) return;
      const slot = current();
      const keepScroll = (ss.wide ? api.side : sheet).scrollTop;
      if (ss.q === null) {
        const cues = sounds.pack.status === 'ready' ? sounds.pack.manifest.cues : [];
        ss.q = slot ? S.seedQuery(slot.text, cues) : '';
        search.value = ss.q;
      }
      if (ss.cat === undefined) ss.cat = sounds.pack.status === 'none' || sounds.pack.status === 'error' ? 'mine' : null;
      paintChips();
      paintResults();
      const prodNow = prod();
      const m = S.summary(script, prodNow);
      panel.replaceChildren(...[
        el('div', { class: 'st-head' }, el('span', { class: 'st-part sb-part' }, 'Sound'), el('span', { class: 'caption tabular st-muted' }, `${num.format(m.chosen + m.added)} of ${num.format(slots().length)}`)),
        slot ? slotHead(slot) : el('p', { class: 'body st-muted' }, 'Right-click or hold a line to add a sound.'),
        slot ? cueSection(slot) : null,
        el('section', { class: 'st-sec sb-find' }, search, chipsRow, results),
        el('section', { class: 'st-sec st-acts' },
          el('button', { type: 'button', class: 'btn', disabled: busy(), onclick: () => done() }, 'Done with this part'),
          el('p', { class: 'caption refusal st-done-err', role: 'alert' })),
      ].filter(Boolean));
      (ss.wide ? api.side : sheet).scrollTop = keepScroll;
    }

    function done() {
      const back = `?production=${encodeURIComponent(id)}`;
      if (!store.share(id)) {
        try { store.update(C.finish(prod(), script, C.SOUND)); } catch (err) {
          const r = panel.querySelector('.st-done-err');
          if (r) r.textContent = err instanceof C.Refusal ? C.refusalText(err) : String(err.message || err);
          return;
        }
      }
      sheet.close();
      if (api.navigate) api.navigate(back, true); else location.href = back;
    }

    /* ---- Add a sound here: a right click or a long press on any line (§3.1 item 3) ---- */

    function closeMenu() { if (ss.menu) { ss.menu.remove(); ss.menu = null; } }
    function openMenu(lineNode, x, y) {
      closeMenu();
      const lid = lineNode.dataset.line;
      const r = api.root.getBoundingClientRect();
      const m = el('div', { class: 'sb-menu', role: 'menu', style: `left: ${Math.max(8, Math.min(x - r.left, r.width - 200))}px; top: ${Math.max(8, y - r.top)}px` },
        el('button', { type: 'button', role: 'menuitem', class: 'sb-menu-item', onclick: () => {
          closeMenu();
          const { production, id: sid } = S.addSlot(prod(), lid);
          store.update(production);
          const v = slots().find(s => s.id === sid);
          if (v) setCur(v, { reveal: false });
          openBoard();
        } }, icon('plus', 'i-inline'), 'Add a sound here'));
      api.root.append(m);
      ss.menu = m;
      m.querySelector('button').focus({ preventScroll: true });
    }
    const onContext = (e) => {
      const ln = e.target.closest && e.target.closest('.rd-line');
      if (!ln || ss.detached) return;
      e.preventDefault();
      openMenu(ln, e.clientX, e.clientY);
    };
    let press = null;
    const onDown = (e) => {
      if (e.pointerType !== 'touch') return;
      const ln = e.target.closest && e.target.closest('.rd-line');
      if (!ln) return;
      const x = e.clientX, y = e.clientY;
      press = { x, y, t: setTimeout(() => { press = null; openMenu(ln, x, y); }, 550) };
    };
    const onMove = (e) => { if (press && Math.hypot(e.clientX - press.x, e.clientY - press.y) > 10) { clearTimeout(press.t); press = null; } };
    const onUp = () => { if (press) { clearTimeout(press.t); press = null; } };
    const onDocDown = (e) => { if (ss.menu && !ss.menu.contains(e.target)) closeMenu(); };
    api.root.addEventListener('contextmenu', onContext);
    api.root.addEventListener('pointerdown', onDown);
    api.root.addEventListener('pointermove', onMove);
    api.root.addEventListener('pointerup', onUp);
    api.root.addEventListener('pointercancel', onUp);
    document.addEventListener('pointerdown', onDocDown, true);

    /* ---- Wide or narrow ---- */

    function place() {
      const wide = api.root.clientWidth >= WIDE;
      if (wide === ss.wide && panel.isConnected) return;
      ss.wide = wide;
      api.root.dataset.studio = wide ? 'wide' : 'narrow';
      if (wide) { if (sheet.open) sheet.close(); api.side.hidden = false; api.side.replaceChildren(panel); }
      else { api.side.hidden = true; api.side.replaceChildren(); sheet.append(panel); }
    }
    const ro = new ResizeObserver(() => place());
    ro.observe(api.root);

    function paint() {
      if (ss.detached) return;
      const had = document.activeElement && document.activeElement.dataset ? document.activeElement.dataset.act : null;
      paintPage();
      paintDock();
      paintTransport();
      paintBoard();
      if (had) { const b = api.root.querySelector(`[data-act="${had}"]:not(:disabled)`); if (b) b.focus({ preventScroll: true }); }
    }
    sounds.onChange = () => { if (!ss.detached) { paintBoard(); paintPage(); } };

    /* ---- Taps and keys ---- */

    const ctl = {
      tap(target, lineNode) {
        if (ss.picking && lineNode) {
          const lid = lineNode.dataset.line;
          const slot = slots().find(s => s.id === ss.picking.slot);
          const at = (x) => script.lines.findIndex(l => l.id === x);
          if (slot && at(lid) >= at(slot.line)) {
            const pick = ss.picking;
            ss.picking = null;
            apply(p => S.updateSound(p, pick.slot, pick.sound, { until: lid }));
            // Wide, the board is beside the page; narrow, the page stays in view with the bed's rule drawn.
            if (ss.wide) openBoard();
          }
          return true;
        }
        const ring = target.closest && target.closest('.sb-ring');
        const host = target.closest && target.closest('.sb-host');
        if (!host && !ring) return false;
        const k = ring ? Number(ring.dataset.slot) : null;
        const all = slots();
        let slot = k !== null ? all[k] : null;
        if (!slot && lineNode) {
          const pieceEl = host.closest('.rd-sfx');
          const piece = pieceEl ? Number(pieceEl.dataset.piece) : null;
          slot = all.find(s => s.line === lineNode.dataset.line && (host.classList.contains('sb-added') ? s.added : !s.added && (s.piece ?? null) === piece));
        }
        if (!slot) return false;
        if (!same(slot, current())) setCur(slot, { reveal: false });
        if (ring || !ss.wide) openBoard();
        return true;
      },
      detach() {
        ss.detached = true;
        clearInterval(ss.clock);
        if (ss.rec) ss.rec.stop();
        window.removeEventListener('keydown', onKey, true);
        document.removeEventListener('pointerdown', onDocDown, true);
        api.root.removeEventListener('contextmenu', onContext);
        ro.disconnect();
        closeMenu();
        if (ss.listen) ss.listen.end();
        P.stopAll();
        if (session) session.end();
        if (sheet.open) sheet.close();
        sounds.onChange = null;
        const n = S.prune(prod());
        if (n !== prod()) store.update(n);
        const held = () => typeof location !== 'undefined' && new URLSearchParams(location.search).get('production') === id;
        store.discardIfAbandoned(id, held).catch((e) => console.error(e));
      },
      get session() { return session; },
    };

    function onKey(e) {
      if (ss.detached || e.metaKey || e.ctrlKey || e.altKey || !api.root.isConnected) return;
      if (e.key === 'Escape' && (ss.menu || ss.picking)) { closeMenu(); ss.picking = null; paint(); e.preventDefault(); return; }
      if (document.querySelector('dialog[open]:not(.st-sheet)')) return;
      const t = e.target;
      if (t && t.closest && t.closest('input:not([type="radio"]):not([type="checkbox"]):not([type="range"]), select, textarea, [contenteditable="true"]')) return;
      const k = e.key;
      if (k === ' ') { if (session && session.phase.kind === 'listening') session.stopListening(); else if (session && session.phase.kind === 'cue') session.cancel(); else recordCue(); }
      else if (k === 'j' || k === 'J') move(1);
      else if (k === 'k' || k === 'K') move(-1);
      else if (k === 's' || k === 'S') openBoard();
      else if (k === 'l' || k === 'L') listen(true);
      else return;
      e.preventDefault();
      e.stopPropagation();
    }
    window.addEventListener('keydown', onKey, true);

    place();
    paint();
    Promise.all([sounds.mine(), sounds.loadPack()]).then(() => {
      if (ss.detached) return;
      if (!ss.typed) ss.q = null;
      if (!ss.catChosen) ss.cat = undefined;
      paint();
    }).catch((e) => console.error(e));
    if (current()) setTimeout(() => { if (!ss.detached && current()) api.go(current().line); }, 0);
    return ctl;
  }

  return { attach, soundsFor, liveCues, mixOptions, missingLine, lineLabel };
})();
