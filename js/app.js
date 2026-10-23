/**
 * Ear Drama on the web: the views, the router, and the player's face.
 *
 * Routes (every view has a URL; the https twins of the apps' links):
 *   ?view=listen                      Listen (also the bare site)
 *   ?view=series&genre=&decade=&network=&sort=   Series browse
 *   ?series={key}&season={1948-49|undated}       a series page
 *   ?item={episode id}                episode Detail
 *   ?view=search&q=                   Search
 *   ?view=library&tab=queue|history|following    Library (this device)
 * Path twins (/series/{key}, /episode/{id}, /search?q=) are forwarded into
 * these by 404.html. Harness doors: ?mute=1, ?door_seconds=n.
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
  const VIEWS = ['listen', 'series', 'show', 'episode', 'search', 'library'];
  const TAB_OF = { listen: 'listen', series: 'series', show: 'series', episode: 'series', search: 'search',
                   library: 'library' };
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
    remove: 'M6.4 5 5 6.4 10.6 12 5 17.6 6.4 19l5.6-5.6 5.6 5.6 1.4-1.4-5.6-5.6L19 6.4 17.6 5 12 10.6z',
  };
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
    if (kind === 'empty') return el('p', { class: 'state caption' }, opts.text);
    const text = kind === 'offline' ? 'You are offline.' : kind === 'missing' ? 'Not in the catalog.'
      : 'This did not load.';
    return el('div', { class: kind === 'offline' ? 'state state-problem state-offline' : 'state state-problem', role: 'alert' },
      el('p', { class: 'body' }, text),
      opts.retry && kind !== 'missing' ? el('button', { type: 'button', class: 'btn', onclick: opts.retry }, 'Try again')
        : null);
  }
  function problem(err) {
    if (err && err.kind === 'missing') return 'missing';
    if ((err && err.kind === 'offline') || navigator.onLine === false) return 'offline';
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

  /* ---- Rows and cards ---- */

  /** An episode row: date first (R1), then title; the series when the list mixes series. */
  function episodeRow(ep, { showSeries = false } = {}) {
    const progress = Store.progress(ep.id);
    const sub = [showSeries ? ep.seriesName : null, fmtLength(ep.length)].filter(Boolean).join(' · ');
    const link = el('a', { class: 'ep-link', href: `?item=${encodeURIComponent(ep.id)}` },
      el('span', { class: 'ep-date tabular' }, ep.date || 'Undated'),
      el('span', { class: 'ep-title body-strong' }, epTitle(ep)),
      sub ? el('span', { class: 'ep-sub caption' }, sub) : null,
      progress > 0 ? el('span', { class: 'ep-progress', 'aria-hidden': 'true' },
        el('span', { style: null, dataset: { p: String(Math.round(progress * 100)) } })) : null);
    const row = el('li', { class: 'ep-row' }, link,
      ep.url ? el('button', {
        type: 'button', class: 'icon-btn', 'aria-label': `Play ${epTitle(ep)}, ${ep.date || 'undated'}`,
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

  function seriesCard(s) {
    return el('li', {},
      el('a', { class: 'series-card', href: `?series=${encodeURIComponent(s.key)}`, dataset: { genre: s.genre || '' } },
        el('span', { class: 'body-strong series-card-name' }, s.name),
        el('span', { class: 'caption' }, seriesMeta(s))));
  }
  function shelf(title, items, idBase) {
    const h = el('h2', { class: 'section-header', id: `${idBase}-h` }, title);
    const ul = el('ul', { class: 'rail', 'aria-labelledby': `${idBase}-h` });
    items.forEach(s => ul.append(seriesCard(s)));
    return el('section', { class: 'shelf' }, h, ul);
  }
  function seriesRow(s) {
    return el('li', { class: 'series-row' },
      el('a', { href: `?series=${encodeURIComponent(s.key)}`, dataset: { genre: s.genre || '' } },
        el('span', { class: 'body-strong' }, s.name),
        el('span', { class: 'caption' }, seriesMeta(s))));
  }

  /* ================================================================
     ROUTER
  ================================================================ */

  function parseRoute() {
    const p = new URLSearchParams(location.search);
    if (p.get('item')) return { view: 'episode', id: p.get('item'), p };
    if (p.get('series')) return { view: 'show', key: p.get('series'), p };
    const v = p.get('view');
    if (['series', 'search', 'library', 'listen'].includes(v)) return { view: v, p };
    return { view: 'listen', p };
  }

  let firstRoute = true;
  function route() {
    const r = parseRoute();
    VIEWS.forEach(v => { $(`view-${v}`).hidden = v !== r.view; });
    document.querySelectorAll('[data-nav]').forEach(a => {
      const on = a.dataset.nav === TAB_OF[r.view];
      a.classList.toggle('active', on);
      if (on) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current');
    });
    ({ listen: renderListen, series: renderBrowse, show: renderShow, episode: renderEpisode,
       search: renderSearch, library: renderLibrary })[r.view](r);
    if (!firstRoute) {
      $('main-content').scrollTop = 0;
      const h = $(`view-${r.view}`).querySelector('h1');
      if (h) h.focus({ preventScroll: true });
    }
    firstRoute = false;
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

    const today = new Date();
    const dayBox = el('div');
    body.append(el('section', { class: 'block', 'aria-labelledby': 'day-h' },
      el('div', { class: 'block-head' },
        el('h2', { class: 'section-header', id: 'day-h' }, 'This day in radio'),
        el('span', { class: 'caption' }, monthDay.format(today))),
      dayBox));
    load(dayBox, () => API.thisDay(today), (rows) => {
      if (!rows.length) { dayBox.append(stateBox('empty', { text: 'Nothing in the catalog aired on this date.' })); return; }
      const first = 6;
      const list = episodeList(rows.slice(0, first), { showSeries: true });
      dayBox.append(list);
      if (rows.length > first) {
        const more = el('button', { type: 'button', class: 'btn btn-ghost' }, `Show all ${num.format(rows.length)}`);
        more.addEventListener('click', () => {
          rows.slice(first).forEach(e => list.append(episodeRow(e, { showSeries: true })));
          paintProgress(list);
          more.remove();
        });
        dayBox.append(more);
      }
    });

    const shelvesBox = el('div');
    body.append(shelvesBox);
    load(shelvesBox, async () => {
      const [d] = await Promise.all([API.listen(), API.manifest().then(m => { manifest = m; })]);
      return d;
    }, (d) => {
      if (!d.shelves.length && !d.most.length) {
        shelvesBox.append(stateBox('empty', { text: 'Nothing in the catalog yet.' }));
        return;
      }
      if (d.most.length) shelvesBox.append(shelf('Most episodes', d.most, 'most'));
      d.shelves.forEach((s, i) => {
        shelvesBox.append(shelf(manifest.genreNames[s.genre] || s.genre, s.series, `genre-${i}`));
      });
    });
  }

  /* ================================================================
     SERIES BROWSE
  ================================================================ */

  const decadeOf = (s) => (s.first ? `${s.first.slice(0, 3)}0` : null);
  const networksOf = (s) => (s.networks ? s.networks.split(', ') : []);

  function browseFilter(rows, f, skip) {
    return rows.filter(s => (skip === 'genre' || !f.genre || s.genre === f.genre)
      && (skip === 'decade' || !f.decade || decadeOf(s) === f.decade)
      && (skip === 'network' || !f.network || networksOf(s).includes(f.network)));
  }

  function fillSelect(sel, allLabel, counts, current, label = (k) => k) {
    sel.replaceChildren(el('option', { value: '' }, allLabel));
    const keys = [...counts.keys()];
    keys.forEach(k => sel.append(el('option', { value: k, selected: k === current }, `${label(k)} (${num.format(counts.get(k))})`)));
    if (current && !counts.has(current)) sel.append(el('option', { value: current, selected: true }, `${label(current)} (0)`));
  }

  function renderBrowse(r) {
    setTitle('Series');
    const f = { genre: r.p.get('genre') || '', decade: r.p.get('decade') || '', network: r.p.get('network') || '',
                sort: r.p.get('sort') || 'name' };
    const body = $('browse-body');
    $('f-sort').value = f.sort;
    load(body, async () => {
      const [idx, m] = await Promise.all([API.seriesIndex(), API.manifest()]);
      manifest = m;
      return idx;
    }, ({ rows }) => {
      const count = (list, fn) => {
        const c = new Map();
        list.forEach(s => [].concat(fn(s)).forEach(k => { if (k) c.set(k, (c.get(k) || 0) + 1); }));
        return c;
      };
      const byCount = (c) => new Map([...c].sort((a, b) => b[1] - a[1] || String(a[0]).localeCompare(b[0])));
      fillSelect($('f-genre'), 'All genres', byCount(count(browseFilter(rows, f, 'genre'), s => s.genre)), f.genre,
        k => manifest.genreNames[k] || k);
      const dec = count(browseFilter(rows, f, 'decade'), decadeOf);
      fillSelect($('f-decade'), 'All decades', new Map([...dec].sort()), f.decade, k => `${k}s`);
      const nets = byCount(count(browseFilter(rows, f, 'network'), networksOf));
      fillSelect($('f-network'), 'All networks', new Map([...nets].slice(0, 40)), f.network);

      const list = browseFilter(rows, f);
      const sorters = {
        name: (a, b) => a.name.localeCompare(b.name, 'en', { sensitivity: 'base' }),
        count: (a, b) => b.episodes - a.episodes || a.name.localeCompare(b.name),
        first: (a, b) => (a.first || '9999').localeCompare(b.first || '9999') || a.name.localeCompare(b.name),
      };
      list.sort(sorters[f.sort] || sorters.name);
      $('browse-count').textContent = plural(list.length, 'series', 'series');
      if (!list.length) { body.append(stateBox('empty', { text: 'No series match these filters.' })); return; }
      const ul = el('ul', { class: 'series-list' });
      body.append(ul);
      let shown = 0;
      const more = el('button', { type: 'button', class: 'btn btn-ghost' }, 'Show more');
      const page = () => {
        list.slice(shown, shown + PAGE).forEach(s => ul.append(seriesRow(s)));
        shown += PAGE;
        if (shown >= list.length) more.remove();
      };
      more.addEventListener('click', page);
      page();
      if (shown < list.length) body.append(more);
    });
  }

  $('browse-filters').addEventListener('change', () => {
    const p = new URLSearchParams({ view: 'series' });
    for (const k of ['genre', 'decade', 'network', 'sort']) {
      const v = $(`f-${k}`).value;
      if (v && !(k === 'sort' && v === 'name')) p.set(k, v);
    }
    navigate(`?${p}`, true);
  });

  /* ================================================================
     SERIES PAGE
  ================================================================ */

  function renderShow(r) {
    const body = $('show-body');
    const scope = r.p.get('season');
    load(body, () => API.seriesPage(r.key), (s) => {
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
      shareBtn.addEventListener('click', () => share(s.name, `?series=${encodeURIComponent(s.key)}`));

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
        listBox.replaceChildren(eps.length ? episodeList(eps) : stateBox('empty', { text: 'No episodes in this season.' }));
      };

      const meta = el('p', { class: 'caption' }, seriesMeta({ ...s, episodes: s.episodes.length }));
      const head = el('header', { class: 'page-head', dataset: { genre: s.genre || '' } },
        el('h1', { class: 'view-heading', id: 'show-h', tabindex: '-1' }, s.name), meta,
        el('div', { class: 'actions' }, followBtn, shareBtn));
      if (s.genre) {
        genreName(s.genre).then(n => meta.prepend(el('a', { href: `?view=series&genre=${encodeURIComponent(s.genre)}` }, n),
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
      return { d, s, rightsLine: lines[0], m: lines[1] };
    }, ({ d, s, rightsLine, m }) => {
      if (d.id !== r.id) history.replaceState(null, '', `?item=${encodeURIComponent(d.id)}`);
      const seriesName = s ? s.name : d.series;
      const title = epTitle(d);
      setTitle(title, d.date, seriesName);
      let chosen = 0;
      const card = () => ({ id: d.id, title, series: d.series, seriesName, date: d.date,
                            url: d.recordings[chosen].url, length: d.recordings[chosen].length || d.length,
                            // The measurement belongs to the default copy only.
                            li: chosen === 0 ? d.li : null, ltp: chosen === 0 ? d.ltp : null });

      const resume = Store.resumeAt(d.id);
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
      shareBtn.addEventListener('click', () => share(`${title} (${d.date || 'undated'})`, `?item=${encodeURIComponent(d.id)}`));

      // An undated episode with no network or credits is most of the catalog: its one line of
      // facts carries "Undated", and the number is not repeated when it already names the episode.
      const facts = [d.date ? null : 'Undated', d.network, fmtLength(d.length), d.season ? `Season ${d.season}` : null,
                     d.title && d.num !== null && d.num !== undefined ? `No. ${d.num}` : null].filter(Boolean).join(' · ');
      body.append(el('header', { class: 'page-head', dataset: { genre: (s && s.genre) || '' } },
        el('a', { class: 'section-header eyebrow-link', href: `?series=${encodeURIComponent(d.series)}` }, seriesName),
        el('h1', { class: 'view-heading', id: 'episode-h', tabindex: '-1' }, title),
        d.date ? el('p', { class: 'body' }, fmtLongDate(d.date)) : null,
        facts ? el('p', { class: 'caption' }, facts) : null,
        d.aka ? el('p', { class: 'caption' }, `Also titled ${d.aka}`) : null,
        el('div', { class: 'actions' }, playBtn, queueBtn, shareBtn)));

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
          dl.append(el('div', { class: 'credit' },
            el('dt', { class: 'caption' }, role.charAt(0).toUpperCase() + role.slice(1)),
            groups.get(role).map(c => el('dd', { class: 'body' }, c.name,
              c.character ? el('span', { class: 'caption' }, ` as ${c.character}`) : null))));
        });
        body.append(el('section', { class: 'block', 'aria-labelledby': 'credits-h' },
          el('h2', { class: 'section-header', id: 'credits-h' }, 'Cast and credits'), dl));
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
      const [series, numbers] = await Promise.all([API.searchSeries(q), API.searchEpisodeNumbers(q)]);
      if (seq !== searchSeq) return;
      body.replaceChildren();
      if (!series.total && !numbers.length) {
        body.append(stateBox('empty', { text: `No matches for “${q.trim()}”.` }));
        return;
      }
      if (series.total) {
        body.append(el('section', { class: 'block', 'aria-labelledby': 'rs-h' },
          el('div', { class: 'block-head' }, el('h2', { class: 'section-header', id: 'rs-h' }, 'Series'),
            el('span', { class: 'caption' }, plural(series.total, 'series', 'series'))),
          el('ul', { class: 'series-list' }, series.rows.map(seriesRow))));
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
    } catch (err) {
      if (seq !== searchSeq) return;
      console.error(err);
      body.replaceChildren(stateBox(problem(err), { retry: () => runSearch(q) }));
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
     LIBRARY (this device)
  ================================================================ */

  function renderLibrary(r) {
    setTitle('Library');
    const tab = ['queue', 'history', 'following'].includes(r.p.get('tab')) ? r.p.get('tab') : 'queue';
    document.querySelectorAll('#library-tabs [data-lib]').forEach(b =>
      b.setAttribute('aria-pressed', String(b.dataset.lib === tab)));
    const body = $('library-body');
    body.replaceChildren();
    if (tab === 'queue') {
      const q = Store.queue();
      if (!q.length) { body.append(stateBox('empty', { text: 'Nothing queued.' })); return; }
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
        row.append(tools);
        ul.append(row);
      });
      paintProgress(ul);
      body.append(ul);
    } else if (tab === 'history') {
      const h = Store.history();
      if (!h.length) { body.append(stateBox('empty', { text: 'Nothing played yet.' })); return; }
      body.append(episodeList(h, { showSeries: true }),
        el('button', { type: 'button', class: 'btn btn-ghost', onclick: () => {
          if (confirm('Clear your listening history and resume points on this device?')) { Store.clearHistory(); route(); }
        } }, 'Clear history'));
    } else {
      const f = Store.follows();
      if (!f.length) { body.append(stateBox('empty', { text: 'Not following any series.' })); return; }
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
    document.querySelectorAll('[data-act="toggle"]').forEach(b => {
      b.setAttribute('aria-label', playing ? 'Pause' : 'Play');
      b.classList.toggle('is-playing', playing);
    });
    const d = isFinite(a.duration) ? a.duration : (cur.length || 0);
    const t = a.currentTime || 0;
    $('mini-progress').style.width = d ? `${Math.min(100, (t / d) * 100)}%` : '0';
    if (kind === 'load' || kind === 'error' || kind === 'state' || kind === 'sleep-fired') {
      $('mini-title').textContent = epTitle(cur);
      $('np-title').textContent = epTitle(cur);
      $('np-series').textContent = cur.seriesName || '';
      $('np-series').setAttribute('href', `?series=${encodeURIComponent(cur.series || '')}`);
      $('np-meta').textContent = [cur.date ? fmtLongDate(cur.date) : 'Undated'].join('');
      const err = kind === 'error' && Player.error;
      const errText = navigator.onLine === false ? 'You are offline.' : 'This recording did not load.';
      $('mini-meta').textContent = err ? errText : [cur.seriesName, cur.date].filter(Boolean).join(' · ');
      $('mini-meta').classList.toggle('is-error', !!err);
      if (err) announce(errText);
    }
    if (!seeking) {
      seekEl.max = String(Math.floor(d));
      seekEl.value = String(Math.floor(t));
    }
    seekEl.setAttribute('aria-valuetext', `${fmtClock(t)} of ${fmtClock(d)}`);
    $('np-pos').textContent = fmtClock(seeking ? Number(seekEl.value) : t);
    $('np-left').textContent = `-${fmtClock(Math.max(0, d - t))}`;
    $('np-speed').value = String(a.playbackRate || 1);
    const st = sleepText();
    document.querySelectorAll('.sleep-label').forEach(x => { x.textContent = st; });
    document.querySelectorAll('[data-act="sleep"]').forEach(b => b.setAttribute('aria-label', st));
    $('sleep-off').hidden = !Player.sleep;
    document.querySelectorAll('#sleep-menu [data-sleep]').forEach(b => {
      const s = Player.sleep;
      const on = s && ((b.dataset.sleep === 'end' && s.kind === 'end') || (s.kind === 'time' && b.dataset.sleep === String(s.minutes)));
      b.setAttribute('aria-current', on ? 'true' : 'false');
    });
    const next = Player.nextInQueue();
    $('np-next').textContent = next ? `Next in queue: ${epTitle(next)}` : '';
    if (kind === 'sleep-fired') announce('Sleep timer ended.');
  }
  Player.onChange(paintPlayer);

  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-act]');
    if (!b) return;
    const act = b.dataset.act;
    if (act === 'toggle') Player.toggle();
    else if (act === 'back') Player.back();
    else if (act === 'fwd') Player.forward();
    else if (act === 'sleep') { if (!np.open) np.showModal(); $('sleep-menu').showPopover(); }
  });
  $('mini-open').addEventListener('click', () => np.showModal());
  $('np-close').addEventListener('click', () => np.close());
  seekEl.addEventListener('input', () => { seeking = true; $('np-pos').textContent = fmtClock(Number(seekEl.value)); });
  seekEl.addEventListener('change', () => { seeking = false; Player.seek(Number(seekEl.value)); });
  $('np-speed').addEventListener('change', (e) => { Player.setRate(e.target.value); announce(`Speed ${e.target.value}×`); });
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
    if (e.key === 'k' || (e.key === ' ' && !t.closest('button, a'))) { e.preventDefault(); Player.toggle(); }
    else if (e.key === 'j') Player.back();
    else if (e.key === 'l') Player.forward();
  });

  Store.onChange(() => { if (np.open) paintPlayer('tick'); });

  /* ================================================================
     BOOT
  ================================================================ */

  const params = new URLSearchParams(location.search);
  if (params.get('mute') === '1') Player.setMuted(true);
  Player.setRate(Store.rate());
  const doorSeconds = Number(params.get('door_seconds'));
  if (doorSeconds > 0) setTimeout(() => navigate('?view=listen'), doorSeconds * 1000);
  /* Offline (WEB-DESIGN §7.3): a status line while the browser reports no network; what was
     opened before still opens from the service worker's copies. */
  const paintOnline = () => { $('offline-note').hidden = navigator.onLine !== false; };
  window.addEventListener('offline', paintOnline);
  window.addEventListener('online', () => { paintOnline(); if (document.querySelector('.state-problem')) route(); });
  paintOnline();

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
