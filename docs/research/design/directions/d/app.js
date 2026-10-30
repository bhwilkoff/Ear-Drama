/* Direction D, D2c-3: one grammar for every level of content (catalog-experience-design rule 11).
   Every object has one skeleton of fixed slots (data-slot): a show tile is window, name, mark, facts; a
   person is window, name, facts; a row is visual, body, length, play; a head board is window, kicker,
   name, facts, mark. The window always exists: the picture that leads (contract 3.3a: the show's own,
   then its star, then the person heard most), graded and mounted (uniform-imagery-design), else the
   title block (the initial cut large like wood type). Boards in their band, onBoard on them, marks for
   data (Decision 064). Data: window.ED (shared/sample.js), window.EDD (d/data.js), window.REC (plays). */
(function () {
  'use strict';
  const K = window.EDK, ED = K.ED, EDD = window.EDD, I = K.I, e = K.esc;
  const q = new URLSearchParams(location.search);
  const n = (x) => Number(x).toLocaleString('en-US');
  const TODAY = '2026-10-29';
  const REC = window.REC;
  const rodney = REC.plays.find((p) => p.id === 'gut-28051');
  const HUES = ['mystery', 'scifi', 'western', 'serial', 'documentary', 'comedy', 'news'];
  const hueOf = (play, name) => { const i = play.roles.findIndex((r) => r.name === name); return i >= 0 && i < HUES.length ? HUES[i] : 'news'; };
  const wave = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 12h2M7 8v8M11 5v14M15 8v8M19 10v4" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>';
  I.invite = '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="10" cy="8" r="4" stroke="currentColor" stroke-width="2" fill="none"/><path d="M3 20a7 7 0 0 1 14 0M19 8v6M16 11h6" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>';

  /* ---------- Series facts: the D2c-3 build (picture, run) over the sample's records ---------- */
  function seriesOf(key) {
    const b = EDD.series[key];
    const base = ED.popular.find((s) => s.key === key) || (key === 'suspense' ? ED.suspense : null) || (key === ED.sparse.key ? ED.sparse : null) || {};
    if (!b && !base.name) return null;
    return { key, ...base, ...(b || {}), name: (b && b.name) || base.name };
  }

  /* ---------- The grade: one SVG filter per measured picture (uniform-imagery-design §2) ---------- */
  const filters = new Map();
  function gradeFilter(url) {
    const g = EDD.grades[url];
    const k = g ? g.k : 1, o = g ? g.o : 0;
    const key = `${k}|${o}`;
    if (!filters.has(key)) filters.set(key, { id: `g${filters.size}`, k, o });
    return `url(#${filters.get(key).id})`;
  }
  const filterDefs = () => `<svg width="0" height="0" style="position:absolute" aria-hidden="true"><defs>${[...filters.values()].map((f) => {
    const fn = (c) => `<feFunc${c} type="linear" slope="${f.k}" intercept="${f.o}"/>`;
    return `<filter id="${f.id}" color-interpolation-filters="sRGB"><feColorMatrix type="saturate" values="0"/><feComponentTransfer>${fn('R')}${fn('G')}${fn('B')}</feComponentTransfer></filter>`;
  }).join('')}</defs></svg>`;

  /* ---------- The window: one slot, three fills ---------- */
  const cropPx = (art) => (EDD.grades[art.url] && EDD.grades[art.url].cropPx) || Math.round((K.cropRect(art) ? K.cropRect(art).h : 1) * art.height);
  /** The graded picture inside a window of about `slot` px, or null under the floor (uniform-imagery-design §4). */
  function picIn(art, slot) {
    if (!art || !art.url) return null;
    const r = K.cropRect(art);
    const filter = gradeFilter(art.url);
    if (!r) {
      if (Math.min(art.width, art.height) < slot / 2) return null;
      return { contain: true, html: `<img alt="" src="${e(K.artURL(art, slot * Math.max(1, K.aspect(art))))}" style="filter:${filter}">` };
    }
    if (cropPx(art) < slot) return null;
    const W = 100 / r.w, H = 100 / r.h;
    return { contain: false, html: `<img alt="" src="${e(K.artURL(art, slot / r.w))}" style="width:${W.toFixed(2)}%;height:${H.toFixed(2)}%;left:${(-r.x * W).toFixed(2)}%;top:${(-r.y * H).toFixed(2)}%;filter:${filter}">` };
  }
  /** A name whose longest word would not fit its slot steps down one type level (never a broken word). */
  const fitOf = (name) => { const L = Math.max(...String(name).split(/[\s\-–]+/).map((w) => w.length)); return L > 14 ? " xlong" : L > 10 ? " long" : ""; };
  const initialOf = (name) => (name || '?').replace(/^(The|A|An)\s+/i, '').replace(/^[^A-Za-z0-9]+/, '').trim().charAt(0).toUpperCase() || '?';
  /** The monogram: the initials of the first two words that start with a letter (articles skipped), else the first character. */
  const STOP = new Set(['the', 'a', 'an', 'of', 'and', '&', 'in', 'on', 'to', 'for', 'el', 'la', 'le', 'de', 'der', 'die']);
  function monogram(name) {
    const words = String(name || '').split(/[\s\-–/]+/).map((w) => w.replace(/^[^A-Za-z0-9]+/, '')).filter(Boolean);
    const lettered = words.filter((w) => /^[A-Za-z]/.test(w) && !STOP.has(w.toLowerCase()));
    const m = lettered.slice(0, 2).map((w) => w.charAt(0).toUpperCase()).join('');
    return m || initialOf(name);
  }
  /** The size that keeps the monogram inside the window: Big Shoulders capitals are about 0.48 em wide, M and W 0.62, I and 1 0.26; at most 104, so a cap stands inside the window. */
  const blockSize = (m) => Math.min(104, Math.floor(86 / [...m].reduce((a, c) => a + (/[MW]/.test(c) ? 0.62 : /[IJ1]/.test(c) ? 0.26 : 0.48) + 0.02, 0)));
  /** The title block: the monogram set large in the display face, standing on the window's foot like wood type. */
  function block(name, round) {
    const m = monogram(name);
    if (round) return `<svg viewBox="0 0 100 100" aria-hidden="true"><text x="50" y="${m.length > 1 ? 66 : 72}" text-anchor="middle" font-size="${m.length > 1 ? 50 : 60}">${e(m)}</text></svg>`;
    return `<svg viewBox="0 0 100 100" aria-hidden="true"><text x="9" y="93" font-size="${blockSize(m)}">${e(m)}</text></svg>`;
  }
  /** A window: `picture` is an art record (with kind) or null; `slot` its size in CSS px. */
  function win(name, picture, slot, { round = false } = {}) {
    const p = picIn(picture, slot);
    const kind = p ? (picture.kind || 'person') : 'block';
    const cls = ['win', round && 'round', !p && 'tb', p && p.contain && 'contain'].filter(Boolean).join(' ');
    return `<span class="${cls}" data-slot="window" data-kind="${kind}">${p ? p.html : block(name, round)}</span>`;
  }

  /* ---------- Marks ---------- */
  const FROM = 1930, TO = 1962;
  /** The run strip on one fixed axis, so every show's mark is the same object; undated: the baseline. */
  function run(hist, { h = 18, sel = null } = {}) {
    const ys = []; for (let y = FROM; y <= TO; y++) ys.push(y);
    const hh = hist || {};
    const max = Math.max(1, ...ys.map((y) => hh[y] || 0));
    const r = ys.map((y, i) => {
      const v = hh[y] || 0;
      if (!v) return `<rect class="z" x="${i * 10}" y="${h - 1}" width="8" height="1"/>`;
      const bh = Math.max(2, Math.round((v / max) * h));
      return `<rect class="b${sel && String(y) !== String(sel) ? ' dim' : ''}" x="${i * 10}" y="${h - bh}" width="8" height="${bh}"/>`;
    }).join('');
    const dated = Object.keys(hh).length;
    const peak = Object.entries(hh).sort((a, b) => b[1] - a[1])[0];
    return `<svg viewBox="0 0 ${ys.length * 10} ${h}" preserveAspectRatio="none" role="img" aria-label="${dated ? `Surviving episodes by year, ${FROM} to ${TO}, most in ${peak[0]}` : 'No dated episodes'}">${r}</svg>`;
  }
  /** Facts that wrap only between facts, each dot kept with the fact before it. */
  const facts = (xs) => { const v = xs.filter(Boolean); return v.map((x, i) => `<span class="nw">${e(x)}${i < v.length - 1 ? ' ·' : ''}</span>`).join(' '); };
  const years = (s) => (s.core ? K.coreYears(s.core) : 'Undated');
  /** The voice strip: the play in 48 bins, each as strong as its share of lines with a human voice. */
  function voiceStrip(play, humanParts) {
    const bins = play.roles[0].presence.length;
    return `<svg class="vs" viewBox="0 0 ${bins * 10} 18" preserveAspectRatio="none" role="img" aria-label="How much of the play has a human voice, start to end">${Array.from({ length: bins }, (_, i) => {
      const all = play.roles.reduce((a, r) => a + r.presence[i], 0) || 1;
      const v = play.roles.filter((r) => humanParts.has(r.name)).reduce((a, r) => a + r.presence[i], 0);
      const h = Math.max(1, Math.round(18 * v / all));
      return v ? `<rect class="b" x="${i * 10}" y="${18 - h}" width="8" height="${h}"/>` : `<rect class="z" x="${i * 10}" y="17" width="8" height="1"/>`;
    }).join('')}</svg>`;
  }

  /* ---------- The show tile: window, name, mark, facts (fixed, row-aligned by subgrid) ---------- */
  function tile(s, { href = '#', lines = null, sel = null } = {}) {
    const f = lines || [years(s), s.episodes ? `${n(s.episodes)} episodes` : null];
    return `<a class="tile" href="${href}" data-genre="${e(s.genre || '')}">
      ${win(s.name, s.picture, 160)}
      <span class="tile-name${fitOf(s.name)}" data-slot="name">${e(s.name)}</span>
      <span class="tile-mark" data-slot="mark">${run(s.hist, { sel })}</span>
      <span class="tile-facts" data-slot="facts">${f.filter(Boolean).map((x) => `<span>${x}</span>`).join('')}</span>
    </a>`;
  }
  const showHref = (k) => (k === 'suspense' ? '?s=series-rich' : '#');
  /* ---------- A person: window (circle), name, facts ---------- */
  const face = (p, href = '#') => `<a class="face" href="${href}">${win(p.name, p.art, 88, { round: true })}
      <span class="nm" data-slot="name">${e(p.name)}</span><span class="n" data-slot="facts">${p.episodes ? n(p.episodes) : ''}</span></a>`;
  /* ---------- A row: visual (48), body, length, play; 64 px whatever it carries ---------- */
  const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const dblock = (date, genre, num) => `<span class="vis dblock" data-slot="visual" data-genre="${e(genre)}">${date
    ? `<i>${MON[+date.slice(5, 7) - 1]}</i><b>${+date.slice(8, 10)}</b>` : `<i>No.</i><b>${e(num)}</b>`}</span>`;
  const visOf = (name, picture, genre) => `<span class="vis" data-slot="visual" data-genre="${e(genre || '')}">${win(name, picture, 48)}</span>`;
  const playDot = () => `<span class="play-dot" aria-hidden="true">${I.play}</span>`;
  const row = (href, vis, title, sub, len, { play = true } = {}) => `<li><${play ? `a href="${href}"` : 'div'} class="row${play ? '' : ' noplay'}">${vis}
      <span class="row-body"><span class="row-title">${title}</span>${sub ? `<span class="row-sub">${sub}</span>` : ''}</span>
      <span class="row-len">${len || ''}</span>${play ? playDot() : ''}</${play ? 'a' : 'div'}></li>`;

  /* ---------- The head board: window, kicker, name, facts, mark (series, episode, drama) ---------- */
  function head({ genre, name, picture, kicker, factsHTML, mark = '', tag = 'header', href = null, level = 'h1', round = false, credits = '' }) {
    const t = href ? 'a' : tag;
    return `<${t} class="board head" data-genre="${e(genre || '')}"${href ? ` href="${href}"` : ''}>
      ${win(name, picture, 200, { round })}
      <div class="head-text">
        <p class="kicker" data-slot="kicker">${kicker}</p>
        <${level} class="board-name${fitOf(name)}" data-slot="name">${e(name)}</${level}>
        ${credits ? `<p class="credits" data-slot="credits">${credits}</p>` : ''}
        <p class="facts" data-slot="facts">${factsHTML}</p>
      </div>
      ${mark ? `<div class="head-mark" data-slot="mark">${mark}</div>` : ''}
    </${t}>`;
  }
  const axis = (sel) => `<div class="axis"><span>${FROM}</span>${sel ? `<span>${e(sel)}</span>` : ''}<span>${TO}</span></div>`;

  /* ---------- The shell (Decision 068), every section a link ---------- */
  const NAV = [['home', 'Home', 'home'], ['browse', 'Browse', 'browse'], ['stations', 'Stations', 'stations'], ['surprise', 'Surprise', 'home'], ['search', 'Search', 'search'], ['library', 'Library', 'library']];
  function shell(active, main, { player = true } = {}) {
    return `<div class="ed-app">
      <nav class="ed-nav" aria-label="Sections"><a class="ed-wordmark" href="?s=home">Ear Drama</a>${NAV.map(([k, l, to]) =>
        `<a href="?s=${to}" class="ed-nav-item${k === active ? ' on' : ''}"${k === active ? ' aria-current="page"' : ''}>${I[k]}<span>${l}</span></a>`).join('')}</nav>
      <main class="ed-main">${main}</main>
      ${player ? `<a class="ed-mini" href="?s=now-playing">${mini()}</a>` : ''}
    </div>`;
  }
  function mini() {
    const r = ED.suspenseRich;
    return `<span class="mini-vis">${win('Hans Conried', r.credits[0].art, 40)}</span>
      <span class="row-body" style="flex:1"><span class="row-title">${e(r.title)}</span><span class="row-sub">Suspense</span></span>
      <span class="icon-btn icon-btn-primary" aria-label="Pause">${I.pause}</span>`;
  }
  const secH = (title, right = '') => `<div class="sec-h"><h2 class="l2">${title}</h2>${right}</div>`;
  const voices = (() => {
    const seen = new Set(); const out = [];
    for (const p of ED.faces) { if (seen.has(p.art && p.art.url)) continue; seen.add(p.art && p.art.url); out.push(p); }
    return out;
  })();
  const topbar = (href, label) => `<div class="top"><a class="back" href="${href}">${I.back}${e(label)}</a><a class="icon-btn way" href="#" aria-label="Share">${I.share}</a></div>`;

  /* A day's or a night's rows: shows first, copies folded (same title, same night), the tail counted. */
  const norm = (t) => String(t || '').toLowerCase().replace(/[^a-z0-9]+/g, '');
  function nightOf(rows, exceptId) {
    const seen = new Set(); const shows = []; let tail = 0;
    for (const r of rows) {
      if (r.id === exceptId) { seen.add(norm(r.title)); continue; }
      if (!r.show) { tail++; continue; }
      if (seen.has(norm(r.title))) continue;
      seen.add(norm(r.title)); shows.push(r);
    }
    return { shows, tail };
  }
  const nightTile = (r) => {
    const s = seriesOf(r.series) || { name: r.seriesName, genre: '' };
    return tile({ ...s, name: s.name || r.seriesName }, { href: '?s=episode-rich', sel: r.date && r.date.slice(0, 4), lines: [e(r.title), K.mins(r.length)] });
  };

  /* ---------- The finished ear dramas: fixtures on the real castable plays (D1c's fixture names) ---------- */
  const NAMES = ['Pat', 'Sam', 'Ada', 'Lou', 'Kim', 'Jo', 'Max', 'Ren', 'Tess', 'Abe'];
  const DRAMAS = ['gut-28051', 'gut-47826', 'gut-27357', 'gut-7364', 'gut-28527', 'gut-28511'].map((id, i) => {
    const p = REC.plays.find((x) => x.id === id);
    const big = p.roles.filter((r) => r.lines >= 6);
    const cast = p.roles.map((r, j) => ({ part: r.name, lines: r.lines, by: r.lines >= 6 ? NAMES[(i * 3 + big.indexOf(r)) % NAMES.length] : null }));
    const day = 29 - i * 3;
    return { id, play: p, cast, published: `2026-10-${String(day).padStart(2, '0')}`, director: cast[0].by };
  });
  const credited = (d) => { const who = [...new Set(d.cast.filter((c) => c.by).map((c) => c.by))]; return who.length > 3 ? `${who.slice(0, 3).join(', ')} and ${who.length - 3} more` : who.join(who.length === 2 ? ' and ' : ', '); };
  const humanOf = (d) => new Set(d.cast.filter((c) => c.by).map((c) => c.part));
  function dramaTile(d, href = '?s=drama') {
    return `<a class="tile" href="${href}" data-genre="${d.play.genre}">
      ${win(d.play.title, null, 160)}
      <span class="tile-name${fitOf(d.play.title)}" data-slot="name">${e(d.play.title)}</span>
      <span class="tile-mark" data-slot="mark">${voiceStrip(d.play, humanOf(d))}</span>
      <span class="tile-facts" data-slot="facts"><span>${e(credited(d))}</span><span>${K.fmtDate(d.published, 'medium')}</span></span>
    </a>`;
  }

  /* ================= Home ================= */
  function dayStrip(rows, sel) {
    const by = {};
    for (const r of rows) {
      const y = +r.date.slice(0, 4);
      const g = (seriesOf(r.series) || {}).genre || '';
      (by[y] = by[y] || {})[g] = (by[y][g] || 0) + 1;
    }
    const ys = Object.keys(by).map(Number);
    const from = 1930, to = Math.max(...ys);
    const tot = (y) => Object.values(by[y] || {}).reduce((a, b) => a + b, 0);
    const max = Math.max(...ys.map(tot));
    const H = 64, W = (to - from + 1) * 10;
    const ORDER = ['drama', 'mystery', 'comedy', 'serial', 'western', 'scifi', 'documentary', 'news', ''];
    let out = '';
    for (let y = from; y <= to; y++) {
      const x = (y - from) * 10;
      if (!by[y]) { out += `<rect class="z" x="${x}" y="${H - 1}" width="8" height="1"/>`; continue; }
      let top = H;
      for (const g of ORDER) {
        const v = by[y][g]; if (!v) continue;
        const h = (v / max) * (H - 4);
        top -= h;
        out += `<rect data-genre="${g}" x="${x}" y="${top.toFixed(1)}" width="8" height="${h.toFixed(1)}" style="fill:var(--genre-accent, var(--color-text-muted))"/>`;
      }
      if (String(y) === sel) out += `<rect class="sel" x="${x - 1.5}" y="${(top - 1.5).toFixed(1)}" width="11" height="${(H - top + 1.5).toFixed(1)}" rx="1"/>`;
    }
    const genresSeen = ORDER.filter((g) => g && ys.some((y) => by[y][g]));
    return { svg: `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" role="img" aria-label="Surviving broadcasts on this date by year, ${from} to ${to}">${out}</svg>`, from, to, genresSeen, years: ys.length };
  }
  function home() {
    const rows = ED.day.rows, sel = '1944';
    const st = dayStrip(rows, sel);
    const night = nightOf(rows.filter((r) => r.date.startsWith(sel)));
    const shows = EDD.top.slice(0, 12).map(seriesOf);
    return shell('home', `
      <section class="day">
        <p class="kicker">Thursday · This day in radio</p>
        <h1 class="l1">${K.fmtDate(TODAY, 'md')}</h1>
        <p class="facts muted">${facts([`${n(rows.length)} surviving broadcasts`, `${st.years} years`])}</p>
        <div class="yrs">${st.svg}<div class="axis"><span>${st.from}</span><span>1944</span><span>${st.to}</span></div></div>
        <div class="legend">${st.genresSeen.map((g) => `<span data-genre="${g}"><i></i>${e(K.genreName(g))}</span>`).join('')}</div>
      </section>
      <section class="sec">
        ${secH(K.fmtDate(`${sel}-10-29`, 'medium'), `<a class="l5" href="#">${night.tail} single recordings</a>`)}
        <div class="tiles six">${night.shows.slice(0, 6).map(nightTile).join('')}</div>
        <a class="more" href="#">All ${night.shows.length} shows that night</a>
      </section>
      <section class="sec">
        ${secH('Most heard', '<a class="l5" href="#">All voices</a>')}
        <div class="wall">${voices.slice(0, 8).map((p) => face(p)).join('')}</div>
      </section>
      <section class="sec">
        ${secH('Most downloaded', `<a class="l5" href="?s=browse">All ${n(EDD.tiers.shows)} shows</a>`)}
        <div class="tiles six">${shows.map((s) => tile(s, { href: showHref(s.key) })).join('')}</div>
      </section>
      <section class="sec">
        ${secH('New ear dramas', '<a class="l5" href="?s=dramas">All</a>')}
        <div class="tiles six">${DRAMAS.slice(0, 3).map((d) => dramaTile(d)).join('')}</div>
      </section>`);
  }

  /* ================= Browse ================= */
  function field() {
    const G = ['drama', 'mystery', 'comedy', 'serial', 'western', 'scifi', 'documentary', 'news'];
    const D = [1920, 1930, 1940, 1950, 1960];
    const v = (g, d) => (EDD.field.find((f) => f.genre === g && f.decade === d) || {}).shows || 0;
    const max = Math.max(...EDD.field.map((f) => f.shows));
    const headRow = `<span></span>${D.map((d) => `<span class="fh">${d}s</span>`).join('')}`;
    const body = G.map((g) => `<span class="fl" data-genre="${g}"><i></i><span>${e(K.genreName(g))}</span></span>${D.map((d) => {
      const x = v(g, d);
      const side = x ? Math.max(6, Math.round(32 * Math.sqrt(x / max))) : 0;
      return `<a class="fc" href="#" data-genre="${g}" aria-label="${e(K.genreName(g))}, ${d}s: ${x} shows">${x ? `<span class="sq" style="width:${side}px;height:${side}px"></span><span class="v">${x}</span>` : ''}</a>`;
    }).join('')}`).join('');
    return `<div class="field" role="grid">${headRow}${body}</div>`;
  }
  const browseSeg = (on) => `<div class="seg" role="tablist">${[['browse', 'Shows'], ['voices', 'Voices'], ['dramas', 'Ear dramas']].map(([k, l]) =>
    `<a role="tab" href="?s=${k === 'voices' ? 'browse' : k}"${k === on ? ' class="on" aria-selected="true"' : ''}>${l}</a>`).join('')}</div>`;
  function browse() {
    const t = EDD.tiers;
    return shell('browse', `
      <h1 class="l1 page-h">Browse</h1>
      ${browseSeg('browse')}
      <p class="count-line"><span class="l3 nw">${n(t.shows)} shows</span><a class="l5 nw" href="#">${n(t.singles)} single recordings</a></p>
      <div class="two browse-two">
        <section class="field-sec">
          ${secH('By decade and genre', `<span class="l5">${n(EDD.fieldUnsorted)} with no genre</span>`)}
          ${field()}
          <p class="l5" style="margin-top:var(--space-3)">By the year a show first aired</p>
        </section>
        <section class="sec shows-sec">
          ${secH('Most downloaded first', '<a class="l5" href="?s=shelf">A to Z</a>')}
          <div class="tiles">${EDD.top.map(seriesOf).map((s) => tile(s, { href: showHref(s.key) })).join('')}</div>
        </section>
      </div>`);
  }
  /* A to Z from B: the catalog as it is, 85% title blocks (D2c-2: 1,737 of 2,036 shows). */
  function shelf() {
    return shell('browse', `
      ${topbar('?s=browse', 'Browse')}
      <h1 class="l1 page-h">A to Z</h1>
      <p class="count-line"><span class="l3 nw">${n(EDD.tiers.shows)} shows</span></p>
      <div class="tiles six">${EDD.az.map(seriesOf).map((s) => tile(s)).join('')}</div>`);
  }

  /* ================= Series ================= */
  function seriesRich() {
    const s = seriesOf('suspense'), log = ED.suspense, sel = '1943';
    const count = new Map();
    for (const ep of log.season) for (const f of ep.faces || []) {
      const c = count.get(f.name) || { name: f.name, art: f.art, episodes: 0 };
      c.episodes++; count.set(f.name, c);
    }
    const heard = [...count.values()].sort((a, b) => b.episodes - a.episodes).slice(0, 6);
    const regular = new Set([...count.values()].filter((p) => p.episodes >= log.season.length / 4).map((p) => p.name));
    const rows = log.season.slice(0, 12).map((ep) => {
      const g = (ep.faces || []).find((x) => !regular.has(x.name) && picIn(x.art, 24));
      return row('?s=episode-rich', dblock(ep.date, s.genre), e(ep.title || `No. ${ep.num}`),
        g ? `<span class="guest">${win(g.name, g.art, 24, { round: true })}<span>${e(g.name)}</span></span>` : '', K.mins(ep.length));
    }).join('');
    return shell('browse', `
      ${topbar('?s=browse', 'Browse')}
      ${head({ genre: s.genre, name: s.name, picture: s.picture, kicker: facts([K.genreName(s.genre), s.networks]),
        factsHTML: facts([years(s), `${n(s.episodes)} episodes`]), mark: run(s.hist, { h: 56, sel }) + axis(`${sel}–44`) })}
      <div class="acts" data-slot="acts"><a class="btn btn-way" href="#">Follow</a></div>
      <div class="two">
        <section class="sec" data-slot="log">${secH('1943–44', `<span class="l5">${log.season.length} episodes</span>`)}<ol class="rows">${rows}</ol>
          <a class="more" href="#">All ${log.season.length}</a></section>
        <section class="sec" data-slot="heard">${secH('Heard most')}<div class="wall row6">${heard.map((p) => face(p)).join('')}</div></section>
      </div>`);
  }
  function seriesSparse() {
    const s = seriesOf(ED.sparse.key);
    const rows = ED.sparse.episodes.map((ep) => row('?s=episode-bare', dblock(null, s.genre, ep.num), e(ep.title), '', K.mins(ep.length))).join('');
    return shell('browse', `
      ${topbar('?s=browse', 'Browse')}
      ${head({ genre: s.genre, name: s.name, picture: s.picture, kicker: facts([K.genreName(s.genre), s.networks]),
        factsHTML: facts([years(s), `${n(s.episodes)} episodes`]), mark: run(s.hist, { h: 56 }) + axis(null) })}
      <div class="acts" data-slot="acts"><a class="btn btn-way" href="#">Follow</a></div>
      <div class="two">
        <section class="sec" data-slot="log">${secH('Episodes', `<span class="l5">${ED.sparse.episodes.length}</span>`)}<ol class="rows">${rows}</ol></section>
      </div>`);
  }

  /* ================= Episode: one skeleton, rich or bare ================= */
  function copies(recs) {
    const by = new Map();
    for (const r of recs) {
      const what = [r.variant && (ED.variantLines[r.variant] || r.variant), r.partial ? 'Incomplete' : 'Full broadcast'].filter(Boolean).join(' · ');
      const k = `${what}|${K.mins(r.length)}`;
      by.set(k, (by.get(k) || 0) + 1);
    }
    return [...by.entries()].map(([k, c]) => { const [what, len] = k.split('|'); return `<li class="cp"><span>${e(what)} · ${e(len)}</span><span class="l5">${c} ${c === 1 ? 'copy' : 'copies'}</span></li>`; }).join('');
  }
  function booklet(ep) {
    const g = K.creditGroups(ep.credits);
    const groups = Object.entries(g).filter(([, v]) => v.length).map(([k, v]) => `<p class="cr-h">${k}</p>${v.map((c) => `<div class="cr">
        ${win(c.name, c.art, 32, { round: true })}
        <span><a href="#" class="l3">${e(c.name)}</a>${c.character || c.roles.some((r) => r !== 'cast') ? `<span class="l5">${e(c.character ? `as ${c.character}` : c.roles.filter((r) => r !== 'cast').join(', '))}</span>` : ''}</span></div>`).join('')}`).join('');
    return `<div class="booklet" data-slot="booklet">
      ${ep.credits.length ? `<details><summary>Cast and credits <span class="l5">${ep.credits.length}</span></summary>${groups}<div style="height:12px"></div></details>` : ''}
      <details><summary>Copies <span class="l5">${ep.recordings.length}</span></summary><ul>${copies(ep.recordings)}</ul></details>
      <p class="rights">${e(ED.rightsLines.unclaimed)}</p></div>`;
  }
  function thatNight(rows, id) {
    const t = nightOf(rows, id);
    if (!t.shows.length) return '';
    return `<section class="sec" data-slot="night">${secH('That night on the radio', t.tail ? `<a class="l5" href="#">${t.tail} single recording${t.tail === 1 ? '' : 's'}</a>` : '')}
      <div class="tiles">${t.shows.slice(0, 6).map(nightTile).join('')}</div></section>`;
  }
  /** The window that leads an episode: the show's own image, then the episode's star, then the show's, then the block. */
  function leadOf(s, ep) {
    if (s.picture && s.picture.kind === 'show') return s.picture;
    const star = ep.credits.find((c) => c.art && c.role === 'cast');
    if (star) return { ...star.art, kind: 'person' };
    return s.picture || null;
  }
  function episode(ep, s, nightRows, back) {
    const air = K.facesOf(ep.credits, 6);
    return shell('browse', `
      ${topbar(back, s.name)}
      <div class="detail">
        <div class="detail-main">
          ${head({ genre: s.genre, name: s.name, picture: leadOf(s, ep), kicker: e(K.genreName(s.genre) || 'Show'), level: 'p', href: back,
            factsHTML: facts([years(s), `${n(s.episodes)} episodes`]) })}
          <h1 class="l1 ep-h1" data-slot="title">${e(ep.title)}</h1>
          <p class="event" data-slot="event">${facts(K.eventLine(ep))}</p>
          <div class="acts" data-slot="acts"><a class="btn btn-primary" href="?s=now-playing">${I.play}Play · ${K.mins(ep.length)}</a>
            <a class="btn btn-way" href="#" aria-label="Add to queue">${I.queue}<span class="lab-wide">Add to queue</span></a></div>
          ${air.length ? `<section class="sec" data-slot="air">${secH('On the air')}<div class="wall row6">${air.map((p) => face(p)).join('')}</div></section>` : ''}
        </div>
        <div class="detail-side">${thatNight(nightRows, ep.id)}${booklet(ep)}</div>
      </div>`);
  }
  const episodeRich = () => episode(ED.suspenseRich, seriesOf('suspense'), ED.sameNight, '?s=series-rich');
  const episodeBare = () => episode(ED.bare, seriesOf(ED.bareSeries.key), ED.sameNightBare, '#');

  /* ================= Now Playing ================= */
  function nowPlaying() {
    const ep = ED.suspenseRich, s = seriesOf('suspense');
    const lead = leadOf(s, ep);
    const who = lead && lead.kind !== 'show' ? ep.credits.find((c) => c.art && c.art.url === lead.url) : null;
    const faces = K.facesOf(ep.credits, 6);
    const night = nightOf(ED.sameNight, ep.id);
    const a = K.aspect(lead) || 1;
    const stage = lead ? `<span class="stage-pic" style="aspect-ratio:${a.toFixed(3)}"><img alt="" src="${e(K.artURL(lead, 320 * Math.max(1, a)))}"></span>` : block(s.name);
    return `<div class="np">
      <div class="top"><a class="icon-btn" href="?s=episode-rich" aria-label="Close">${I.down}</a><a class="icon-btn way" href="#" aria-label="Share">${I.share}</a></div>
      <div class="np-grid">
        <figure class="np-art"><span class="stage${lead ? '' : ' tb'}" data-genre="${e(s.genre)}" data-slot="window">${stage}</span>${who ? `<figcaption>${e(who.name)}</figcaption>` : ''}</figure>
        <div>
          <a class="chip-board" href="?s=series-rich" data-genre="${e(s.genre)}">${e(s.name)}</a>
          <h1 class="l1 ep-h1">${e(ep.title)}</h1>
          <p class="event">${facts(K.eventLine(ep))}</p>
          <div class="scrub"><span style="width:38%"></span></div>
          <div class="scrub-t l6 muted"><span>11:24</span><span>−18:26</span></div>
          <div class="transport"><button class="icon-btn" aria-label="Back 15 seconds">${I.r15}</button>
            <button class="np-play" aria-label="Pause">${I.pause}</button>
            <button class="icon-btn" aria-label="Forward 30 seconds">${I.f30}</button></div>
          <div class="acts opts"><button class="btn btn-way">1×</button><button class="btn btn-way" aria-label="Sleep timer">${I.moon}</button><button class="btn btn-way" aria-label="More">${I.more}</button></div>
        </div>
      </div>
      <section class="sec">${secH('On the air')}<div class="wall row6">${faces.map((p) => face(p)).join('')}</div></section>
      <section class="sec">${secH('That night on the radio')}<div class="tiles">${night.shows.slice(0, 4).map(nightTile).join('')}</div></section>
    </div>`;
  }

  /* ================= Search ================= */
  function search() {
    const qy = 'Conrad';
    const people = voices.filter((p) => p.name.includes(qy));
    const shows = EDD.top.map(seriesOf).filter((s) => (s.picture && (s.picture.who || '').includes(qy)) || (s.star || '').includes(qy) || s.name.includes(qy));
    const g = seriesOf('gunsmoke');
    const eps = ED.gunsmoke.sample.slice(0, 5).map((x) => row('#', visOf(g.name, g.picture, g.genre), e(x.title), facts([g.name, K.fmtDate(x.date)]), K.mins(x.length))).join('');
    return shell('search', `
      <h1 class="l1 page-h">Search</h1>
      <label class="search">${I.search}<input value="${qy}" aria-label="Search"></label>
      <section class="sec">${secH('Voices')}<div class="wall">${people.map((p) => face(p)).join('')}</div></section>
      <section class="sec">${secH('Shows', `<span class="l5">${shows.length}</span>`)}<div class="tiles six">${shows.map((s) => tile(s)).join('')}</div></section>
      <section class="sec">${secH('Episodes')}<ol class="rows">${eps}</ol></section>`);
  }

  /* ================= Stations ================= */
  function timeline(slots, { h = 28 } = {}) {
    const t0 = 18 * 60 + 30, t1 = 23 * 60;
    const m = (s) => { const [a, b] = s.split(':').map(Number); return a * 60 + b; };
    const r = slots.map((s) => {
      const x = m(s.et_start) - t0, w = Math.max(2, m(s.et_end) - m(s.et_start) - 2);
      if (s.episode) {
        const g = (seriesOf(s.episode.id.split('|')[0]) || {}).genre || '';
        return `<rect class="on" data-genre="${g}" x="${x}" y="0" width="${w}" height="${h}" rx="2"/>`;
      }
      if (s.known_series) return `<rect class="known" x="${x + 0.5}" y="0.5" width="${w - 1}" height="${h - 1}" rx="2"/>`;
      return `<rect class="gap" x="${x}" y="${h / 2 - 1}" width="${w}" height="2"/>`;
    }).join('');
    return `<svg viewBox="0 0 ${t1 - t0} ${h}" preserveAspectRatio="none" role="img" aria-label="The evening from 6:30 to 11:00 Eastern; filled slots survive">${r}</svg>
      <div class="axis"><span>6:30</span><span>8:00</span><span>9:30</span><span>11:00</span></div>`;
  }
  function slotRows(slots) {
    const out = []; let gap = null;
    for (const s of slots) {
      if (!s.episode && !s.known_series) { if (gap) gap.et_end = s.et_end; else gap = { ...s }; continue; }
      if (gap) { out.push(gap); gap = null; }
      out.push(s);
    }
    if (gap) out.push(gap);
    return out.map((s) => {
      const t = K.clock(s.et_start);
      if (s.episode) {
        const key = s.episode.id.split('|')[0], sr = seriesOf(key) || { name: s.episode.series, genre: '' };
        return row('#', visOf(sr.name, sr.picture, sr.genre), e(s.episode.series), facts([t, s.episode.title]), `${s.length_min} min`);
      }
      return row('#', '<span class="vis hatch" data-slot="visual"></span>', s.known_series ? e(s.known_series) : 'Not surviving',
        facts([t, s.known_series ? 'Not surviving' : `until ${K.clock(s.et_end)}`]), '', { play: false });
    }).join('');
  }
  function stations() {
    const ev = ED.evening;
    return shell('stations', `
      <h1 class="l1 page-h">Stations</h1>
      <section class="day">
        <p class="kicker">Tonight · ${e(ev.network)} · ${e(ev.station)}</p>
        <h2 class="l1">${K.fmtDate(ev.evening, 'long').replace(/, \d{4}$/, '')}</h2>
        <p class="facts muted">${K.fmtDate(ev.evening, 'year')} · Eastern time</p>
        <div class="tl">${timeline(ev.slots)}</div>
        <div class="acts"><a class="btn btn-primary" href="?s=now-playing">${I.play}Listen live</a></div>
      </section>
      <div class="two">
        <section class="sec"><ol class="rows">${slotRows(ev.slots)}</ol></section>
        <section class="sec">${secH(`October 29 on ${e(ev.station)}`)}
          <div class="evenings">${ev.years.map((y) => `<a class="evening" href="#"><span class="row-title">${K.fmtDate(y.evening, 'long')}</span>
            <div class="tl">${timeline(y.slots, { h: 18 })}</div>
            <span class="row-sub">${y.slots.filter((s) => s.episode).map((s) => e(s.episode.series)).join(' · ')}</span></a>`).join('')}</div></section>
      </div>`);
  }

  /* ================= Library (a fixture: the sample holds no personal data) ================= */
  const pface = (play, part, who) => who
    ? `<span class="pface" data-hue="${hueOf(play, part)}" aria-hidden="true">${e(who.charAt(0))}</span>`
    : `<span class="pface voice" data-hue="${hueOf(play, part)}" aria-hidden="true">${wave}</span>`;
  function library() {
    const r = ED.suspenseRich, g = seriesOf('gunsmoke'), s = seriesOf('suspense');
    const cont = [
      { name: 'Suspense', pic: leadOf(s, r), genre: 'mystery', title: r.title, left: '18 min left', p: 38, href: '?s=now-playing' },
      { name: g.name, pic: g.picture, genre: g.genre, title: ED.gunsmoke.sample[0].title, left: '22 min left', p: 24, href: '#' },
    ];
    const follow = ['suspense', 'gunsmoke', 'escape', 'dragnet', 'ourmissbrooks', 'xminusone'].map(seriesOf).filter(Boolean);
    const mine = { play: rodney, cast: [], published: null };
    return shell('library', `
      <h1 class="l1 page-h">Library</h1>
      <section>${secH('Continue listening')}<ol class="rows">${cont.map((c) => row(c.href, visOf(c.name, c.pic, c.genre), e(c.title),
        `${e(c.name)}<span class="progress"><span style="width:${c.p}%"></span></span>`, c.left)).join('')}</ol></section>
      <section class="sec">${secH('Your ear dramas', '<a class="l5" href="record.html?s=pick">Start one</a>')}
        <div class="tiles six">
          <a class="tile" href="record.html?s=ready" data-genre="${rodney.genre}">${win(rodney.title, null, 160)}
            <span class="tile-name${fitOf(rodney.title)}" data-slot="name">${e(rodney.title)}</span>
            <span class="tile-mark" data-slot="mark">${voiceStrip(rodney, new Set(['URIAH', 'FRANKLIN']))}</span>
            <span class="tile-facts" data-slot="facts"><span>RODNEY · you</span><span>5 of 76 lines</span></span></a>
          ${dramaTile(DRAMAS[1])}
        </div></section>
      <section class="sec">${secH('Following', `<span class="l5">${follow.length}</span>`)}<div class="tiles six">${follow.map((x) => tile(x, { href: showHref(x.key) })).join('')}</div></section>`);
  }

  /* ================= An ear drama: in progress (signed in), the invitation (signed out), finished ================= */
  function bill(play, cast, { signedOut = false, finished = false } = {}) {
    const words = Object.fromEntries(play.roles.map((r) => [r.name, r.words]));
    const list = [...cast].sort((a, b) => (words[b.part] || 0) - (words[a.part] || 0));
    return `<ul class="bill" data-slot="bill">${list.map((c) => {
      const hasTakes = c.by && (c.done == null || c.done > 0);
      const state = !c.by ? 'Device voice' : c.done != null && c.done < c.lines ? `${c.done} of ${c.lines} lines` : `${c.lines} ${c.lines === 1 ? 'line' : 'lines'}`;
      const act = hasTakes ? `<a class="play-dot" href="#" aria-label="Play ${e(c.by)}'s takes">${I.play}</a>`
        : finished ? '' : `<a class="btn btn-way take" href="${signedOut ? '?s=invite-join' : 'record.html?s=ready'}">Take part</a>`;
      return `<li><span class="bill-face">${pface(play, c.part, c.by)}</span>
        <span class="bill-body"><span class="part">${e(c.part)}</span><span class="by">${c.by ? `<b>${e(c.by)}</b>` : ''}<span class="l5">${e(state)}</span></span></span>${act}</li>`;
    }).join('')}</ul>`;
  }
  function dramaPage({ active = 'library', back = ['?s=library', 'Library'], kicker, play, cast, factsArr, credits, acts, signedOut = false, finished = false, extra = '', player = false }) {
    const human = new Set(cast.filter((c) => c.by && (c.done == null || c.done > 0)).map((c) => c.part));
    const ev = (ED.play.rights.evidence || [])[0];
    return shell(active, `
      ${topbar(back[0], back[1])}
      ${head({ genre: play.genre, name: play.title, picture: null, kicker, credits, factsHTML: facts(factsArr), mark: voiceStrip(play, human) })}
      <div class="acts" data-slot="acts">${acts}</div>
      <section class="sec" data-slot="cast">${secH('Cast', `<span class="l5">${cast.length} parts</span>`)}${bill(play, cast, { signedOut, finished })}</section>
      <p class="rights">Script: <a href="${e(ED.play.source.url)}">${e(ED.play.source.name)}</a>. ${e(ED.play.source.name)}'s claim: <a href="${e(ev.src)}">${e(ev.claim)}</a></p>
      ${extra}`, { player });
  }
  const prodCast = () => ED.production.cast.map((c) => ({ ...c }));
  const listenBtn = (label = "Listen through") => `<a class="btn btn-primary" href="record.html?s=listen">${I.play}<span>${label}<span class="dur">&nbsp;· ${K.aboutMin(rodney.words).replace("about ", "")}</span></span></a>`;
  const production = () => dramaPage({ kicker: 'Ear drama · in progress', play: rodney, cast: prodCast(),
    credits: `Directed by ${e(ED.production.director)}`, factsArr: [`Since ${K.fmtDate(ED.production.recorded[0], 'md')}`, '4 of 6 parts taken'],
    acts: `${listenBtn()}<a class="btn btn-way" href="#" aria-label="Invite">${I.invite}<span class="lab-wide">Invite</span></a>` });
  const invite = (extra = '') => dramaPage({ active: 'home', back: ['?s=home', 'Ear Drama'], kicker: 'Ear drama · in progress', play: rodney, cast: prodCast(),
    credits: `Directed by ${e(ED.production.director)}`, factsArr: [`Since ${K.fmtDate(ED.production.recorded[0], 'md')}`, '4 of 6 parts taken'],
    acts: listenBtn(), signedOut: true, extra });
  const inviteJoin = () => invite(`<div class="scrim" aria-hidden="true"></div><div class="sheet" role="dialog" aria-label="Take part">
      <p class="sheet-h">FRANKLIN</p><p>Taking a part needs an account.</p>
      <div class="acts sheet-acts"><a class="btn btn-primary" href="#">Sign in with Apple</a><a class="btn btn-way" href="#">Sign in with Google</a></div></div>`);
  function dramaFinished() {
    const d = DRAMAS[0];
    return dramaPage({ active: 'browse', back: ['?s=dramas', 'Ear dramas'], kicker: 'Ear drama · Radio play', play: d.play, cast: d.cast,
      credits: e(credited(d)), factsArr: [K.fmtDate(d.published, 'medium'), K.aboutMin(d.play.words).replace('about ', '')],
      acts: listenBtn('Listen'), finished: true, player: true });
  }
  function dramas() {
    return shell('browse', `
      <h1 class="l1 page-h">Browse</h1>
      ${browseSeg('dramas')}
      <p class="count-line"><span class="l3 nw">${DRAMAS.length} ear dramas</span><span class="l5 nw">Newest first</span></p>
      <div class="tiles six">${DRAMAS.map((d, i) => dramaTile(d, i === 0 ? '?s=drama' : '#')).join('')}</div>`);
  }

  const R = { home, browse, shelf, 'series-rich': seriesRich, 'series-sparse': seriesSparse, 'episode-rich': episodeRich,
    'episode-bare': episodeBare, 'now-playing': nowPlaying, search, stations, library, production, invite: () => invite(),
    'invite-join': inviteJoin, dramas, drama: dramaFinished };
  if (q.get('theme')) document.documentElement.dataset.theme = q.get('theme');
  const s = q.get('s') || 'home';
  const html = (R[s] || home)();
  document.getElementById('app').innerHTML = html + filterDefs();
  document.body.dataset.screen = s;
  /* The fit gate's negative control: ?break=1 must fail every check. */
  if (q.get('break')) {
    document.head.insertAdjacentHTML('beforeend', '<style>.acts{flex-wrap:wrap!important;max-width:150px}.btn{white-space:normal!important;max-width:72px}.board-name{word-break:break-all!important}h2.l2{text-wrap:wrap!important}body{min-width:1600px}.tile-mark{display:none}.tiles>.tile:nth-child(2)>.tile-facts{margin-top:9px}.board.head{border-left:6px solid var(--color-text)}.row:first-child .vis{display:none}body[data-screen="episode-bare"] .ep-h1{margin-top:40px}</style>');
    const t = document.querySelector('.tile-name'); if (t) t.textContent += ' Supercalifragilisticexpialidociousness';
    const b = document.querySelector('.board-name'); if (b) b.textContent += ' Supercalifragilisticexpialidociousness';
    const h = document.querySelector('h2.l2');
    if (h) {
      h.textContent = 'Shows by the year they first aired';
      const rg = document.createRange(); rg.selectNodeContents(h);
      h.style.width = `${Math.ceil(rg.getBoundingClientRect().width) + 2}px`; h.style.flex = 'none';
      h.textContent += ' a';
    }
  }
})();
