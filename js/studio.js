/**
 * The studio inside the reader (WEB-DESIGN §4.16 item 14, PLAYS-DESIGN §2.9; Decision 076 S3). The
 * owner, 2026-11-14: "The recording experience should allow you to read the script as you would any
 * book or script while you record your lines."
 *
 * The reader keeps the page; this file draws what recording adds to it: each of my lines' take state,
 * the current line, the dock (the mode, one status row, the level meter), the transport in the bottom
 * bar, and the panel (the line's takes, the cast, Listen through from here, Delete unused takes, Done
 * with this part), beside the script from the spread width and in a sheet below it. The engine is the
 * shipped RecordingSession; what moves where is StudioCore (js/studio-core.js, tested without a DOM).
 */
const Studio = (() => {
  'use strict';
  const C = PlaysCore;
  const SC = StudioCore;
  const WIDE = ReaderCore.SPREAD_MIN;
  const MODE_LABEL = { run: 'Run through', lines: 'Line by line', step: 'Step' };
  const ICON = {
    record: 'M12 5a7 7 0 1 0 0 14 7 7 0 0 0 0-14z',
    stop: 'M7 7h10v10H7z',
    pause: 'M7 5h4v14H7zm6 0h4v14h-4z',
    play: 'M8 5v14l11-7z',
    wave: 'M7 9h2v6H7zm4-3h2v12h-2zm4 3h2v6h-2z',
    prev: 'M15.4 7.4 14 6l-6 6 6 6 1.4-1.4-4.6-4.6z',
    next: 'M8.6 16.6 10 18l6-6-6-6-1.4 1.4 4.6 4.6z',
    check: 'M9 16.2 4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4z',
    warn: 'M1 21h22L12 2zm12-3h-2v-2h2zm0-4h-2v-4h2z',
    studio: 'M3 5h18v2H3zm0 6h12v2H3zm0 6h18v2H3zm15-7.5 4 2.5-4 2.5z',
    trash: 'M6 19a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z',
    headphones: 'M12 3a9 9 0 0 0-9 9v6a3 3 0 0 0 3 3h2v-8H5v-1a7 7 0 0 1 14 0v1h-3v8h2a3 3 0 0 0 3-3v-6a9 9 0 0 0-9-9z',
  };
  const num = new Intl.NumberFormat('en-US');
  const muted = () => typeof location !== 'undefined' && new URLSearchParams(location.search).get('mute') === '1';
  const secs = (t) => `${(t.frames / t.sampleRate).toFixed(1)} s`;

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

  /** The store PlaysUI keeps, so the cast sheet and the studio read one record. */
  const openStore = () => PlaysUI.openStore();

  /** Signed out, a second production asks for an account at the press (Decision 079, PLAYS-DESIGN §2.3). */
  const SECOND = 'A second production needs an account.';
  function accountNeeded() {
    const e = new Error(SECOND);
    e.account = true;
    return e;
  }
  /** True when the press stopped for the account: the sign-in sheet opens with the reason. */
  function askAccount(e) {
    if (!e || !e.account) return false;
    if (typeof AccountUI !== 'undefined') AccountUI.openSheet({ reason: e.message });
    return true;
  }

  /**
   * The reader's Record (§2.9 rule 1): the production to record this part in, taking the part or
   * making the production when it must. Resolves to the production's id; rejects with `account` set
   * when making one would be a signed-out person's second.
   */
  async function begin(script, part) {
    const store = await openStore();
    const whole = Array.isArray(script.lines) ? script : await API.playScript(script.id);
    const pick = SC.productionFor(store.productions, (id) => !!store.share(id), whole, part);
    if (pick.make && C.secondProductionNeedsAccount(store.productions, API.account.signedIn())) throw accountNeeded();
    let p = pick.make ? await store.create(whole) : store.production(pick.id);
    if (pick.make && navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(() => {});
    if (pick.make || pick.take) {
      p = C.take(store.production(p.id), whole, part, '');
      await store.save(p);
    }
    return p.id;
  }

  /** Attaches the studio to an open reader (`api`, js/reader.js studioApi) for `production` and `part`. */
  function attach(api, { production: id, part, store, line = null }) {
    const { el, script } = api;
    const p = store.production(id);
    const hue = C.partHue(script, part) || 'none';
    let ready = false;
    const s = RecordingSession.create({
      production: p, script, part, store,
      audio: LiveAudio.create({ muted: muted() }),
      voice: StandInVoice.create({ muted: muted(), cast: api.cast }),
      announce: async () => { const live = document.getElementById('live'); if (live) live.textContent = 'Your line'; },
      onChange: () => { if (ready) paint(); },
    });
    if (typeof Store !== 'undefined') s.setMode(Store.recorderMode());
    const core = SC.create({ session: s, script, part, store, line: line || null });
    const ss = { headphones: false, clock: null, listen: null, preview: null, wide: false, detached: false };

    /* ---- The page: each of my lines' take state, the current line ---- */

    const badges = new Map();
    for (const lid of core.mine) {
      const node = api.line(lid);
      const sp = node && (node.querySelector(`.rd-sp[data-part="${CSS.escape(part)}"]`) || node.querySelector('.rd-sp'));
      const who = sp && sp.querySelector('.rd-who');
      // A stage direction has no name row: its take state sits at the line's end (B32 §2 item 2).
      const host = who || (node && !sp ? node : null);
      if (!host) continue;
      const b = el('button', { type: 'button', class: who ? 'rd-take' : 'rd-take rd-take-end', dataset: { line: lid } });
      if (who) host.append(b); else host.prepend(b);
      badges.set(lid, b);
    }
    function paintBadge(lid) {
      const b = badges.get(lid);
      if (!b) return;
      const st = core.lineState(lid);
      b.dataset.state = st.state;
      const n = st.takes;
      b.replaceChildren(...(st.state === 'flagged' ? [icon('warn')] : [el('span', { class: 'rd-take-dot' })]),
        n ? el('span', { class: 'rd-take-n tabular' }, String(n)) : '');
      b.setAttribute('aria-label', st.state === 'none' ? 'No take'
        : st.state === 'flagged' ? 'Re-take: the microphone heard the device voice'
          : `${n === 1 ? '1 take' : `${num.format(n)} takes`}, take ${st.chosen} chosen`);
    }
    // Every other part's line a device voice reads carries a dashed ring and the voice's name; a tap casts it (§2.9 rule 3a).
    const rings = [];
    for (const line of script.lines) {
      if (line.kind !== 'speech' || core.mine.includes(line.id)) continue;
      const node = api.line(line.id);
      if (!node) continue;
      for (const sp of node.querySelectorAll('.rd-sp')) {
        const pp = sp.dataset.part;
        const who = sp.querySelector('.rd-who');
        if (!who || pp === part || !C.isSpeaking(pp)) continue;
        const b = el('button', { type: 'button', class: 'rd-vc', dataset: { part: pp, line: line.id } });
        who.append(b);
        rings.push(b);
      }
    }
    const shortName = (n) => String(n || '').replace(/\s*\([^)]*\)\s*$/, '');
    function paintRings() {
      const said = new Map();
      for (const b of rings) {
        const pp = b.dataset.part;
        b.hidden = !!C.usableTake(s.production, b.dataset.line);
        if (b.hidden) continue;
        if (!said.has(pp)) said.set(pp, CastUI.describe(api.cast, pp));
        const d = said.get(pp);
        const text = d.r && d.r.read && !d.r.none ? shortName(d.text) : d.text;
        if (b.dataset.text === text) continue;
        b.dataset.text = text;
        b.replaceChildren(el('span', { class: 'rd-vc-ring' }, icon('wave')), el('span', { class: 'rd-vc-name' }, text));
        b.setAttribute('aria-label', `Device voice for ${C.partTitle(pp)}: ${d.label}`);
      }
    }
    function castPart(pp) {
      CastUI.picker({ script, cast: api.cast, voice: api.voice, part: pp, onChange: () => { paintRings(); castBox.paint(); } });
    }

    let marked = [];
    function paintLines() {
      for (const n of marked) n.classList.remove('rd-cur', 'rd-armed', 'rd-rec');
      marked = [];
      const ph = s.phase;
      const node = core.current ? api.line(core.current) : null;
      if (node) {
        const listening = ph.kind === 'listening' && ph.lineID === core.current;
        const armed = ph.kind === 'cue' && !s.run && C.cueLines(script, core.current, true).some(c => c.id === ph.lineID);
        node.classList.add(listening ? 'rd-rec' : armed ? 'rd-armed' : 'rd-cur');
        marked.push(node);
      }
      if (!['cue', 'listening'].includes(ph.kind)) api.follow(null);
    }

    /* ---- The dock: the mode, the status row, the level meter ---- */

    const dock = el('div', { class: 'st-dock', dataset: { hue } });
    const transport = el('div', { class: 'st-transport' });
    const sheetBtn = el('button', { type: 'button', class: 'icon-btn rd-icon st-open', 'aria-label': 'Studio', title: 'Studio',
                                    onclick: () => openPanel() }, icon('studio'));
    const panel = el('div', { class: 'st-panel', dataset: { hue } });
    const sheet = api.sheet('Studio', panel);
    sheet.classList.add('st-sheet');
    api.root.append(sheet);
    api.dock.hidden = false;
    api.dock.replaceChildren(dock);
    api.footer.insertBefore(transport, api.hideBtn);
    api.footer.insertBefore(sheetBtn, api.footer.firstChild);
    api.studioMode(true);

    function failure() {
      if (s.phase.kind !== 'failed') return null;
      const r = s.phase.reason;
      if (r === 'NotAllowedError' || r === 'SecurityError') return 'Ear Drama needs the microphone to record your part. Allow it for this site in the browser\'s settings.';
      if (r === 'NotFoundError' || r === 'OverconstrainedError') return 'No microphone found.';
      if (r === 'save') return 'This take was not saved.';
      return 'Recording did not start.';
    }

    /** The headphones, then Start recording (PLAYS-DESIGN §2.9 rule 9, §4.3), in place of the status row.
        No account is asked: a first take needs none (Decision 079). */
    function gate() {
      const box = el('div', { class: 'st-gate' });
      if (!LiveAudio.supported()) { box.append(el('p', { class: 'body' }, 'This browser cannot record.')); return box; }
      const start = el('button', { type: 'button', class: 'btn btn-record st-go', disabled: !ss.headphones,
                                   onclick: () => { if (typeof Player !== 'undefined' && Player.pause) Player.pause(); s.begin(); paint(); } },
        icon('record', 'i-inline'), 'Start recording');
      const check = el('input', { type: 'checkbox', id: 'st-headphones', checked: ss.headphones,
                                  onchange: () => { ss.headphones = check.checked; start.disabled = !check.checked; } });
      const failed = failure();
      box.append(...[
        el('div', { class: 'st-gate-h' }, icon('headphones', 'st-gate-icon'),
          el('span', {}, el('span', { class: 'body-strong' }, 'Headphones on'), el('span', { class: 'caption st-why' }, 'This browser cannot tell whether they are on.'))),
        el('div', { class: 'st-gate-go' }, el('label', { class: 'pl-check', for: 'st-headphones' }, check, el('span', { class: 'body-strong' }, 'My headphones are on')), start),
        failed ? el('p', { class: 'caption refusal', role: 'alert' }, failed) : null].filter(Boolean));
      return box;
    }

    function meter() {
      const bars = Array.from({ length: 40 }, () => el('i'));
      const m = el('div', { class: 'pl-meter st-meter', 'aria-hidden': 'true' }, bars);
      const draw = (levels) => {
        const shown = levels.slice(-40);
        bars.forEach((b, i) => { const v = shown[i - (40 - shown.length)]; b.style.height = `${Math.max(3, Math.round(22 * (v || 0)))}px`; });
      };
      s.onLevel = draw;
      draw(s.levels);
      return m;
    }

    function takesLabel(lid) {
      const st = core.lineState(lid);
      if (st.state === 'none') return 'No take';
      if (st.state === 'flagged') return 'Re-take';
      return `Take ${st.chosen} of ${num.format(st.takes)}`;
    }

    function status() {
      const ph = s.phase;
      const row = el('div', { class: 'st-status', role: 'status' });
      const failed = failure();
      if (ph.kind === 'listening') {
        row.classList.add('st-on');
        row.append(el('span', { class: 'st-rec tabular' }, el('span', { class: 'dot' }), 'Recording 0:00'), meter());
        return row;
      }
      if (ph.kind === 'cue') {
        const line = script.lines.find(l => l.id === ph.lineID);
        const lp = line ? C.linePart(line) : null;
        row.append(el('span', { class: 'st-who', dataset: { hue: C.partHue(script, lp) || 'none' } }, line ? (line.role || C.partTitle(lp)) : ''),
          el('span', { class: 'caption st-muted' }, ph.deviceVoice ? 'Device voice' : 'Take'));
        return row;
      }
      if (ph.kind === 'runReview') {
        const n = s.runTakes().length;
        row.append(el('span', { class: 'body-strong' }, `This run · ${n === 1 ? '1 take' : `${num.format(n)} takes`}`));
        return row;
      }
      const i = core.mine.indexOf(core.current);
      row.append(el('span', { class: 'tabular' }, `Line ${num.format(i + 1)} of ${num.format(core.mine.length)}`));
      // Run through's round control runs on from here; a line gone back to is re-taken alone (§2.9 rule 5).
      if (s.mode === 'run' && !s.run && core.lineState(core.current).state !== 'none') {
        row.append(el('button', { type: 'button', class: 'btn btn-again st-again-line', dataset: { act: 'again-line' }, disabled: s.isBusy(),
                                  onclick: () => { quiet(); core.again(); } }, el('span', { class: 'dot' }), 'Again'));
      }
      row.append(
        el('button', { type: 'button', class: 'st-takes-btn', 'aria-label': `${takesLabel(core.current)}: the takes`, onclick: () => openPanel() },
          el('span', { class: core.lineState(core.current).state === 'flagged' ? 'st-warn-t' : '' }, takesLabel(core.current))));
      if (failed) row.append(el('span', { class: 'caption refusal', role: 'alert' }, failed));
      return row;
    }

    function modes() {
      const locked = s.isBusy() || !!s.run;
      return el('div', { class: 'pl-mode st-mode', role: 'radiogroup', 'aria-label': 'Recording mode' },
        C.MODES.map(m => el('label', { class: s.mode === m ? 'on' : '' },
          el('input', { type: 'radio', name: 'st-mode', value: m, checked: s.mode === m, disabled: locked,
                        onchange: () => { if (s.setMode(m) && typeof Store !== 'undefined') Store.setRecorderMode(m); } }),
          MODE_LABEL[m])));
    }

    function paintDock() {
      clearInterval(ss.clock);
      const ph = s.phase;
      if (!s.started) { dock.replaceChildren(gate()); return; }
      if (ph.kind === 'roomTone') {
        dock.replaceChildren(el('div', { class: 'st-status', role: 'status' },
          el('span', { class: 'body-strong' }, 'Quiet, please. Recording the room.'), el('span', { class: 'st-count tabular' }, String(ph.secondsLeft))));
        return;
      }
      dock.replaceChildren(modes(), status());
      if (ph.kind === 'listening') {
        const t0 = Date.now();
        const out = dock.querySelector('.st-rec');
        ss.clock = setInterval(() => {
          const sec = Math.floor((Date.now() - t0) / 1000);
          if (out) out.lastChild.textContent = `Recording ${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}`;
        }, 500);
      }
    }

    /* ---- The transport: the bottom bar while the studio is attached ---- */

    function round(act, cls, name, label, onclick, disabled = false) {
      return el('button', { type: 'button', class: `pl-recbtn st-recbtn ${cls}`.trim(), dataset: { act }, 'aria-label': label, title: label, disabled, onclick }, icon(name));
    }
    function paintTransport() {
      const ph = s.phase;
      api.footer.classList.toggle('st-reviewing', (s.mode === 'step' && ph.kind === 'review') || ph.kind === 'runReview');
      if (!s.started || ph.kind === 'roomTone') { transport.replaceChildren(); return; }
      const busy = s.isBusy();
      if (s.mode === 'step' && ph.kind === 'review') {
        const t = C.chosenTake(s.production, core.current);
        transport.replaceChildren(
          el('button', { type: 'button', class: 'btn btn-again', dataset: { act: 'again' }, onclick: () => core.again() }, el('span', { class: 'dot' }), 'Again'),
          el('button', { type: 'button', class: 'btn btn-way', dataset: { act: 'with-cue' }, disabled: !t, onclick: () => s.playWithCue(t) }, icon('play', 'i-inline'), 'With cue'),
          el('button', { type: 'button', class: 'btn btn-primary', dataset: { act: 'keep' }, onclick: () => { core.keep(); revealCurrent(); } }, icon('check', 'i-inline'), 'Keep'));
        return;
      }
      if (ph.kind === 'runReview') {
        const n = s.runTakes().length;
        transport.replaceChildren(
          el('button', { type: 'button', class: 'btn btn-way', dataset: { act: 'discard' }, onclick: () => s.discardRun() }, 'Discard the run'),
          el('button', { type: 'button', class: 'btn btn-primary', dataset: { act: 'keep' }, onclick: () => core.keep() },
            icon('check', 'i-inline'), n === 1 ? 'Keep 1 take' : `Keep ${num.format(n)} takes`));
        return;
      }
      const listening = ph.kind === 'listening';
      let center;
      if (s.mode === 'run' && !s.run && (listening || ph.kind === 'cue')) {
        center = listening ? round('stop', 'stop', 'stop', 'Stop', () => s.stopListening()) : round('cancel', 'ink', 'stop', 'Cancel', () => s.cancel());
      } else if (s.mode === 'run') {
        center = !s.run ? round('record', '', 'record', 'From here', () => { api.refollow(); core.primary(); }, busy)
          : listening ? round('pause', 'stop', 'stop', 'Stop', () => s.pause())
            : round('pause', 'ink', 'pause', 'Pause', () => s.pause());
      } else {
        center = listening ? round('stop', 'stop', 'stop', 'Stop', () => s.stopListening())
          : ph.kind === 'cue' ? round('cancel', 'ink', 'stop', 'Cancel', () => s.cancel())
            : round('record', '', 'record', 'Record', () => core.primary(), busy);
      }
      const i = core.mine.indexOf(core.current);
      const locked = busy || !!s.run;
      const hearing = !!(ss.listen && ss.listen.playing);
      center.addEventListener('click', quiet, true);
      transport.replaceChildren(
        el('button', { type: 'button', class: 'icon-btn', dataset: { act: 'prev' }, 'aria-label': 'Previous line', title: 'Previous line',
                       disabled: locked || i <= 0, onclick: () => { core.move(-1); revealCurrent(); } }, icon('prev')),
        center,
        el('button', { type: 'button', class: 'icon-btn', dataset: { act: 'next' }, 'aria-label': 'Next line', title: 'Next line',
                       disabled: locked || i + 1 >= core.mine.length, onclick: () => { core.move(1); revealCurrent(); } }, icon('next')),
        el('button', { type: 'button', class: 'icon-btn st-hear', dataset: { act: 'listen' }, 'aria-label': hearing ? 'Stop' : 'Listen from here',
                       title: hearing ? 'Stop' : 'Listen from here', 'aria-pressed': hearing ? 'true' : 'false',
                       disabled: !hearing && locked, onclick: () => listenFromHere() }, icon(hearing ? 'stop' : 'play')));
    }
    /** Recording and listening never overlap: a record press stops the listen-through first. */
    function quiet() { if (ss.listen && ss.listen.playing) ss.listen.stop(); }

    /* ---- The panel: the line's takes, the run, the cast, Listen through, the rest ---- */

    /** A take heard on its own: through the session once it runs, else from the file, unmixed and unkept. */
    async function hear(t) {
      if (s.started) { s.playTake(t); return; }
      if (ss.preview) { ss.preview.pause(); URL.revokeObjectURL(ss.preview.src); }
      const bytes = await store.readTake(id, t.file);
      ss.preview = new Audio(URL.createObjectURL(new Blob([bytes], { type: 'audio/wav' })));
      ss.preview.muted = muted();
      if (typeof Player !== 'undefined' && Player.pause) Player.pause();
      ss.preview.play().catch(() => {});
    }

    function takeList() {
      const lid = core.current;
      const line = script.lines.find(l => l.id === lid);
      const takes = core.takes(lid);
      const chosen = s.production.chosen[lid];
      const busy = s.isBusy() || !!s.run;
      const i = core.mine.indexOf(lid);
      const box = el('section', { class: 'st-sec st-takes', 'aria-label': 'Takes' },
        el('h3', { class: 'st-h' }, `Line ${num.format(i + 1)} of ${num.format(core.mine.length)}`),
        line ? el('p', { class: 'st-words' }, C.spokenText(line)) : null);
      if (!takes.length) box.append(el('p', { class: 'caption st-muted' }, 'No take'));
      else {
        box.append(el('ol', { class: 'st-take-list' }, takes.map((t, k) => {
          const on = chosen === t.id;
          return el('li', { class: `st-take${on ? ' on' : ''}` },
            el('label', { class: 'st-take-pick' },
              el('input', { type: 'radio', name: `st-take-${lid}`, checked: on, disabled: busy, onchange: () => core.choose(t) }),
              el('span', { class: 'st-take-t' }, el('span', { class: 'body-strong' }, `Take ${k + 1}`), el('span', { class: 'caption tabular st-muted' }, secs(t)),
                typeof OwnScripts !== 'undefined' && OwnScripts.wordsChanged(script, t) ? el('span', { class: 'caption st-muted' }, 'Words changed') : null),
              t.bleed ? icon('warn', 'st-flag') : null),
            el('button', { type: 'button', class: 'pl-play-dot', 'aria-label': `Play take ${k + 1}`, disabled: s.isBusy(), onclick: () => hear(t) }, icon('play')),
            el('button', { type: 'button', class: 'btn btn-way st-cue', disabled: !s.started || busy, onclick: () => s.playWithCue(t) }, 'With cue'),
            on ? el('span', { class: 'st-del-gap' }) : el('button', { type: 'button', class: 'icon-btn st-del', 'aria-label': `Delete take ${k + 1}`, title: `Delete take ${k + 1}`,
                                                                       disabled: busy, onclick: async () => { await core.deleteTake(t); } }, icon('trash')));
        })));
        const c = C.chosenTake(s.production, lid);
        if (c && c.bleed) box.append(el('p', { class: 'pl-warn', role: 'alert' }, icon('warn'), 'The microphone heard the device voice. Re-take this line with headphones.'));
      }
      box.append(el('button', { type: 'button', class: 'btn btn-again st-again', dataset: { act: 'again-panel' }, disabled: !s.started || s.isBusy(),
                                onclick: () => { sheet.close(); core.again(); } }, el('span', { class: 'dot' }), takes.length ? 'Record again' : 'Record'));
      return box;
    }

    function runList() {
      const takes = s.runTakes();
      return el('section', { class: 'st-sec', 'aria-label': 'This run' },
        el('h3', { class: 'st-h' }, `This run · ${takes.length === 1 ? '1 take' : `${num.format(takes.length)} takes`}`),
        el('ol', { class: 'st-take-list' }, takes.map(t => {
          const n = core.mine.indexOf(t.lineID) + 1;
          return el('li', { class: 'st-take' },
            el('span', { class: 'st-take-pick' }, el('span', { class: 'st-take-t' }, el('span', { class: 'body-strong' }, `Line ${num.format(n)}`), el('span', { class: 'caption tabular st-muted' }, secs(t))),
              t.bleed ? icon('warn', 'st-flag') : null),
            el('button', { type: 'button', class: 'pl-play-dot', 'aria-label': `Play line ${n} with its cue`, disabled: s.isBusy(), onclick: () => s.playWithCue(t) }, icon('play')),
            el('button', { type: 'button', class: 'btn btn-again', disabled: s.isBusy(), onclick: () => core.again(t.lineID) }, el('span', { class: 'dot' }), 'Again'));
        })));
    }

    const castBox = CastUI.list({ script, cast: api.cast, voice: api.voice });
    // A part another member holds shows who they are, not a voice (shared productions only).
    const link = store.share ? store.share(id) : null;
    if (link && typeof API !== 'undefined' && API.plays && API.account && API.account.signedIn()) {
      API.plays.get(link.pid).then((rec) => {
        if (ss.detached || !rec) return;
        castBox.setNames(SC.heldBy(rec, API.account.state().user_id));
      }).catch((err) => console.error(err));
    }
    const listenBtn = el('button', { type: 'button', class: 'btn btn-way st-listen', onclick: () => listenFromHere() });
    function listenFromHere() {
      if (ss.listen && ss.listen.playing) { ss.listen.stop(); return; }
      if (s.isBusy() || s.run) return;
      sheet.close();
      if (typeof Player !== 'undefined' && Player.pause) Player.pause();
      api.refollow();
      const lt = ListenThrough.create({
        production: s.production, script, store, audio: LiveAudio.create({ muted: muted() }),
        voice: StandInVoice.create({ muted: muted(), cast: api.cast }),
        onChange: (x) => { const e = x.playing ? x.current() : null; api.follow(e ? e.lineID : null); paintListen(); paintTransport(); },
      });
      const k = script.lines.findIndex(l => l.id === core.current);
      const from = lt.plan.findIndex(e => script.lines.findIndex(l => l.id === e.lineID) >= k);
      lt.index = Math.max(0, from);
      ss.listen = lt;
      lt.play();
    }
    function paintListen() {
      const on = !!(ss.listen && ss.listen.playing);
      listenBtn.replaceChildren(icon(on ? 'stop' : 'play', 'i-inline'), on ? 'Stop' : 'Listen through from here');
      listenBtn.disabled = !on && (s.isBusy() || !!s.run);
    }

    function paintPanel() {
      const unused = core.unused().length;
      const missing = core.mine.length - core.kept();
      const locked = s.isBusy() || !!s.run;
      paintListen();
      castBox.paint();
      const keys = [['Space', s.mode === 'run' ? 'Start or pause' : 'Record or stop'], ['J K', 'My next, previous line'], ['R', 'Record again'], ['Return', 'Keep']];
      panel.replaceChildren(
        el('div', { class: 'st-head' }, el('span', { class: 'st-part' }, C.partTitle(part)), el('span', { class: 'caption tabular st-muted' }, `${num.format(core.kept())} of ${num.format(core.mine.length)}`)),
        s.phase.kind === 'runReview' ? runList() : takeList(),
        el('section', { class: 'st-sec', 'aria-label': 'Cast' }, el('h3', { class: 'st-h' }, 'Cast'), castBox),
        el('section', { class: 'st-sec st-acts' }, listenBtn,
          unused ? el('button', { type: 'button', class: 'btn', disabled: locked, onclick: async () => {
            // eslint-disable-next-line no-alert
            if (!confirm(`Delete ${unused === 1 ? '1 unused take' : `${num.format(unused)} unused takes`} of ${C.partTitle(part)}?`)) return;
            await core.deleteUnused();
          } }, 'Delete unused takes') : null,
          // Stage directions never block (B32 §2 item 3): Done from the first take, the rest silent.
          el('button', { type: 'button', class: 'btn', disabled: locked || (C.isSpeaking(part) ? missing > 0 : core.kept() === 0), onclick: () => done() }, 'Done with this part'),
          missing && C.isSpeaking(part) ? el('p', { class: 'caption st-muted' }, missing === 1 ? '1 line to go' : `${num.format(missing)} lines to go`) : null,
          missing && !C.isSpeaking(part) && core.kept() ? el('p', { class: 'caption st-muted' }, 'The rest silent') : null,
          el('p', { class: 'caption refusal st-done-err', role: 'alert' })),
        el('dl', { class: 'pl-keys st-keys' }, keys.flatMap(([k, v]) => [el('dt', {}, el('kbd', {}, k)), el('dd', {}, v)])));
    }

    function openPanel() {
      if (ss.wide) { const t = panel.querySelector('.st-takes'); if (t) t.scrollIntoView({ block: 'nearest' }); return; }
      if (!sheet.open) sheet.showModal();
    }

    /** "Done with this part" (§2.5): the cast sheet, where a shared part is finished and uploaded. */
    function done() {
      const back = `?production=${encodeURIComponent(id)}`;
      if (!store.share(id)) {
        try { store.update(C.finish(store.production(id), script, part)); } catch (err) {
          const r = panel.querySelector('.st-done-err');
          if (r) r.textContent = err instanceof C.Refusal ? C.refusalText(err) : String(err.message || err);
          return;
        }
      }
      sheet.close();
      if (api.navigate) api.navigate(back, true); else location.href = back;
    }

    /* ---- Wide or narrow: the panel beside the script from the spread width, else a sheet ---- */

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

    function revealCurrent() { if (core.current) api.go(core.current); }

    function paint() {
      if (ss.detached) return;
      // A repaint keeps the keyboard where it was.
      const had = document.activeElement && document.activeElement.dataset ? document.activeElement.dataset.act : null;
      for (const lid of badges.keys()) paintBadge(lid);
      paintRings();
      paintLines();
      paintDock();
      paintTransport();
      paintPanel();
      if (had) { const b = api.root.querySelector(`[data-act="${had}"]:not(:disabled)`); if (b) b.focus({ preventScroll: true }); }
    }
    core.onChange = () => paint();
    // The line being heard or recorded is lit, and a run turns its own pages to it.
    core.onFollow = (lid) => api.follow(lid);

    /* ---- Taps and keys ---- */

    const ctl = {
      /** A tap on the page (js/reader.js): true when the studio used it. */
      tap(target, lineNode) {
        const ring = target.closest && target.closest('.rd-vc');
        if (ring) { castPart(ring.dataset.part); return true; }
        const badge = target.closest && target.closest('.rd-take');
        const lid = badge ? badge.dataset.line : lineNode && lineNode.dataset.line;
        if (!lid || !core.mine.includes(lid)) return false;
        core.select(lid);
        if (badge) openPanel();
        return true;
      },
      detach() {
        ss.detached = true;
        clearInterval(ss.clock);
        window.removeEventListener('keydown', onKey, true);
        ro.disconnect();
        if (ss.listen) ss.listen.end();
        if (ss.preview) { ss.preview.pause(); URL.revokeObjectURL(ss.preview.src); }
        s.end();
        if (sheet.open) sheet.close();
        // Left with no take, and not for this production's cast sheet: an abandoned try is deleted (§2.3 rule 3a).
        // Only after the take writes of this session have settled, so a take still landing is never lost.
        const held = () => typeof location !== 'undefined' && new URLSearchParams(location.search).get('production') === id;
        store.discardIfAbandoned(id, held).catch((e) => console.error(e));
      },
      core, session: s,
    };

    /* Space, J, K, R and Return, captured before the reader's and the player's own keys (§2.9 rule 8). */
    function onKey(e) {
      if (ss.detached || e.metaKey || e.ctrlKey || e.altKey || !api.root.isConnected) return;
      if (document.querySelector('dialog[open]:not(.st-sheet)')) return;
      const t = e.target;
      if (t && t.closest && t.closest('input:not([type="radio"]):not([type="checkbox"]), select, textarea, [contenteditable="true"]')) return;
      const k = e.key;
      if (k === ' ') { if (!s.started) return; quiet(); core.primary(); }
      else if (k === 'j' || k === 'J') { if (core.move(1)) revealCurrent(); }
      else if (k === 'k' || k === 'K') { if (core.move(-1)) revealCurrent(); }
      else if (k === 'r' || k === 'R') { if (!s.started || s.isBusy()) return; quiet(); core.again(); }
      else if (k === 'Enter' && !(t && t.closest && t.closest('button, a'))) { if (['review', 'runReview'].includes(s.phase.kind)) core.keep(); else return; }
      else return;
      e.preventDefault();
      e.stopPropagation();
    }
    window.addEventListener('keydown', onKey, true);

    ready = true;
    place();
    paint();
    if (core.current) setTimeout(() => { if (!ss.detached) revealCurrent(); }, 0);
    return ctl;
  }

  return { attach, begin, askAccount, SECOND };
})();
