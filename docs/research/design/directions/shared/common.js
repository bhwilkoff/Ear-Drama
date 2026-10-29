/* Shared helpers for the D2 direction prototypes. Data comes only from
   window.ED (shared/sample.js). Each direction's app.js draws its own screens. */
(function () {
  'use strict';
  const ED = window.ED;
  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'];
  const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  function parts(iso) {
    const [y, m, d] = iso.split('-').map(Number);
    return { y, m, d, wd: new Date(Date.UTC(y, m - 1, d)).getUTCDay() };
  }
  /** 'long' Thursday, December 2, 1943 · 'medium' December 2, 1943 · 'md' December 2 · 'year' 1943 · 'tab' 1943-12-02 */
  function fmtDate(iso, style = 'medium') {
    if (!iso) return 'Undated';
    const p = parts(iso);
    if (style === 'year') return String(p.y);
    if (style === 'tab') return iso;
    if (style === 'md') return `${MONTHS[p.m - 1]} ${p.d}`;
    if (style === 'short') return `${MONTHS[p.m - 1].slice(0, 3)} ${p.d}`;
    if (style === 'long') return `${DAYS[p.wd]}, ${MONTHS[p.m - 1]} ${p.d}, ${p.y}`;
    return `${MONTHS[p.m - 1]} ${p.d}, ${p.y}`;
  }
  function mins(sec) {
    if (!sec) return '';
    const m = Math.round(sec / 60);
    if (m < 60) return `${m} min`;
    return m % 60 ? `${Math.floor(m / 60)} hr ${m % 60} min` : `${Math.floor(m / 60)} hr`;
  }
  function clock(et) {
    const [h, m] = et.split(':').map(Number);
    const hh = ((h + 11) % 12) + 1;
    return `${hh}:${String(m).padStart(2, '0')}`;
  }
  /** "Carlton, Henry Fisk" -> "Henry Fisk Carlton"; strips the parenthetical. */
  function author(a) {
    if (!a) return '';
    const n = a.name.replace(/\s*\(.*\)\s*/, '');
    const [last, first] = n.split(', ');
    return first ? `${first} ${last}` : last;
  }
  const genreName = (g) => (g && ED.genreNames[g]) || '';

  /* ---- Art: the app's one helper and one crop formula (js/api.js) ---- */
  const STEPS = [120, 330, 500, 960];
  function artURL(art, px) {
    if (!art || !art.url) return null;
    const w = STEPS.find((x) => x >= px * 2) || STEPS[STEPS.length - 1];
    return `${art.url}?width=${w}`;
  }
  const aspect = (art) => (art && art.width > 0 && art.height > 0 ? art.width / art.height : null);
  const isWide = (art) => (aspect(art) || 0.8) > 1.15;
  function cropRect(art) {
    const a = aspect(art);
    if (a === null) return null;
    const f = Array.isArray(art.face) && art.face.length === 4 ? art.face : null;
    if (!f && a > 1.15) return null;
    const full = Math.min(a, 1);
    const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
    let s = full, left = 0.5 * (a - full), top = 0.2 * (1 - full);
    if (f) {
      s = clamp(2 * Math.max(f[2] * a, f[3]), full / 4, full);
      left = clamp((f[0] + f[2] / 2) * a - s / 2, 0, a - s);
      top = clamp(f[1] + f[3] / 2 - s / 2, 0, 1 - s);
    }
    return { x: left / a, y: top, w: s / a, h: s };
  }
  /** A square crop at the published face, `size` px; null when the picture may not be cropped. */
  function faceCrop(art, size, cls = '') {
    const r = cropRect(art);
    const url = artURL(art, size / (r ? r.w : 1));
    if (!r || !url) return null;
    const W = size / r.w, H = size / r.h;
    return `<span class="ed-crop ${cls}" style="width:${size}px;height:${size}px"><img alt="" src="${esc(url)}" style="width:${W.toFixed(1)}px;height:${H.toFixed(1)}px;left:${(-r.x * W).toFixed(1)}px;top:${(-r.y * H).toFixed(1)}px"></span>`;
  }
  /** The picture whole at its own aspect, bounded by height h (and maxW). */
  function print(art, h, maxW = 9999, cls = '') {
    const a = aspect(art) || 0.8;
    let H = h, W = h * a;
    if (W > maxW) { W = maxW; H = W / a; }
    return `<img class="ed-print ${cls}" alt="" src="${esc(artURL(art, W))}" width="${Math.round(W)}" height="${Math.round(H)}">`;
  }
  /** A row tile: the face crop, else the first letter on the genre hue. */
  function tile(name, art, genre, size = 56, cls = '') {
    const c = art && faceCrop(art, size, cls);
    if (c) return c;
    const letter = (name || '?').replace(/^(The|A|An)\s+/i, '').trim().charAt(0).toUpperCase();
    return `<span class="ed-letter ${cls}" data-genre="${esc(genre || '')}" style="width:${size}px;height:${size}px;font-size:${Math.round(size * 0.5)}px">${esc(letter)}</span>`;
  }

  /* ---- The run strip: surviving episodes per year, a word-sized graphic ---- */
  function runStrip(hist, { from = 1930, to = 1962, w = 132, h = 18, genre = '', label = true, core = null, marks = null } = {}) {
    const years = [];
    for (let y = from; y <= to; y++) years.push(y);
    const max = Math.max(1, ...years.map((y) => hist[y] || 0));
    const bw = w / years.length;
    const bars = years.map((y, i) => {
      const n = hist[y] || 0;
      if (!n) return `<rect x="${(i * bw).toFixed(2)}" y="${h - 1}" width="${Math.max(1, bw - 1).toFixed(2)}" height="1" class="gap"/>`;
      const bh = Math.max(2, Math.round((n / max) * h));
      const mk = marks && marks.includes(y) ? ' mark' : '';
      return `<rect x="${(i * bw).toFixed(2)}" y="${h - bh}" width="${Math.max(1, bw - 1).toFixed(2)}" height="${bh}" class="bar${mk}"><title>${y}: ${n}</title></rect>`;
    }).join('');
    const total = Object.values(hist).reduce((a, b) => a + b, 0);
    const peak = Object.entries(hist).sort((a, b) => b[1] - a[1])[0];
    const aria = core ? `Aired ${core[0]} to ${core[1]}, most in ${peak ? peak[0] : core[0]}` : `${total} dated`;
    return `<svg class="ed-strip" data-genre="${esc(genre)}" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" role="img" aria-label="${esc(aria)}">${bars}</svg>`;
  }
  const coreYears = (core) => (core ? (core[0] === core[1] ? `${core[0]}` : `${core[0]}–${core[1]}`) : '');

  /* ---- Icons (inline SVG, R-ICON-1) ---- */
  const I = {
    play: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 4.5v15l13-7.5z" fill="currentColor"/></svg>',
    pause: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 4h4v16H6zM14 4h4v16h-4z" fill="currentColor"/></svg>',
    queue: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 6h12M4 11h12M4 16h8M18 13v8M14 17h8" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
    share: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v12M7 8l5-5 5 5M5 13v7h14v-7" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    back: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M15 5l-7 7 7 7" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    down: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 9l7 7 7-7" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    chev: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 5l7 7-7 7" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    r15: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5a8 8 0 1 1-8 8M12 5V1L7 5l5 4V5" stroke="currentColor" stroke-width="1.8" fill="none" stroke-linecap="round"/><text x="12" y="16.5" font-size="7" text-anchor="middle" fill="currentColor" font-family="system-ui">15</text></svg>',
    f30: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5a8 8 0 1 0 8 8M12 5V1l5 4-5 4V5" stroke="currentColor" stroke-width="1.8" fill="none" stroke-linecap="round"/><text x="12" y="16.5" font-size="7" text-anchor="middle" fill="currentColor" font-family="system-ui">30</text></svg>',
    moon: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z" stroke="currentColor" stroke-width="1.8" fill="none"/></svg>',
    more: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="5" cy="12" r="1.8" fill="currentColor"/><circle cx="12" cy="12" r="1.8" fill="currentColor"/><circle cx="19" cy="12" r="1.8" fill="currentColor"/></svg>',
    mic: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="9" y="3" width="6" height="11" rx="3" fill="currentColor"/><path d="M6 11a6 6 0 0 0 12 0M12 17v4" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
    stop: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="6" y="6" width="12" height="12" rx="2" fill="currentColor"/></svg>',
    check: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    search: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5" stroke="currentColor" stroke-width="2" fill="none"/><path d="M15.5 15.5L21 21" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
    home: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 11l8-7 8 7v9h-5v-6H9v6H4z" stroke="currentColor" stroke-width="1.8" fill="none" stroke-linejoin="round"/></svg>',
    browse: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="4" width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.8" fill="none"/><rect x="13" y="4" width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.8" fill="none"/><rect x="4" y="13" width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.8" fill="none"/><rect x="13" y="13" width="7" height="7" rx="1.5" stroke="currentColor" stroke-width="1.8" fill="none"/></svg>',
    stations: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="9" width="18" height="11" rx="2" stroke="currentColor" stroke-width="1.8" fill="none"/><path d="M7 9l10-5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><circle cx="15.5" cy="14.5" r="2.5" stroke="currentColor" stroke-width="1.8" fill="none"/></svg>',
    surprise: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h3l10 10h3M4 17h3l3-3M14 10l3-3h3M18 4l2 3-2 3M18 14l2 3-2 3" stroke="currentColor" stroke-width="1.8" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    library: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 4v16M10 4v16M15 4l4 16" stroke="currentColor" stroke-width="1.8" fill="none" stroke-linecap="round"/></svg>',
  };

  /* ---- The shell: Decision 068's six sections ---- */
  const SECTIONS = [['home', 'Home'], ['browse', 'Browse'], ['stations', 'Stations'], ['surprise', 'Surprise'], ['search', 'Search'], ['library', 'Library']];
  function shell(active, mainHTML, { player = null } = {}) {
    const nav = SECTIONS.map(([k, label]) => {
      const href = k === 'home' || k === 'browse' ? `?s=${k}` : '#';
      return `<a href="${href}" class="ed-nav-item${k === active ? ' on' : ''}"${k === active ? ' aria-current="page"' : ''}>${I[k]}<span>${label}</span></a>`;
    }).join('');
    return `<div class="ed-app">
      <nav class="ed-nav" aria-label="Sections"><a class="ed-wordmark" href="?s=home">Ear Drama</a>${nav}</nav>
      <main class="ed-main">${mainHTML}</main>
      ${player ? `<a class="ed-mini" href="?s=now-playing">${player}</a>` : ''}
    </div>`;
  }

  /* ---- Prototype routing: ?s=<screen>; ?theme=dark for the dark shots ---- */
  const SCREENS = ['home', 'browse', 'series-rich', 'series-sparse', 'episode-rich', 'episode-bare',
    'now-playing', 'create-pick', 'create-part', 'create-record', 'production'];
  function boot(render) {
    const q = new URLSearchParams(location.search);
    if (q.get('theme')) document.documentElement.dataset.theme = q.get('theme');
    const s = q.get('s') || 'home';
    document.getElementById('app').innerHTML = render(s);
    document.body.dataset.screen = s;
  }

  /* ---- Data lookups ---- */
  const popular = () => ED.popular;
  const seriesByKey = (k) => ED.popular.find((s) => s.key === k);
  const roleWords = (r) => (r.words / 150);
  const aboutMin = (words) => { const m = words / 150; return m < 1 ? 'under 1 min' : `about ${Math.round(m)} min`; };
  const creditGroups = (credits) => {
    const ON = new Set(['cast', 'host', 'announcer', 'narrator', 'guest', 'commercial spokesperson']);
    const WR = new Set(['writer', 'adaptor', 'author', 'creator', 'screenwriter']);
    const by = new Map();
    for (const c of credits) {
      if (c.character && c.role === 'cast') { /* keep the character line */ }
      const g = ON.has(c.role) ? 'On the air' : WR.has(c.role) ? 'Writing' : (c.role === 'the man in black' ? null : 'Production');
      if (!g) continue;
      const k = g + '|' + c.name;
      if (!by.has(k)) by.set(k, { group: g, name: c.name, roles: [], character: null, art: c.art });
      const e = by.get(k);
      if (c.character) e.character = c.character;
      if (!e.roles.includes(c.role)) e.roles.push(c.role);
      if (!e.art && c.art) e.art = c.art;
    }
    const out = { 'On the air': [], Writing: [], Production: [] };
    for (const e of by.values()) out[e.group].push(e);
    return out;
  };
  const facesOf = (credits, n = 3) => {
    const seen = new Set(); const out = [];
    for (const c of credits) if (c.art && c.role === 'cast' && !seen.has(c.name)) { seen.add(c.name); out.push(c); }
    for (const c of credits) if (c.art && !seen.has(c.name)) { seen.add(c.name); out.push(c); }
    return out.slice(0, n);
  };
  /** The broadcast line: network · long date · sponsor, at most three facts. */
  const eventLine = (ep) => [ep.network, ep.date ? fmtDate(ep.date, 'long') : 'Undated', ep.sponsor].filter(Boolean);

  window.EDK = { ED, esc, fmtDate, mins, clock, author, genreName, artURL, aspect, isWide, cropRect, faceCrop,
    print, tile, runStrip, coreYears, I, shell, boot, SCREENS, popular, seriesByKey, roleWords, aboutMin,
    creditGroups, facesOf, eventLine, MONTHS };
})();
