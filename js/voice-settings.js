/**
 * Library > Voices (Decision 086, amended 2026-11-22; WEB-DESIGN §4.11a; PLAYS-DESIGN §2.8 rule 11): the
 * device's voice defaults, which every part nobody cast reads. A section of the Library view (no
 * Settings page, no sheet), reached by ?view=library&section=voices, which the "Better voices" offer
 * on a cast opens (`open()`).
 *
 *   1. The high-fidelity (Kokoro) voices: Download (the size from the manifest), progress and Cancel,
 *      Delete, the attribution; where this browser cannot run them, one refusal.
 *   2. Speed: the Default parts' speed.
 *   3. The voices in the Default order, the downloaded first, then this device's own best first: each
 *      with a Use tick, Move up and Move down, its quality, and Hear (a line of today's scene, live).
 *
 * Kept in this browser only (`ed.voices`, VoiceCast.loadDefaults), never synced. No speech API here.
 */
const VoiceSettings = (() => {
  'use strict';
  const V = VoiceCast;
  const { el, stepper, speedText } = CastUI;
  const ATTRIBUTION = 'Kokoro-82M by hexgrad, Apache-2.0. Trained in part on Koniwa (CC BY 3.0) and SIWIS (CC BY 4.0).';
  const ARROW = { up: 'M7.4 15.4 12 10.8l4.6 4.6L18 14l-6-6-6 6z', down: 'M7.4 8.6 12 13.2l4.6-4.6L18 10l-6 6-6-6z' };
  const PATHS = { play: 'M8 5v14l11-7z', stop: 'M7 7h10v10H7z' };
  function icon(d) {
    const ns = 'http://www.w3.org/2000/svg';
    const s = document.createElementNS(ns, 'svg');
    s.setAttribute('viewBox', '0 0 24 24');
    s.setAttribute('aria-hidden', 'true');
    const p = document.createElementNS(ns, 'path');
    p.setAttribute('d', d);
    s.append(p);
    return s;
  }
  const mb = (n) => `${Math.round(n / 1e6).toLocaleString('en-US')} MB`;

  let config = { muted: false, sample: async () => null, go: () => {} };
  /** app.js: `muted` (?mute=1), `go()` (opens Library at Voices) and `sample()`, which resolves { text, script } (a line of today's scene) or null. */
  function configure(c) { config = { ...config, ...c }; }

  /** The quality a row states: Kokoro's own grade, or the tier a system voice's name carries. */
  function quality(v) {
    if (v.engine === 'kokoro') return `Grade ${(v.grade || '').replace('-', '−')}`;
    const word = ['Standard', 'Enhanced', 'Premium'][v.tier || 0];
    return new RegExp(`\\b${word}\\b`, 'i').test(v.name) ? v.lang : `${word} · ${v.lang}`;
  }

  let mounted = null;
  /** Library at the Voices section. */
  function open() { config.go(); }
  /** Stops a Hear in progress and lets go of the section (the route left Library). */
  function leave() { if (mounted) { const m = mounted; mounted = null; m.leave(); } }
  /** Paints the Voices section into `host` (an empty element in Library) and returns it. */
  function mount(host) {
    leave();
    const h = Voices.shared();
    const voice = StandInVoice.create({ muted: config.muted });
    let sample = null;
    config.sample().then((s) => {
      sample = s;
      if (s && s.script && typeof KokoroVoice !== 'undefined') KokoroVoice.prepare(s.script);
    }).catch(() => {});
    let hearing = null;

    const hifi = el('div', { class: 'vs-hifi', 'aria-live': 'polite' });
    const steps = el('div', { class: 'vc-steps' });
    const speed = stepper('Speed', V.RATE, () => V.loadDefaults().rate,
      (rate) => { V.saveDefaults({ ...V.loadDefaults(), rate }); paint(); }, speedText);
    steps.append(speed);
    const lists = el('div', { class: 'vs-lists' });

    async function paintHifi() {
      const st = h.status();
      const kids = [];
      const name = el('span', { class: 'body' }, 'Kokoro voices');
      if (st === 'unsupported') {
        kids.push(el('p', { class: 'caption refusal' }, 'This browser can’t run Kokoro voices.'));
      } else if (st === 'probing') {
        h.probe().then(paint);
      } else if (st === 'absent' || st === 'failed') {
        const size = await h.size();
        const offline = !h.online();
        kids.push(el('div', { class: 'vs-hifi-row' }, name,
          el('button', { type: 'button', class: 'btn btn-primary vs-get', disabled: offline || !size, onclick: () => h.download() },
            st === 'failed' ? 'Try again' : size ? `Download (${mb(size)})` : 'Download')));
        if (st === 'failed') kids.push(el('p', { class: 'caption vs-error', role: 'alert' }, 'The download failed.'));
        else if (offline) kids.push(el('p', { class: 'caption' }, 'Offline'));
        else if (!size) kids.push(el('p', { class: 'caption refusal' }, 'Not available yet'));
      } else if (st === 'downloading') {
        const p = h.progress();
        kids.push(el('div', { class: 'vs-hifi-row' }, name,
          el('button', { type: 'button', class: 'btn', onclick: () => h.cancel() }, 'Cancel')),
        el('progress', { class: 'vs-progress', max: String(p.total || 1), value: String(p.done), 'aria-label': 'Downloading Kokoro voices' }),
        el('p', { class: 'caption tabular' }, p.total ? `${mb(p.done)} of ${mb(p.total)}` : mb(p.done)));
      } else if (st === 'checking') {
        kids.push(el('div', { class: 'vs-hifi-row' }, name, el('span', { class: 'caption' }, 'Checking this browser')));
      } else if (st === 'refused') {
        kids.push(el('div', { class: 'vs-hifi-row' }, name,
          el('button', { type: 'button', class: 'btn', onclick: () => h.recheck() }, 'Try again')),
        el('p', { class: 'caption refusal' }, 'This browser can’t run Kokoro voices.'),
        el('button', { type: 'button', class: 'btn btn-ghost vs-delete', onclick: () => h.remove() }, 'Delete'));
      } else if (st === 'ready') {
        const size = await h.size();
        kids.push(el('div', { class: 'vs-hifi-row' }, name,
          el('button', { type: 'button', class: 'btn btn-ghost vs-delete', onclick: () => h.remove() }, size ? `Delete (${mb(size)})` : 'Delete')),
        el('p', { class: 'caption vs-credit' }, ATTRIBUTION));
      }
      hifi.replaceChildren(...kids);
      hifi.dataset.state = st;
    }

    function hear(btn, v) {
      if (hearing === btn) { voice.cancel(); stopHearing(); return; }
      stopHearing();
      hearing = btn;
      btn.replaceChildren(icon(PATHS.stop));
      btn.setAttribute('aria-label', `Stop ${v.name}`);
      const text = (sample && sample.text) || v.name.replace(/\s*\(.*\)$/, '');
      voice.speakAs(text, v, { rate: V.loadDefaults().rate }).then(() => { if (hearing === btn) stopHearing(); });
    }
    function stopHearing() {
      if (!hearing) return;
      const b = hearing;
      hearing = null;
      b.replaceChildren(icon(PATHS.play));
      b.setAttribute('aria-label', `Hear ${b.dataset.name}`);
    }

    function rowFor(v, i, n, all) {
      const d = V.loadDefaults();
      const use = el('input', { type: 'checkbox', 'aria-label': `Use ${v.name}` });
      use.checked = V.usesVoice(v, d);
      use.addEventListener('change', () => {
        const cur = V.loadDefaults();
        V.saveDefaults({ ...cur, off: { ...cur.off, [V.voiceKey(v)]: !use.checked } });
        paint();
      });
      const nudge = (by) => { V.saveDefaults(V.move(all, V.loadDefaults(), v, by)); paint(); };
      const hearBtn = el('button', { type: 'button', class: 'icon-btn vc-hear', 'aria-label': `Hear ${v.name}`, dataset: { name: v.name } }, icon(PATHS.play));
      hearBtn.addEventListener('click', () => hear(hearBtn, v));
      return el('li', { class: 'vc-row vs-row', dataset: { voice: V.voiceKey(v) } },
        el('label', { class: 'vc-pick' }, use,
          el('span', { class: 'vs-name' }, el('span', { class: 'vc-name' }, v.name), el('span', { class: 'caption vc-lang' }, quality(v)))),
        el('button', { type: 'button', class: 'icon-btn vs-move', 'aria-label': `Move ${v.name} up`, disabled: i === 0, onclick: () => nudge(-1) }, icon(ARROW.up)),
        el('button', { type: 'button', class: 'icon-btn vs-move', 'aria-label': `Move ${v.name} down`, disabled: i === n - 1, onclick: () => nudge(1) }, icon(ARROW.down)),
        hearBtn);
    }

    let deviceOpen = null;
    function paintLists() {
      const all = [...h.voices(), ...StandInVoice.voices()];
      const ordered = V.ordered(all, V.loadDefaults());
      const kv = ordered.filter(v => v.engine === 'kokoro');
      const sv = ordered.filter(v => v.engine === 'system');
      stopHearing();
      const kids = [];
      if (kv.length) {
        kids.push(el('h4', { class: 'caption vc-group' }, 'Downloaded'),
          el('ul', { class: 'vc-list', 'aria-label': 'Downloaded voices, in order' }, ...kv.map((v, i) => rowFor(v, i, kv.length, all))));
      }
      const device = sv.length
        ? el('ul', { class: 'vc-list', 'aria-label': 'Voices on this device, in order' }, ...sv.map((v, i) => rowFor(v, i, sv.length, all)))
        : el('p', { class: 'caption refusal' }, 'This browser has no voice on this device.');
      const more = el('p', { class: 'caption vc-more-voices' }, 'Your system’s speech settings add voices.');
      if (kv.length) {
        // With Kokoro here the device's voices are the fallback: folded, as the person left them.
        const det = el('details', { class: 'vs-device' }, el('summary', { class: 'caption vc-group' }, `On this device (${sv.length.toLocaleString('en-US')})`), device, more);
        det.open = deviceOpen === true;
        det.addEventListener('toggle', () => { deviceOpen = det.open; });
        kids.push(det);
      } else {
        kids.push(el('h4', { class: 'caption vc-group' }, 'On this device'), device, more);
      }
      lists.replaceChildren(...kids);
    }

    function paint() {
      if (!host.isConnected) { leave(); return; }
      paintHifi();
      speed.paint(true);
      paintLists();
    }

    host.replaceChildren(
      el('h2', { id: 'voices-h', class: 'section-header vs-head', tabindex: '-1' }, 'Voices'),
      hifi,
      steps,
      el('p', { class: 'caption vs-order' }, 'Parts you haven’t cast take the ticked voices in this order, the largest part first.'),
      lists);
    host.setAttribute('aria-labelledby', 'voices-h');
    const offVoices = StandInVoice.onVoices(paint);
    const offHifi = h.onChange(() => { if (h.status() === 'downloading') paintHifi(); else paint(); });
    mounted = { leave() { offVoices(); offHifi(); voice.cancel(); stopHearing(); } };
    paint();
    return host;
  }

  return { configure, open, mount, leave, quality, ATTRIBUTION };
})();
