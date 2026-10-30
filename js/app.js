/**
 * Ear Drama on the web: the views, the router, and the player's face.
 *
 * Routes (every view has a URL; the https twins of the apps' links). The six
 * sections are actions (Decision 068, WEB-DESIGN §4.1):
 *   ?view=home                        Home (also the bare site)
 *   ?view=browse&kind=&script=1&genre=&decade=&network=&sort=   Browse: series and plays
 *   ?view=stations                    Stations: Tonight in 19xx on the one clock
 *   ?view=surprise                    Surprise: three random picks
 *   ?series={key}&season={1948-49|undated}       a series page
 *   ?item={episode id}                episode Detail
 *   ?view=search&q=                   Search
 *   ?view=library&tab=queue|history|following|dramas    Library (this device)
 *   ?play={script id}, ?production={id}, ?production={id}&part={part id}
 *                                     an ear drama (js/plays-ui.js; this browser only)
 * The names before 068 (listen, series, radio, plays) are rewritten in place.
 *   ?room={CODE}                      Listen Together's join sheet, over the view (§4.12)
 *   /invite#{TOKEN}, #invite={TOKEN}  an ear drama invite, shown in Library's Ear dramas (§4.10a)
 * Path twins (/series/{key}, /episode/{id}) are static pages with link previews that hand
 * a person to these (catalog/tools/build_share_pages.py); the router also reads the path
 * form itself and the web shares it. Other twins (/search?q=) are forwarded by 404.html. Harness doors: ?mute=1, ?door_seconds=n.
 *
 * Every list has loading, empty, error, and offline states (stateBox).
 * Lists and shelves come from the catalog's data only; no copy is written here
 * beyond labels, headings, and refusals.
 */

(function () {
  const saved = (() => { try { return localStorage.getItem('app_theme'); } catch { return null; } })();
  if (saved === 'dark' || saved === 'light') document.documentElement.setAttribute('data-theme', saved);
})();

(function () {
  'use strict';

  const $ = (id) => document.getElementById(id);
  /* Views are named by their section ids in index.html (view-listen is Home, view-series Browse,
     view-radio Stations); the URL and the nav use the section names. */
  const VIEWS = ['listen', 'series', 'show', 'episode', 'person', 'radio', 'surprise', 'plays', 'search', 'library'];
  const VIEW_OF = { home: 'listen', browse: 'series', stations: 'radio', surprise: 'surprise', search: 'search',
                    library: 'library' };
  const TAB_OF = { listen: 'home', series: 'browse', show: 'browse', episode: 'browse', person: 'browse', radio: 'stations',
                   surprise: 'surprise', plays: 'browse', search: 'search', library: 'library' };
  /** Decision 068's renames: an old ?view= opens the new section, and the address is rewritten. */
  const RENAMED = { listen: 'home', series: 'browse', radio: 'stations', plays: 'browse' };
  const PAGE = 60;

  /* ================================================================
     HELPERS
  ================================================================ */

  /** el('a', { href, class }, ...children): a DOM node; strings become text, never HTML. */
  function el(tag, attrs, ...children) {
    const n = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (v === null || v === undefined || v === false) continue;
      if (k === 'class') n.className = v;
      else if (k === 'dataset') Object.assign(n.dataset, v);
      else if (k.startsWith('on')) n.addEventListener(k.slice(2), v);
      else n.setAttribute(k, v === true ? '' : v);
    }
    for (const c of children.flat()) {
      if (c === null || c === undefined || c === false) continue;
      n.append(c instanceof Node ? c : document.createTextNode(String(c)));
    }
    return n;
  }

  const ICONS = {
    play: 'M8 5v14l11-7z',
    queue: 'M4 6h12v2H4zm0 5h12v2H4zm0 5h8v2H4zm14-1v-3h2v3h3v2h-3v3h-2v-3h-3v-2z',
    queued: 'M4 6h12v2H4zm0 5h12v2H4zm0 5h8v2H4zm11.6 1.4 1.4-1.4 2 2 4-4 1.4 1.4-5.4 5.4z',
    share: 'M18 16a3 3 0 0 0-2.4 1.2l-7-3.5a3 3 0 0 0 0-1.4l7-3.5A3 3 0 1 0 15 7l-7 3.5a3 3 0 1 0 0 3l7 3.5A3 3 0 1 0 18 16z',
    up: 'M12 8l-6 6 1.4 1.4 4.6-4.6 4.6 4.6L18 14z',
    down: 'M12 16l6-6-1.4-1.4-4.6 4.6-4.6-4.6L6 10z',
    remove: 'M6.4 5 5 6.4 10.6 12 5 17.6 6.4 19l5.6-5.6 5.6 5.6 1.4-1.4-5.6-5.6L19 6.4 17.6 5 12 10.6z',  };
  function icon(name) {
    const ns = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('aria-hidden', 'true');
    const p = document.createElementNS(ns, 'path');
    p.setAttribute('d', ICONS[name]);
    svg.append(p);
    return svg;
  }

  const longDate = new Intl.DateTimeFormat('en-US', { dateStyle: 'full', timeZone: 'UTC' });
  const monthDay = new Intl.DateTimeFormat('en-US', { month: 'long', day: 'numeric' });
  const num = new Intl.NumberFormat('en-US');

  function fmtLongDate(iso) {
    if (!iso || iso.length !== 10) return iso || '';
    return longDate.format(new Date(`${iso}T00:00:00Z`));
  }
  function fmtLength(s) {
    if (!s) return null;
    const m = Math.round(s / 60);
    return m >= 60 ? `${Math.floor(m / 60)} hr ${m % 60} min` : `${m} min`;
  }
  function fmtClock(s) {
    if (!isFinite(s) || s < 0) s = 0;
    s = Math.floor(s);
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = String(s % 60).padStart(2, '0');
    return h ? `${h}:${String(m).padStart(2, '0')}:${sec}` : `${m}:${sec}`;
  }
  function years(first, last) {
    const a = first && first.slice(0, 4);
    const b = last && last.slice(0, 4);
    if (!a) return null;
    return !b || a === b ? a : `${a}–${b}`;
  }
  /** An episode's name: its title, else its number in the series, else "Untitled"; never its id. */
  function epTitle(ep) {
    if (ep.title) return ep.title;
    return ep.num !== null && ep.num !== undefined ? `No. ${ep.num}` : 'Untitled';
  }
  function plural(n, one, many) { return `${num.format(n)} ${n === 1 ? one : many}`; }
  /** The smart-TV layer (tv.js) is on: TVs play back only, so nothing here starts an ear drama. */
  const onTV = () => document.documentElement.classList.contains('tv');
  function seriesMeta(s) {
    return [s.networks, years(s.first, s.last), s.episodes ? plural(s.episodes, 'episode', 'episodes') : null]
      .filter(Boolean).join(' · ');
  }
  function announce(text) {
    const a = $('announcer');
    a.textContent = '';
    setTimeout(() => { a.textContent = text; }, 30);
  }

  let manifest = null;
  async function genreName(g) {
    if (!g) return null;
    if (!manifest) manifest = await API.manifest();
    return (manifest.genreNames && manifest.genreNames[g]) || g;
  }

  /* ---- The four states every list has ---- */

  function stateBox(kind, opts = {}) {
    if (kind === 'loading') {
      return el('div', { class: 'state', role: 'status' }, el('div', { class: 'spinner', 'aria-hidden': 'true' }),
        el('span', { class: 'sr-only' }, 'Loading'));
    }
    // The empty state (WEB-DESIGN §7.1a): the fact, and at most one way on, a link.
    if (kind === 'empty') {
      if (!opts.action) return el('p', { class: 'state caption' }, opts.text);
      return el('div', { class: 'state' }, el('p', { class: 'caption' }, opts.text),
        el('a', { class: 'btn', href: opts.action.href }, opts.action.label));
    }
    const text = kind === 'offline' ? 'You are offline.' : kind === 'missing' ? 'Not in the catalog.'
      : 'This did not load.';
    return el('div', { class: kind === 'offline' ? 'state state-problem state-offline' : 'state state-problem', role: 'alert' },
      el('p', { class: 'body' }, text),
      opts.retry && kind !== 'missing' ? el('button', { type: 'button', class: 'btn', onclick: opts.retry }, 'Try again')
        : null);
  }
  function problem(err) {
    if (err && err.kind === 'missing') return 'missing';
    if ((err && err.kind === 'offline') || API.isOffline()) return 'offline';
    return 'error';
  }
  /** Fill `box` from an async loader, showing loading, then the result or the right problem state. */
  async function load(box, loader, render) {
    box.replaceChildren(stateBox('loading'));
    try {
      const data = await loader();
      box.replaceChildren();
      render(data, box);
    } catch (err) {
      console.error(err);
      box.replaceChildren(stateBox(problem(err), { retry: () => load(box, loader, render) }));
    }
  }

  /* ---- Art (§6.4, Decision 069): a served portrait, else a card drawn from data ---- */

  function initialOf(name) {
    const w = String(name || '').replace(/^[^\p{L}\p{N}]+/u, '').replace(/^(the|a|an)\s+/i, '');
    const m = w.match(/[\p{L}\p{N}]/u);
    return m ? m[0].toUpperCase() : '';
  }
  /** A small square crop (§6.4): the square `API.cropRect` picks around the published face,
      the image scaled so that square fills the box, at the smallest Commons step that covers
      it on this screen. A wide picture with no face is not cropped; an unknown size keeps the
      stylesheet's plain fill crop; a failed load leaves the box as it was: the tile's letter,
      or nothing. */
  function putImage(box, art, px, alt) {
    const r = API.cropRect(art);
    if (!r && API.artAspect(art) !== null) return null;
    const dpr = typeof devicePixelRatio === 'number' && devicePixelRatio > 1 ? 2 : 1;
    const pct = (v) => `${+(v * 100).toFixed(2)}%`;
    const img = el('img', { src: API.artURL(art, (r ? px / r.w : px) * dpr), alt, loading: 'lazy', decoding: 'async',
                            style: r ? `object-fit: fill; max-width: none; width: ${pct(1 / r.w)}; height: ${pct(1 / r.h)}; `
                              + `left: ${pct(-r.x / r.w)}; top: ${pct(-r.y / r.h)}` : null });
    img.addEventListener('error', () => { img.remove(); box.classList.remove('has-img'); });
    box.classList.add('has-img');
    box.append(img);
    return img;
  }
  /** A row's 40 px tile: the series' star, else its first letter on its genre. Filled from the
      series index by paintArt when the row knows only the series key. */
  function artTile(s) {
    const t = el('span', { class: 'art-tile', 'aria-hidden': 'true', dataset: { genre: (s && s.genre) || '' } },
      el('span', { class: 'art-letter' }, initialOf(s && s.name)));
    if (s && s.art) { t.dataset.done = '1'; putImage(t, s.art, 40, ''); } else if (s && s.key) t.dataset.series = s.key;
    return t;
  }
  let artPending = false;
  function paintArt() {
    if (artPending) return;
    artPending = true;
    queueMicrotask(() => {
      artPending = false;
      const tiles = [...document.querySelectorAll('.art-tile[data-series]:not([data-done])')];
      if (!tiles.length) return;
      tiles.forEach(t => { t.dataset.done = '1'; });
      API.seriesIndex().then(({ byKey }) => tiles.forEach(t => {
        const s = byKey.get(t.dataset.series);
        if (!s) return;
        t.dataset.genre = s.genre || '';
        t.querySelector('.art-letter').textContent = initialOf(s.name);
        if (s.art) putImage(t, s.art, 40, '');
      })).catch(() => tiles.forEach(t => { delete t.dataset.done; }));
    });
  }
  new MutationObserver(paintArt).observe(document.body, { childList: true, subtree: true });

  /** A picture in a box of its own shape (§6.4a, `artwork-presentation-design`): never a wash,
      bars, or a filter behind it. `--a` carries the aspect to the stylesheet; an unknown size is
      drawn at 4:5 until the image decodes, then takes its own (and a wide one becomes a plate,
      via `onShape`). A failed image removes its box. */
  function shapedImage(art, px, alt, onShape) {
    const dpr = typeof devicePixelRatio === 'number' && devicePixelRatio > 1 ? 2 : 1;
    const a = API.artAspect(art);
    const frame = el('span', { class: `art-frame${a ? '' : ' no-size'}`, style: `--a: ${(a || 0.8).toFixed(3)}` });
    const img = el('img', { src: API.artURL(art, px * dpr), alt, decoding: 'async',
                            width: art.width || null, height: art.height || null });
    img.addEventListener('error', () => frame.remove());
    if (!a) {
      img.addEventListener('load', () => {
        if (!img.naturalWidth || !img.naturalHeight) return;
        const own = img.naturalWidth / img.naturalHeight;
        frame.style.setProperty('--a', own.toFixed(3));
        frame.classList.remove('no-size');
        if (onShape) onShape(own > API.wideAspect ? 'wide' : 'upright');
      });
    }
    frame.append(img);
    return frame;
  }
  /** A page's face (§6.4a): the print beside an upright one's heading, the plate above a wide
      one's, captioned with whose it is (when the heading does not already say) and, when its
      license asks, the credit, linked to the file page. `head` takes the shape's class. */
  function faceFigure(head, art, name) {
    const setShape = (shape) => {
      head.classList.toggle('face-print', shape !== 'wide');
      head.classList.toggle('face-plate', shape === 'wide');
    };
    const wide = API.artShape(art) === 'wide';
    const desk = typeof matchMedia === 'function' && matchMedia('(min-width: 768px)').matches;
    const px = wide ? (desk ? 720 : 375) : Math.round((desk ? 240 : 168) * Math.min(API.artAspect(art) || 0.8, 1.15));
    setShape(wide ? 'wide' : 'upright');
    const credit = art.credit ? el('a', { class: 'face-credit', href: art.evidence, rel: 'noopener', target: '_blank' }, art.credit) : null;
    const fig = el('figure', { class: 'face-fig' }, shapedImage(art, px, name || '', setShape),
      name || credit ? el('figcaption', { class: 'caption' }, name || null, name && credit ? ' · ' : null, credit) : null);
    fig.querySelector('img').addEventListener('error', () => { fig.remove(); head.classList.remove('has-face', 'face-print', 'face-plate'); });
    return fig;
  }
  /** The typographic card (R11): the name, one meta line, on the genre. Any titled work with a year
      and a genre draws one: a series, or a stage play. */
  function typeCard({ name, line, genre }) {
    return el('span', { class: 'type-card', dataset: { genre: genre || '' } },
      el('span', { class: 'type-card-name' }, name || ''), line ? el('span', { class: 'caption' }, line) : null);
  }

  /* ---- The grammar (WEB-DESIGN §6.4b): one skeleton per object, whatever it carries ---- */

  const SVG_NS = 'http://www.w3.org/2000/svg';
  function svgEl(tag, attrs, ...kids) {
    const n = document.createElementNS(SVG_NS, tag);
    for (const [k, v] of Object.entries(attrs || {})) if (v !== null && v !== undefined) n.setAttribute(k, v);
    kids.forEach(c => n.append(c instanceof Node ? c : document.createTextNode(String(c))));
    return n;
  }
  /** The picture's grade as one SVG filter per distinct grade: monochrome, then k * v + o in sRGB. */
  const gradeIds = new Map();
  function gradeFilter(art) {
    const { k, o } = API.gradeOf(art);
    const key = `${k}_${o}`;
    if (gradeIds.has(key)) return gradeIds.get(key);
    const id = `grade-${gradeIds.size}`;
    let defs = document.getElementById('grade-defs');
    if (!defs) {
      defs = svgEl('svg', { id: 'grade-defs', width: 0, height: 0, 'aria-hidden': 'true', style: 'position:absolute' }, svgEl('defs'));
      document.body.append(defs);
    }
    const lin = (ch) => svgEl(ch, { type: 'linear', slope: k, intercept: o });
    defs.firstChild.append(svgEl('filter', { id, 'color-interpolation-filters': 'sRGB' },
      svgEl('feColorMatrix', { type: 'saturate', values: '0' }),
      svgEl('feComponentTransfer', {}, lin('feFuncR'), lin('feFuncG'), lin('feFuncB'))));
    gradeIds.set(key, id);
    return id;
  }
  /** The title block: the name's monogram as an outline in the board's onBoard color. */
  function titleBlock(name) {
    const m = API.monogram(name);
    return svgEl('svg', { class: 'g-block', viewBox: '0 0 100 100', 'aria-hidden': 'true' },
      svgEl('text', { x: 9, y: 93, 'font-size': API.blockSize(m) }, m));
  }
  /** Fills a window with the series' picture (crop or whole, graded) or the title block. */
  function fillWindow(win, s, slot) {
    const pic = s && (s.picture !== undefined ? s.picture : s.art);
    const fill = API.windowFill(pic, slot);
    win.replaceChildren();
    win.dataset.genre = (s && s.genre) || '';
    const block = () => { win.dataset.fill = 'block'; win.replaceChildren(titleBlock(s && s.name)); };
    if (fill.kind === 'block') return block();
    const dpr = typeof devicePixelRatio === 'number' && devicePixelRatio > 1 ? 2 : 1;
    const r = fill.kind === 'crop' ? fill.rect : null;
    const pct = (v) => `${+(v * 100).toFixed(2)}%`;
    const img = el('img', { src: API.artURL(pic, (r ? slot / r.w : slot) * dpr), alt: '', loading: 'lazy', decoding: 'async',
      style: `filter: url(#${gradeFilter(pic)})${r ? `; width: ${pct(1 / r.w)}; height: ${pct(1 / r.h)}; left: ${pct(-r.x / r.w)}; top: ${pct(-r.y / r.h)}` : ''}` });
    img.addEventListener('error', block);
    win.dataset.fill = fill.kind;
    win.append(img);
  }
  /** The window (one square slot): from the series when it is in hand, else from the index by key. */
  function pictureWindow(s, slot) {
    const win = el('span', { class: 'g-window', 'aria-hidden': 'true', dataset: { slot: String(slot) } });
    if (s && (s.picture !== undefined || !s.key)) fillWindow(win, s, slot);
    else {
      fillWindow(win, { name: s && s.name, genre: s && s.genre }, slot);
      if (s && s.key) win.dataset.series = s.key;
    }
    return win;
  }
  /** The run strip: the years from the first to the last broadcast on the fixed 1930 to 1962 axis. */
  function runStrip(first, last, cls = 'g-strip', h = 18) {
    const span = API.runSpan(first, last);
    return svgEl('svg', { class: cls, viewBox: `0 0 100 ${h}`, preserveAspectRatio: 'none', 'aria-hidden': 'true' },
      svgEl('line', { class: 'g-axis', x1: 0, y1: h - 0.5, x2: 100, y2: h - 0.5 }),
      span ? svgEl('rect', { x: (span.from * 100).toFixed(2), y: h - 15, width: ((span.to - span.from) * 100).toFixed(2), height: 15 }) : null);
  }
  /** An event line: the facts joined by " · ", each separator kept with the fact before it. */
  function eventLine(facts, cls = 'caption') {
    const parts = API.eventParts(facts);
    if (!parts.length) return null;
    return el('span', { class: `g-event ${cls}` }, ...parts.flatMap((p, i) => [i ? ' ' : null, el('span', {}, p.replace(/ \u00b7$/, '\u00a0\u00b7'))]));
  }
  /** The show tile: window, name, run strip, facts, on the genre's board. `facts` replaces the two
      default facts (Home's night tiles say the episode, not the run); `href` replaces the series link. */
  function showTile(s, { href = null, facts = null } = {}) {
    const eps = typeof s.episodes === 'number' ? s.episodes : null;
    const lines = facts || [years(s.first, s.last) || 'Undated', eps !== null ? plural(eps, 'episode', 'episodes') : null];
    return el('li', { class: 'g-tile-li' },
      el('a', { class: 'g-tile', href: href || `?series=${encodeURIComponent(s.key)}`, dataset: { genre: s.genre || '' } },
        pictureWindow(s, 200),
        el('span', { class: 'g-name', dataset: { step: String(API.nameStep(s.name)) } }, s.name),
        runStrip(s.first, s.last),
        el('span', { class: 'g-facts caption' }, ...lines.filter(Boolean).map(t => el('span', {}, t)))));
  }
  /** The head board (series, episode, ear drama): the window, the kicker, the name, the facts, and
      the run strip full width under both. Built in D3-1; the pages adopt it in D3-3. */
  function headBoard({ series, kicker, name, facts, first, last }) {
    const slot = typeof matchMedia === 'function' && matchMedia('(min-width: 1024px)').matches ? 176
      : typeof matchMedia === 'function' && matchMedia('(min-width: 600px)').matches ? 128 : 96;
    return el('header', { class: 'g-head', dataset: { genre: (series && series.genre) || '' } },
      pictureWindow(series, slot),
      el('div', { class: 'g-head-text' },
        kicker ? el('span', { class: 'g-kicker caption' }, kicker) : null,
        el('h1', { class: 'g-head-name', dataset: { step: String(API.nameStep(name)) }, tabindex: '-1' }, name),
        eventLine(facts || [], 'caption g-head-facts')),
      runStrip(first, last, 'g-strip g-head-strip', 56));
  }
  /** A date as an event line's fact, as the catalog stores it (R1, the same on every platform), never
      broken at its hyphens. */
  function factDate(iso) { return iso ? iso.replace(/-/g, '\u2011') : null; }
  const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  /** The date block: the month and year in small caps over the day, on the series' board; an undated
      numbered episode says "No." over its number. */
  function dateBlock(ep, genre, key) {
    const d = ep.date || '';
    const [y, mo, day] = [d.slice(0, 4), +d.slice(5, 7) || 0, +d.slice(8, 10) || 0];
    let small = '', big = '';
    if (day && mo) { small = `${MON[mo - 1]} \u2019${y.slice(2)}`; big = String(day); }
    else if (mo) { small = `\u2019${y.slice(2)}`; big = MON[mo - 1]; }
    else if (y) { big = y; }
    else if (ep.num !== null && ep.num !== undefined) { small = 'No.'; big = String(ep.num); }
    const b = el('span', { class: 'g-date', 'aria-hidden': 'true', dataset: { genre: genre || '' } },
      el('span', { class: 'g-date-small' }, small), el('span', { class: 'g-date-big', dataset: { len: String(big.length) } }, big));
    if (!genre && key) b.dataset.series = key;
    return b;
  }
  /** Fills windows and date blocks that know only their series key, from the series index. */
  let gPending = false;
  function paintGrammar() {
    if (gPending) return;
    gPending = true;
    queueMicrotask(() => {
      gPending = false;
      const nodes = [...document.querySelectorAll('.g-window[data-series]:not([data-done]), .g-date[data-series]:not([data-done])')];
      if (!nodes.length) return;
      nodes.forEach(n => { n.dataset.done = '1'; });
      API.seriesIndex().then(({ byKey }) => nodes.forEach(n => {
        const s = byKey.get(n.dataset.series);
        if (!s) return;
        if (n.classList.contains('g-window')) fillWindow(n, s, +n.dataset.slot || 48);
        else n.dataset.genre = s.genre || '';
      })).catch(() => nodes.forEach(n => { delete n.dataset.done; }));
    });
  }
  new MutationObserver(paintGrammar).observe(document.body, { childList: true, subtree: true });

  /* ---- Rows and cards ---- */

  /** An episode row (§6.4b): the visual (the date block in one series' list, the series' window where
      series mix; R1, the date leads), the title, the sub line, the length, Play. */
  function episodeRow(ep, { showSeries = false, note = null, genre = null } = {}) {
    const progress = Store.progress(ep.id);
    const dateText = ep.date && (ep.date.length === 10 ? fmtLongDate(ep.date) : ep.date);
    const sub = eventLine(showSeries ? [ep.seriesName, factDate(ep.date) || 'Undated', note] : [note]);
    const len = fmtLength(ep.length);
    const link = el('a', { class: 'ep-link g-link', href: `?item=${encodeURIComponent(ep.id)}`,
                           'aria-label': [epTitle(ep), showSeries ? ep.seriesName : null, dateText || 'Undated', note, len].filter(Boolean).join(', ') },
      showSeries ? pictureWindow({ key: ep.series, name: ep.seriesName }, 48) : dateBlock(ep, genre, ep.series),
      el('span', { class: 'g-text' },
        el('span', { class: 'ep-title body-strong' }, epTitle(ep)),
        sub ? el('span', { class: 'ep-sub' }, sub) : null,
        progress > 0 ? el('span', { class: 'ep-progress', 'aria-hidden': 'true' },
          el('span', { style: null, dataset: { p: String(Math.round(progress * 100)) } })) : null));
    const row = el('li', { class: 'ep-row g-row' }, link,
      len ? el('span', { class: 'g-len tabular', 'aria-hidden': 'true' }, len) : null,
      ep.url ? el('button', {
        type: 'button', class: 'icon-btn g-play', 'aria-label': `Play ${epTitle(ep)}, ${ep.date || 'undated'}`,
        onclick: () => Player.load({ ...ep, title: epTitle(ep) }),
      }, icon('play')) : null);
    return row;
  }
  function episodeList(eps, opts) {
    const ul = el('ul', { class: 'ep-list' });
    eps.forEach(e => ul.append(episodeRow(e, opts)));
    paintProgress(ul);
    return ul;
  }
  /** Progress widths are set from data-p so the stylesheet keeps no inline styles. */
  function paintProgress(root) {
    root.querySelectorAll('.ep-progress > span[data-p]').forEach(s => { s.style.width = `${s.dataset.p}%`; });
  }

  function shelf(title, items, idBase) {
    const h = el('h2', { class: 'section-header', id: `${idBase}-h` }, title);
    const ul = el('ul', { class: 'rail g-rail', 'aria-labelledby': `${idBase}-h` });
    items.forEach(s => ul.append(showTile(s)));
    return el('section', { class: 'shelf' }, h, ul);
  }
  /** A series in a list (§6.4b's row): its window, the name, an event line of its facts. */
  function seriesRow(s) {
    const sub = eventLine([s.networks, years(s.first, s.last) || 'Undated',
      s.episodes ? plural(s.episodes, 'episode', 'episodes') : null]);
    return el('li', { class: 'series-row g-row' },
      el('a', { class: 'g-link', href: `?series=${encodeURIComponent(s.key)}` },
        pictureWindow(s, 48),
        el('span', { class: 'g-text' }, el('span', { class: 'ep-title body-strong' }, s.name),
          sub ? el('span', { class: 'ep-sub' }, sub) : null)));
  }

  /* ================================================================
     ROUTER
  ================================================================ */

  function parseRoute() {
    const p = API.pathQuery(location.pathname) || new URLSearchParams(location.search);
    if (p.get('item')) return { view: 'episode', id: p.get('item'), p };
    if (p.get('series')) return { view: 'show', key: p.get('series'), p };
    if (p.get('person')) return { view: 'person', id: p.get('person'), p };
    if (p.get('production') || p.get('play')) return { view: 'plays', p };
    const old = p.get('view');
    if (RENAMED[old]) {
      if (old === 'plays') p.set('kind', 'plays');
      p.set('view', RENAMED[old]);
      history.replaceState(null, '', `?${p}${location.hash}`);
    }
    return { view: VIEW_OF[p.get('view')] || 'listen', p };
  }

  let firstRoute = true;
  function route() {
    takeRoomLink();
    takeInviteLink();
    const r = parseRoute();
    VIEWS.forEach(v => { $(`view-${v}`).hidden = v !== r.view; });
    // A production is the person's own, so it sits under Library; a play's page under Browse.
    const tab = r.view === 'plays' && r.p.get('production') ? 'library' : TAB_OF[r.view];
    document.querySelectorAll('[data-nav]').forEach(a => {
      const on = a.dataset.nav === tab;
      a.classList.toggle('active', on);
      if (on) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current');
    });
    if (r.view !== 'plays') PlaysUI.leave();
    ({ listen: renderListen, series: renderBrowse, show: renderShow, episode: renderEpisode, person: renderPerson,
       radio: renderRadio, surprise: renderSurprise, plays: renderPlays, search: renderSearch,
       library: renderLibrary })[r.view](r);
    if (!firstRoute) {
      $('main-content').scrollTop = 0;
      const h = $(`view-${r.view}`).querySelector('h1');
      if (h) h.focus({ preventScroll: true });
    }
    firstRoute = false;
  }
  /** `?room=CODE` (DEEP_LINKS.md): opens the join sheet with the code filled in, then leaves the address. */
  function takeRoomLink() {
    const p = new URLSearchParams(location.search);
    const code = p.get('room');
    if (code === null) return;
    p.delete('room');
    const q = p.toString();
    history.replaceState(null, '', q ? `?${q}` : location.pathname);
    TogetherUI.open(code);
  }

  /** An ear drama invite (DEEP_LINKS.md, PLAYS-DESIGN §11.7 rule 3): held for this tab, cleared from the address, shown in Library's Ear dramas. */
  function takeInviteLink() {
    const tok = PlaysShare.inviteToken(location);
    if (!tok) return;
    PlaysShare.holdInvite(tok);
    history.replaceState(null, '', '?view=library&tab=dramas');
  }

  function setTitle(...parts) { document.title = [...parts.filter(Boolean), 'Ear Drama'].join(' · '); }

  function navigate(href, replace = false) {
    if (replace) history.replaceState(null, '', href); else history.pushState(null, '', href);
    route();
  }

  document.addEventListener('click', (e) => {
    const a = e.target.closest('a[href^="?"]');
    if (!a || e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    e.preventDefault();
    if (a.closest('dialog[open]')) a.closest('dialog').close();
    navigate(a.getAttribute('href'));
  });
  window.addEventListener('popstate', route);

  /* ================================================================
     LISTEN
  ================================================================ */

  function renderListen() {
    setTitle();
    const body = $('listen-body');
    body.replaceChildren();

    const cont = Store.inProgress(10);
    if (cont.length) {
      body.append(el('section', { class: 'block', 'aria-labelledby': 'cont-h' },
        el('h2', { class: 'section-header', id: 'cont-h' }, 'Continue listening'),
        episodeList(cont, { showSeries: true })));
    }
    const follows = Store.follows();
    if (follows.length) body.append(shelf('Following', follows, 'follow'));

    // The day board and the night, then the most downloaded shows (WEB-DESIGN §6.4c).
    const today = new Date();
    const homeBox = el('div');
    body.append(homeBox);
    load(homeBox, async () => {
      const [rows, idx] = await Promise.all([API.thisDay(today, undefined, Infinity), API.seriesIndex(),
        API.manifest().then(m => { manifest = m; })]);
      return { rows, idx };
    }, ({ rows, idx }) => {
      const shows = idx.rows.filter(s => API.isShow(s.episodes));
      if (!rows.length && !shows.length) {
        homeBox.append(stateBox('empty', { text: 'Nothing in the catalog yet.' }));
        return;
      }
      if (rows.length) homeBox.append(dayAndNight(rows, idx, today));
      if (shows.length) {
        const key = s => s.sortName || s.name;
        const top = [...shows].sort(API.byDownloads((a, b) => key(a).localeCompare(key(b), 'en', { sensitivity: 'base' }))).slice(0, 12);
        const h = el('h2', { class: 'section-header', id: 'popular-h' }, 'Most downloaded');
        const ul = el('ul', { class: 'rail g-rail', 'aria-labelledby': 'popular-h' });
        top.forEach(s => ul.append(showTile(s)));
        homeBox.append(el('section', { class: 'shelf' },
          el('div', { class: 'block-head' }, h, el('a', { class: 'caption', href: '?view=browse' }, `All ${num.format(shows.length)} shows`)), ul));
      }
    });
  }

  /** The day board (the years this date was on the air, stacked by genre) and the night picked on it. */
  function dayAndNight(rows, idx, today) {
    const dy = API.dayYears(rows, (r) => (idx.byKey.get(r.series) || {}).genre);
    const box = el('div');
    if (!dy.years.length) return box;
    const first = Math.min(1930, dy.years[0].year), last = Math.max(dy.years[dy.years.length - 1].year, first + 1);
    const W = (last - first + 1) * 10, H = 64, top = Math.max(...dy.years.map(y => y.total));
    const byYear = new Map(dy.years.map(y => [y.year, y]));
    const night = el('section', { class: 'block g-night' });
    const axisSel = el('span', {}, '');
    const svg = svgEl('svg', { class: 'g-years', viewBox: `0 0 ${W} ${H}`, preserveAspectRatio: 'none', role: 'radiogroup',
      'aria-label': `Surviving broadcasts on ${monthDay.format(today)} by year` });
    const bars = new Map();
    for (let y = first; y <= last; y++) {
      const x = (y - first) * 10, o = byYear.get(y);
      if (!o) { svg.append(svgEl('rect', { class: 'g-yr-zero', x, y: H - 1, width: 8, height: 1 })); continue; }
      const g = svgEl('g', { class: 'g-yr', role: 'radio', 'aria-checked': 'false', tabindex: '-1', 'data-year': y,
        'aria-label': `${y}, ${plural(o.total, 'broadcast', 'broadcasts')}` });
      g.append(svgEl('rect', { class: 'g-yr-hit', x: x - 1, y: 0, width: 10, height: H }));
      let t = H;
      for (const k of [...API.genreOrder, '']) {
        const n = o.genres[k]; if (!n) continue;
        const h = (n / top) * (H - 4);
        t -= h;
        g.append(svgEl('rect', { class: 'g-yr-bar', 'data-genre': k, x, y: t.toFixed(1), width: 8, height: h.toFixed(1) }));
      }
      g.append(svgEl('rect', { class: 'g-yr-sel', x: x - 1.5, y: (t - 1.5).toFixed(1), width: 11, height: (H - t + 1.5).toFixed(1), rx: 1 }));
      bars.set(y, g);
      svg.append(g);
    }
    const select = (y, focus) => {
      bars.forEach((g, k) => { g.setAttribute('aria-checked', String(k === y)); g.setAttribute('tabindex', k === y ? '0' : '-1'); });
      axisSel.textContent = String(y);
      paintNight(y);
      if (focus) bars.get(y).focus();
    };
    const ys = [...bars.keys()];
    svg.addEventListener('click', (e) => {
      const g = e.target.closest('.g-yr');
      if (g) select(+g.dataset.year);
    });
    svg.addEventListener('keydown', (e) => {
      const g = e.target.closest('.g-yr');
      if (!g) return;
      const i = ys.indexOf(+g.dataset.year);
      const next = { ArrowRight: ys[i + 1], ArrowDown: ys[i + 1], ArrowLeft: ys[i - 1], ArrowUp: ys[i - 1], Home: ys[0], End: ys[ys.length - 1] }[e.key];
      if (next !== undefined) { e.preventDefault(); select(next, true); }
      else if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); select(ys[i]); }
    });
    const facts = [plural(dy.count, 'surviving broadcast', 'surviving broadcasts'), plural(dy.years.length, 'year', 'years')];
    const board = el('section', { class: 'g-day', 'aria-labelledby': 'day-h' },
      el('p', { class: 'g-kicker caption' }, 'This day in radio'),
      el('h2', { class: 'view-heading g-day-date', id: 'day-h' }, monthDay.format(today)),
      el('p', { class: 'caption' }, el('span', { class: 'nw' }, `${facts[0]} ·`), ' ', el('span', { class: 'nw' }, facts[1])),
      el('div', { class: 'g-years-wrap' }, svg,
        el('div', { class: 'g-axis-labels caption tabular', 'aria-hidden': 'true' }, el('span', {}, String(first)), axisSel, el('span', {}, String(last)))),
      el('ul', { class: 'g-legend caption' }, ...dy.genres.map(g =>
        el('li', { dataset: { genre: g } }, el('i', { 'aria-hidden': 'true' }), genreLabel(g)))));
    const paintNight = (y) => {
      const ofYear = rows.filter(r => r.date && r.date.startsWith(String(y)));
      const nt = API.nightShows(ofYear, (r) => idx.byKey.get(r.series));
      const all = nt.shows;
      const draw = (n) => {
        const ul = el('ul', { class: 'g-grid' });
        all.slice(0, n).forEach(r => {
          const s = idx.byKey.get(r.series);
          ul.append(showTile(s, { href: `?item=${encodeURIComponent(r.id)}`, facts: [epTitle(r), fmtLength(r.length)] }));
        });
        return ul;
      };
      const h = el('h2', { class: 'section-header', id: 'night-h' }, `${monthDay.format(today)}, ${y}`);
      night.replaceChildren(el('div', { class: 'block-head' }, h,
        nt.singles ? el('span', { class: 'caption' }, plural(nt.singles, 'single recording', 'single recordings')) : null));
      if (!all.length) return;
      let list = draw(6);
      night.append(list);
      if (all.length > 6) {
        const more = el('button', { type: 'button', class: 'btn btn-ghost' }, `All ${num.format(all.length)} shows that night`);
        more.addEventListener('click', () => { const next = draw(all.length); list.replaceWith(next); list = next; more.remove(); });
        night.append(more);
      }
    };
    box.append(board, night);
    select(dy.peak);
    return box;
  }

  function genreLabel(g) { return (manifest && manifest.genreNames && manifest.genreNames[g]) || g; }

  /* ================================================================
     RADIO: Tonight in 19xx on the one clock (R9, R10, R14; contract §8)
  ================================================================ */

  /* Harness door, local servers only: ?now=ISO runs the clock from that instant, so a
     screenshot can show an evening on the air whatever the hour. */
  const NOW_DOOR = (() => {
    const v = new URLSearchParams(location.search).get('now');
    const local = ['localhost', '127.0.0.1', '[::1]'].includes(location.hostname);
    const t = v && local ? Date.parse(v) : NaN;
    return isFinite(t) ? { at: t, set: Date.now() } : null;
  })();
  const clockNow = () => (NOW_DOOR ? NOW_DOOR.at + (Date.now() - NOW_DOOR.set) : Date.now());

  const localClock = new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit' });
  /** "19:30" as printed in the paper's Eastern clock, drawn "7:30 PM". */
  function fmtEt(hhmm) {
    const [h, m] = hhmm.split(':').map(Number);
    return `${h % 12 || 12}:${String(m).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
  }
  /** True when this device's clock reads the same as the evening's zone at that instant. */
  function sameAsZone(iso, zone) {
    const z = new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit', timeZone: zone });
    return z.format(new Date(iso)) === localClock.format(new Date(iso));
  }

  /* Listening live: the slot on the air plays from where the clock stands; when its recording
     ends, the next surviving slot plays when its own time comes. A pause, another episode, or
     the sleep timer ends it, and so does the evening's last slot: nothing plays after (R14). */
  // { slots, day (an evening) or station (a genre), details, playing: utc_start of the slot loaded, waiting }
  let live = null;
  let liveTimer = null;

  function cardOf(d, seriesName) {
    return { id: d.id, title: epTitle(d), series: d.series, seriesName, date: d.date, network: d.network || null,
             url: d.recordings[0].url, length: d.recordings[0].length || d.length, li: d.li, ltp: d.ltp };
  }

  function stopLive() {
    live = null;
    clearInterval(liveTimer);
    liveTimer = null;
    if (!$('view-radio').hidden) paintRadio();
  }

  function liveTick() {
    if (!live) return;
    const where = API.onAir(live.slots, clockNow());
    if (where.phase === 'after') { stopLive(); return; }
    const s = where.index >= 0 ? live.slots[where.index] : null;
    const d = s && s.episode && live.details.get(s.episode.id);
    if (!d || live.playing === s.utc_start) return;
    if (live.playing && !live.waiting) return;   // the listener took the player elsewhere
    const at = (clockNow() - Date.parse(s.utc_start)) / 1000;
    const length = d.recordings[0].length || d.length || s.length_s || s.length_min * 60;
    if (at >= length - 5) return;                 // its recording ended inside its slot
    live.playing = s.utc_start;
    live.waiting = false;
    live.id = d.id;
    Player.load(cardOf(d, s.episode.series), { at: Math.max(0, at), arc: false });
    if (!$('view-radio').hidden) paintRadio();
  }

  function tuneIn(day, details, station = null, slots = day && day.slots) {
    live = { slots, day, station, details,
             playing: null, waiting: true, id: null };
    clearInterval(liveTimer);
    liveTimer = setInterval(liveTick, 1000);
    liveTick();
    announce('Listening live');
  }

  Player.onChange((kind) => {
    if (!live || !live.playing) return;
    const cur = Player.current;
    if (!cur || cur.id !== live.id || Player.fired) { stopLive(); return; }
    if (kind === 'ended') live.waiting = true;
    else if (kind === 'pause' && !Player.audio.ended) stopLive();
  });

  let radioState = null;      // { day, base, details, stations } for the view's repaint
  let radioTimer = null;

  function renderRadio() {
    setTitle('Stations');
    const body = $('radio-body');
    clearInterval(radioTimer);
    load(body, async () => {
      // A missing or unreachable stations file leaves Tonight alone, as before any station existed.
      const stations = API.stations().catch((e) => { console.error(e); return []; });
      const day = await API.tonight(API.localDate(new Date(clockNow())));
      if (!day) return { day: null, stations: await stations };
      return { day, base: day, details: await eveningDetails(day), stations: await stations };
    }, (data) => {
      radioState = data;
      if (!data.day && !data.stations.length) {
        body.append(stateBox('empty', { text: 'No evening is published for today.' }));
        return;
      }
      paintRadio();
      radioTimer = setInterval(() => {
        if ($('view-radio').hidden) { clearInterval(radioTimer); return; }
        paintRadio();
      }, 15000);
    });
  }

  async function eveningDetails(day) {
    const ids = day.slots.filter(s => s.episode).map(s => s.episode.id);
    const got = await Promise.all(ids.map(id => API.episodeDetail(id)));
    return new Map(got.filter(Boolean).map(d => [d.id, d]));
  }

  /** Decision 067: the same date in another published year, a whole evening of its own on tonight's clock. */
  function yearChoices(base) {
    const all = [base, ...(base.years || []).map(y => ({ ...y, zone: base.zone, years: base.years }))];
    return all.sort((a, b) => byText(a.evening, b.evening));
  }
  function byText(a, b) { return a < b ? -1 : a > b ? 1 : 0; }

  async function pickYear(evening) {
    const base = radioState.base;
    const day = evening === base.evening ? base : yearChoices(base).find(e => e.evening === evening);
    if (!day) return;
    if (live) stopLive();
    const details = await eveningDetails(day);
    radioState = { ...radioState, day, base, details };
    paintRadio();
    announce(`Tonight in ${evening.slice(0, 4)}`);
  }

  /* The stations row (WEB-DESIGN §4.9): Tonight first, then each genre station, each with what is
     on now and one Listen live. A station's episodes are fetched only when someone tunes in. */
  function liveButton(isLive, canListen, name, start) {
    if (isLive) {
      return el('button', { type: 'button', class: 'btn btn-live', 'aria-pressed': 'true',
                            onclick: () => { Player.pause(); stopLive(); } }, 'Listening live');
    }
    return canListen ? el('button', { type: 'button', class: 'btn btn-primary', 'aria-label': `Listen live to ${name}`,
                                      onclick: start }, icon('play'), 'Listen live') : null;
  }

  function stationRow(name, slot, note, button) {
    const ep = slot && !slot.withheld && slot.episode;
    return el('li', { class: 'station' },
      ep ? artTile({ key: ep.id.split('|')[0], name: ep.series }) : null,
      el('div', { class: 'station-main' },
        el('span', { class: 'body-strong' }, name),
        ep ? el('span', { class: 'body' }, ep.series) : null,
        ep && ep.title ? el('span', { class: 'caption station-title' }, ep.title) : null,
        note ? el('span', { class: 'caption' }, note) : null),
      button);
  }

  async function tuneInStation(st) {
    const slots = API.ahead(st.slots, clockNow());
    const ids = slots.filter(s => s.episode && !s.withheld).map(s => s.episode.id);
    const got = await Promise.all(ids.map(id => API.episodeDetail(id).catch(() => null)));
    tuneIn(null, new Map(got.filter(Boolean).map(d => [d.id, d])), st.genre, slots);
    paintRadio();
  }

  function stationsList(day, details, stations) {
    const rows = [];
    if (day) {
      const where = API.onAir(day.slots, clockNow());
      const slot = where.index >= 0 ? day.slots[where.index] : null;
      const d = slot && slot.episode && details.get(slot.episode.id);
      const last = day.slots[day.slots.length - 1];
      const note = where.phase === 'before' ? `Starts at ${localClock.format(new Date(day.slots[0].utc_start))}`
        : where.phase === 'after' ? `Ended at ${localClock.format(new Date(last.utc_end))}`
        : slot && !d ? (slot.withheld || slot.episode ? 'Not in the catalog' : 'Not surviving') : null;
      const name = `Tonight in ${day.evening.slice(0, 4)}`;
      rows.push(stationRow(name, d ? slot : null, note,
        liveButton(live && live.day === day, Boolean(d), name, () => { tuneIn(day, details); paintRadio(); })));
    }
    for (const st of stations) {
      const on = API.onNow(st.slots, clockNow());
      const playable = on && !on.slot.withheld && on.slot.episode;
      rows.push(stationRow(st.name, on && on.slot, on && !playable ? 'Not in the catalog' : null,
        liveButton(live && live.station === st.genre, Boolean(playable), st.name, () => tuneInStation(st))));
    }
    return el('ul', { class: 'stations', 'aria-label': 'Stations' }, ...rows);
  }

  function paintRadio() {
    if (!radioState) return;
    const { day, details, base } = radioState;
    const stations = radioState.stations || [];
    const body = $('radio-body');
    if (!day) {
      body.replaceChildren(stationsList(null, null, stations));
      return;
    }
    const where = API.onAir(day.slots, clockNow());
    const zone = day.zone;

    const list = el('ol', { class: 'slots' });
    day.slots.forEach((s, i) => {
      const d = s.episode && details.get(s.episode.id);
      const now = i === where.index;
      const local = localClock.format(new Date(s.utc_start));
      const same = sameAsZone(s.utc_start, zone);
      const time = el('div', { class: 'slot-time' },
        el('span', { class: 'tabular' }, same ? `${local} ET` : local),
        same ? null : el('span', { class: 'caption tabular' }, `${fmtEt(s.et_start)} ET`));
      let main;
      if (d) {
        main = el('a', { class: 'slot-main has-art', href: `?item=${encodeURIComponent(d.id)}` },
          artTile({ key: d.series, name: s.episode.series }),
          el('span', { class: 'slot-text' },
            el('span', { class: 'body-strong' }, s.episode.series),
            el('span', { class: 'body slot-title' }, epTitle(d)),
            el('span', { class: 'caption' }, [now ? 'Now' : null, `${s.length_min} min`].filter(Boolean).join(' · '))));
      } else {
        // A gap is stated, never filled (R9). The paper's printed text stays in the file as
        // witness and is not drawn until the owner rules on it (WEB-DESIGN §4.9).
        const why = s.withheld || s.episode ? 'Not in the catalog' : 'Not surviving';
        main = el('div', { class: 'slot-main' },
          s.known_series ? el('span', { class: 'body' }, s.known_series) : null,
          el('span', { class: 'caption' }, [now ? 'Now' : null, why, `${s.length_min} min`].filter(Boolean).join(' · ')));
      }
      const play = d ? el('button', {
        type: 'button', class: 'icon-btn', 'aria-label': `Play ${epTitle(d)}, ${s.episode.series}`,
        onclick: () => { if (live) stopLive(); Player.load(cardOf(d, s.episode.series)); },
      }, icon('play')) : null;
      list.append(el('li', { class: `slot${d ? '' : ' slot-gap'}${now ? ' slot-now' : ''}`,
                             'aria-current': now ? 'time' : null }, time, main, play));
    });

    const w = day.witness || {};
    const choices = base && base.years && base.years.length ? yearChoices(base) : null;
    const years = choices ? el('label', { class: 'filter radio-year' }, el('span', { class: 'caption' }, 'Year'),
      el('select', { 'aria-label': 'Year', onchange: (e) => pickYear(e.target.value) },
        ...choices.map(c => el('option', { value: c.evening, selected: c.evening === day.evening ? '' : null },
          c.evening.slice(0, 4))))) : null;
    body.replaceChildren(
      stationsList(day, details, stations),
      el('header', { class: 'radio-head' },
        el('h2', { class: 'section-header', id: 'tonight-h' }, `Tonight in ${day.evening.slice(0, 4)}`),
        years,
        el('p', { class: 'body' }, fmtLongDate(day.evening)),
        el('p', { class: 'caption' }, [day.network, day.station].filter(Boolean).join(' · '))),
      el('section', { 'aria-labelledby': 'tonight-h' }, list),
      w.url ? el('p', { class: 'caption witness' }, 'Schedule: ',
        el('a', { href: w.url, rel: 'noopener', target: '_blank' }, w.paper || 'newspaper listing'),
        w.via ? `, via ${w.via.replace(/\s*\(.*\)$/, '')}` : '') : null);
  }

  /* ================================================================
     SERIES BROWSE
  ================================================================ */

  const decadeOf = (s) => (s.first ? `${s.first.slice(0, 3)}0` : null);
  const networksOf = (s) => (s.networks ? s.networks.split(', ') : []);

  /* Browse lists series and plays together (WEB-DESIGN §4.3). A play's record carries no genre,
     decade, or network, so any of those narrows to series; "Has a script" keeps what carries one:
     the plays, and a series with an episode that links one (its index row's `scripts`). */
  function browseFilter(rows, f, ...skips) {
    const on = (k) => !skips.includes(k);
    return rows.filter(s => (on('kind') ? !f.kind || s.kind === f.kind : true)
      && (s.kind === 'plays' || !!f.singles === !API.isShow(s.episodes))
      && (on('script') ? !f.script || s.hasScript : true)
      && (on('genre') ? !f.genre || s.genre === f.genre : true)
      && (on('decade') ? !f.decade || decadeOf(s) === f.decade : true)
      && (on('network') ? !f.network || networksOf(s).includes(f.network) : true));
  }

  /** A castable script as a Browse row (contract: castable-scripts.json, read through API). */
  function playItem(script) {
    return { kind: 'plays', hasScript: true, key: script.id, name: script.title, sortName: script.sort_name, script,
             author: PlaysCore.authorLine(script), episodes: 0, first: null, genre: null, networks: null };
  }
  function playMeta(script) {
    const parts = PlaysCore.castParts(script).filter(x => PlaysCore.isSpeaking(x.id)).length;
    return [PlaysCore.authorLine(script), plural(parts, 'part', 'parts')].filter(Boolean).join(' · ');
  }
  function playRow(script) {
    const sub = eventLine([PlaysCore.authorLine(script),
      plural(PlaysCore.castParts(script).filter(x => PlaysCore.isSpeaking(x.id)).length, 'part', 'parts')]);
    return el('li', { class: 'series-row g-row ear-drama-only' },
      el('a', { class: 'g-link', href: `?play=${encodeURIComponent(script.id)}` },
        pictureWindow({ name: script.title, picture: null }, 48),
        el('span', { class: 'g-text' }, el('span', { class: 'ep-title body-strong' }, script.title),
          sub ? el('span', { class: 'ep-sub' }, sub) : null)));
  }
  /** The plays, or none when the file does not load: Browse and Search still list the series. */
  const castable = () => API.castableScripts().catch((err) => { console.error(err); return []; });

  function fillSelect(sel, allLabel, counts, current, label = (k) => k) {
    sel.replaceChildren(el('option', { value: '' }, allLabel));
    const keys = [...counts.keys()];
    keys.forEach(k => sel.append(el('option', { value: k, selected: k === current }, `${label(k)} (${num.format(counts.get(k))})`)));
    if (current && !counts.has(current)) sel.append(el('option', { value: current, selected: true }, `${label(current)} (0)`));
    sel.parentElement.hidden = !counts.size && !current;
  }

  function renderBrowse(r) {
    setTitle('Browse');
    const kind = ['series', 'plays'].includes(r.p.get('kind')) ? r.p.get('kind') : '';
    const f = { kind, script: r.p.get('script') === '1', genre: r.p.get('genre') || '', decade: r.p.get('decade') || '',
                network: r.p.get('network') || '', sort: r.p.get('sort') || 'popular', singles: r.p.get('singles') === '1' };
    const body = $('browse-body');
    $('f-sort').value = f.sort;
    $('f-script').checked = f.script;
    load(body, async () => {
      const [idx, m, scripts] = await Promise.all([API.seriesIndex(), API.manifest(), onTV() ? [] : castable()]);
      manifest = m;
      return { rows: [...idx.rows.map(s => ({ ...s, kind: 'series', hasScript: !onTV() && s.scripts > 0 })), ...scripts.map(playItem)] };
    }, ({ rows }) => {
      const count = (list, fn) => {
        const c = new Map();
        list.forEach(s => [].concat(fn(s)).forEach(k => { if (k) c.set(k, (c.get(k) || 0) + 1); }));
        return c;
      };
      const byCount = (c) => new Map([...c].sort((a, b) => b[1] - a[1] || String(a[0]).localeCompare(b[0])));
      const kinds = count(browseFilter(rows, f, 'kind'), s => s.kind);
      fillSelect($('f-kind'), 'Any kind', new Map(['series', 'plays'].filter(k => kinds.has(k)).map(k => [k, kinds.get(k)])),
        f.kind, k => (k === 'plays' ? 'Plays' : 'Series'));
      const scripted = browseFilter(rows, f, 'script').filter(s => s.hasScript).length;
      $('f-script-label').textContent = `Has a script (${num.format(scripted)})`;
      $('f-script-label').parentElement.hidden = !scripted && !f.script;
      fillSelect($('f-genre'), 'All genres', byCount(count(browseFilter(rows, f, 'genre'), s => s.genre)), f.genre,
        k => manifest.genreNames[k] || k);
      const dec = count(browseFilter(rows, f, 'decade'), decadeOf);
      fillSelect($('f-decade'), 'All decades', new Map([...dec].sort()), f.decade, k => `${k}s`);
      const nets = byCount(count(browseFilter(rows, f, 'network'), networksOf));
      fillSelect($('f-network'), 'All networks', new Map([...nets].slice(0, 40)), f.network);

      const list = browseFilter(rows, f);
      const key = s => s.sortName || s.name;
      const byName = (a, b) => key(a).localeCompare(key(b), 'en', { sensitivity: 'base' });
      const sorters = {
        popular: API.byDownloads(byName),
        name: byName,
        count: (a, b) => b.episodes - a.episodes || byName(a, b),
        first: (a, b) => (a.first || '9999').localeCompare(b.first || '9999') || byName(a, b),
      };
      list.sort(sorters[f.sort] || sorters.popular);
      const plays = list.filter(s => s.kind === 'plays').length;
      const series = list.length - plays;
      const here = (over) => {
        const p = new URLSearchParams({ view: 'browse' });
        const v = { ...f, ...over };
        for (const k of ['kind', 'genre', 'decade', 'network', 'sort']) if (v[k] && !(k === 'sort' && v[k] === 'popular')) p.set(k, v[k]);
        if (v.script) p.set('script', '1');
        if (v.singles) p.set('singles', '1');
        return `?${p}`;
      };
      const other = browseFilter(rows, { ...f, singles: !f.singles }).filter(s => s.kind === 'series').length;
      const countLine = $('browse-count');
      countLine.replaceChildren(...[
        el('span', { class: 'g-count nw' }, plural(series, f.singles ? 'single recording' : 'show', f.singles ? 'single recordings' : 'shows')),
        plays ? el('span', { class: 'caption nw' }, plural(plays, 'play', 'plays')) : null,
        other ? el('a', { class: 'caption nw', href: here({ singles: !f.singles }) },
          f.singles ? plural(other, 'show', 'shows') : plural(other, 'single recording', 'single recordings')) : null].filter(Boolean));

      const fld = API.decadeField(browseFilter(rows, f, 'genre', 'decade').filter(s => s.kind === 'series'));
      const sectionHead = (title, right) => el('div', { class: 'block-head' }, el('h2', { class: 'section-header' }, title), right);
      const fieldBox = fld.genres.length ? el('section', { class: 'g-field-sec', 'aria-label': 'Shows by decade and genre' },
        sectionHead('By decade and genre', fld.none ? el('span', { class: 'caption' }, `${num.format(fld.none)} with no genre or date`) : null),
        el('div', { class: 'g-field', role: 'grid', style: `--n: ${fld.decades.length}` },
          el('span', { class: 'g-field-corner' }),
          ...fld.decades.map(d => el('span', { class: 'g-field-head caption tabular', role: 'columnheader', 'aria-label': `${d}s` }, `\u2019${String(d % 100).padStart(2, '0')}s`)),
          ...fld.genres.flatMap(g => [
            el('span', { class: 'g-field-label caption', dataset: { genre: g } }, el('i', { 'aria-hidden': 'true' }), el('span', {}, genreLabel(g))),
            ...fld.decades.map(d => {
              const n = fld.count(g, d), side = API.fieldSide(n, fld.max);
              if (!n) return el('span', { class: 'g-field-cell', role: 'gridcell' });
              const on = f.genre === g && f.decade === String(d);
              return el('a', { class: 'g-field-cell', role: 'gridcell', dataset: { genre: g }, href: here({ genre: g, decade: String(d) }),
                'aria-label': `${genreLabel(g)}, ${d}s: ${plural(n, 'show', 'shows')}`, 'aria-current': on ? 'true' : null },
                el('span', { class: 'g-field-mark', style: `width: ${side}px; height: ${side}px` }), el('span', { class: 'caption tabular' }, String(n)));
            })]))) : null;

      if (!list.length) {
        const clear = f.sort === 'popular' ? '?view=browse' : `?view=browse&sort=${encodeURIComponent(f.sort)}`;
        body.append(stateBox('empty', { text: 'Nothing matches these filters.', action: { label: 'Clear filters', href: clear } }));
        return;
      }
      const SORT_TITLE = { popular: 'Most downloaded first', name: 'A to Z', count: 'Most episodes', first: 'Oldest first' };
      const grid = el('ul', { class: 'g-grid', 'aria-label': SORT_TITLE[f.sort] || SORT_TITLE.popular });
      let shown = 0;
      const more = el('button', { type: 'button', class: 'btn btn-ghost' }, 'Show more');
      const tileOf = (s) => (s.kind === 'plays'
        ? showTile({ key: s.key, name: s.name, genre: '', first: null, picture: null }, { href: `?play=${encodeURIComponent(s.key)}`, facts: [s.author, plural(PlaysCore.castParts(s.script).filter(x => PlaysCore.isSpeaking(x.id)).length, 'part', 'parts')] })
        : showTile(s));
      const page = () => {
        list.slice(shown, shown + PAGE).forEach(s => grid.append(tileOf(s)));
        shown += PAGE;
        if (shown >= list.length) more.remove();
      };
      more.addEventListener('click', page);
      page();
      const results = el('section', { class: 'g-results' }, sectionHead(SORT_TITLE[f.sort] || SORT_TITLE.popular), grid, shown < list.length ? more : null);
      body.append(el('div', { class: `g-browse${fieldBox ? ' has-field' : ''}` }, fieldBox, results));
    });
  }

  $('browse-filters').addEventListener('change', () => {
    const p = new URLSearchParams({ view: 'browse' });
    for (const k of ['kind', 'genre', 'decade', 'network', 'sort']) {
      const v = $(`f-${k}`).value;
      if (v && !(k === 'sort' && v === 'popular')) p.set(k, v);
    }
    if ($('f-script').checked) p.set('script', '1');
    if (new URLSearchParams(location.search).get('singles') === '1') p.set('singles', '1');
    navigate(`?${p}`, true);
  });

  /* ================================================================
     SERIES PAGE
  ================================================================ */

  function renderShow(r) {
    const body = $('show-body');
    const scope = r.p.get('season');
    load(body, () => API.seriesPage(r.key), (s) => {
      if (s.key !== r.key) {   // a moved series key (contract §3.5): the address names the series it now is
        const p = new URLSearchParams(r.p);
        p.set('series', s.key);
        history.replaceState(null, '', `?${p}${location.hash}`);
      }
      setTitle(s.name);
      const following = Store.isFollowing(s.key);
      const followBtn = el('button', { type: 'button', class: 'btn', 'aria-pressed': String(following) },
        following ? 'Following' : 'Follow');
      followBtn.addEventListener('click', () => {
        const on = Store.toggleFollow({ ...s, episodes: s.episodes.length });
        followBtn.setAttribute('aria-pressed', String(on));
        followBtn.textContent = on ? 'Following' : 'Follow';
        announce(on ? `Following ${s.name}` : `Stopped following ${s.name}`);
      });
      const shareBtn = el('button', { type: 'button', class: 'btn btn-ghost', 'aria-label': `Share ${s.name}` },
        icon('share'), 'Share');
      shareBtn.addEventListener('click', () => share(s.name, API.shareLink('series', s.key)));

      const undated = s.episodes.some(e => !e.date);
      const scopes = [['', 'All'], ...s.seasons.map(x => [x, x]), ...(undated ? [['undated', 'Undated']] : [])];
      const seg = el('div', { class: 'segmented segmented-scroll', role: 'group', 'aria-label': 'Season' });
      scopes.forEach(([v, label]) => {
        const b = el('button', { type: 'button', 'aria-pressed': String((scope || '') === v) }, label);
        b.addEventListener('click', () => {
          const p = new URLSearchParams({ series: s.key });
          if (v) p.set('season', v);
          history.replaceState(null, '', `?${p}`);
          seg.querySelectorAll('button').forEach(x => x.setAttribute('aria-pressed', String(x === b)));
          drawEpisodes(v);
        });
        seg.append(b);
      });

      const countLine = el('p', { class: 'caption', 'aria-live': 'polite' });
      const listBox = el('div');
      const drawEpisodes = (v) => {
        const eps = v === 'undated' ? s.episodes.filter(e => !e.date)
          : v ? s.episodes.filter(e => e.season === v) : s.episodes;
        countLine.textContent = plural(eps.length, 'episode', 'episodes');
        listBox.replaceChildren(eps.length ? episodeList(eps, { genre: s.genre }) : stateBox('empty', { text: 'No episodes in this season.' }));
      };

      const meta = el('p', { class: 'caption' }, seriesMeta({ ...s, episodes: s.episodes.length }));
      const head = el('header', { class: `page-head${s.art ? ' has-face' : ' as-card'}`, dataset: { genre: s.genre || '' } },
        el('div', { class: 'page-head-text' },
          el('h1', { class: 'view-heading', id: 'show-h', tabindex: '-1' }, s.name), meta),
        el('div', { class: 'actions' }, followBtn, shareBtn));
      if (s.art) head.prepend(faceFigure(head, s.art, s.star));
      if (s.genre) {
        genreName(s.genre).then(n => meta.prepend(el('a', { href: `?view=browse&genre=${encodeURIComponent(s.genre)}` }, n),
          ' · '));
      }
      body.append(head);
      if (scopes.length > 2) body.append(seg);
      body.append(countLine, listBox);
      drawEpisodes(scope || '');
    });
  }

  /* ================================================================
     EPISODE DETAIL
  ================================================================ */

  function renderEpisode(r) {
    const body = $('episode-body');
    load(body, async () => {
      const d = await API.episodeDetail(r.id);
      if (!d) throw new API.DataError('missing', r.id);
      const s = await API.seriesPage(d.series).catch(() => null);
      const lines = await Promise.all([API.rightsLine(d.rights, d.rightsBasis), API.manifest()]);
      // Decision 068: an episode whose row links a castable script can become an ear drama,
      // when this browser's copy of the castable file holds that script (contract §3.1).
      const script = d.script && !onTV() ? (await castable()).find(x => x.id === d.script) || null : null;
      return { d, s, rightsLine: lines[0], m: lines[1], script };
    }, ({ d, s, rightsLine, m, script }) => {
      if (d.id !== r.id) history.replaceState(null, '', `?item=${encodeURIComponent(d.id)}`);
      const seriesName = s ? s.name : d.series;
      const title = epTitle(d);
      setTitle(title, d.date, seriesName);
      let chosen = 0;
      const card = () => ({ id: d.id, title, series: d.series, seriesName, date: d.date, network: d.network || null,
                            url: d.recordings[chosen].url, length: d.recordings[chosen].length || d.length,
                            // The measurement belongs to the default copy only.
                            li: chosen === 0 ? d.li : null, ltp: chosen === 0 ? d.ltp : null });

      const resume = Store.resumeAt(d.id, d.recordings[0].length || d.length);
      const playBtn = el('button', { type: 'button', class: 'btn btn-primary' }, icon('play'),
        resume ? `Resume at ${fmtClock(resume)}` : 'Play');
      playBtn.addEventListener('click', () => Player.load(card()));
      const queued = Store.inQueue(d.id);
      const queueBtn = el('button', { type: 'button', class: 'btn', 'aria-pressed': String(queued) },
        icon(queued ? 'queued' : 'queue'), queued ? 'In queue' : 'Add to queue');
      queueBtn.addEventListener('click', () => {
        const on = !Store.inQueue(d.id);
        if (on) Store.enqueue(card()); else Store.dequeue(d.id);
        queueBtn.replaceChildren(icon(on ? 'queued' : 'queue'), on ? 'In queue' : 'Add to queue');
        queueBtn.setAttribute('aria-pressed', String(on));
        announce(on ? 'Added to queue' : 'Removed from queue');
      });
      const shareBtn = el('button', { type: 'button', class: 'btn btn-ghost', 'aria-label': `Share ${title}` },
        icon('share'), 'Share');
      shareBtn.addEventListener('click', () => share(`${title} (${d.date || 'undated'})`, API.shareLink('episode', d.id)));

      // An undated episode with no network or credits is most of the catalog: its one line of
      // facts carries "Undated", and the number is not repeated when it already names the episode.
      const facts = [d.date ? null : 'Undated', d.network, d.sponsor, fmtLength(d.length), d.season ? `Season ${d.season}` : null,
                     d.title && d.num !== null && d.num !== undefined ? `No. ${d.num}` : null].filter(Boolean).join(' · ');
      const star = d.star ? d.credits.find(c => c.person === d.star && c.art) : null;
      const head = el('header', { class: `page-head${star ? ' has-face' : ''}`, dataset: { genre: (s && s.genre) || '' } },
        el('div', { class: 'page-head-text' },
        el('a', { class: 'section-header eyebrow-link', href: `?series=${encodeURIComponent(d.series)}` }, seriesName),
        el('h1', { class: 'view-heading', id: 'episode-h', tabindex: '-1' }, title),
        d.date ? el('p', { class: 'body' }, fmtLongDate(d.date)) : null,
        facts ? el('p', { class: 'caption' }, facts) : null,
        d.aka ? el('p', { class: 'caption' }, `Also titled ${d.aka}`) : null),
        el('div', { class: 'actions' }, playBtn, queueBtn, shareBtn,
          script ? PlaysUI.startButton(script, playsHelpers) : null));
      if (star) head.prepend(faceFigure(head, star.art, star.name));
      body.append(head);

      // R16: the automatic transcript, only where the gate passed (the row's `transcript`
      // is null otherwise), fetched from archive.org the first time it is opened.
      if (d.transcript) body.append(transcriptBlock(d.transcript));

      if (d.credits.length) {
        const groups = new Map();
        d.credits.forEach(c => {
          const role = c.role || 'cast';
          if (!groups.has(role)) groups.set(role, []);
          groups.get(role).push(c);
        });
        const order = [...groups.keys()].sort((a, b) => (b === 'cast') - (a === 'cast'));
        const dl = el('dl', { class: 'credits' });
        order.forEach(role => {
          const faces = groups.get(role).some(c => c.art);
          dl.append(el('div', { class: 'credit' },
            el('dt', { class: 'caption' }, role.charAt(0).toUpperCase() + role.slice(1)),
            groups.get(role).map(c => {
              const slot = faces ? el('span', { class: 'face-sm', 'aria-hidden': 'true' }) : null;
              if (c.art) putImage(slot, c.art, 32, '');
              // withPerson: a credited name opens the person's page (§4.14).
              const name = c.person ? el('a', { class: 'eyebrow-link', href: `?person=${encodeURIComponent(c.person)}` }, c.name) : c.name;
              return el('dd', { class: `body${faces ? ' with-face' : ''}` }, slot,
                el('span', {}, name, c.character ? el('span', { class: 'caption' }, ` as ${c.character}`) : null));
            })));
        });
        // CC BY and BY-SA portraits carry their credit (Decision 069); the header's face already does.
        const owed = [...new Map(d.credits.filter(c => c.art && c.art.credit && c !== star)
          .map(c => [c.person, c])).values()];
        body.append(el('section', { class: 'block', 'aria-labelledby': 'credits-h' },
          el('h2', { class: 'section-header', id: 'credits-h' }, 'Cast and credits'), dl,
          owed.length ? el('p', { class: 'caption photo-credits' }, owed.flatMap((c, i) => [i ? ' · ' : '',
            `${c.name}: `, el('a', { href: c.art.evidence, rel: 'noopener', target: '_blank' }, c.art.credit)])) : null));
      }

      const fs = el('fieldset', { class: 'versions' },
        el('legend', { class: 'section-header' }, d.recordings.length > 1 ? 'Recordings' : 'Recording'));
      d.recordings.forEach((rec, i) => {
        const label = rec.archiveId || rec.format || `Recording ${i + 1}`;
        const facts2 = [rec.archiveId ? rec.format : null, rec.kbps ? `${rec.kbps} kbps` : null, fmtLength(rec.length),
                        m.variantLines[rec.variant] || rec.variant || null, rec.partial ? m.partialLine : null]
          .filter(Boolean).join(' · ');
        const input = el('input', { type: 'radio', name: 'version', value: String(i), checked: i === 0,
                                    id: `ver-${i}` });
        input.addEventListener('change', () => { chosen = i; });
        fs.append(el('div', { class: 'version' }, input,
          el('label', { for: `ver-${i}` }, el('span', { class: 'body-strong' }, label),
            facts2 ? el('span', { class: 'caption' }, facts2) : null),
          rec.archiveId ? el('a', { class: 'caption', href: `https://archive.org/details/${encodeURIComponent(rec.archiveId)}`,
                    rel: 'noopener', target: '_blank', 'aria-label': `${rec.archiveId} on the Internet Archive` },
          'Source') : null));
      });
      body.append(fs);
      if (rightsLine) body.append(el('p', { class: 'caption rights' }, rightsLine));
    });
  }

  /* ================================================================
     A PERSON (withPerson, §4.14): every served episode crediting them, by series
  ================================================================ */

  const roleWord = (r) => { const w = r || 'cast'; return w.charAt(0).toUpperCase() + w.slice(1); };
  function rolesLine(roles) {
    return roles.map(r => r.character ? `${roleWord(r.role)} as ${r.character}` : roleWord(r.role)).join(', ');
  }

  function renderPerson(r) {
    const body = $('person-body');
    load(body, async () => {
      const p = await API.personPage(r.id);
      if (!p) throw new API.DataError('missing', r.id);
      return { p, index: await API.seriesIndex() };
    }, ({ p, index }) => {
      setTitle(p.name);
      const count = new Set(p.credits.map(c => c.id)).size;
      const facts = [API.lifeYears(p.birth, p.death), plural(count, 'episode', 'episodes')].filter(Boolean).join(' · ');
      const head = el('header', { class: `page-head${p.art ? ' has-face' : ''}` },
        el('div', { class: 'page-head-text' },
          el('h1', { class: 'view-heading', id: 'person-h', tabindex: '-1' }, p.name),
          el('p', { class: 'caption' }, facts)));
      if (p.art) head.prepend(faceFigure(head, p.art, null));
      body.append(head);

      const seg = el('div', { class: 'segmented', role: 'group', 'aria-label': 'Order' });
      const listBox = el('div');
      const draw = (newest) => {
        listBox.replaceChildren();
        API.personGroups(p.credits, newest).forEach((g, i) => {
          const s = index.byKey.get(g.series);
          const name = s ? s.name : g.series;
          listBox.append(el('section', { class: 'block', 'aria-labelledby': `pg-${i}` },
            el('div', { class: 'block-head' },
              el('h2', { class: 'section-header', id: `pg-${i}` },
                el('a', { class: 'eyebrow-link', href: `?series=${encodeURIComponent(g.series)}` }, name)),
              el('span', { class: 'caption' }, plural(g.episodes.length, 'episode', 'episodes'))),
            (() => {
              const ul = el('ul', { class: 'ep-list' });
              g.episodes.forEach(e => ul.append(episodeRow({ ...e, seriesName: name }, { note: rolesLine(e.roles), genre: s ? s.genre : null })));
              paintProgress(ul);
              return ul;
            })()));
        });
      };
      [['oldest', 'Oldest first'], ['newest', 'Newest first']].forEach(([v, label]) => {
        const b = el('button', { type: 'button', 'aria-pressed': String((r.p.get('order') === 'newest') === (v === 'newest')) },
          label);
        b.addEventListener('click', () => {
          const q = new URLSearchParams({ person: p.id });
          if (v === 'newest') q.set('order', 'newest');
          history.replaceState(null, '', `?${q}`);
          seg.querySelectorAll('button').forEach(x => x.setAttribute('aria-pressed', String(x === b)));
          draw(v === 'newest');
        });
        seg.append(b);
      });
      if (count > 1) body.append(seg);
      body.append(listBox);
      draw(r.p.get('order') === 'newest');
    });
  }

  function personRow(p) {
    return el('li', { class: 'series-row' },
      el('a', { href: `?person=${encodeURIComponent(p.id)}` },
        artTile({ name: p.name, art: p.art }),
        el('span', { class: 'series-row-text' }, el('span', { class: 'body-strong' }, p.name),
          el('span', { class: 'caption' }, plural(p.episodes, 'episode', 'episodes')))));
  }

  /** A disclosure that loads the text on first open; `#transcript` in the URL opens it. */
  function transcriptBlock(url) {
    const box = el('div', { class: 'transcript-body' });
    const details = el('details', { class: 'block transcript', id: 'transcript' },
      el('summary', { class: 'section-header' }, API.transcriptLabel), box);
    let loaded = false;
    details.addEventListener('toggle', () => {
      if (!details.open || loaded) return;
      loaded = true;
      load(box, () => API.transcript(url), (text) => {
        box.append(el('div', { class: 'transcript-text body' }, API.transcriptLines(text).join('\n')));
      });
    });
    if (location.hash === '#transcript') {
      details.open = true;
      requestAnimationFrame(() => details.scrollIntoView({ block: 'start' }));
    }
    return details;
  }

  async function share(title, query) {
    const url = new URL(query, location.href).href;
    try {
      const how = await shareTarget({ title, url });
      if (how === 'copied') announce('Link copied');
    } catch { announce('Could not share'); }
  }

  /* ================================================================
     SEARCH (word-prefix, two phases: series from the index, then episodes)
  ================================================================ */

  let searchSeq = 0;
  let searchTimer = null;

  /** Word-prefix, as everywhere (WEB-DESIGN §4.6): every query word begins a word of the title or author. */
  function scriptsMatching(scripts, words) {
    return scripts.filter(s => {
      const have = API.tokens(`${s.title} ${PlaysCore.authorLine(s)}`);
      return words.every(w => have.some(h => h.startsWith(w)));
    });
  }

  function renderSearch(r) {
    setTitle('Search');
    const q = r.p.get('q') || '';
    const input = $('search-q');
    if (input.value !== q) input.value = q;
    runSearch(q);
  }

  async function runSearch(q) {
    const seq = ++searchSeq;
    const body = $('search-body');
    const words = API.tokens(q).filter(w => w.length >= 2);
    if (!words.length) { body.replaceChildren(); return; }
    body.replaceChildren(stateBox('loading'));
    try {
      const [series, numbers, scripts, people, aired, saidAll] = await Promise.all([API.searchSeries(q),
        API.searchEpisodeNumbers(q), onTV() ? [] : castable(), API.searchPeople(q), API.searchAired(q),
        API.searchSaidNumbers(q)]);
      if (seq !== searchSeq) return;
      const plays = scriptsMatching(scripts, words);
      const titled = new Set(numbers);
      const said = saidAll.filter(n => !titled.has(n));
      body.replaceChildren();
      if (!series.total && !people.total && !numbers.length && !plays.length && !(aired && aired.rows.length)
          && !said.length) {
        body.append(stateBox('empty', { text: `No matches for “${q.trim()}”.` }));
        return;
      }
      if (series.total) {
        body.append(el('section', { class: 'block', 'aria-labelledby': 'rs-h' },
          el('div', { class: 'block-head' }, el('h2', { class: 'section-header', id: 'rs-h' }, 'Series'),
            el('span', { class: 'caption' }, plural(series.total, 'series', 'series'))),
          el('ul', { class: 'series-list' }, series.rows.map(seriesRow))));
      }
      if (people.total) {
        body.append(el('section', { class: 'block', 'aria-labelledby': 'rpe-h' },
          el('div', { class: 'block-head' }, el('h2', { class: 'section-header', id: 'rpe-h' }, 'People'),
            el('span', { class: 'caption' }, plural(people.total, 'person', 'people'))),
          el('ul', { class: 'series-list' }, people.rows.map(personRow))));
      }
      if (plays.length) {
        body.append(el('section', { class: 'block', 'aria-labelledby': 'rp-h' },
          el('div', { class: 'block-head' }, el('h2', { class: 'section-header', id: 'rp-h' }, 'Plays'),
            el('span', { class: 'caption' }, plural(plays.length, 'play', 'plays'))),
          el('ul', { class: 'series-list' }, plays.map(playRow))));
      }
      if (aired && aired.rows.length) {
        const { byKey } = await API.seriesIndex();
        if (seq !== searchSeq) return;
        body.append(pagedEpisodes('ra-h', `Aired ${API.dateLabel(aired.prefix)}`, aired.rows.length,
          async (from, to) => aired.rows.slice(from, to), byKey, seq, q));
      }
      if (numbers.length) {
        const { byKey } = await API.seriesIndex();
        const list = el('ul', { class: 'ep-list' });
        const sec = el('section', { class: 'block', 'aria-labelledby': 're-h' },
          el('div', { class: 'block-head' }, el('h2', { class: 'section-header', id: 're-h' }, 'Episodes'),
            el('span', { class: 'caption' }, plural(numbers.length, 'episode', 'episodes'))), list);
        body.append(sec);
        let shown = 0;
        const more = el('button', { type: 'button', class: 'btn btn-ghost' }, 'Show more');
        const page = async () => {
          more.disabled = true;
          try {
            const docs = await API.searchDocs(numbers.slice(shown, shown + 30));
            if (seq !== searchSeq) return;
            docs.forEach(d => list.append(episodeRow({ ...d, seriesName: byKey.get(d.series)?.name || null },
              { showSeries: true })));
            paintProgress(list);
            shown += docs.length;
            if (shown >= numbers.length) more.remove();
          } catch (err) {
            console.error(err);
            more.replaceWith(stateBox(problem(err), { retry: () => runSearch(q) }));
          }
          more.disabled = false;
        };
        more.addEventListener('click', page);
        await page();
        if (shown < numbers.length) sec.append(more);
      }
      if (said.length) {
        const { byKey } = await API.seriesIndex();
        if (seq !== searchSeq) return;
        const heard = API.saidWords(q);
        body.append(pagedEpisodes('rt-h', API.transcriptLabel, said.length,
          (from, to) => API.searchDocs(said.slice(from, to)), byKey, seq, q, 10, (ep, row) => quoteInto(ep, row, heard)));
      }
    } catch (err) {
      if (seq !== searchSeq) return;
      console.error(err);
      body.replaceChildren(stateBox(problem(err), { retry: () => runSearch(q) }));
    }
  }

  /** A titled section of episode rows, `size` at a time behind Show more; `decorate` adds to each row. */
  function pagedEpisodes(id, title, total, fetchRows, byKey, seq, q, size = 30, decorate = null) {
    const list = el('ul', { class: 'ep-list' });
    const sec = el('section', { class: 'block', 'aria-labelledby': id },
      el('div', { class: 'block-head' }, el('h2', { class: 'section-header', id }, title),
        el('span', { class: 'caption' }, plural(total, 'episode', 'episodes'))), list);
    let shown = 0;
    const more = el('button', { type: 'button', class: 'btn btn-ghost' }, 'Show more');
    const page = async () => {
      more.disabled = true;
      try {
        const docs = await fetchRows(shown, shown + size);
        if (seq !== searchSeq) return;
        docs.forEach(d => {
          const ep = { ...d, seriesName: byKey.get(d.series)?.name || null };
          const row = episodeRow(ep, { showSeries: true });
          if (decorate) decorate(ep, row);
          list.append(row);
        });
        paintProgress(list);
        shown += docs.length;
        if (shown >= total) more.remove();
        else if (!more.isConnected) sec.append(more);
      } catch (err) {
        console.error(err);
        more.replaceWith(stateBox(problem(err), { retry: () => runSearch(q) }));
      }
      more.disabled = false;
    };
    more.addEventListener('click', page);
    page();
    return sec;
  }

  /** The line where the words are said, verbatim from the automatic transcript; nothing when it does not load. */
  async function quoteInto(ep, row, words) {
    const quote = el('span', { class: 'ep-quote caption' });
    row.querySelector('.g-text').append(quote);
    try {
      const d = await API.episodeDetail(ep.id);
      const text = d && d.transcript ? await API.transcript(d.transcript) : null;
      const line = text && API.transcriptSnippet(text, words);
      if (line) quote.textContent = line;
      else quote.remove();
    } catch (err) {
      quote.remove();
    }
  }

  $('search-q').addEventListener('input', (e) => {
    clearTimeout(searchTimer);
    const q = e.target.value;
    searchTimer = setTimeout(() => {
      const p = new URLSearchParams({ view: 'search' });
      if (q) p.set('q', q);
      history.replaceState(null, '', `?${p}`);
      runSearch(q);
    }, 180);
  });
  $('search-form').addEventListener('submit', (e) => { e.preventDefault(); clearTimeout(searchTimer); runSearch($('search-q').value); });

  /* ================================================================
     PLAYS (js/plays-ui.js draws them with these helpers)
  ================================================================ */

  const playsHelpers = { el, icon, stateBox, problem, setTitle, navigate, announce };
  function renderPlays(r) {
    PlaysUI.render(r, playsHelpers);
  }

  /* ================================================================
     SURPRISE (WEB-DESIGN §4.13): an episode, an evening, a play, drawn at random
  ================================================================ */

  const pickOf = (list) => list[Math.floor(Math.random() * list.length)];

  /** A recommendable episode with a recording: a random day file (recommendAnd applied at build). */
  async function randomEpisode() {
    for (let tries = 0; tries < 6; tries++) {
      const d = new Date(2024, 0, 1 + Math.floor(Math.random() * 366));
      const rows = (await API.thisDay(d)).filter(e => e.url);
      if (rows.length) return pickOf(rows);
    }
    return null;
  }

  /** One published evening and its first surviving slot the catalog serves. */
  async function randomEvening() {
    const file = await API.tonightFile();
    const days = file ? Object.values(file.days || {}) : [];
    if (!days.length) return null;
    const day = pickOf(days);
    for (const s of day.slots) {
      if (!s.episode) continue;
      const d = await API.episodeDetail(s.episode.id).catch(() => null);
      if (d && d.recordings.length) return { day, first: cardOf(d, s.episode.series) };
    }
    return { day, first: null };
  }

  function pickBox(title, ...children) {
    return el('section', { class: 'pick' }, el('h2', { class: 'section-header' }, title), ...children);
  }

  function renderSurprise() {
    setTitle('Surprise');
    const body = $('surprise-body');
    load(body, () => Promise.all([
      randomEpisode().catch((err) => { console.error(err); return null; }),
      randomEvening().catch((err) => { console.error(err); return null; }),
      onTV() ? [] : castable(),
    ]), ([ep, evening, scripts]) => {
      const picks = el('div', { class: 'picks' });
      if (ep) {
        const card = { ...ep, title: epTitle(ep) };
        picks.append(pickBox('An episode',
          el('a', { class: 'pick-title body-strong', href: `?item=${encodeURIComponent(ep.id)}` }, epTitle(ep)),
          el('p', { class: 'caption' }, [ep.seriesName, ep.date].filter(Boolean).join(' · ')),
          el('div', { class: 'actions' }, el('button', { type: 'button', class: 'btn btn-primary',
            onclick: () => Player.load(card) }, icon('play'), 'Play'))));
      }
      if (evening) {
        const { day, first } = evening;
        picks.append(pickBox('An evening',
          el('p', { class: 'body-strong' }, fmtLongDate(day.evening)),
          el('p', { class: 'caption' }, [day.network, day.station].filter(Boolean).join(' · ')),
          first ? el('p', { class: 'caption' }, [first.seriesName, first.title].filter(Boolean).join(' · ')) : null,
          first ? el('div', { class: 'actions' }, el('button', { type: 'button', class: 'btn btn-primary',
            onclick: () => { if (live) stopLive(); Player.load(first); } }, icon('play'), 'Play')) : null));
      }
      if (scripts.length) {
        const script = pickOf(scripts);
        picks.append(pickBox('A play',
          el('a', { class: 'pick-title body-strong', href: `?play=${encodeURIComponent(script.id)}` }, script.title),
          el('p', { class: 'caption' }, playMeta(script)),
          el('div', { class: 'actions' }, PlaysUI.startButton(script, playsHelpers))));
      }
      if (!picks.children.length) { body.append(stateBox('empty', { text: 'Nothing to pick from yet.' })); return; }
      body.append(picks);
    });
  }
  $('surprise-again').addEventListener('click', () => { renderSurprise(); announce('Shuffled'); });

  /* ================================================================
     LIBRARY (this device)
  ================================================================ */

  const BROWSE = { label: 'Browse', href: '?view=browse' };
  function renderLibrary(r) {
    setTitle('Library');
    AccountUI.paintRow($('account-row'));
    TogetherUI.paintRow($('together-row'));
    const tab = ['queue', 'history', 'following', 'dramas'].includes(r.p.get('tab')) ? r.p.get('tab') : 'queue';
    document.querySelectorAll('#library-tabs [data-lib]').forEach(b =>
      b.setAttribute('aria-pressed', String(b.dataset.lib === tab)));
    const body = $('library-body');
    body.replaceChildren();
    if (tab === 'queue') {
      const q = Store.queue();
      if (!q.length) { body.append(stateBox('empty', { text: 'Nothing queued.', action: BROWSE })); return; }
      const ul = el('ul', { class: 'ep-list' });
      q.forEach((ep, i) => {
        const row = episodeRow(ep, { showSeries: true });
        const tools = el('div', { class: 'row-tools' },
          el('button', { type: 'button', class: 'icon-btn', 'aria-label': `Move ${epTitle(ep)} up`, disabled: i === 0,
                         onclick: () => { Store.moveInQueue(ep.id, -1); route(); } }, icon('up')),
          el('button', { type: 'button', class: 'icon-btn', 'aria-label': `Move ${epTitle(ep)} down`,
                         disabled: i === q.length - 1, onclick: () => { Store.moveInQueue(ep.id, 1); route(); } }, icon('down')),
          el('button', { type: 'button', class: 'icon-btn', 'aria-label': `Remove ${epTitle(ep)} from queue`,
                         onclick: () => { Store.dequeue(ep.id); announce('Removed from queue'); route(); } }, icon('remove')));
        row.classList.add('ep-row-queue');
        row.append(tools);
        ul.append(row);
      });
      paintProgress(ul);
      body.append(ul);
    } else if (tab === 'history') {
      const h = Store.history();
      if (!h.length) { body.append(stateBox('empty', { text: 'Nothing played yet.', action: BROWSE })); return; }
      body.append(episodeList(h, { showSeries: true }),
        el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => {
          if (confirm('Clear your listening history and resume points on this device?')) { Store.clearHistory(); route(); }
        } }, 'Clear history'));
    } else if (tab === 'dramas') {
      PlaysUI.renderMine(body, playsHelpers);
    } else {
      const f = Store.follows();
      if (!f.length) { body.append(stateBox('empty', { text: 'Not following any series.', action: BROWSE })); return; }
      body.append(el('ul', { class: 'series-list' }, f.map(seriesRow)));
    }
  }
  $('library-tabs').addEventListener('click', (e) => {
    const b = e.target.closest('[data-lib]');
    if (b) navigate(`?view=library&tab=${b.dataset.lib}`, true);
  });

  /* ================================================================
     THE PLAYER'S FACE
  ================================================================ */

  const np = $('now-playing');
  const seekEl = $('np-seek');
  let seeking = false;

  /* Listen Together (§4.12): the session, its card for a room's episode (the host's copy), and its face. */
  const together = Together.make({
    api: API.rooms, core: TogetherCore, player: Player,
    storage: (() => { try { return sessionStorage; } catch { return null; } })(),
    cardFor: async (st) => {
      const url = TogetherCore.urlOfCopy(st);
      const d = await API.episodeDetail(st.episode_id).catch(() => null);
      if (!d) return { id: st.episode_id, url };
      const s = await API.seriesPage(d.series).catch(() => null);
      const first = d.recordings[0];
      const same = !!first && first.url === url;
      // The loudness measurement belongs to the default copy only (as on Detail).
      return { id: d.id, title: epTitle(d), series: d.series, seriesName: s ? s.name : d.series, date: d.date, url,
               length: same ? (first.length || d.length) : null, li: same ? d.li : null, ltp: same ? d.ltp : null };
    },
  });
  TogetherUI.mount(together, {
    share: (code) => share(Player.current ? epTitle(Player.current) : 'Ear Drama', `?room=${code}`),
  });
  together.onChange(() => paintPlayer('state'));
  /** A guest's Play is the host's; it is offered only when the browser would not start the sound by itself. */
  /** A Listen Together guest's toggle is their own hold (Decision 067); it also answers a refused autoplay. */
  function togglePressed() { Player.toggle(); }

  function sleepText() {
    const s = Player.sleep;
    if (!s) return 'Sleep timer';
    if (s.kind === 'end') return 'Sleep: end of episode';
    return `Sleep: ${fmtClock(Player.sleepRemaining())}`;
  }

  function paintPlayer(kind) {
    const cur = Player.current;
    const a = Player.audio;
    $('player').hidden = !cur;
    if (!cur) return;
    const playing = !a.paused;
    const room = together.info();
    const guest = Player.following;
    document.querySelectorAll('[data-act="toggle"]').forEach(b => {
      b.setAttribute('aria-label', playing ? 'Pause' : 'Play');
      b.classList.toggle('is-playing', playing);

    });
    document.querySelectorAll('[data-act="back"], [data-act="fwd"]').forEach(b => { b.disabled = guest; });
    seekEl.disabled = guest;
    $('np-speed').disabled = guest;
    const d = isFinite(a.duration) ? a.duration : (cur.length || 0);
    const t = a.currentTime || 0;
    $('mini-progress').style.width = d ? `${Math.min(100, (t / d) * 100)}%` : '0';
    if (kind === 'load' || kind === 'error' || kind === 'state' || kind === 'sleep-fired') {
      $('mini-title').textContent = epTitle(cur);
      $('np-title').textContent = epTitle(cur);
      $('np-series').textContent = cur.seriesName || '';
      $('np-series').setAttribute('href', `?series=${encodeURIComponent(cur.series || '')}`);
      $('np-meta').textContent = [cur.date ? fmtLongDate(cur.date) : 'Undated', cur.network].filter(Boolean).join(' · ');
      const err = kind === 'error' && Player.error;
      const errText = API.isOffline() ? 'You are offline.' : 'This recording did not load.';
      $('mini-meta').textContent = err ? errText
        : room.inRoom ? `Listening together · ${room.members}` : [cur.seriesName, cur.date].filter(Boolean).join(' · ');
      $('mini-meta').classList.toggle('is-error', !!err);
      if (err) announce(errText);
    }
    if (kind === 'load') { paintTranscriptLink(cur); paintPlayerArt(cur); }
    if (!seeking) {
      seekEl.max = String(Math.floor(d));
      seekEl.value = String(Math.floor(t));
    }
    seekEl.setAttribute('aria-valuetext', `${fmtClock(t)} of ${fmtClock(d)}`);
    $('np-pos').textContent = fmtClock(seeking ? Number(seekEl.value) : t);
    $('np-left').textContent = `-${fmtClock(Math.max(0, d - t))}`;
    $('np-speed').value = String(Player.nearestSpeed(a.playbackRate || 1));
    $('np-level').setAttribute('aria-pressed', Player.leveling ? 'true' : 'false');
    $('np-level').disabled = !Player.canLevel;
    $('np-level-note').hidden = Player.canLevel;
    const st = sleepText();
    document.querySelectorAll('.sleep-label').forEach(x => { x.textContent = st; });
    document.querySelectorAll('[data-act="sleep"]').forEach(b => b.setAttribute('aria-label', st));
    $('sleep-off').hidden = !Player.sleep;
    document.querySelectorAll('#sleep-menu [data-sleep]').forEach(b => {
      const s = Player.sleep;
      const on = s && ((b.dataset.sleep === 'end' && s.kind === 'end') || (s.kind === 'time' && b.dataset.sleep === String(s.minutes)));
      b.setAttribute('aria-current', on ? 'true' : 'false');
    });
    const next = Player.upNext();
    $('np-next').textContent = !next ? '' : next.kind === 'part' ? `Next part: ${epTitle(next.card)}`
      : `Next in queue: ${epTitle(next.card)}`;
    const story = Player.nextStory();
    $('np-story').hidden = !story || guest;
    if (story) $('np-story').setAttribute('aria-label', `Next story: ${epTitle(story)}`);
    if (kind === 'sleep-fired') announce('Sleep timer ended.');
  }
  Player.onChange(paintPlayer);

  /** Now Playing's picture and the lock screen's (§5.6): the episode's face, else the series',
      else the series' typographic card, the same art on both. */
  let lockArtURL = null;
  function paintPlayerArt(cur) {
    const box = $('np-art');
    box.replaceChildren();
    Player.setArtwork(null);
    Promise.all([API.episodeDetail(cur.id).catch(() => null), API.seriesIndex().catch(() => null)]).then(([d, idx]) => {
      if (!Player.current || Player.current.id !== cur.id) return;
      const s = idx && idx.byKey.get(cur.series || (d && d.series));
      const face = (d && d.star && d.credits.find(c => c.person === d.star && c.art)) || null;
      const art = face ? face.art : s && s.art;
      if (art) {
        const np = shapedImage(art, Math.round(360 * Math.min(API.artAspect(art) || 0.8, 1)), (face ? face.name : s.star) || '');
        np.classList.add('np-face');
        np.setAttribute('aria-hidden', 'true');
        box.append(np);
        // Shown larger than a page's head, so a credited portrait carries its credit here too (Decision 069).
        if (art.credit) box.append(el('a', { class: 'caption face-credit np-credit', href: art.evidence, rel: 'noopener', target: '_blank' }, art.credit));
        Player.setArtwork([{ src: API.artURL(art, 500), sizes: '500x500', type: 'image/jpeg' }]);
        API.cropBlobURL(art, 500).then(url => {
          if (!url) return;
          if (lockArtURL) URL.revokeObjectURL(lockArtURL);
          lockArtURL = url;
          if (Player.current && Player.current.id === cur.id) Player.setArtwork([{ src: url, sizes: '500x500', type: 'image/jpeg' }]);
        });
        return;
      }
      const name = (s && s.name) || cur.seriesName;
      if (!name) return;
      const line = s ? [years(s.first, s.last), s.networks].filter(Boolean).join(' · ') : null;
      const card = typeCard({ name, line, genre: s && s.genre });
      card.setAttribute('aria-hidden', 'true');
      box.append(card);
      const png = cardImage(card, name, line);
      if (png) {
        png.then(url => {
          if (Player.current && Player.current.id === cur.id) Player.setArtwork([{ src: url, sizes: '512x512', type: 'image/png' }]);
        });
      }
    });
  }
  let cardURL = null;
  /** The typographic card painted for the lock screen, from the drawn card's own colors. */
  function cardImage(card, name, line) {
    const c = document.createElement('canvas');
    c.width = c.height = 512;
    const g = c.getContext && c.getContext('2d');
    if (!g || !c.toBlob) return null;
    const cs = getComputedStyle(card);
    g.fillStyle = cs.backgroundColor || '#F4F4F5';
    g.fillRect(0, 0, 512, 512);
    g.fillStyle = cs.getPropertyValue('--genre-accent').trim() || cs.color;
    g.fillRect(0, 0, 24, 512);
    g.fillStyle = cs.color;
    g.font = `700 56px ${cs.fontFamily}`;
    const lines = [];
    let at = '';
    for (const w of String(name).split(/\s+/)) {
      const t = at ? `${at} ${w}` : w;
      if (g.measureText(t).width > 420 && at) { lines.push(at); at = w; } else at = t;
    }
    if (at) lines.push(at);
    const shown = lines.slice(0, 5);
    let y = 512 - 64 - (line ? 52 : 0) - (shown.length - 1) * 64;
    shown.forEach(l => { g.fillText(l, 56, y); y += 64; });
    if (line) { g.font = `400 34px ${cs.fontFamily}`; g.fillText(line, 56, y - 8); }
    return new Promise(res => c.toBlob(b => {
      if (!b) return;
      if (cardURL) URL.revokeObjectURL(cardURL);
      cardURL = URL.createObjectURL(b);
      res(cardURL);
    }, 'image/png'));
  }

  /** The player's way to the transcript (R16): Detail with the transcript open. */
  function paintTranscriptLink(cur) {
    const a = $('np-transcript');
    a.hidden = true;
    API.episodeDetail(cur.id).then(d => {
      if (!d || !d.transcript || !Player.current || Player.current.id !== cur.id) return;
      a.setAttribute('href', `?item=${encodeURIComponent(d.id)}#transcript`);
      a.hidden = false;
    }).catch(() => {});
  }

  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-act]');
    if (!b) return;
    const act = b.dataset.act;
    if (act === 'toggle') togglePressed();
    else if (act === 'back') Player.back();
    else if (act === 'fwd') Player.forward();
    else if (act === 'sleep') { if (!np.open) np.showModal(); $('sleep-menu').showPopover(); }
  });
  $('mini-open').addEventListener('click', () => np.showModal());
  $('np-close').addEventListener('click', () => np.close());
  seekEl.addEventListener('input', () => { seeking = true; $('np-pos').textContent = fmtClock(Number(seekEl.value)); });
  seekEl.addEventListener('change', () => { seeking = false; Player.seek(Number(seekEl.value)); });
  $('np-speed').addEventListener('change', (e) => { Player.setRate(e.target.value); announce(`Speed ${e.target.value}×`); });
  $('np-story').addEventListener('click', () => {
    const story = Player.nextStory();
    if (story) Player.load(story);
  });
  $('np-level').addEventListener('click', () => {
    const on = !Player.leveling;
    Player.setLeveling(on);
    announce(on ? 'Volume leveling on' : 'Volume leveling off');
  });
  // Another speaker (WEB-DESIGN §5.10): the browser's own AirPlay or Cast picker, shown while a target is there.
  {
    const audio = $('audio');
    RemoteOutput.watch(audio, window, (kind) => {
      const b = $('np-remote');
      b.hidden = !kind || onTV();
      if (b.hidden) return;
      $('np-remote-label').textContent = RemoteOutput.LABELS[kind];
      b.querySelectorAll('svg[data-kind]').forEach((s) => { s.hidden = s.dataset.kind !== kind; });
    });
    $('np-remote').addEventListener('click', () => RemoteOutput.prompt(audio, window));
  }
  $('sleep-menu').addEventListener('click', (e) => {
    const b = e.target.closest('[data-sleep]');
    if (!b) return;
    Player.setSleep(b.dataset.sleep);
    $('sleep-menu').hidePopover();
    announce(b.dataset.sleep === 'off' ? 'Sleep timer off' : `Sleep timer: ${b.textContent}`);
  });

  document.addEventListener('keydown', (e) => {
    if (e.metaKey || e.ctrlKey || e.altKey || !Player.current) return;
    const t = e.target;
    if (t.closest('input, select, textarea, [contenteditable="true"]')) return;
    if (e.key === 'k' || (e.key === ' ' && !t.closest('button, a'))) { e.preventDefault(); togglePressed(); }
    else if (e.key === 'j') Player.back();
    else if (e.key === 'l') Player.forward();
  });

  Store.onChange(() => { if (np.open) paintPlayer('tick'); });

  /* Sync (M5, WEB-DESIGN §4.11): rows from the Worker arrive as ids, and become the same cards
     the Detail page queues. A Library on screen redraws when they land. */
  Sync.start({ card: (d, seriesName) => ({ id: d.id, title: epTitle(d), series: d.series, seriesName, date: d.date,
                                          url: d.recordings[0].url, length: d.recordings[0].length || d.length,
                                          li: d.li, ltp: d.ltp }) });
  Sync.onChange((kind) => {
    if (kind !== 'changed' && kind !== 'signed-out') return;
    const r = parseRoute();
    if (r.view === 'library') renderLibrary(r);
  });
  // Contract §3.5: ids the catalog moved are rewritten once, and their cards drawn again.
  API.forwarding().then((f) => {
    if (Store.forward(f)) Sync.hydrate().catch(e => console.error('forwarded cards', e));
  }).catch(() => {});

  /* ================================================================
     BOOT
  ================================================================ */

  const params = new URLSearchParams(location.search);
  if (params.get('mute') === '1') Player.setMuted(true);
  Player.setRate(Store.rate());
  const doorSeconds = Number(params.get('door_seconds'));
  if (doorSeconds > 0) setTimeout(() => navigate('?view=home'), doorSeconds * 1000);
  /* Offline (WEB-DESIGN §7.3): a status line while the browser reports no network; what was
     opened before still opens from the service worker's copies. */
  const paintOnline = () => { $('offline-note').hidden = !API.offlineLine(); };
  window.addEventListener('offline', paintOnline);
  window.addEventListener('online', () => { paintOnline(); if (document.querySelector('.state-problem')) route(); });
  paintOnline();
  together.restore();

  /* The service worker runs on the real site. On a local server it runs only with ?sw=1 and is
     removed otherwise, so a cache-first shell never hides an edit during development. */
  if ('serviceWorker' in navigator && window.isSecureContext && /^https?:$/.test(location.protocol)) {
    const local = ['localhost', '127.0.0.1', '[::1]'].includes(location.hostname);
    if (!local || params.get('sw') === '1') {
      navigator.serviceWorker.register('sw.js').catch(err => console.error('service worker', err));
    } else {
      navigator.serviceWorker.getRegistrations().then(rs => rs.forEach(r => r.unregister())).catch(() => {});
    }
  }
  route();
})();
