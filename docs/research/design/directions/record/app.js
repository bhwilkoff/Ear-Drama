/* D2b-2 Record a Line: a clickable prototype. No microphone and no speech:
   every state is simulated, and the level meter is a timer. ?s=<screen> opens a
   frozen frame for the screenshots; pressing a control runs the scene live.
   Every script word is the bundle's (data.js from catalog/plays/castable-scripts.json). */
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
    phones: '<svg viewBox="0 0 96 96" aria-hidden="true"><path d="M16 60V48a32 32 0 0 1 64 0v12" stroke="currentColor" stroke-width="6" fill="none" stroke-linecap="round"/><rect x="10" y="54" width="18" height="30" rx="7" fill="currentColor"/><rect x="68" y="54" width="18" height="30" rx="7" fill="currentColor"/></svg>',
    micOff: '<svg viewBox="0 0 96 96" aria-hidden="true"><rect x="36" y="12" width="24" height="44" rx="12" stroke="currentColor" stroke-width="6" fill="none"/><path d="M24 46a24 24 0 0 0 48 0M48 70v14" stroke="currentColor" stroke-width="6" fill="none" stroke-linecap="round"/><path d="M14 14l68 68" stroke="currentColor" stroke-width="6" stroke-linecap="round"/></svg>',
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
  const years = (a) => (a.born && a.died ? `${a.born}–${a.died}` : '');
  const byline = (p) => p.authors.length ? p.authors.map((a) => `${a.name}${years(a) ? ', ' + years(a) : ''}`).join(' and ') : 'Project Gutenberg';
  const bylineHTML = (p) => p.authors.length ? p.authors.map((a) => `<span class="nowrap">${esc(a.name)}${years(a) ? ', ' + years(a) : ''}</span>`).join(' and ') : 'Project Gutenberg';
  const longTitle = (t) => t.length > 34 || t.split(' ').some((w) => w.length > 12);
  const longName = (n) => n.split(' ').some((w) => w.length > 10) || n.length > 14;
  const fmtNum = (n) => n.toLocaleString('en-US');

  const rodney = plays.find((p) => p.id === 'gut-28051');
  /* The production on this device: who holds which part (names as typed). */
  const PROD = {
    URIAH: { who: 'Pat', done: true },
    FRANKLIN: { who: 'Ada', done: true },
    MCKEEN: { who: 'Sam', kept: 12 },
    RODNEY: { who: 'Lou', me: true, kept: 5 },
  };
  const roleOf = (name) => rodney.roles.find((r) => r.name === name);
  const initial = (who) => who.slice(0, 1).toUpperCase();

  function face(play, part, { size = '', ok = false, live = false, now = false } = {}) {
    const hue = hueOf(play, part);
    const c = play === rodney ? PROD[part] : null;
    if (c) return `<span class="face ${size}${live ? ' live' : ''}${now ? ' now' : ''}" data-hue="${hue}" aria-hidden="true">${esc(initial(c.who))}${ok ? `<span class="ok">${I.check}</span>` : ''}</span>`;
    return `<span class="face voice ${size}" data-hue="${hue}" aria-hidden="true">${I.wave}</span>`;
  }
  const speaker = (part) => {
    const c = PROD[part];
    if (c && c.me) return 'You';
    if (c && (c.done || c.kept)) return c.who;
    return 'Device voice';
  };
  const printBar = (play) => `<div class="print-bar" role="img" aria-label="${play.roles.length} parts by size">${
    play.roles.map((r) => `<i data-hue="${hueOf(play, r.name)}" style="flex:${r.words}"></i>`).join('')}</div>`;
  const presence = (play, r) => {
    const max = Math.max(1, ...r.presence);
    return `<div class="presence" data-hue="${hueOf(play, r.name)}" role="img" aria-label="Where ${esc(r.name)} speaks">${
      r.presence.map((v) => v ? `<i style="height:${Math.max(3, Math.round(18 * v / max))}px"></i>` : '<i class="z"></i>').join('')}</div>`;
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
  const keptBefore = (id) => MINE.indexOf(id);

  /* ---- The shell (Decision 068) ---- */
  const SECTIONS = [['home', 'Home'], ['browse', 'Browse'], ['stations', 'Stations'], ['surprise', 'Surprise'], ['search', 'Search'], ['library', 'Library']];
  const shell = (main) => `<div class="ed-app"><nav class="ed-nav" aria-label="Sections"><span class="ed-wordmark">Ear Drama</span>${
    SECTIONS.map(([k, l]) => `<a href="#" class="ed-nav-item${k === 'library' ? ' on' : ''}">${I[k]}<span>${l}</span></a>`).join('')
  }</nav><main class="ed-main">${main}</main></div>`;

  /* ---- Pick a play ---- */
  function playCard(p) {
    return `<a class="card" href="?s=part" data-hue="${p.genre}">
      <div class="top"><span class="kind">${p.radio ? 'Radio play' : 'Stage play'}</span>
        <span class="title disp${longTitle(p.title) ? ' long' : ''}">${esc(p.title)}</span>
        <span class="by">${bylineHTML(p)}</span></div>
      <div class="bottom">${printBar(p)}
        <div class="facts"><span class="l6">${minutes(p.words)} · ${p.roles.length} parts</span>
          <span class="faces">${p.roles.slice(0, 3).map((r) => `<span class="face xs" data-hue="${hueOf(p, r.name)}" title="${esc(r.name)}">${esc(r.name.replace(/^(MRS?\. |THE )/, '').slice(0, 1))}</span>`).join('')}</span></div>
      </div></a>`;
  }
  function pick() {
    const radio = plays.filter((p) => p.radio);
    const stage = plays.filter((p) => !p.radio);
    const cont = `<a class="cont" href="?s=ready" data-hue="${rodney.genre}">
      <div class="top"><span class="title disp" style="font:700 30px/1 var(--font-display)">${esc(rodney.title)}</span>
        <span class="faces">${Object.keys(PROD).map((k) => face(rodney, k, { size: 'sm' })).join('')}</span></div>
      <div class="row"><span class="mine">${face(rodney, 'RODNEY')}<span><b class="l3">RODNEY</b><span class="l5" style="display:block">5 of 76 lines</span></span></span>
        <span class="btn btn-primary nowrap">Continue</span></div></a>`;
    return shell(`<div class="pk-head"><h1 class="l1">Start an ear drama</h1></div>
      ${cont}
      <div class="pk-sec"><h2 class="l2">Radio plays</h2><span class="l5">Shortest first</span></div>
      <div class="pk-grid">${radio.map(playCard).join('')}</div>
      <div class="pk-sec"><h2 class="l2">Stage plays</h2><span class="l5">Shortest first</span></div>
      <div class="pk-grid">${stage.map(playCard).join('')}</div>`);
  }

  /* ---- Claim a part: the playbill ---- */
  function partCard(r) {
    const c = PROD[r.name];
    const hue = hueOf(rodney, r.name);
    const open = !c;
    const suggested = r.name === 'ANNOUNCER';
    let who;
    if (c && c.me) who = `${face(rodney, r.name, { size: 'sm' })}<span class="st"><b>You</b><span>${c.kept} of ${r.lines}</span></span>`;
    else if (c && c.done) who = `${face(rodney, r.name, { size: 'sm', ok: true })}<span class="st"><b>${esc(c.who)}</b><span>Recorded</span></span>`;
    else if (c) who = `${face(rodney, r.name, { size: 'sm' })}<span class="st"><b>${esc(c.who)}</b><span>${c.kept} of ${r.lines}</span></span>`;
    else who = `<span class="face voice sm" data-hue="${hue}" aria-hidden="true">${I.wave}</span><span class="muted">Device voice</span>`;
    const action = c && c.me ? `<a class="btn btn-primary" href="?s=ready">Continue</a>`
      : open ? `<a class="btn ${suggested ? 'btn-ink-outline' : 'btn-way'}" href="?s=preflight">Take part</a>` : '';
    return `<div class="part${c && c.me ? ' mine' : ''}" data-hue="${hue}">
      <span class="nm disp${longName(r.name) ? ' long' : ''}">${esc(r.name)}</span>
      <span class="l6 two"><span>${minutes(r.words)}</span><span>${r.lines} ${r.lines === 1 ? 'line' : 'lines'}</span></span>
      ${presence(rodney, r)}
      <span class="who">${who}</span>${action}</div>`;
  }
  function part() {
    const p = rodney;
    return shell(`<a href="?s=pick" class="l5" style="display:inline-flex;align-items:center;gap:4px;color:var(--color-link);margin-bottom:var(--space-3)"><span style="width:18px;height:18px;display:inline-block">${I.back}</span>Start an ear drama</a>
      <section class="pb-hero" data-hue="${p.genre}"><span class="kind">Radio play</span>
        <h1 class="disp">${esc(p.title)}</h1><span class="by">${bylineHTML(p)}</span><span class="by"><span class="nowrap">${minutes(p.words)}</span> · <span class="nowrap">${p.roles.length} parts</span></span>
        ${printBar(p)}
        <a class="rights" href="${esc(p.source)}">${esc(p.rights)} · Project Gutenberg</a></section>
      <div class="pb-actions"><a class="btn btn-primary" href="?s=listen">${I.play}Listen through</a><a class="btn btn-way" href="#">Invite</a></div>
      <div class="pb-as"><span>Recording as <b>Lou</b></span><a href="#" class="l3" style="color:var(--color-link)">Change</a></div>
      <div class="pb-grid">${p.roles.map(partCard).join('')}</div>`);
  }

  /* ---- The record screen ---- */
  const ST = { index: MINE.indexOf('L0118'), phase: 'ready', cue: 0.62, rec: 2.1, takes: [], speed: '1×', flagged: false, interrupted: null };
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
  function meterBars(seconds, maxBars) {
    const n = Math.min(maxBars, Math.round(seconds * 14));
    const r = seeded(n, 7);
    return r.map((v, i) => {
      const env = Math.min(1, i / 4) * (0.55 + 0.45 * Math.sin(i / 3.1) ** 2);
      return `<i style="height:${Math.round(6 + 34 * env * (0.6 + 0.4 * v))}px"></i>`;
    }).join('');
  }
  function takeWave(n, seed) {
    return seeded(n, seed).map((v, i) => `<i style="height:${Math.round(4 + 24 * (0.35 + 0.65 * Math.sin(i / 2.7) ** 2) * (0.5 + 0.5 * v))}px"></i>`).join('');
  }
  function partnersNear(id) {
    const k = L.findIndex((l) => l.id === id);
    const seen = [];
    for (const l of L.slice(Math.max(0, k - 12), k + 24)) if (l.role !== 'RODNEY' && l.role !== 'ANNOUNCER' && !seen.includes(l.role)) seen.push(l.role);
    return seen;
  }
  function oppRow(id) {
    return partnersNear(id).map((r) => `<span class="p">${face(rodney, r, { size: 'xs' })}<b>${esc(r)}</b><span class="muted">${esc(speaker(r))}</span></span>`).join('');
  }
  function lineBlock(line, cls, extra = '') {
    const sp = speaker(line.role);
    return `<div class="ln ${cls}">${face(rodney, line.role, { size: 'sm' })}<div><div class="who">${esc(line.role)}<span class="tag">${esc(sp)}</span>${extra}</div><p class="say">${sayHTML(line)}</p></div></div>`;
  }

  function stage() {
    const id = MINE[ST.index];
    const me = lineById(id);
    const k = L.findIndex((l) => l.id === id);
    const cue = cueFor(id);
    const before = L.slice(Math.max(0, k - (cue ? 2 : 1)), cue ? k - 1 : k).slice(-1);
    const after = L[k + 1];
    const out = [];
    for (const b of before) out.push(lineBlock(b, 'past', b.role === 'RODNEY' ? `<span class="tag" style="display:inline-flex;align-items:center;gap:2px"><span style="width:14px;height:14px;display:inline-block">${I.check}</span>Take 2</span>` : ''));
    if (cue) {
      const playing = ST.phase === 'cue';
      let say = sayHTML(cue, playing);
      if (playing) {
        const n = wordCount(cue);
        const lit = Math.round(n * ST.cue);
        let i = 0;
        say = say.replace(/<span class="w">/g, () => (i++ < lit ? '<span class="w lit">' : '<span class="w">'));
      }
      out.push(`<div class="cue" data-hue="${hueOf(rodney, cue.role)}">${lineBlock(cue, 'cur').replace('class="say">' + sayHTML(cue), 'class="say">' + say)}${playing ? `<span class="stream" style="--p:${Math.round(ST.cue * 100)}%"></span>` : ''}</div>`);
    }
    const ph = ST.phase;
    let head = `<span>RODNEY · You</span>`;
    let body = '';
    let cls = '';
    if (ph === 'cue') { cls = ' armed'; head += `<span class="pill redo"><span class="dot"></span>Next</span>`; }
    if (ph === 'rec') {
      cls = ' on';
      head += `<span class="pill red" role="status"><span class="dot"></span>Recording 0:0${Math.floor(ST.rec)}</span>`;
      body = `<div class="meter" aria-hidden="true">${meterBars(ST.rec, 60)}</div>`;
    }
    if (ph === 'review' || ph === 'flagged') {
      const n = ph === 'flagged' ? 1 : 2;
      head += `<span class="takes" aria-label="Takes">${Array.from({ length: n }, (_, i) => `<span class="t${i === n - 1 ? (ph === 'flagged' ? ' flag' : ' on') : ''}">${i + 1}</span>`).join('')}</span>`;
      body = `<div class="take"><button class="play-dot" aria-label="Play take ${n}">${I.play}</button><div class="wave" aria-hidden="true">${takeWave(44, n * 13)}</div><span class="l6">${ph === 'flagged' ? '3.4' : '3.1'} s</span></div>`;
      if (ph === 'flagged') body += `<div class="warn" role="alert">${I.warn}<span>The microphone heard the device voice. Record it again with headphones on.</span></div>`;
    }
    out.push(`<div class="mine-ln${cls}" data-hue="${hueOf(rodney, 'RODNEY')}"><div class="who">${head}</div><p class="big say">${sayHTML(me)}</p>${body}</div>`);
    if (after) out.push(lineBlock(after, 'next'));
    return out.join('');
  }

  function dock() {
    const ph = ST.phase;
    if (ph === 'review' || ph === 'flagged') {
      return `<div class="dock three">
        <button class="btn btn-again" data-act="again"><span class="dot"></span>Again</button>
        <button class="btn btn-way" data-act="listen">${I.play}With cue</button>
        <button class="btn btn-primary" data-act="keep"${ph === 'flagged' ? ' disabled' : ''}>${I.check}Keep</button></div>`;
    }
    const first = ST.index === 0;
    const last = ST.index === MINE.length - 1;
    const busy = ph === 'cue' || ph === 'rec';
    const center = ph === 'cue'
      ? `<button class="recbtn armed" data-act="cancel" aria-label="Cancel">${I.mic}</button><span class="lab">Cancel</span>`
      : ph === 'rec'
        ? `<button class="recbtn stop" data-act="stop" aria-label="Stop">${I.stop}</button><span class="lab">Stop</span>`
        : `<button class="recbtn" data-act="record" aria-label="Record">${I.mic}</button><span class="lab">Record</span>`;
    return `<div class="dock">
      <div class="side"><button class="icon-btn" data-act="prev" aria-label="Previous line"${first || busy ? ' disabled' : ''}>${I.prev}</button></div>
      <div style="display:flex;flex-direction:column;align-items:center">${center}</div>
      <div class="side"><button class="icon-btn" data-act="next" aria-label="Next line"${last || busy ? ' disabled' : ''}>${I.next}</button></div></div>`;
  }
  const aids = () => {
    const busy = ST.phase === 'cue' || ST.phase === 'rec';
    return `<div class="aids"><button class="aid" data-act="runup"${busy ? ' disabled' : ''}>${I.runup}Run-up</button><button class="aid" data-act="hear"${busy ? ' disabled' : ''}>${I.ear}Hear it read</button><button class="aid" data-act="speed"${busy ? ' disabled' : ''}>${I.speed}${ST.speed}</button></div>`;
  };
  function strip(play, part, kept, current, recOn) {
    const r = play.roles.find((x) => x.name === part);
    return `<div class="strip" data-hue="${hueOf(play, part)}" role="img" aria-label="${kept} of ${r.lines} lines kept">${
      Array.from({ length: r.lines }, (_, i) => `<i class="${i === current ? 'c' + (recOn ? ' rec-on' : '') : i < kept ? 'k' : ''}"></i>`).join('')}</div>`;
  }
  function top(sub, count) {
    return `<div class="rec-top"><a class="icon-btn" href="?s=part" aria-label="Close">${I.down}</a>
      <div class="t"><div class="part-name">RODNEY</div><div class="play">${esc(sub)}</div></div><span class="count">${count}</span></div>`;
  }
  function rails() {
    const id = MINE[ST.index];
    const near = partnersNear(id);
    const left = `<aside class="rail l"><h3>In this scene</h3>${
      [`<div class="r1">${face(rodney, 'RODNEY', { size: 'lg', live: ST.phase === 'rec' })}<span><span class="nm">RODNEY</span><span class="l5">You · Lou</span></span></div>`]
        .concat(near.map((r) => `<div class="r1">${face(rodney, r, { size: 'lg' })}<span><span class="nm">${esc(r)}</span><span class="l5">${esc(speaker(r))}</span></span></div>`)).join('')}</aside>`;
    const right = `<aside class="rail r"><h3>This line</h3>
      <div class="aids" style="flex-direction:column;align-items:stretch;padding:0">${aids().replace('<div class="aids">', '').replace(/<\/div>$/, '')}</div>
      <h3>Keys</h3><div class="keys"><kbd>Space</kbd><span>Record or stop</span><kbd>Return</kbd><span>Keep</span><kbd>R</kbd><span>Again</span><kbd>← →</kbd><span>Line</span></div></aside>`;
    return left + right;
  }
  function record() {
    const id = MINE[ST.index];
    const kept = ST.index + (ST.phase === 'review' ? 0 : 0);
    return `<div class="rec" data-screen="record">
      ${top(rodney.title, `${kept} of ${MINE.length}`)}
      ${strip(rodney, 'RODNEY', kept, ST.index, ST.phase === 'rec')}
      <div class="opp" aria-label="Opposite you">${oppRow(id)}</div>
      <div class="stage" aria-live="polite">${stage()}</div>
      ${aids()}
      ${dock()}
      ${rails()}</div>`;
  }

  /* ---- Before the first take ---- */
  function oppList() {
    return `<div class="opp-list">${partnersNear('L0108').map((r) => `<div class="r">${face(rodney, r, { size: 'sm' })}<span class="nm">${esc(r)}</span><span class="${speaker(r) === 'Device voice' ? 'muted' : ''}">${esc(speaker(r))}</span></div>`).join('')}</div>`;
  }
  function preflight(on) {
    return `<div class="rec">${top(rodney.title, '')}<div class="pre">
      <div class="art">${I.phones}</div><h2 class="disp">Headphones on</h2>
      <p class="why">They keep the other voices out of your take. This browser cannot tell whether they are on.</p>
      <button class="check" data-act="phones"><span class="box${on ? ' on' : ''}">${on ? I.check : ''}</span>My headphones are on</button>
      ${oppList()}
      <div class="go"><a class="btn ${on ? 'btn-record' : 'btn-record" aria-disabled="true" style="opacity:.4;pointer-events:none'}" href="?s=roomtone">${I.mic}Start recording</a></div></div></div>`;
  }
  function denied() {
    return `<div class="rec">${top(rodney.title, '')}<div class="pre">
      <div class="art" style="color:var(--color-text-muted)">${I.micOff}</div><h2 class="disp">No microphone</h2>
      <div class="warn err" role="alert">${I.warn}<span>Ear Drama needs the microphone to record your part. Allow it for this site in the browser's settings.</span></div>
      <div class="go"><a class="btn btn-way" href="?s=preflight">Try again</a></div></div></div>`;
  }
  function roomtone() {
    const left = 3; const frac = (5 - left) / 5;
    const C = 2 * Math.PI * 92;
    return `<div class="rec">${top(rodney.title, '')}<div class="tone" role="status">
      <span class="pill red"><span class="dot"></span>Recording the room</span>
      <div class="ring"><svg viewBox="0 0 200 200" aria-hidden="true"><circle cx="100" cy="100" r="92" stroke="var(--color-border)" stroke-width="8" fill="none"/><circle cx="100" cy="100" r="92" stroke="var(--color-record)" stroke-width="8" fill="none" stroke-linecap="round" stroke-dasharray="${C}" stroke-dashoffset="${C * (1 - frac)}"/></svg><span class="n">${left}</span></div>
      <h2 class="disp">Quiet, please</h2></div></div>`;
  }
  function interrupted() {
    ST.phase = 'ready';
    const rec = record();
    return rec.replace('<div class="stage" aria-live="polite">', `<div class="stage" aria-live="polite"><div class="warn" role="alert">${I.warn}<span>Your headphones came out. That take was not kept.</span></div>`);
  }
  function done() {
    const cast = rodney.roles.slice(0, 7);
    return `<div class="rec"><div class="done-wrap">${top(rodney.title, '76 of 76')}
      <section class="done-hero" data-hue="serial"><span class="big disp">RODNEY</span><span class="sub">${I.check}Recorded by you · 76 lines</span></section>
      <div class="done-cast"><h2 class="l2">The cast so far</h2><div class="faces-row">${cast.map((r) => {
        const c = PROD[r.name];
        const ok = r.name === 'RODNEY' || (c && c.done);
        return `<span class="fc">${face(rodney, r.name, { size: 'lg', ok })}<b>${esc(r.name)}</b><span class="muted">${c ? esc(c.me ? 'You' : c.who) : 'Open'}</span></span>`;
      }).join('')}</div><span class="l5">${rodney.roles.length - 7} more parts</span></div>
      <div class="done-act"><a class="btn btn-primary" href="?s=listen">${I.play}Listen through</a><a class="btn btn-way" href="?s=part">Pass the phone</a></div>
      <div class="next-part" data-hue="western"><span><span class="nm">ANNOUNCER</span><span class="l5" style="display:block">Open · about 4 min · 10 lines</span></span><a class="btn btn-way" href="?s=preflight">Take part</a></div>
      </div></div>`;
  }

  /* ---- Listen through ---- */
  function listen() {
    const p = rodney;
    const now = L.findIndex((l) => l.id === 'L0130');
    const span = L.slice(now - 2, now + 4);
    const total = scene.total;
    const humanParts = new Set(['URIAH', 'FRANKLIN', 'RODNEY']);
    const human = ['URIAH', 'FRANKLIN', 'RODNEY', 'MCKEEN'];
    const bins = p.roles[0].presence.length;
    const at = Math.floor(scene.speechIndex.L0130 * bins / total);
    const stripHTML = Array.from({ length: bins }, (_, i) => {
      const all = p.roles.reduce((n, r) => n + r.presence[i], 0) || 1;
      const mine = p.roles.filter((r) => human.includes(r.name)).reduce((n, r) => n + r.presence[i], 0);
      return i === at ? '<i class="here"></i>' : `<i style="opacity:${(0.18 + 0.82 * mine / all).toFixed(2)}"></i>`;
    }).join('');
    const castHTML = p.roles.slice(0, 7).map((r) => {
      const c = PROD[r.name];
      const human = humanParts.has(r.name) || (c && c.kept);
      return `<span class="fc">${face(p, r.name, { size: '', now: r.name === 'URIAH' })}${esc(r.name)}</span>`;
    }).join('');
    const lines = span.map((l, i) => {
      const isNow = l.id === 'L0130';
      const sp = speaker(l.role);
      const voice = sp === 'Device voice';
      const join = voice ? `<a class="join" href="?s=preflight">Take this part</a>` : '';
      return `<div class="lt-ln${isNow ? ' now' : ''}" data-hue="${hueOf(p, l.role)}">${face(p, l.role, { size: 'sm' })}<div><div class="who">${esc(l.role)}<span class="tag">${esc(sp === 'You' ? 'Lou' : sp)}</span>${join}</div><p class="say">${sayHTML(l)}</p></div></div>`;
    }).join('');
    return `<div class="rec"><div class="lt-wrap" style="display:flex;flex-direction:column;flex:1">
      <div class="rec-top"><a class="icon-btn" href="?s=part" aria-label="Close">${I.down}</a><div class="t"><div class="part-name">Listen through</div></div><span class="count">4 of 12 parts</span></div>
      <section class="lt-head" data-hue="${p.genre}"><h1 class="disp">${esc(p.title)}</h1><span class="by">${bylineHTML(p)}</span>
        <div class="lt-strip" role="img" aria-label="Recorded and device-voice lines across the play">${stripHTML}</div></section>
      <div class="lt-cast">${castHTML}</div>
      <div class="lt-lines">${lines}</div>
      <div class="transport"><button class="icon-btn" aria-label="Previous line">${I.prev}</button><button class="big" aria-label="Pause">${I.pause}</button><button class="icon-btn" aria-label="Next line">${I.next}</button></div>
      </div></div>`;
  }

  /* ---- Routing and the live simulation ---- */
  const SCREENS = {
    pick, part, preflight: () => preflight(q.get('phones') === '1'), 'preflight-on': () => preflight(true), denied, roomtone,
    ready: () => { ST.phase = 'ready'; return record(); },
    cue: () => { ST.phase = 'cue'; return record(); },
    recording: () => { ST.phase = 'rec'; return record(); },
    review: () => { ST.phase = 'review'; return record(); },
    flagged: () => { ST.phase = 'flagged'; return record(); },
    interrupted, done, listen,
  };
  /* The fit check's negative control: ?break=1 stacks the review buttons and puts an unbreakable word in a heading. */
  if (q.get('break')) {
    document.head.insertAdjacentHTML('beforeend', '<style>.dock.three{grid-template-columns:1fr!important}.btn{white-space:normal!important;max-width:60px}</style>');
    rodney.title = 'Caesar Rodney\'s Ride Supercalifragilisticexpialidociousness';
  }
  let screen = q.get('s') || 'pick';
  const app = document.getElementById('app');
  function paint(html) { app.innerHTML = html; document.body.dataset.screen = screen; }
  paint((SCREENS[screen] || pick)());

  let timer = null;
  const live = () => { screen = 'live'; paint(record()); };
  function run(phase) {
    clearInterval(timer);
    ST.phase = phase;
    if (phase === 'cue') {
      const cue = cueFor(MINE[ST.index]);
      if (!cue) return run('rec');
      ST.cue = 0;
      const dur = 600 + wordCount(cue) * 330;
      const t0 = performance.now();
      timer = setInterval(() => { ST.cue = Math.min(1, (performance.now() - t0) / dur); live(); if (ST.cue >= 1) run('rec'); }, 80);
    } else if (phase === 'rec') {
      ST.rec = 0;
      const dur = 900 + wordCount(lineById(MINE[ST.index])) * 380;
      const t0 = performance.now();
      timer = setInterval(() => { ST.rec = (performance.now() - t0) / 1000; live(); if (ST.rec * 1000 >= dur) run('review'); }, 80);
    } else live();
  }
  app.addEventListener('click', (e) => {
    const b = e.target.closest('[data-act]');
    if (!b) return;
    const a = b.dataset.act;
    if (a === 'phones') { screen = 'preflight-on'; paint(preflight(!app.querySelector('.box.on'))); return; }
    if (a === 'record' || a === 'again') run('cue');
    else if (a === 'cancel') run('ready');
    else if (a === 'stop') run('review');
    else if (a === 'keep') { if (ST.index + 1 >= MINE.length) { screen = 'done'; paint(done()); return; } ST.index++; run('cue'); }
    else if (a === 'prev') { ST.index = Math.max(0, ST.index - 1); run('ready'); }
    else if (a === 'next') { ST.index = Math.min(MINE.length - 1, ST.index + 1); run('ready'); }
    else if (a === 'listen') run('cue');
    else if (a === 'speed') { ST.speed = ST.speed === '1×' ? '0.8×' : ST.speed === '0.8×' ? '1.2×' : '1×'; live(); }
  });
  window.addEventListener('keydown', (e) => {
    if (!app.querySelector('.rec .dock')) return;
    const map = { ' ': ST.phase === 'rec' ? 'stop' : ST.phase === 'cue' ? 'cancel' : (ST.phase === 'ready' ? 'record' : null), Enter: ST.phase === 'review' ? 'keep' : null, r: ST.phase === 'review' || ST.phase === 'flagged' ? 'again' : null, ArrowLeft: 'prev', ArrowRight: 'next' };
    const act = map[e.key];
    if (!act) return;
    e.preventDefault();
    const btn = app.querySelector(`[data-act="${act}"]`);
    if (btn && !btn.disabled) btn.click();
  });
})();
