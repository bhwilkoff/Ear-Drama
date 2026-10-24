/**
 * The Plays views (WEB-DESIGN §4.10; PLAYS-DESIGN §2, binding): the plays a
 * person can cast, a play's parts and rights, the cast sheet, and recording
 * one part line by line. app.js's router calls render() with its helpers and
 * leave() whenever it shows another view, which ends a recording session and
 * stops the microphone.
 *
 * Every word of a script is drawn as printed; nothing here writes a list or
 * a blurb (§8 rule 2). The device voice is always labeled where it plays.
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

  async function renderMine(body, helpers) {
    h = helpers;
    const my = ++token;
    body.replaceChildren(h.stateBox('loading'));
    try {
      await openStore();
    } catch (err) {
      if (my === token) failBox(body, err, () => renderMine(body, helpers));
      return;
    }
    if (my !== token) return;
    const mine = store.productions;
    if (!mine.length) { body.replaceChildren(h.stateBox('empty', { text: 'No ear dramas yet.' })); return; }
    const ul = h.el('ul', { class: 'play-list' });
    for (const p of mine) {
      const script = await store.script(p);
      if (my !== token) return;
      ul.append(h.el('li', { class: 'play-row' },
        h.el('a', { class: 'play-link', href: `?production=${encodeURIComponent(p.id)}` },
          h.el('span', { class: 'body-strong' }, p.title),
          h.el('span', { class: 'caption' }, progressLine(p, script)))));
    }
    body.replaceChildren(ul);
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
    manage.append(h.el('button', { type: 'button', class: 'btn btn-ghost', onclick: async () => {
      if (!confirm(`Delete ${p.title}? Every take is removed from this browser.`)) return;
      if (mix && mix.id === id) { URL.revokeObjectURL(mix.url); mix = null; }
      await store.delete(id);
      h.navigate('?view=library&tab=dramas', true);
    } }, 'Delete production'));

    body.replaceChildren(
      h.el('p', { class: 'caption cast-progress' }, progressLine(p, script)),
      h.el('ul', { class: 'cast-list', 'aria-label': 'Parts' }, rows),
      refusal,
      listenThrough(p, script, rerender),
      manage);
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
    if (C.stateOf(p, part).status !== 'recording') {
      body.replaceChildren(back, h.el('ol', { class: 'read-along' },
        C.linesFor(script, part).map(l => h.el('li', {}, lineView(l)))));
      return;
    }
    rec = { key, id, part, script, s: null, index: 0, headphones: false, back };
    paintRecording();
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
    const start = h.el('button', { type: 'button', class: 'btn btn-primary', disabled: !rec.headphones,
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

  function render(r, helpers) {
    h = helpers;
    const my = ++token;
    const body = $('plays-body');
    const id = r.p.get('production');
    const part = r.p.get('part');
    if (!(id && part && rec && rec.key === `${id} ${part}`)) leave();
    if (id && part) return renderPart(body, my, id, part);
    if (id) return renderProduction(body, my, id);
    return renderScript(body, my, r.p.get('play'));
  }

  return { render, renderMine, startButton, leave };
})();
