/* Direction D: one cohesive design from the owner's D2 feedback (2026-10-29).
   Pictures lead (The Company), graded and mounted as one set (uniform-imagery-design);
   genre boards and big display type carry the structure (The Sleeve); run strips, the
   day's years and the decade field where the data supports them (The Almanac).
   Data: window.ED (shared/sample.js), window.EDD (d/data.js: series facts and measured
   grades), window.REC (record/data.js: the castable plays and their part hues). */
(function () {
  'use strict';
  const K = window.EDK, ED = K.ED, EDD = window.EDD, I = K.I, e = K.esc;
  const q = new URLSearchParams(location.search);
  const n = (x) => Number(x).toLocaleString('en-US');
  const TODAY = '2026-10-29';
  const REC = window.REC;
  const rodney = REC.plays.find((p) => p.id === 'gut-28051');
  const HUES = ['mystery', 'scifi', 'western', 'serial', 'documentary', 'comedy', 'news'];
  const hueOf = (name) => { const i = rodney.roles.findIndex((r) => r.name === name); return i >= 0 && i < HUES.length ? HUES[i] : 'news'; };
  const wave = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 12h2M7 8v8M11 5v14M15 8v8M19 10v4" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>';

  /* ---------- Series facts: the sample's records first, then the series index ---------- */
  const seriesOf = (key) => ED.popular.find((s) => s.key === key) || (key === 'suspense' ? ED.suspense : null) || (EDD.series[key] && { key, ...EDD.series[key] }) || null;

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

  /* The crop's side in source pixels, measured; the floor is cropPx >= the slot (§4). */
  const cropPx = (art) => (EDD.grades[art.url] && EDD.grades[art.url].cropPx) || Math.round((K.cropRect(art) ? K.cropRect(art).h : 1) * art.height);
  /** A graded picture in a repeated square slot of about `slot` px, or null under the floor. */
  function pic(art, slot, round = false) {
    if (!art || !art.url) return null;
    const r = K.cropRect(art);
    const filter = gradeFilter(art.url);
    if (!r) {
      if (art.width < slot) return null;
      return `<span class="pic contain${round ? ' round' : ''}"><img alt="" src="${e(K.artURL(art, slot * Math.max(1, K.aspect(art))))}" style="filter:${filter}"></span>`;
    }
    if (cropPx(art) < slot) return null;
    const W = 100 / r.w, H = 100 / r.h;
    return `<span class="pic${round ? ' round' : ''}"><img alt="" src="${e(K.artURL(art, slot / r.w))}" style="width:${W.toFixed(2)}%;height:${H.toFixed(2)}%;left:${(-r.x * W).toFixed(2)}%;top:${(-r.y * H).toFixed(2)}%;filter:${filter}"></span>`;
  }
  const initialOf = (name) => (name || '?').replace(/^(The|A|An)\s+/i, '').replace(/^['"]/, '').trim().charAt(0).toUpperCase();
  const faceArt = (name, art, slot) => pic(art, slot, true) || `<span class="initial">${e(initialOf(name))}</span>`;
  const thumb = (name, art, genre, slot = 48) => pic(art, slot) || `<span class="initial sq" data-genre="${e(genre || '')}">${e(initialOf(name))}</span>`;
  /** The original, ungraded, at its own aspect: the page about the picture (§ by slot: header). */
  function original(art, h, maxW) {
    const a = K.aspect(art) || 0.8;
    let H = Math.min(h, art.height), W = H * a;
    if (W > maxW) { W = maxW; H = W / a; }
    return `<img class="original" alt="" src="${e(K.artURL(art, W))}" width="${Math.round(W)}" height="${Math.round(H)}">`;
  }

  /* ---------- Data marks ---------- */
  /** Bars per year (a run strip), as a responsive SVG; rect.b bars, rect.z empty years. */
  function bars(hist, from, to, { h = 18, sel = null } = {}) {
    const ys = []; for (let y = from; y <= to; y++) ys.push(y);
    const max = Math.max(1, ...ys.map((y) => hist[y] || 0));
    const w = ys.length * 10;
    const r = ys.map((y, i) => {
      const v = hist[y] || 0;
      if (!v) return `<rect class="z" x="${i * 10}" y="${h - 1}" width="8" height="1"/>`;
      const bh = Math.max(2, Math.round((v / max) * h));
      return `<rect class="b${sel && String(y) !== String(sel) ? ' dim' : ''}" x="${i * 10}" y="${h - bh}" width="8" height="${bh}"><title>${y}: ${v}</title></rect>`;
    }).join('');
    const peak = Object.entries(hist).sort((a, b) => b[1] - a[1])[0];
    return `<svg viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" role="img" aria-label="Surviving episodes by year, ${from} to ${to}${peak ? `, most in ${peak[0]}` : ''}">${r}</svg>`;
  }
  const histFrom = (s) => s.hist || null;
  /** Facts that wrap only between facts, each dot kept with the fact after it. */
  const facts = (xs) => xs.filter(Boolean).map((x, i) => `<span class="nw">${i ? '· ' : ''}${e(x)}</span>`).join(' ');
  const span = (s) => (s.core ? K.coreYears(s.core) : s.first ? K.coreYears([+s.first.slice(0, 4), +(s.last || s.first).slice(0, 4)]) : '');

  /* ---------- The canonical tile: a show, or one of its episodes ---------- */
  function tile(s, { href = '?s=series-rich', sub = null, strip = true } = {}) {
    const p = s.art ? pic(s.art, 160) : null;
    const meta = sub != null ? sub : [span(s), s.episodes && `${n(s.episodes)} episodes`].filter(Boolean).map((x) => `<span class="nw" style="display:block">${e(x)}</span>`).join("");
    const h = histFrom(s);
    return `<a class="tile" href="${href}" data-genre="${e(s.genre || '')}">
      ${p || `<span class="card"><span>${e(s.name)}</span></span>`}
      ${p ? `<span class="tile-name">${e(s.name)}</span>` : ''}
      ${strip && h ? `<span class="bars">${bars(h, 1930, 1962)}</span>` : ''}
      ${meta ? `<span class="tile-sub">${meta}</span>` : ''}
    </a>`;
  }
  const face = (p, slot = 76, href = '#') => `<a class="face" href="${href}">${faceArt(p.name, p.art, slot)}
      <span class="nm">${e(p.name)}</span>${p.episodes ? `<span class="n">${n(p.episodes)}</span>` : ''}</a>`;
  const playDot = () => `<span class="play-dot" aria-hidden="true">${I.play}</span>`;
  const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const dblock = (date, genre, num) => date
    ? `<span class="dblock" data-genre="${e(genre)}"><i>${MON[+date.slice(5, 7) - 1]}</i><b>${+date.slice(8, 10)}</b></span>`
    : `<span class="dblock" data-genre="${e(genre)}"><i>No.</i><b>${e(num)}</b></span>`;

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
    return `<span style="width:40px;flex:none">${thumb('Hans Conried', r.credits[0].art, 'mystery', 40)}</span>
      <span class="row-body" style="flex:1"><span class="row-title">${e(r.title)}</span><span class="row-sub">Suspense</span></span>
      <span class="icon-btn icon-btn-primary" aria-label="Pause">${I.pause}</span>`;
  }
  const secH = (title, right = '') => `<div class="sec-h"><h2 class="l2">${title}</h2>${right}</div>`;
  const voices = (() => {
    const seen = new Set(); const out = [];
    for (const p of ED.faces) { if (seen.has(p.art && p.art.url)) continue; seen.add(p.art && p.art.url); out.push(p); }
    return out;
  })();

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
    return tile({ ...s, name: s.name || r.seriesName, hist: null }, { href: '?s=episode-rich', sub: `${e(r.title)} <span class="nw">· ${K.mins(r.length)}</span>`, strip: false });
  };

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
    const H = 64, cols = to - from + 1, W = cols * 10;
    const ORDER = ['drama', 'mystery', 'comedy', 'serial', 'western', 'scifi', 'documentary', 'news', ''];
    let out = '';
    for (let y = from; y <= to; y++) {
      const x = (y - from) * 10;
      if (!by[y]) { out += `<rect x="${x}" y="${H - 1}" width="8" height="1" fill="var(--color-border)"/>`; continue; }
      let top = H;
      for (const g of ORDER) {
        const v = by[y][g]; if (!v) continue;
        const h = (v / max) * (H - 4);
        top -= h;
        out += `<rect class="b" data-genre="${g}" x="${x}" y="${top.toFixed(1)}" width="8" height="${h.toFixed(1)}" style="fill:var(--genre-accent)"/>`;
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
    const shows = ED.popular.slice(0, 12);
    return shell('home', `
      <section class="board neutral day" data-genre="">
        <p class="kicker">Thursday · This day in radio</p>
        <h1 class="board-name">${K.fmtDate(TODAY, 'md')}</h1>
        <p class="facts"><span class="nw">${n(rows.length)} surviving broadcasts</span> <span class="nw">· ${st.years} years</span></p>
        <div class="yrs">${st.svg}<div class="axis"><span>${st.from}</span><span>1944</span><span>${st.to}</span></div></div>
        <div class="legend">${st.genresSeen.map((g) => `<span data-genre="${g}"><i></i>${e(K.genreName(g))}</span>`).join('')}</div>
      </section>
      <section class="sec">
        ${secH(K.fmtDate(`${sel}-10-29`, 'medium'), `<a class="l5" href="#">${night.tail} single recordings</a>`)}
        <div class="tiles six">${night.shows.slice(0, 6).map(nightTile).join('')}</div>
        <a class="more" href="#">All ${night.shows.length} shows that night</a>
      </section>
      <section class="sec">
        ${secH('Most heard', '<a class="l5" href="?s=browse">All voices</a>')}
        <div class="wall">${voices.slice(0, 8).map((p) => face(p)).join('')}</div>
      </section>
      <section class="sec">
        ${secH('Most downloaded', `<a class="l5" href="?s=browse">All ${n(ED.tiers.shows)} shows</a>`)}
        <div class="tiles six">${shows.map((s) => tile(s, { href: s.key === 'suspense' ? '?s=series-rich' : '#' })).join('')}</div>
      </section>`);
  }

  /* ================= Browse ================= */
  function field() {
    const G = ['drama', 'mystery', 'comedy', 'serial', 'western', 'scifi', 'documentary', 'news'];
    const D = [1920, 1930, 1940, 1950, 1960];
    const v = (g, d) => (ED.field.find((f) => f.genre === g && f.decade === d) || {}).shows || 0;
    const max = Math.max(...ED.field.map((f) => f.shows));
    const head = `<span></span>${D.map((d) => `<span class="fh">${d}s</span>`).join('')}`;
    const body = G.map((g) => `<span class="fl" data-genre="${g}"><i></i><span>${e(K.genreName(g))}</span></span>${D.map((d) => {
      const x = v(g, d);
      const side = x ? Math.max(6, Math.round(32 * Math.sqrt(x / max))) : 0;
      return `<a class="fc" href="#" data-genre="${g}" aria-label="${e(K.genreName(g))}, ${d}s: ${x} shows">${x ? `<span class="sq" style="width:${side}px;height:${side}px"></span><span class="v">${x}</span>` : ''}</a>`;
    }).join('')}`).join('');
    return `<div class="field" role="grid">${head}${body}</div>`;
  }
  function browse() {
    const t = ED.tiers;
    return shell('browse', `
      <h1 class="l1 page-h">Browse</h1>
      <div class="seg" role="tablist"><a role="tab" class="on" aria-selected="true" href="?s=browse">Shows</a><a role="tab" href="#">Voices</a></div>
      <p class="count-line"><span class="l3 nw">${n(t.shows)} shows</span><a class="l5 nw" href="?s=series-sparse">${n(t.singles)} single recordings</a></p>
      <div class="two browse-two">
        <section class="field-sec">
          ${secH('By decade and genre', `<span class="l5">${ED.fieldUnsorted} with no genre</span>`)}
          ${field()}
          <p class="l5" style="margin-top:var(--space-3)">By the year a show first aired</p>
        </section>
        <section class="sec shows-sec">
          ${secH('Most downloaded first')}
          <div class="tiles">${ED.popular.map((s) => tile(s, { href: s.key === 'suspense' ? '?s=series-rich' : '#' })).join('')}</div>
        </section>
      </div>`);
  }

  /* ================= Series ================= */
  const topbar = (href, label) => `<div class="top"><a class="back" href="${href}">${I.back}${e(label)}</a><a class="icon-btn way" href="#" aria-label="Share">${I.share}</a></div>`;
  function seriesRich() {
    const s = ED.suspense, sel = '1943';
    const count = new Map();
    for (const ep of s.season) for (const f of ep.faces || []) {
      const c = count.get(f.name) || { name: f.name, art: f.art, episodes: 0 };
      c.episodes++; count.set(f.name, c);
    }
    const heard = [...count.values()].sort((a, b) => b.episodes - a.episodes).slice(0, 6);
    const regular = new Set([...count.values()].filter((p) => p.episodes >= s.season.length / 4).map((p) => p.name));
    const rows = s.season.slice(0, 12).map((ep) => {
      const g = (ep.faces || []).find((x) => !regular.has(x.name) && pic(x.art, 24, true));
      return `<li><a class="row" href="?s=episode-rich">${dblock(ep.date, s.genre)}
        <span class="row-body"><span class="row-title">${e(ep.title || `No. ${ep.num}`)}</span>
          ${g ? `<span class="guest">${pic(g.art, 24, true)}<span>${e(g.name)}</span></span>` : ''}</span>
        <span class="row-len">${K.mins(ep.length)}</span>${playDot()}</a></li>`;
    }).join('');
    return shell('browse', `
      ${topbar('?s=browse', 'Browse')}
      <header class="board hero" data-genre="${e(s.genre)}">
        <p class="kicker">${e(K.genreName(s.genre))} · ${e(s.networks)}</p>
        <h1 class="board-name">${e(s.name)}</h1>
        <p class="facts"><span class="nw">${K.coreYears(s.core)}</span> <span class="nw">· ${n(s.episodes)} episodes</span></p>
        <div class="run">${bars(s.hist, 1940, 1962, { h: 56, sel })}<div class="axis"><span>1940</span><span>${sel}–44</span><span>1962</span></div></div>
      </header>
      <div class="acts"><a class="btn btn-way" href="#">Follow</a></div>
      <div class="two">
        <section class="sec">
          ${secH('1943–44', `<span class="l5">${s.season.length} episodes</span>`)}
          <ol class="rows">${rows}</ol>
          <a class="more" href="#">All ${s.season.length}</a>
        </section>
        <section class="sec">
          ${secH('Heard most')}
          <div class="wall row6">${heard.map((p) => face(p, 76)).join('')}</div>
        </section>
      </div>`);
  }
  function seriesSparse() {
    const s = ED.sparse;
    const rows = s.episodes.map((ep) => `<li><a class="row" href="?s=episode-bare">${dblock(null, s.genre, ep.num)}
        <span class="row-body"><span class="row-title">${e(ep.title)}</span></span>
        <span class="row-len">${K.mins(ep.length)}</span>${playDot()}</a></li>`).join('');
    return shell('browse', `
      ${topbar('?s=browse', 'Browse')}
      <header class="board hero bare-card" data-genre="${e(s.genre)}">
        <p class="kicker">${e(K.genreName(s.genre))} · ${e(s.networks)}</p>
        <h1 class="board-name">${e(s.name)}</h1>
        <p class="facts">${s.episodes.length} episodes</p>
      </header>
      <div class="acts"><a class="btn btn-way" href="#">Follow</a></div>
      <section class="sec"><ol class="rows">${rows}</ol></section>`);
  }

  /* ================= Episode ================= */
  function copies(recs) {
    const by = new Map();
    for (const r of recs) {
      const what = [r.variant && (ED.variantLines[r.variant] || r.variant), r.partial ? 'Incomplete' : 'Full broadcast'].filter(Boolean).join(' · ');
      const k = `${what}|${K.mins(r.length)}`;
      by.set(k, (by.get(k) || 0) + 1);
    }
    return [...by.entries()].map(([k, c]) => { const [what, len] = k.split('|'); return `<li class="cr" style="grid-template-columns:minmax(0,1fr) auto"><span>${e(what)} · ${e(len)}</span><span class="l5">${c} ${c === 1 ? 'copy' : 'copies'}</span></li>`; }).join('');
  }
  function booklet(ep) {
    const g = K.creditGroups(ep.credits);
    const groups = Object.entries(g).filter(([, v]) => v.length).map(([k, v]) => `<p class="cr-h">${k}</p>${v.map((c) => `<div class="cr">
        ${pic(c.art, 32, true) || `<span class="initial">${e(initialOf(c.name))}</span>`}
        <span><a href="#" class="l3">${e(c.name)}</a>${c.character || c.roles.some((r) => r !== 'cast') ? `<span class="l5">${e(c.character ? `as ${c.character}` : c.roles.filter((r) => r !== 'cast').join(', '))}</span>` : ''}</span></div>`).join('')}`).join('');
    return `<div class="booklet">
      ${ep.credits.length ? `<details open><summary>Cast and credits <span class="l5">${ep.credits.length}</span></summary>${groups}<div style="height:12px"></div></details>` : ''}
      <details><summary>Copies <span class="l5">${ep.recordings.length}</span></summary><ul>${copies(ep.recordings)}</ul></details>
      <p class="rights">${e(ED.rightsLines.unclaimed)}</p></div>`;
  }
  const epActs = (len) => `<div class="acts"><a class="btn btn-primary" href="?s=now-playing">${I.play}Play · ${K.mins(len)}</a>
      <a class="btn btn-way" href="#" aria-label="Add to queue">${I.queue}<span class="lab-wide">Add to queue</span></a>
      <a class="icon-btn way" href="#" aria-label="Share">${I.share}</a></div>`;
  function thatNight(rows, id) {
    const t = nightOf(rows, id);
    return `<section class="sec">${secH('That night on the radio', t.tail ? `<a class="l5" href="#">${t.tail} single recording${t.tail === 1 ? '' : 's'}</a>` : '')}
      <div class="tiles">${t.shows.slice(0, 6).map(nightTile).join('')}</div></section>`;
  }
  function episodeRich() {
    const ep = ED.suspenseRich;
    const faces = K.facesOf(ep.credits, 3);
    return shell('browse', `
      ${topbar('?s=series-rich', 'Suspense')}
      <div class="detail">
        <div>
          <div class="faces3">${faces.map((c) => `<figure>${original(c.art, 132, 108)}<figcaption>${e(c.name)}</figcaption></figure>`).join('')}</div>
          <a class="chip-board" href="?s=series-rich" data-genre="mystery">Suspense</a>
          <h1 class="l1 ep-h1">${e(ep.title)}</h1>
          <p class="event">${facts(K.eventLine(ep))}</p>
          ${epActs(ep.length)}
          ${thatNight(ED.sameNight, ep.id)}
        </div>
        ${booklet(ep)}
      </div>`);
  }
  function episodeBare() {
    const ep = ED.bare, s = ED.bareSeries;
    return shell('browse', `
      ${topbar('#', s.name)}
      <div class="detail">
        <div>
          <a class="board hero bare-card" href="#" data-genre="${e(s.genre)}">
            <span class="kicker">${e(K.genreName(s.genre))}</span>
            <span class="board-name">${e(s.name)}</span>
            <span class="facts"><span class="nw">${n(s.episodes)} episodes</span></span></a>
          <h1 class="l1 ep-h1">${e(ep.title)}</h1>
          <p class="event">${facts(K.eventLine(ep))}</p>
          ${epActs(ep.length)}
        </div>
        <div>${thatNight(ED.sameNightBare, ep.id)}<p class="rights">${e(ED.rightsLines.unclaimed)}</p></div>
      </div>`);
  }

  /* ================= Now Playing ================= */
  function nowPlaying() {
    const ep = ED.suspenseRich, lead = ep.credits[0];
    const faces = K.facesOf(ep.credits, 6);
    const night = nightOf(ED.sameNight, ep.id);
    return `<div class="np">
      <div class="top"><a class="icon-btn" href="?s=episode-rich" aria-label="Close">${I.down}</a><a class="icon-btn way" href="#" aria-label="Share">${I.share}</a></div>
      <div class="np-grid">
        <figure class="np-art">${original(lead.art, 300, 300)}<figcaption>${e(lead.name)}</figcaption></figure>
        <div>
          <a class="chip-board" href="?s=series-rich" data-genre="mystery">Suspense</a>
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
      <section class="sec">${secH('On the air')}<div class="wall row6">${faces.map((p) => face(p, 76)).join('')}</div></section>
      <section class="sec">${secH('That night on the radio')}<div class="tiles">${night.shows.slice(0, 4).map(nightTile).join('')}</div></section>
    </div>`;
  }

  /* ================= Search ================= */
  function search() {
    const qy = 'Conrad';
    const people = voices.filter((p) => p.name.includes(qy));
    const shows = ED.popular.filter((s) => (s.star || '').includes(qy) || s.name.includes(qy));
    const g = ED.gunsmoke;
    const eps = g.sample.slice(0, 5).map((x) => `<li><a class="row" href="#">${thumb(g.name, g.art, g.genre)}
        <span class="row-body"><span class="row-title">${e(x.title)}</span><span class="row-sub"><span class="nw">${e(g.name)}</span> <span class="nw">· ${K.fmtDate(x.date)}</span></span></span>
        <span class="row-len">${K.mins(x.length)}</span>${playDot()}</a></li>`).join('');
    return shell('search', `
      <h1 class="l1 page-h">Search</h1>
      <label class="search">${I.search}<input value="${qy}" aria-label="Search"></label>
      <section class="sec">${secH('Voices')}<div class="wall">${people.map((p) => face(p)).join('')}</div></section>
      <section class="sec">${secH('Shows', `<span class="l5">${shows.length}</span>`)}<div class="tiles">${shows.map((s) => tile(s, { href: '#' })).join('')}</div></section>
      <section class="sec">${secH('Episodes')}<ol class="rows">${eps}</ol></section>`);
  }

  /* ================= Stations ================= */
  function timeline(slots, { h = 28 } = {}) {
    const t0 = 18 * 60 + 30, t1 = 23 * 60;
    const m = (s) => { const [a, b] = s.split(':').map(Number); return a * 60 + b; };
    const W = (t1 - t0);
    const r = slots.map((s) => {
      const x = m(s.et_start) - t0, w = Math.max(2, m(s.et_end) - m(s.et_start) - 2);
      if (s.episode) {
        const g = (seriesOf(s.episode.id.split('|')[0]) || {}).genre || '';
        return `<rect class="on" data-genre="${g}" x="${x}" y="0" width="${w}" height="${h}" rx="2"><title>${e(s.episode.series)}</title></rect>`;
      }
      if (s.known_series) return `<rect class="known" x="${x + 0.5}" y="0.5" width="${w - 1}" height="${h - 1}" rx="2"/>`;
      return `<rect class="gap" x="${x}" y="${h / 2 - 1}" width="${w}" height="2"/>`;
    }).join('');
    return `<svg viewBox="0 0 ${W} ${h}" preserveAspectRatio="none" role="img" aria-label="The evening from 6:30 to 11:00 Eastern; filled slots survive">${r}</svg>
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
        return `<li><a class="row" href="#">${thumb(sr.name, sr.art, sr.genre)}<span class="row-body"><span class="row-sub l6">${t}</span><span class="row-title">${e(s.episode.series)}</span><span class="row-sub">${e(s.episode.title)}</span></span><span class="row-len">${s.length_min} min</span>${playDot()}</a></li>`;
      }
      const label = s.known_series ? `<span class="row-title">${e(s.known_series)}</span><span class="row-sub">Not surviving</span>` : `<span class="row-sub">Not surviving until ${K.clock(s.et_end)}</span>`;
      return `<li><div class="row noplay"><span class="hatch"></span><span class="row-body"><span class="row-sub l6">${t}</span>${label}</span><span></span></div></li>`;
    }).join('');
  }
  function stations() {
    const ev = ED.evening;
    return shell('stations', `
      <h1 class="l1 page-h">Stations</h1>
      <section class="board neutral" data-genre="">
        <p class="kicker">Tonight · ${e(ev.network)} · ${e(ev.station)}</p>
        <h2 class="board-name">${K.fmtDate(ev.evening, 'long').replace(/, \d{4}$/, '')}</h2>
        <p class="facts">${K.fmtDate(ev.evening, 'year')} · Eastern time</p>
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
  const pface = (part, who, me = false) => who
    ? `<span class="pface" data-hue="${hueOf(part)}" title="${e(part)}">${e(who.charAt(0))}</span>`
    : `<span class="pface voice" data-hue="${hueOf(part)}" title="${e(part)}">${wave}</span>`;
  function library() {
    const r = ED.suspenseRich, g = ED.gunsmoke;
    const cont = [
      { name: 'Suspense', art: r.credits[0].art, genre: 'mystery', title: r.title, left: '18 min left', p: 38, href: '?s=now-playing' },
      { name: g.name, art: g.art, genre: g.genre, title: g.sample[0].title, left: '22 min left', p: 24, href: '#' },
    ];
    const follow = ['suspense', 'gunsmoke', 'escape', 'dragnet', 'ourmissbrooks', 'xminusone'].map(seriesOf).filter(Boolean);
    const prod = [['URIAH', 'Pat'], ['FRANKLIN', 'Ada'], ['MCKEEN', 'Sam'], ['RODNEY', 'Lou'], ['PRUDENCE', null]];
    return shell('library', `
      <h1 class="l1 page-h">Library</h1>
      <section>${secH('Continue listening')}<ol class="rows">${cont.map((c) => `<li><a class="row" href="${c.href}">${thumb(c.name, c.art, c.genre)}
        <span class="row-body"><span class="row-title">${e(c.title)}</span><span class="row-sub">${e(c.name)}</span><span class="progress"><span style="width:${c.p}%"></span></span></span>
        <span class="row-len">${c.left}</span>${playDot(c.href)}</a></li>`).join('')}</ol></section>
      <section class="sec">${secH('Your ear dramas')}
        <div class="makes">
          <a class="board" href="record.html?s=ready" data-genre="drama">
            <p class="kicker">Radio play · in progress</p>
            <p class="board-name">${e(rodney.title)}</p>
            <p class="facts"><span class="nw">RODNEY · you</span> <span class="nw">· 5 of 76 lines</span></p>
            <div class="cast-row">${prod.map(([p, w]) => pface(p, w)).join('')}</div>
          </a>
          <a class="board neutral" href="record.html?s=pick" data-genre="">
            <p class="kicker">${REC.plays.length} plays</p>
            <p class="board-name">Start an ear drama</p>
            <div class="cast-row">${REC.plays.slice(0, 5).map((p) => `<span class="pface" data-hue="${p.genre === 'comedy' ? 'comedy' : 'serial'}">${e(initialOf(p.title))}</span>`).join('')}</div>
          </a>
        </div></section>
      <section class="sec">${secH('Following', `<span class="l5">${follow.length}</span>`)}<div class="tiles six">${follow.map((s) => tile(s, { href: s.key === 'suspense' ? '?s=series-rich' : '#' })).join('')}</div></section>`);
  }

  /* ================= The shared production (D1c's fixture cast: Pat, Sam, Ada) ================= */
  function production() {
    const p = ED.play, pr = ED.production, ev = p.rights.evidence[0];
    const words = Object.fromEntries(rodney.roles.map((r) => [r.name, r.words]));
    const cast = [...pr.cast].sort((a, b) => (words[b.part] || 0) - (words[a.part] || 0));
    const vs = rodney.roles[0].presence.map((_, i) => {
      const v = rodney.roles.reduce((a, r) => a + (pr.cast.find((c) => c.part === r.name && c.by && c.done === c.lines) ? r.presence[i] : 0), 0);
      const all = rodney.roles.reduce((a, r) => a + r.presence[i], 0) || 1;
      return `<i style="opacity:${(0.25 + 0.75 * v / all).toFixed(2)}"></i>`;
    }).join('');
    return shell('library', `
      <div class="top"><a class="back" href="?s=library">${I.back}Library</a></div>
      <header class="board hero" data-genre="drama">
        <p class="kicker">Ear drama · Radio play</p>
        <h1 class="board-name">${e(p.title)}</h1>
        <p class="facts"><span class="nw">${e(K.author(p.authors[0]))}</span> <span class="nw">· Recorded ${K.fmtDate(pr.recorded[0], 'md')}–${+pr.recorded[1].slice(8)}, 2026</span></p>
        <div class="vstrip" role="img" aria-label="How much of the play has a human voice, start to end">${vs}</div>
      </header>
      <div class="acts"><a class="btn btn-primary" href="record.html?s=listen">${I.play}Listen through · ${K.aboutMin(rodney.words).replace('about ', '')}</a><a class="icon-btn way" href="#" aria-label="Share">${I.share}</a></div>
      <section class="sec">${secH('Cast', `<span class="l5">${cast.length} parts</span>`)}
        <ul class="bill">${cast.map((c) => `<li data-hue="${hueOf(c.part)}"><span class="part">${e(c.part)}</span>
          <span class="by">${pface(c.part, c.by)}<span>${c.by ? `<span class="l3">${e(c.by)}</span>` : 'Device voice'}${c.by && c.done < c.lines ? `<span class="l5" style="display:block">${c.done} of ${c.lines} lines</span>` : `<span class="l5" style="display:block">${c.lines} lines</span>`}</span></span></li>`).join('')}</ul></section>
      <p class="rights">Script: <a href="${e(p.source.url)}">${e(p.source.name)}</a>. ${e(p.source.name)}'s claim: <a href="${e(ev.src)}">${e(ev.claim)}</a></p>`, { player: false });
  }

  const R = { home, browse, 'series-rich': seriesRich, 'series-sparse': seriesSparse, 'episode-rich': episodeRich,
    'episode-bare': episodeBare, 'now-playing': nowPlaying, search, stations, library, production };
  if (q.get('theme')) document.documentElement.dataset.theme = q.get('theme');
  const s = q.get('s') || 'home';
  const html = (R[s] || home)();
  document.getElementById('app').innerHTML = html + filterDefs();
  document.body.dataset.screen = s;
  /* The fit gate's negative control: ?break=1 must fail every check. */
  if (q.get('break')) {
    document.head.insertAdjacentHTML('beforeend', '<style>.acts{flex-wrap:wrap!important;max-width:150px}.btn{white-space:normal!important;max-width:72px}.board-name{word-break:break-all!important}h2.l2{text-wrap:wrap!important}body{min-width:1600px}</style>');
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
