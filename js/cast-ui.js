/**
 * The voice chip, the voice picker and the reader's Voices list (WEB-DESIGN §4.10 "The voices on
 * the cast sheet", §4.16 item 13; PLAYS-DESIGN §2.8). Both the cast sheet and the reader draw
 * these over one VoiceCast caster, so a choice made in either is the voice every player reads.
 *
 * The preview reads the part's own first line (the play's words, never a sample sentence),
 * live through StandInVoice: nothing here touches the speech API or keeps any sound (§5).
 */
const CastUI = (() => {
  'use strict';
  const C = PlaysCore;
  const V = VoiceCast;

  const ICON = {
    play: 'M8 5v14l11-7z',
    stop: 'M7 7h10v10H7z',
    warn: 'M1 21h22L12 2zm12-3h-2v-2h2zm0-4h-2v-4h2z',
    more: 'M7 10l5 5 5-5z',
    close: 'M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z',
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
  function el(tag, attrs, ...kids) {
    const n = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (v === null || v === undefined || v === false) continue;
      if (k === 'class') n.className = v;
      else if (k === 'dataset') Object.assign(n.dataset, v);
      else if (k.startsWith('on')) n.addEventListener(k.slice(2), v);
      else n.setAttribute(k, v === true ? '' : v);
    }
    for (const k of kids.flat()) if (k !== null && k !== undefined && k !== false) n.append(k);
    return n;
  }

  /** What the chip and the picker say about a part's voice now. */
  function describe(cast, part) {
    const r = cast.resolve(part);
    if (r.none) return { r, text: 'No voice', label: 'No voice in this browser' };
    if (!r.read) return { r, text: 'Not read', label: 'Not read' };
    if (r.missing) return { r, text: r.voice.name, warn: true, label: `${r.missing} is not in this browser; ${r.voice.name} reads instead` };
    return { r, text: r.voice.name, label: r.voice.name };
  }

  /** The words the preview reads: the part's own first line. */
  function firstLine(script, part) {
    const l = C.linesFor(script, part).find(x => C.spokenText(x).trim());
    return l ? C.spokenText(l) : C.partTitle(part);
  }

  /** The voice chip: the voice's own name; Not read; or the warning glyph and the voice reading instead. */
  function chip({ script, cast, voice, part, onChange = () => {} }) {
    const b = el('button', { type: 'button', class: 'vc-chip' });
    b.paint = () => {
      const d = describe(cast, part);
      // Two parts on one voice differ by pitch (auto-cast's second round), so the chip says it.
      const tune = d.r.read ? [d.r.rate !== 1 ? speedText(d.r.rate) : null, d.r.pitch !== 1 ? `pitch ${pitchText(d.r.pitch)}` : null].filter(Boolean).join(', ') : '';
      b.replaceChildren(...[d.warn ? svg('warn', 'vc-warn') : null, el('span', { class: 'vc-chip-name' }, d.text),
        tune ? el('span', { class: 'vc-chip-tune' }, tune) : null, svg('more', 'vc-more')].filter(Boolean));
      b.setAttribute('aria-label', `Voice for ${C.partTitle(part)}: ${d.label}${tune ? `, ${tune}` : ''}`);
      b.dataset.state = d.r.none ? 'none' : !d.r.read ? 'off' : d.warn ? 'missing' : 'on';
    };
    b.addEventListener('click', () => picker({ script, cast, voice, part, onChange: () => { b.paint(); onChange(); } }));
    b.paint();
    return b;
  }

  /** A − value + stepper over a VoiceCast range. */
  function stepper(label, range, get, set, show) {
    const lab = el('span', { class: 'tabular vc-step-val', 'aria-live': 'polite' });
    const down = el('button', { type: 'button', class: 'btn vc-step-btn', 'aria-label': `${label} lower` }, '−');
    const up = el('button', { type: 'button', class: 'btn vc-step-btn', 'aria-label': `${label} higher` }, '+');
    const box = el('div', { class: 'vc-step', role: 'group', 'aria-label': label }, el('span', { class: 'caption vc-step-lab' }, label), down, lab, up);
    const nudge = (d) => set(Math.round((get() + d * range.step) * 100) / 100);
    down.addEventListener('click', () => nudge(-1));
    up.addEventListener('click', () => nudge(1));
    box.paint = (enabled) => {
      const v = get();
      lab.textContent = show(v);
      down.disabled = !enabled || v <= range.min + 1e-9;
      up.disabled = !enabled || v >= range.max - 1e-9;
    };
    return box;
  }
  const speedText = (v) => `${v.toFixed(Math.round(v * 100) % 10 ? 2 : 1)}×`;
  const pitchText = (v) => { const s = Math.round((v - 1) * 10); return s === 0 ? '0' : s > 0 ? `+${s}` : `−${-s}`; };

  /** The voice picker for one part (a dialog, the reader's sheet). Every choice is kept at once. */
  function picker({ script, cast, voice, part, onChange = () => {} }) {
    const title = C.partTitle(part);
    const speaking = C.isSpeaking(part);
    const text = firstLine(script, part);
    const warn = el('p', { class: 'pl-warn vc-missing', role: 'alert', hidden: true });
    const list = el('ul', { class: 'vc-list', role: 'radiogroup', 'aria-label': `Voice for ${title}` });
    const none = el('p', { class: 'caption refusal', hidden: true }, 'This browser has no voice on this device.');
    const more = el('p', { class: 'caption vc-more-voices' }, 'Your system’s speech settings add voices.');
    const group = el('h3', { class: 'caption vc-group' }, 'On this device');
    let hearing = null;
    const entry = () => cast.entry(part) || V.NOT_READ;
    const reading = () => entry().engine !== 'none';
    const speed = stepper('Speed', V.RATE, () => entry().rate, (rate) => { cast.set(part, { rate }); changed(); }, speedText);
    const pitch = stepper('Pitch', V.PITCH, () => entry().pitch, (p) => { cast.set(part, { pitch: p }); changed(); }, pitchText);

    function hear(btn, v) {
      if (hearing === btn) { voice.cancel(); stopHearing(); return; }
      stopHearing();
      hearing = btn;
      btn.replaceChildren(svg('stop'));
      btn.setAttribute('aria-label', `Stop ${v.name}`);
      const e = entry();
      voice.speakAs(text, v, { rate: e.engine === 'none' ? 1 : e.rate, pitch: e.engine === 'none' ? 1 : e.pitch })
        .then(() => { if (hearing === btn) stopHearing(); });
    }
    function stopHearing() {
      if (!hearing) return;
      const b = hearing;
      hearing = null;
      b.replaceChildren(svg('play'));
      b.setAttribute('aria-label', `Hear ${b.dataset.name}`);
    }

    function row(value, name, caption, v) {
      const input = el('input', { type: 'radio', name: `vc-${part}`, value });
      input.addEventListener('change', () => {
        if (!input.checked) return;
        if (v) cast.set(part, { engine: v.engine, voice: v.id, name: v.name });
        else cast.set(part, { engine: 'none' });
        changed();
      });
      const hearBtn = v ? el('button', { type: 'button', class: 'icon-btn vc-hear', 'aria-label': `Hear ${v.name}`, dataset: { name: v.name } }, svg('play')) : null;
      if (hearBtn) hearBtn.addEventListener('click', () => hear(hearBtn, v));
      return el('li', { class: 'vc-row' },
        el('label', { class: 'vc-pick' }, input, el('span', { class: 'vc-name' }, name), caption ? el('span', { class: 'caption vc-lang' }, caption) : null),
        hearBtn);
    }

    function paint() {
      const voices = cast.voices();
      const d = describe(cast, part);
      warn.hidden = !d.warn;
      warn.replaceChildren(svg('warn'), `${d.r.missing || ''} is not in this browser.`);
      none.hidden = voices.length > 0;
      group.hidden = list.hidden = more.hidden = !voices.length;
      const e = entry();
      const current = e.engine === 'none' ? 'none' : (d.r.voice ? d.r.voice.id : e.voice);
      const rows = [];
      if (!speaking) rows.push(row('none', 'Not read', null, null));
      for (const v of voices) rows.push(row(v.id, v.name, v.lang, v));
      stopHearing();
      list.replaceChildren(...rows);
      for (const i of list.querySelectorAll('input')) i.checked = i.value === current;
      speed.paint(reading() && voices.length > 0);
      pitch.paint(reading() && voices.length > 0);
    }
    function changed() { paint(); onChange(); }

    const d = el('dialog', { class: 'rd-sheet vc-sheet', 'aria-label': `Voice for ${title}` },
      el('div', { class: 'rd-sheet-head' }, el('h2', { class: 'section-header' }, title),
        el('button', { type: 'button', class: 'icon-btn rd-icon', 'aria-label': 'Close', onclick: () => d.close() }, svg('close'))),
      warn, el('div', { class: 'vc-steps' }, speed, pitch), group, list, none, more);
    d.addEventListener('click', (e) => { if (e.target === d) d.close(); });
    const off = StandInVoice.onVoices(paint);
    d.addEventListener('close', () => { off(); voice.cancel(); d.remove(); });
    paint();
    document.body.append(d);
    d.showModal();
    const checked = list.querySelector('input:checked');
    if (checked) checked.focus();
    return d;
  }

  /** The reader's Voices: every part with its chip, then Recast all. */
  function list({ script, cast, voice, onChange = () => {} }) {
    const chips = [];
    const rows = C.castParts(script).map(p => {
      const c = chip({ script, cast, voice, part: p.id, onChange });
      chips.push(c);
      return el('li', { class: 'vc-cast-row' },
        el('span', { class: 'vc-cast-part' }, el('span', { class: 'body-strong' }, p.title),
          el('span', { class: 'caption tabular' }, `${p.lineCount === 1 ? '1 line' : `${p.lineCount.toLocaleString('en-US')} lines`}`)), c);
    });
    const recast = el('button', { type: 'button', class: 'btn', onclick: () => { cast.recast(); paint(); onChange(); } }, 'Recast all');
    const box = el('div', { class: 'vc-cast' }, el('ul', { class: 'vc-cast-list' }, rows), el('div', { class: 'actions' }, recast));
    function paint() { chips.forEach(c => c.paint()); }
    box.paint = paint;
    return box;
  }

  /** One caster per production (seeded from its play's cast) or per play (the reader). */
  function castFor({ script, production = null }) {
    return V.caster({
      key: production ? V.productionKey(production) : V.scriptKey(script.id),
      seed: production ? V.scriptKey(script.id) : null,
      parts: C.castParts(script),
      voices: () => StandInVoice.voices(),
    });
  }

  return { chip, picker, list, castFor, describe, firstLine };
})();
