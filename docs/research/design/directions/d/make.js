/* Direction D's making screens, D2c-3: D2b-2's Record a Line on D's grammar (catalog-experience-design
   rule 11) and its color system (Decision 064), with the owner's three recording modes:
     Run through   the play runs straight through, other parts in human takes or live device voices, and
                   the microphone opens at each of your lines as it comes; review after the run;
     Line by line  record any line, tap any line to record it again;
     Step          each cue waits for a tap (D2b-2's per-line flow).
   One native control picks the mode (a segmented radio group: UISegmentedControl / SegmentedButton).
   The states are D2b-2's (Ready, Cue playing, Your turn, Recording, Review, Kept, and the refusals);
   the mode only changes what follows a take. No microphone and no speech: every state is simulated.
   Every script word is the bundle's (../record/data.js from catalog/plays/castable-scripts.json). */
(function () {
  'use strict';
  const { plays, scene } = window.REC;
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const q = new URLSearchParams(location.search);
  if (q.get('theme')) document.documentElement.dataset.theme = q.get('theme');

  const I = {
    back: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M15 5l-7 7 7 7" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    down: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 9l7 7 7-7" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    prev: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 5v14M19 5l-9 7 9 7z" stroke="currentColor" stroke-width="2" fill="none" stroke-linejoin="round" stroke-linecap="round"/></svg>',
    next: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18 5v14M5 5l9 7-9 7z" stroke="currentColor" stroke-width="2" fill="none" stroke-linejoin="round" stroke-linecap="round"/></svg>',
    play: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 4.5v15l13-7.5z" fill="currentColor"/></svg>',
    pause: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 4h4v16H6zM14 4h4v16h-4z" fill="currentColor"/></svg>',
    mic: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="9" y="3" width="6" height="11" rx="3" fill="currentColor"/><path d="M6 11a6 6 0 0 0 12 0M12 17v4" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
    stop: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="6" y="6" width="12" height="12" rx="2" fill="currentColor"/></svg>',
    check: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5" stroke="currentColor" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    wave: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 12h2M7 8v8M11 5v14M15 8v8M19 10v4M21 12h0" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
    warn: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3l10 18H2z" stroke="currentColor" stroke-width="2" fill="none" stroke-linejoin="round"/><path d="M12 10v5M12 18v.5" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
    runup: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 12a8 8 0 1 0 2.3-5.6M4 4v4h4" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    ear: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 9a5 5 0 0 1 10 0c0 3-3 4-3 7a3 3 0 0 1-6 0" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
    speed: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 16a8 8 0 1 1 16 0M12 16l4-5" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
    home: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 11l8-7 8 7v9h-5v-6H9v6H4z" stroke="currentColor" stroke-width="1.8" fill="none" stroke-linejoin="round"/></svg>',
    browse: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="4" width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.8" fill="none"/><rect x="13" y="4" width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.8" fill="none"/><rect x="4" y="13" width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.8" fill="none"/><rect x="13" y="13" width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.8" fill="none"/></svg>',
    stations: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="9" width="18" height="11" rx="2" stroke="currentColor" stroke-width="1.8" fill="none"/><path d="M7 9l10-5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><circle cx="15.5" cy="14.5" r="2.5" stroke="currentColor" stroke-width="1.8" fill="none"/></svg>',
    surprise: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h3l10 10h3M4 17h3l3-3M14 10l3-3h3M18 4l2 3-2 3M18 14l2 3-2 3" stroke="currentColor" stroke-width="1.8" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    search: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5" stroke="currentColor" stroke-width="2" fill="none"/><path d="M15.5 15.5L21 21" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
    library: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 4v16M10 4v16M15 4l4 16" stroke="currentColor" stroke-width="1.8" fill="none" stroke-linecap="round"/></svg>',
  };

  /* ---- Facts ---- */
  const HUES = ['mystery', 'scifi', 'western', 'serial', 'documentary', 'comedy', 'news'];
  const hueOf = (play, name) => { const i = play.roles.findIndex((r) => r.name === name); return i >= 0 && i < HUES.length ? HUES[i] : 'none'; };
  const minutes = (w) => { const m = w / 150; return m < 1 ? 'under 1 min' : `about ${Math.round(m)} min`; };
  const author = (p) => (p.authors.length ? p.authors.map((a) => a.name).join(' and ') : 'Project Gutenberg');
  const facts = (xs) => { const v = xs.filter(Boolean); return v.map((x, i) => `<span class="nowrap">${esc(x)}${i < v.length - 1 ? ' ·' : ''}</span>`).join(' '); };

  const fitOf = (name) => { const L = Math.max(...String(name).split(/[\s\-–]+/).map((w) => w.length)); return L > 14 ? " xlong" : L > 10 ? " long" : ""; };
  const rodney = plays.find((p) => p.id === 'gut-28051');
  /* The production on this device: who holds which part (names as typed). */
  const PROD = { URIAH: { who: 'Pat', done: true }, FRANKLIN: { who: 'Ada', done: true }, MCKEEN: { who: 'Sam', kept: 12 }, RODNEY: { who: 'Lou', me: true, kept: 5 } };
  const initial = (who) => who.slice(0, 1).toUpperCase();

  /* ---- D's window and title block (the same grammar as index.html) ---- */
  const STOP = new Set(['the', 'a', 'an', 'of', 'and', '&', 'in', 'on', 'to', 'for']);
  function monogram(name) {
    const words = String(name || '').split(/[\s\-–/]+/).map((w) => w.replace(/^[^A-Za-z0-9]+/, '')).filter(Boolean);
    const m = words.filter((w) => /^[A-Za-z]/.test(w) && !STOP.has(w.toLowerCase())).slice(0, 2).map((w) => w.charAt(0).toUpperCase()).join('');
    return m || '?';
  }
  const blockSize = (m) => Math.min(104, Math.floor(86 / [...m].reduce((a, c) => a + (/[MW]/.test(c) ? 0.62 : /[IJ1]/.test(c) ? 0.26 : 0.48) + 0.02, 0)));
  const win = (name) => `<span class="win tb" data-slot="window" data-kind="block"><svg viewBox="0 0 100 100" aria-hidden="true"><text x="9" y="93" font-size="${blockSize(monogram(name))}">${esc(monogram(name))}</text></svg></span>`;

  function face(play, part, { size = '', ok = false, live = false, now = false } = {}) {
    const hue = hueOf(play, part);
    const c = play === rodney ? PROD[part] : null;
    if (c) return `<span class="vf ${size}${live ? ' live' : ''}${now ? ' now' : ''}" data-hue="${hue}" aria-hidden="true">${esc(initial(c.who))}${ok ? `<span class="ok">${I.check}</span>` : ''}</span>`;
    return `<span class="vf voice ${size}" data-hue="${hue}" aria-hidden="true">${I.wave}</span>`;
  }
  const speaker = (part) => { const c = PROD[part]; if (c && c.me) return 'You'; if (c && (c.done || c.kept)) return c.who; return 'Device voice'; };
  /* The fingerprint: each part's share of the play's words, largest first, as marks. */
  const printBar = (play) => `<div class="print-bar" role="img" aria-label="${play.roles.length} parts by size">${
    play.roles.map((r) => `<i data-hue="${hueOf(play, r.name)}" style="flex:${r.words}"></i>`).join('')}</div>`;
  const presence = (play, r) => {
    const max = Math.max(1, ...r.presence);
    return `<div class="presence" data-hue="${hueOf(play, r.name)}" role="img" aria-label="Where ${esc(r.name)} speaks">${
      r.presence.map((v) => (v ? `<i style="height:${Math.max(3, Math.round(18 * v / max))}px"></i>` : '<i class="z"></i>')).join('')}</div>`;
  };

  /* ---- Script ---- */
  const L = scene.lines;
  const lineById = (id) => L.find((l) => l.id === id);
  const sayHTML = (line, words) => line.parts.map((p) => {
    if (p.dir) return `<span class="dir">[${esc(p.dir)}]</span>`;
    if (!words) return esc(p.say);
    return p.say.split(/(\s+)/).map((w) => (/\s/.test(w) ? w : `<span class="w">${esc(w)}</span>`)).join('');
  }).join(' ');
  const wordCount = (line) => line.parts.reduce((n, p) => n + (p.say ? p.say.split(/\s+/).length : 0), 0);
  const MINE = scene.rodneyLines;

  /* ---- The shell (Decision 068), every section a link to D ---- */
  const SECTIONS = [['home', 'Home', 'home'], ['browse', 'Browse', 'browse'], ['stations', 'Stations', 'stations'], ['surprise', 'Surprise', 'home'], ['search', 'Search', 'search'], ['library', 'Library', 'library']];
  const shell = (main) => `<div class="ed-app"><nav class="ed-nav" aria-label="Sections"><a class="ed-wordmark" href="index.html?s=home">Ear Drama</a>${
    SECTIONS.map(([k, l, to]) => `<a href="index.html?s=${to}" class="ed-nav-item${k === 'library' ? ' on' : ''}">${I[k]}<span>${l}</span></a>`).join('')
  }</nav><main class="ed-main">${main}</main></div>`;

  /* ---- Pick a play: tiles in D's grammar (window, title, the cast fingerprint, facts) ---- */
  function playTile(p) {
    return `<a class="tile" href="?s=part" data-genre="${p.genre}">${win(p.title)}
      <span class="tile-name${fitOf(p.title)}" data-slot="name">${esc(p.title)}</span>
      <span class="tile-mark" data-slot="mark">${printBar(p)}</span>
      <span class="tile-facts" data-slot="facts"><span>${esc(author(p))}</span><span>${facts([minutes(p.words).replace('about ', ''), `${p.roles.length} parts`])}</span></span></a>`;
  }
  function pick() {
    const radio = plays.filter((p) => p.radio);
    const stage = plays.filter((p) => !p.radio);
    return shell(`<h1 class="l1 page-h">Start an ear drama</h1>
      <ol class="rows"><li><a class="row" href="?s=ready"><span class="vis" data-slot="visual" data-genre="${rodney.genre}">${win(rodney.title)}</span>
        <span class="row-body"><span class="row-title">${esc(rodney.title)}</span><span class="row-sub">${facts(['RODNEY · you', '5 of 76 lines'])}</span></span>
        <span class="row-len"></span><span class="btn btn-primary">Continue</span></a></li></ol>
      <div class="sec-h pk-sec"><h2 class="l2">Radio plays</h2><span class="l5">Shortest first</span></div>
      <div class="tiles six">${radio.map(playTile).join('')}</div>
      <div class="sec-h pk-sec"><h2 class="l2">Stage plays</h2><span class="l5">Shortest first</span></div>
      <div class="tiles six">${stage.map(playTile).join('')}</div>`);
  }

  /* ---- Claim a part: the playbill (the part's face is its hue; no edge stripe) ---- */
  function partCard(r) {
    const c = PROD[r.name];
    const open = !c;
    const suggested = r.name === 'ANNOUNCER';
    const state = c && c.me ? `You · ${c.kept} of ${r.lines}` : c && c.done ? `${c.who} · recorded` : c ? `${c.who} · ${c.kept} of ${r.lines}` : 'Device voice';
    const action = c && c.me ? '<a class="btn btn-primary" href="?s=ready">Continue</a>'
      : open ? `<a class="btn ${suggested ? 'btn-ink-outline' : 'btn-way'}" href="?s=preflight">Take part</a>` : '<span class="btn-hold"></span>';
    return `<div class="part${c && c.me ? ' mine' : ''}">
      <span class="part-head">${face(rodney, r.name, { size: 'sm', ok: c && c.done })}<span class="nm disp">${esc(r.name)}</span></span>
      <span class="l6 two">${facts([minutes(r.words), `${r.lines} ${r.lines === 1 ? 'line' : 'lines'}`])}</span>
      ${presence(rodney, r)}
      <span class="who">${esc(state)}</span>${action}</div>`;
  }
  function part() {
    const p = rodney;
    return shell(`<div class="top"><a href="?s=pick" class="back">${I.back}Start an ear drama</a></div>
      <header class="board head" data-genre="${p.genre}">${win(p.title)}
        <div class="head-text"><p class="kicker" data-slot="kicker">Radio play</p><h1 class="board-name${fitOf(p.title)}" data-slot="name">${esc(p.title)}</h1>
          <p class="credits" data-slot="credits">${esc(author(p))}</p><p class="facts" data-slot="facts">${facts([minutes(p.words), `${p.roles.length} parts`])}</p></div>
        <div class="head-mark" data-slot="mark">${printBar(p)}</div></header>
      <div class="acts"><a class="btn btn-primary" href="?s=listen">${I.play}Listen through</a><a class="btn btn-way" href="#">Invite</a></div>
      <div class="pb-as"><span>Recording as <b>Lou</b></span><a href="#" class="l3" style="color:var(--color-link)">Change</a></div>
      <div class="pb-grid">${p.roles.map(partCard).join('')}</div>
      <p class="rights"><a href="${esc(p.source)}">${esc(p.rights)} · Project Gutenberg</a></p>`);
  }

  /* ---- The recorder ---- */
  const MODES = [['run', 'Run through'], ['lines', 'Line by line'], ['step', 'Step']];
  const ST = { mode: 'step', index: MINE.indexOf('L0118'), phase: 'ready', cue: 0.62, rec: 2.1, speed: '1×' };
  const busy = () => ST.phase === 'cue' || ST.phase === 'rec';
  /* One native control: a segmented radio group; it holds its place, disabled while the microphone is armed or open. */
  const modeSeg = () => `<div class="seg mode" role="radiogroup" aria-label="Recording mode">${MODES.map(([k, l]) =>
    `<label class="${k === ST.mode ? 'on' : ''}"><input type="radio" name="mode" value="${k}"${k === ST.mode ? ' checked' : ''}${busy() ? ' disabled' : ''} data-act="mode">${l}</label>`).join('')}</div>`;
  function cueFor(id) {
    const k = L.findIndex((l) => l.id === id);
    const prev = L[k - 1];
    return prev && prev.role !== 'RODNEY' ? prev : null;
  }
  function seeded(n, seed) {
    let s = seed; const out = [];
    for (let i = 0; i < n; i++) { s = (s * 9301 + 49297) % 233280; out.push(s / 233280); }
    return out;
  }
  const meterBars = (seconds, maxBars) => seeded(Math.min(maxBars, Math.round(seconds * 14)), 7).map((v, i) => {
    const env = Math.min(1, i / 4) * (0.55 + 0.45 * Math.sin(i / 3.1) ** 2);
    return `<i style="height:${Math.round(6 + 34 * env * (0.6 + 0.4 * v))}px"></i>`;
  }).join('');
  const takeWave = (n, seed) => seeded(n, seed).map((v, i) => `<i style="height:${Math.round(4 + 24 * (0.35 + 0.65 * Math.sin(i / 2.7) ** 2) * (0.5 + 0.5 * v))}px"></i>`).join('');
  function partnersNear(id) {
    const k = L.findIndex((l) => l.id === id);
    const seen = [];
    for (const l of L.slice(Math.max(0, k - 12), k + 24)) if (l.role !== 'RODNEY' && l.role !== 'ANNOUNCER' && !seen.includes(l.role)) seen.push(l.role);
    return seen;
  }
  const oppRow = (id) => partnersNear(id).map((r) => `<span class="p">${face(rodney, r, { size: 'xs' })}<b>${esc(r)}</b><span class="muted">${esc(speaker(r))}</span></span>`).join('');
  function lineBlock(line, cls, extra = '') {
    return `<div class="ln ${cls}">${face(rodney, line.role, { size: 'sm' })}<div><div class="who">${esc(line.role)}<span class="tag">${esc(speaker(line.role))}</span>${extra}</div><p class="say">${sayHTML(line)}</p></div></div>`;
  }
  /** The cue card, lit word by word while it plays; the streamer is a mark inside the card, not its edge. */
  function cueCard(cue, playing, p = ST.cue) {
    let say = sayHTML(cue, playing);
    if (playing) { const lit = Math.round(wordCount(cue) * p); let i = 0; say = say.replace(/<span class="w">/g, () => (i++ < lit ? '<span class="w lit">' : '<span class="w">')); }
    return `<div class="cue" data-hue="${hueOf(rodney, cue.role)}">${lineBlock(cue, 'cur').replace(`class="say">${sayHTML(cue)}`, `class="say">${say}`)}${playing ? `<span class="stream"><span style="width:${Math.round(p * 100)}%"></span></span>` : ''}</div>`;
  }
  /** Your line's box: Ready, armed (dashed red, "Next"), recording (solid red), review (the take). */
  function mineBox(me, ph, head = 'RODNEY · You') {
    let pill = '', body = '', cls = '';
    if (ph === 'cue') { cls = ' armed'; pill = '<span class="pill redo"><span class="dot"></span>Next</span>'; }
    if (ph === 'rec') { cls = ' on'; pill = `<span class="pill red" role="status"><span class="dot"></span>Recording 0:0${Math.floor(ST.rec)}</span>`; body = `<div class="meter" aria-hidden="true">${meterBars(ST.rec, 60)}</div>`; }
    if (ph === 'review') {
      pill = '<span class="takes" aria-label="Takes"><span class="t">1</span><span class="t on">2</span></span>';
      body = `<div class="take"><button class="play-dot" aria-label="Play take 2">${I.play}</button><div class="wave" aria-hidden="true">${takeWave(44, 26)}</div><span class="l6">3.1 s</span></div>`;
    }
    return `<div class="mine-ln${cls}" data-hue="${hueOf(rodney, 'RODNEY')}"><div class="who"><span>${head}</span>${pill}</div><p class="big say">${sayHTML(me)}</p>${body}</div>`;
  }
  function stage() {
    const id = MINE[ST.index];
    const me = lineById(id);
    const k = L.findIndex((l) => l.id === id);
    const cue = cueFor(id);
    const before = L.slice(Math.max(0, k - (cue ? 2 : 1)), cue ? k - 1 : k).slice(-1);
    const out = before.map((b) => lineBlock(b, 'past'));
    if (cue) out.push(cueCard(cue, ST.phase === 'cue'));
    out.push(mineBox(me, ST.phase));
    if (L[k + 1]) out.push(lineBlock(L[k + 1], 'next'));
    return out.join('');
  }
  /* The dock. Step: Record / Cancel / Stop, then Again, With cue, Keep (Keep waits on the next line's Ready). */
  function dock() {
    const ph = ST.phase;
    if (ph === 'review') {
      return `<div class="dock three">
        <button class="btn btn-again" data-act="again"><span class="dot"></span>Again</button>
        <button class="btn btn-way" data-act="listen">${I.play}With cue</button>
        <button class="btn btn-primary" data-act="keep">${I.check}Keep</button></div>`;
    }
    const center = ph === 'cue' ? `<button class="recbtn armed" data-act="cancel" aria-label="Cancel">${I.mic}</button><span class="lab">Cancel</span>`
      : ph === 'rec' ? `<button class="recbtn stop" data-act="stop" aria-label="Stop">${I.stop}</button><span class="lab">Stop</span>`
        : `<button class="recbtn" data-act="record" aria-label="Record">${I.mic}</button><span class="lab">Record</span>`;
    return `<div class="dock">
      <div class="side"><button class="icon-btn" data-act="prev" aria-label="Previous line"${ST.index === 0 || busy() ? ' disabled' : ''}>${I.prev}</button></div>
      <div class="ctr">${center}</div>
      <div class="side"><button class="icon-btn" data-act="next" aria-label="Next line"${ST.index === MINE.length - 1 || busy() ? ' disabled' : ''}>${I.next}</button></div></div>`;
  }
  const aidButtons = () => `<button class="aid" data-act="runup"${busy() ? ' disabled' : ''}>${I.runup}Run-up</button><button class="aid" data-act="hear"${busy() ? ' disabled' : ''}>${I.ear}Hear it read</button><button class="aid" data-act="speed"${busy() ? ' disabled' : ''}>${I.speed}${ST.speed}</button>`;
  const aids = () => `<div class="aids">${aidButtons()}</div>`;
  function strip(kept, current, recOn, marks = []) {
    const r = rodney.roles.find((x) => x.name === 'RODNEY');
    return `<div class="strip" data-slot="strip" data-hue="${hueOf(rodney, 'RODNEY')}" role="img" aria-label="${kept} of ${r.lines} lines kept">${
      Array.from({ length: r.lines }, (_, i) => `<i class="${i === current ? 'c' + (recOn ? ' rec-on' : '') : marks.includes(i) ? 'n' : i < kept ? 'k' : ''}"></i>`).join('')}</div>`;
  }
  const top = (count) => `<div class="rec-top" data-slot="top"><a class="icon-btn" href="?s=part" aria-label="Close">${I.down}</a>
      <div class="t"><div class="part-name">RODNEY</div><div class="play">${esc(rodney.title)}</div></div><span class="count">${count}</span></div>`;
  function rails(right) {
    const id = MINE[ST.index];
    const left = `<aside class="rail l"><h3>In this scene</h3>${
      [`<div class="r1">${face(rodney, 'RODNEY', { size: 'lg', live: ST.phase === 'rec' })}<span><span class="nm">RODNEY</span><span class="l5">You · Lou</span></span></div>`]
        .concat(partnersNear(id).map((r) => `<div class="r1">${face(rodney, r, { size: 'lg' })}<span><span class="nm">${esc(r)}</span><span class="l5">${esc(speaker(r))}</span></span></div>`)).join('')}</aside>`;
    return left + `<aside class="rail r">${right}</aside>`;
  }
  const keysStep = `<h3>This line</h3><div class="aids col">${aidButtons()}</div>
      <h3>Keys</h3><div class="keys"><kbd>Space</kbd><span>Record or stop</span><kbd>Return</kbd><span>Keep</span><kbd>R</kbd><span>Again</span><kbd>← →</kbd><span>Line</span></div>`;
  function recorder(body, { count, stripHTML, below, right }) {
    return `<div class="rec" data-screen="record">
      ${top(count)}
      ${stripHTML}
      <div class="mode-row" data-slot="mode">${modeSeg()}</div>
      <div class="opp" aria-label="Opposite you">${oppRow(MINE[ST.index])}</div>
      <div class="scene" aria-live="polite">${body}</div>
      ${below}
      ${rails(right)}</div>`;
  }
  const step = () => { ST.mode = 'step'; return recorder(stage(), { count: `${ST.index} of ${MINE.length}`, stripHTML: strip(ST.index, ST.index, ST.phase === 'rec'), below: aids() + dock(), right: keysStep }); };

  /* Run through: the scene plays; the microphone opens on each of your lines as it comes. */
  function runThrough(ph) {
    ST.mode = 'run'; ST.phase = ph === 'rec' ? 'rec' : 'cue';
    const id = MINE[ST.index];
    const k = L.findIndex((l) => l.id === id);
    const cue = cueFor(id);
    const out = [];
    if (ph === 'play') {
      out.push(lineBlock(L[k - 2], 'past'));
      if (cue) out.push(cueCard(cue, true, 0.4));
      out.push(mineBox(lineById(id), 'cue'));
    } else {
      if (cue) out.push(lineBlock(cue, 'past'));
      out.push(mineBox(lineById(id), 'rec'));
      if (L[k + 1]) out.push(lineBlock(L[k + 1], 'next'));
    }
    const center = ph === 'rec'
      ? `<button class="recbtn stop" data-act="pause" aria-label="Stop">${I.stop}</button><span class="lab">Stop</span>`
      : `<button class="np-play" data-act="pause" aria-label="Pause">${I.pause}</button><span class="lab">Pause</span>`;
    const dockHTML = `<div class="dock"><div class="side"><span class="l6 muted">${ph === 'rec' ? '3 taken' : '2 taken'}</span></div><div class="ctr">${center}</div><div class="side"></div></div>`;
    const right = '<h3>Keys</h3><div class="keys"><kbd>Space</kbd><span>Pause</span></div>';
    return recorder(out.join(''), { count: `${ST.index} of ${MINE.length}`, stripHTML: strip(ST.index - 2, ST.index, ph === 'rec', [ST.index - 2, ST.index - 1]), below: `<div class="aids"></div>${dockHTML}`, right });
  }
  /* After a run: the takes it made, each heard in place; keep them all, or record any again. */
  function runReview() {
    ST.mode = 'run'; ST.phase = 'review';
    const ids = MINE.slice(ST.index - 2, ST.index + 1);
    const rows = ids.map((id, i) => {
      const quiet = i === 1;
      return `<li class="rv${quiet ? ' quiet' : ''}"><div class="rv-h"><span class="l6">Line ${MINE.indexOf(id) + 1}</span>${quiet ? `<span class="note">${I.warn}Very quiet. Hold the phone closer?</span>` : ''}</div>
        <p class="say">${sayHTML(lineById(id))}</p>
        <div class="take"><button class="play-dot" aria-label="Play with its cue">${I.play}</button><div class="wave" aria-hidden="true">${takeWave(36, 11 + i * 7)}</div><span class="l6">${(2.4 + i * 0.7).toFixed(1)} s</span>
          <button class="btn btn-again sm" data-act="again"><span class="dot"></span>Again</button></div></li>`;
    }).join('');
    const below = `<div class="aids"></div><div class="dock two"><button class="btn btn-way" data-act="discard">Discard the run</button><button class="btn btn-primary" data-act="keep">${I.check}Keep 3 takes</button></div>`;
    return recorder(`<h2 class="l2">This run · 3 takes</h2><ol class="rv-list">${rows}</ol>`, { count: `${ST.index - 2} of ${MINE.length}`, stripHTML: strip(ST.index - 2, -1, false, [ST.index - 2, ST.index - 1, ST.index]), below, right: '<h3>Keys</h3><div class="keys"><kbd>Return</kbd><span>Keep all</span><kbd>R</kbd><span>Again</span></div>' });
  }
  /* Line by line: every line of your part, in order; tap any line to record it (again). */
  function lineByLine(rec) {
    ST.mode = 'lines'; ST.phase = rec ? 'rec' : 'ready';
    const sel = ST.index;
    const rows = MINE.slice(Math.max(0, sel - 2), sel + 4).map((id) => {
      const i = MINE.indexOf(id);
      const kept = i < 5 || i === sel - 1;
      const cue = cueFor(id);
      if (i === sel) {
        return `<li class="lx sel">${cue ? `<div class="lx-cue">${face(rodney, cue.role, { size: 'xs' })}<span class="l5">${esc(cue.role)} · ${esc(speaker(cue.role))}</span><p class="say">${sayHTML(cue)}</p></div>` : ''}
          ${mineBox(lineById(id), rec ? 'rec' : 'ready', `Line ${i + 1}`)}
          <div class="lx-acts">${rec ? `<button class="btn btn-record" data-act="stop">${I.stop}Stop</button>` : `<button class="btn btn-record" data-act="record">${I.mic}Record</button><button class="btn btn-way" data-act="listen">${I.play}Cue</button>`}</div></li>`;
      }
      return `<li><button class="lx" data-act="line" data-i="${i}"><span class="l6 n">${i + 1}</span><span class="say">${sayHTML(lineById(id))}</span>
        <span class="st${kept ? ' kept' : ''}">${kept ? `${I.check}Take ${i % 2 + 1}` : 'Not yet'}</span></button></li>`;
    }).join('');
    const right = '<h3>Keys</h3><div class="keys"><kbd>↑ ↓</kbd><span>Line</span><kbd>Space</kbd><span>Record or stop</span></div>';
    return recorder(`<ol class="lx-list">${rows}</ol>`, { count: `${sel} of ${MINE.length}`, stripHTML: strip(sel, sel, rec), below: '<div class="aids"></div>', right });
  }

  /* ---- Before the first take ---- */
  const oppList = () => `<div class="opp-list">${partnersNear('L0108').map((r) => `<div class="r">${face(rodney, r, { size: 'sm' })}<span class="nm">${esc(r)}</span><span class="${speaker(r) === 'Device voice' ? 'muted' : ''}">${esc(speaker(r))}</span></div>`).join('')}</div>`;
  function done() {
    const cast = rodney.roles.slice(0, 7);
    return `<div class="rec"><div class="done-wrap">${top('76 of 76')}
      <section class="board done-hero" data-genre="${rodney.genre}"><span class="big disp">RODNEY</span><span class="sub">${I.check}Recorded by you · 76 lines</span></section>
      <div class="done-cast"><h2 class="l2">The cast so far</h2><div class="faces-row">${cast.map((r) => {
        const c = PROD[r.name];
        const ok = r.name === 'RODNEY' || (c && c.done);
        return `<span class="fc">${face(rodney, r.name, { size: 'lg', ok })}<b>${esc(r.name)}</b><span class="muted">${c ? esc(c.me ? 'You' : c.who) : 'Open'}</span></span>`;
      }).join('')}</div><span class="l5">${rodney.roles.length - 7} more parts</span></div>
      <div class="done-act"><a class="btn btn-primary" href="?s=listen">${I.play}Listen through</a><a class="btn btn-way" href="?s=part">Pass the phone</a></div>
      <div class="next-part">${face(rodney, 'ANNOUNCER', { size: 'sm' })}<span class="np-body"><span class="nm">ANNOUNCER</span><span class="l5">${facts(['Open', 'about 4 min', '10 lines'])}</span></span><a class="btn btn-way" href="?s=preflight">Take part</a></div>
      </div></div>`;
  }

  /* ---- Listen through ---- */
  function listen() {
    const p = rodney;
    const now = L.findIndex((l) => l.id === 'L0130');
    const span = L.slice(now - 2, now + 4);
    const human = ['URIAH', 'FRANKLIN', 'RODNEY', 'MCKEEN'];
    const bins = p.roles[0].presence.length;
    const at = Math.floor(scene.speechIndex.L0130 * bins / scene.total);
    const stripHTML = `<svg viewBox="0 0 ${bins * 10} 22" preserveAspectRatio="none" role="img" aria-label="Recorded and device-voice lines across the play">${Array.from({ length: bins }, (_, i) => {
      const all = p.roles.reduce((n, r) => n + r.presence[i], 0) || 1;
      const v = p.roles.filter((r) => human.includes(r.name)).reduce((n, r) => n + r.presence[i], 0);
      const h = Math.max(1, Math.round(22 * v / all));
      return `<rect class="${i === at ? 'here' : v ? 'b' : 'z'}" x="${i * 10}" y="${i === at ? 0 : v ? 22 - h : 21}" width="8" height="${i === at ? 22 : v ? h : 1}"/>`;
    }).join('')}</svg>`;
    const castHTML = p.roles.slice(0, 7).map((r) => `<span class="fc">${face(p, r.name, { now: r.name === 'URIAH' })}${esc(r.name)}</span>`).join('');
    const lines = span.map((l) => {
      const sp = speaker(l.role);
      const join = sp === 'Device voice' ? '<a class="join" href="?s=preflight">Take this part</a>' : '';
      return `<div class="lt-ln${l.id === 'L0130' ? ' now' : ''}" data-hue="${hueOf(p, l.role)}">${face(p, l.role, { size: 'sm' })}<div><div class="who">${esc(l.role)}<span class="tag">${esc(sp === 'You' ? 'Lou' : sp)}</span>${join}</div><p class="say">${sayHTML(l)}</p></div></div>`;
    }).join('');
    return `<div class="rec"><div class="lt-wrap">
      <div class="rec-top"><a class="icon-btn" href="?s=part" aria-label="Close">${I.down}</a><div class="t"><div class="part-name">Listen through</div></div><span class="count">4 of 12 parts</span></div>
      <section class="board head lt-head" data-genre="${p.genre}">${win(p.title)}<div class="head-text"><p class="kicker">Radio play</p><h1 class="board-name">${esc(p.title)}</h1><p class="credits">${esc(author(p))}</p></div>
        <div class="head-mark">${stripHTML}</div></section>
      <div class="lt-cast">${castHTML}</div>
      <div class="lt-lines">${lines}</div>
      <div class="transport"><button class="icon-btn" aria-label="Previous line">${I.prev}</button><button class="big" aria-label="Pause">${I.pause}</button><button class="icon-btn" aria-label="Next line">${I.next}</button></div>
      </div></div>`;
  }
  function preflight(on) {
    return `<div class="rec">${top('')}<div class="pre">
      <h2 class="disp">Headphones on</h2>
      <p class="why">They keep the other voices out of your take. This browser cannot tell whether they are on.</p>
      <button class="check" data-act="phones"><span class="box${on ? ' on' : ''}">${on ? I.check : ''}</span>My headphones are on</button>
      ${oppList()}
      <div class="go"><a class="btn btn-record${on ? '' : ' off'}" href="?s=ready"${on ? '' : ' aria-disabled="true"'}>${I.mic}Start recording</a></div></div></div>`;
  }

  /* ---- Routing and the live simulation ---- */
  const SCREENS = {
    pick, part, preflight: () => preflight(false), done, listen,
    ready: () => { ST.phase = 'ready'; return step(); },
    cue: () => { ST.phase = 'cue'; return step(); },
    recording: () => { ST.phase = 'rec'; return step(); },
    review: () => { ST.phase = 'review'; return step(); },
    run: () => runThrough('play'), 'run-recording': () => runThrough('rec'), 'run-review': runReview,
    lines: () => lineByLine(false), 'lines-recording': () => lineByLine(true),
  };
  /* The fit check's negative control: ?break=1 stacks the review buttons and puts an unbreakable word in a heading. */
  if (q.get('break')) {
    document.head.insertAdjacentHTML('beforeend', '<style>.dock.three,.dock.two{grid-template-columns:1fr!important}.btn{white-space:normal!important;max-width:60px}.seg label{white-space:normal!important;max-width:40px}.part{border-top:6px solid red}body[data-screen="lines"] .mode-row{padding-top:30px}</style>');
    rodney.title = 'Caesar Rodney\'s Ride Supercalifragilisticexpialidociousness';
  }
  let screen = q.get('s') || 'pick';
  const app = document.getElementById('app');
  const paint = (html) => { app.innerHTML = html; document.body.dataset.screen = screen; };
  paint((SCREENS[screen] || pick)());

  let timer = null;
  const live = () => paint(ST.mode === 'lines' ? lineByLine(ST.phase === 'rec') : step());
  function run(phase) {
    clearInterval(timer);
    ST.phase = phase;
    if (phase === 'cue' && ST.mode === 'step') {
      const cue = cueFor(MINE[ST.index]);
      if (!cue) return run('rec');
      ST.cue = 0;
      const dur = 600 + wordCount(cue) * 330, t0 = performance.now();
      timer = setInterval(() => { ST.cue = Math.min(1, (performance.now() - t0) / dur); live(); if (ST.cue >= 1) run('rec'); }, 80);
    } else if (phase === 'rec') {
      ST.rec = 0;
      const dur = 900 + wordCount(lineById(MINE[ST.index])) * 380, t0 = performance.now();
      timer = setInterval(() => { ST.rec = (performance.now() - t0) / 1000; live(); if (ST.rec * 1000 >= dur) run(ST.mode === 'lines' ? 'ready' : 'review'); }, 80);
    } else live();
  }
  app.addEventListener('click', (ev) => {
    const b = ev.target.closest('[data-act]');
    if (!b) return;
    const a = b.dataset.act;
    if (a === 'mode') { const v = b.value; screen = v; paint(v === 'run' ? runThrough('play') : v === 'lines' ? lineByLine(false) : (ST.phase = 'ready', step())); return; }
    if (a === 'phones') { paint(preflight(!app.querySelector('.box.on'))); return; }
    if (a === 'line') { ST.index = +b.dataset.i; run('ready'); return; }
    if (a === 'record' || a === 'again') run(ST.mode === 'lines' ? 'rec' : 'cue');
    else if (a === 'cancel') run('ready');
    else if (a === 'stop') run(ST.mode === 'lines' ? 'ready' : 'review');
    else if (a === 'keep') { if (ST.index + 1 >= MINE.length) { paint(done()); return; } ST.index++; run('ready'); }
    else if (a === 'prev') { ST.index = Math.max(0, ST.index - 1); run('ready'); }
    else if (a === 'next') { ST.index = Math.min(MINE.length - 1, ST.index + 1); run('ready'); }
    else if (a === 'listen') run('cue');
    else if (a === 'pause') paint(runReview());
    else if (a === 'speed') { ST.speed = ST.speed === '1×' ? '0.8×' : ST.speed === '0.8×' ? '1.2×' : '1×'; live(); }
  });
  window.addEventListener('keydown', (ev) => {
    if (!app.querySelector('.rec .dock')) return;
    const map = { ' ': ST.phase === 'rec' ? 'stop' : ST.phase === 'cue' ? 'cancel' : (ST.phase === 'ready' ? 'record' : null), Enter: ST.phase === 'review' ? 'keep' : null, r: ST.phase === 'review' ? 'again' : null, ArrowLeft: 'prev', ArrowRight: 'next' };
    const act = map[ev.key];
    if (!act) return;
    ev.preventDefault();
    const btn = app.querySelector(`[data-act="${act}"]`);
    if (btn && !btn.disabled) btn.click();
  });
})();
