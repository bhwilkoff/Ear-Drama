/* Direction A, The Almanac: the date is the way in (D1a §4.4, D1b Pattern 4). */
(function () {
  'use strict';
  const K = window.EDK, ED = K.ED, e = K.esc, I = K.I;
  const TODAY = '2026-10-29';
  const shortMin = (w) => (w < 150 ? '<1 min' : `${Math.round(w / 150)} min`);

  const playDot = (href = '?s=now-playing') => `<a class="play-dot" href="${href}" aria-label="Play">${I.play}</a>`;
  const row = ({ left, title, sub, len, href, play = true, cls = '', dated = false }) => `
    <li class="log-row ${cls}${dated ? ' dated' : ''}">
      <span class="log-left l6">${left || ''}</span>
      <a class="log-body" href="${href || '#'}">${dated ? `<span class="l6 d">${left}</span>` : ''}<span class="l3">${e(title)}</span>${sub ? `<span class="l5">${sub}</span>` : ''}</a>
      <span class="log-len l6 muted">${len || ''}</span>
      ${play ? playDot() : '<span></span>'}
    </li>`;

  /* The years a date survives in, as a strip of counted years. */
  function yearStrip(rows, selected) {
    const by = {};
    for (const r of rows) by[r.date.slice(0, 4)] = (by[r.date.slice(0, 4)] || 0) + 1;
    const years = []; for (let y = 1930; y <= 1962; y++) years.push(y);
    const max = Math.max(...Object.values(by));
    return `<div class="years" role="list">${years.map((y) => {
      const n = by[y] || 0;
      const h = n ? Math.max(4, Math.round((n / max) * 44)) : 1;
      const on = String(y) === selected;
      const lab = y % 10 === 0 || on ? `<span class="yl">${on ? y : `’${String(y).slice(2)}`}</span>` : '';
      return `<a role="listitem" class="yr${n ? '' : ' none'}${on ? ' on' : ''}" href="${n ? '#' : ''}" aria-label="${y}: ${n}"><span class="yb" style="height:${h}px"></span>${lab}</a>`;
    }).join('')}</div>`;
  }

  /* Merge consecutive gaps (D1a §3.2 Stations) into one row. */
  function evening(slots) {
    const out = []; let gap = null;
    for (const s of slots) {
      if (s.gap && !s.known_series) { if (gap) gap.et_end = s.et_end; else gap = { ...s }; continue; }
      if (gap) { out.push(gap); gap = null; }
      out.push(s);
    }
    if (gap) out.push(gap);
    return out.map((s) => {
      const t = `${K.clock(s.et_start)}`;
      if (s.episode) return row({ left: t, title: s.episode.series, sub: e(s.episode.title), len: `${s.length_min} min`, cls: 'aired' });
      if (s.known_series) return `<li class="log-row gap"><span class="log-left l6">${t}</span><span class="log-body"><span>${e(s.known_series)}</span><span class="l5">Not surviving</span></span><span></span><span></span></li>`;
      return `<li class="log-row gap"><span class="log-left l6">${t}</span><span class="log-body l5">Not surviving until ${K.clock(s.et_end)}</span><span></span><span></span></li>`;
    }).join('');
  }

  function home() {
    const rows = ED.day.rows;
    const sel = '1944';
    const all = rows.filter((r) => r.date.startsWith(sel)).sort((a, b) => a.seriesName.localeCompare(b.seriesName));
    const night = all.filter((r) => r.show), rest = all.length - night.length;
    const years = new Set(rows.map((r) => r.date.slice(0, 4))).size;
    const ev = ED.evening;
    return K.shell('home', `
      <header class="masthead">
        <p class="l5 kicker">Thursday</p>
        <h1 class="date-big">${K.fmtDate(TODAY, 'md')}</h1>
        <p class="l5">${rows.length} surviving broadcasts · ${years} years</p>
      </header>
      ${yearStrip(rows, sel)}
      <div class="home-grid">
      <section class="sheet">
        <h2 class="l2">${K.fmtDate(`${sel}-10-29`, 'long')}</h2>
        <ol class="log">${night.map((r) => row({ left: '', title: r.seriesName, sub: e(r.title), len: K.mins(r.length), href: '?s=episode-rich' })).join('')}</ol>
        ${rest ? `<a class="more" href="#">${rest} single recordings</a>` : ''}
      </section>
      <section class="sheet">
        <h2 class="l2">Tonight on Stations</h2>
        <p class="l5">${K.fmtDate(ev.evening, 'long')} · ${e(ev.station)} · ${e(ev.network)} · ET</p>
        <ol class="log evening">${evening(ev.slots)}</ol>
      </section>
      </div>`, { player: mini() });
  }

  function mini() {
    const r = ED.suspenseRich;
    const face = r.credits[0].art;
    return `${K.tile('', face, 'mystery', 40)}<span class="mini-t"><span class="l3">${e(r.title)}</span><span class="l5">Suspense · ${K.fmtDate(r.date, 'year')}</span></span><span class="icon-btn icon-btn-primary">${I.pause}</span>`;
  }

  function field() {
    const G = ['drama', 'mystery', 'comedy', 'serial', 'western', 'scifi', 'documentary', 'news'];
    const D = [1920, 1930, 1940, 1950, 1960];
    const n = (g, d) => (ED.field.find((f) => f.genre === g && f.decade === d) || {}).shows || 0;
    const max = Math.max(...ED.field.map((f) => f.shows));
    const head = `<span></span>${G.map((g) => `<span class="fh" data-genre="${g}">${e(K.genreName(g))}</span>`).join('')}`;
    const body = D.map((d) => `<span class="fd l6">${d}s</span>${G.map((g) => {
      const v = n(g, d);
      return `<a href="#" class="fc${v ? '' : ' zero'}" data-genre="${g}" style="--o:${v ? (0.12 + 0.88 * Math.sqrt(v / max)).toFixed(2) : 0}" aria-label="${K.genreName(g)}, ${d}s: ${v}">${v || ''}</a>`;
    }).join('')}`).join('');
    return `<div class="field" role="grid">${head}${body}</div>`;
  }

  function showRow(s) {
    return `<li class="show-row" data-genre="${e(s.genre || '')}">
      <a href="?s=series-rich" class="show-body"><span class="l3">${e(s.name)}</span>
        <span class="l5">${K.coreYears(s.core)} · ${s.episodes.toLocaleString('en-US')} episodes</span></a>
      ${K.runStrip(s.hist, { genre: s.genre || '', w: 112, h: 20 })}
    </li>`;
  }

  function browse() {
    const t = ED.tiers;
    return K.shell('browse', `
      <h1 class="l1">Browse</h1>
      <div class="chips"><button class="chip">Genre</button><button class="chip">Decade</button><button class="chip">Network</button><button class="chip">Popular</button></div>
      <section class="sheet">
        <h2 class="l2">Shows by decade</h2>
        <p class="l5">By the year a show first aired · ${ED.fieldUnsorted} shows have no genre</p>
        ${field()}
      </section>
      <section class="sheet">
        <div class="sheet-head"><h2 class="l2">${t.shows.toLocaleString('en-US')} shows</h2><a href="#" class="l5 link">${t.singles.toLocaleString('en-US')} single recordings</a></div>
        <div class="strip-axis l6 muted"><span>1930</span><span>1962</span></div>
        <ol class="shows">${ED.popular.slice(0, 16).map(showRow).join('')}</ol>
      </section>`);
  }

  /* A guest is a face not heard on a quarter or more of the season (D1b §3 rule b). */
  function guests(season) {
    const n = {};
    for (const ep of season) for (const f of ep.faces || []) n[f.name] = (n[f.name] || 0) + 1;
    const regular = new Set(Object.keys(n).filter((k) => n[k] >= season.length * 0.25));
    return (ep) => (ep.faces || []).map((f) => f.name).filter((x) => !regular.has(x));
  }

  function bigStrip(hist, sel) {
    const years = []; for (let y = 1940; y <= 1962; y++) years.push(y);
    const max = Math.max(...Object.values(hist));
    return `<div class="run" data-genre="mystery">${years.map((y) => {
      const v = hist[y] || 0;
      return `<a href="#" class="run-y${String(y) === sel ? ' on' : ''}${v ? '' : ' none'}" aria-label="${y}: ${v}"><span class="run-b" style="height:${v ? Math.max(3, Math.round((v / max) * 56)) : 1}px"></span><span class="run-l l6">${y % 5 === 0 || String(y) === sel ? y : ''}</span></a>`;
    }).join('')}</div>`;
  }

  function seriesHead(s, facts) {
    return `<header class="card-head" data-genre="${e(s.genre || '')}">
      <h1 class="l1 card-title">${e(s.name)}</h1>
      <p class="l5">${facts.join(' · ')}</p>
      <div class="actions"><button class="btn btn-way">Follow</button><button class="icon-btn" aria-label="Share">${I.share}</button></div>
    </header>`;
  }

  function seriesRich() {
    const s = ED.suspense, g = guests(s.season);
    const rows = s.season.slice(0, 18).map((ep) => {
      const gs = g(ep);
      return row({ dated: true, left: ep.date, title: ep.title, sub: gs.length ? e(gs.slice(0, 2).join(', ')) : '', len: K.mins(ep.length), href: ep.date === '1943-12-02' ? '?s=episode-rich' : '#' });
    }).join('');
    return K.shell('browse', `
      ${seriesHead(s, [`<a href="#">${K.genreName(s.genre)}</a>`, e(s.networks), K.coreYears(s.core), `${s.episodes.toLocaleString('en-US')} episodes`])}
      <section class="sheet">
        ${bigStrip(s.hist, '1943')}
        <div class="scope"><span class="l3">1943–44</span><span class="l5">${s.season.length} broadcasts</span></div>
        <ol class="log">${rows}</ol>
        <a class="more" href="#">${s.season.length - 18} more</a>
      </section>`);
  }

  function seriesSparse() {
    const s = ED.sparse;
    return K.shell('browse', `
      ${seriesHead(s, [`<a href="#">${K.genreName(s.genre)}</a>`, e(s.networks), `${s.episodes.length} episodes`])}
      <section class="sheet">
        <ol class="log">${s.episodes.map((ep) => row({ dated: true, left: ep.date || `No. ${ep.num}`, title: ep.title, len: K.mins(ep.length), href: '?s=episode-bare' })).join('')}</ol>
      </section>`);
  }

  function night(list, exclude) {
    const rows = list.filter((r) => !exclude(r)).sort((a, b) => b.show - a.show);
    return `<aside class="sheet night">
      <h2 class="l2">That night</h2>
      <ol class="log">${rows.map((r) => row({ title: r.seriesName, sub: e(r.title), len: K.mins(r.length), href: '#' })).join('')}</ol>
    </aside>`;
  }

  function credits(list) {
    const G = K.creditGroups(list);
    return Object.entries(G).filter(([, v]) => v.length).map(([g, v]) => `<h3 class="l5 grp">${g}</h3><ul class="credits">${v.map((c) => `<li><a href="#">${e(c.name)}</a>${c.character ? ` <span class="muted">as ${e(c.character)}</span>` : ''}${c.group !== 'On the air' || c.roles.length > 1 ? ` <span class="muted">${e(c.roles.filter((r) => r !== 'cast').join(', '))}</span>` : ''}</li>`).join('')}</ul>`).join('');
  }

  function episode(ep, seriesName, nightList, exclude) {
    const faces = K.facesOf(ep.credits, 3);
    const line = K.eventLine(ep);
    return K.shell('browse', `
      <div class="ep">
        <div class="ep-main">
          <div class="ep-top"><a class="l3" href="?s=${ep.credits.length ? 'series-rich' : 'series-sparse'}">${e(seriesName)}</a><button class="icon-btn" aria-label="Share">${I.share}</button></div>
          <h1 class="l1 ep-title">${e(ep.title)}</h1>
          <p class="event">${line.map(e).join(' <span class="dot">·</span> ')}</p>
          <div class="actions">
            <a class="btn btn-primary" href="?s=now-playing">${I.play}Play · ${K.mins(ep.length)}</a>
            <button class="btn btn-way">${I.queue}Add to queue</button>
          </div>
          ${faces.length ? `<ul class="faces">${faces.map((c) => `<li><a href="#">${K.faceCrop(c.art, 56, 'round')}<span class="l5">${e(c.name)}</span></a></li>`).join('')}</ul>` : ''}
          ${ep.credits.length ? `<details class="disc"><summary class="l3">Cast and credits</summary>${credits(ep.credits)}</details>` : ''}
          ${ep.transcript ? '<details class="disc"><summary class="l3">Automatic transcript</summary></details>' : ''}
          ${ep.recordings.length > 1 ? `<details class="disc"><summary class="l3">${ep.recordings.length} copies</summary><ul class="credits">${ep.recordings.map((r) => `<li>${K.mins(r.length)} <span class="muted">${e(r.format)}</span> <a href="#">Source</a></li>`).join('')}</ul></details>` : ''}
          <p class="l5 rights">${e(ED.rightsLines[ep.rights] || ED.rightsLines.unclaimed)}</p>
        </div>
        ${nightList && nightList.length ? night(nightList, exclude) : ''}
      </div>`, { player: mini() });
  }

  function nowPlaying() {
    const ep = ED.suspenseRich, art = ep.credits[0].art;
    const nightRows = ED.sameNight.filter((r) => r.series !== 'suspense' && !/suspense/i.test(r.seriesName));
    return `<div class="np">
      <div class="np-top"><a class="icon-btn" href="?s=episode-rich" aria-label="Close">${I.down}</a><span class="l5">${K.fmtDate(ep.date, 'long')}</span><span class="icon-btn">${I.more}</span></div>
      <div class="np-art">${K.print(art, 300, 300)}</div>
      <p class="l5 np-cap">Hans Conried</p>
      <a class="l3" href="?s=series-rich">Suspense</a>
      <h1 class="l2 np-title">${e(ep.title)}</h1>
      <p class="l5">${e(ep.network)} · ${e(ep.sponsor)}</p>
      <div class="scrub"><span class="scrub-fill" style="width:38%"></span></div>
      <div class="scrub-t l6 muted"><span>11:22</span><span>−18:28</span></div>
      <div class="transport"><button class="icon-btn" aria-label="Back 15 seconds">${I.r15}</button><button class="icon-btn icon-btn-primary big" aria-label="Pause">${I.pause}</button><button class="icon-btn" aria-label="Forward 30 seconds">${I.f30}</button></div>
      <div class="opts"><button class="opt l5">1×</button><button class="opt l5">${I.moon}Sleep</button></div>
      <section class="np-night"><h2 class="l2">That night</h2><ol class="log">${nightRows.map((r) => row({ title: r.seriesName, sub: e(r.title), len: K.mins(r.length) })).join('')}</ol></section>
    </div>`;
  }

  function createPick() {
    const list = [...ED.plays].sort((a, b) => (a.kind === b.kind ? a.words - b.words : a.kind === 'radio' ? -1 : 1));
    const grp = (k, label) => `<section class="sheet"><h2 class="l2">${label}</h2><ol class="log">${list.filter((p) => p.kind === k).map((p) => row({
      left: shortMin(p.words), title: p.title, sub: `${e(p.authors.map(K.author).join(', '))} · ${p.parts} parts`, href: p.id === 'gut-28051' ? '?s=create-part' : '#', play: false,
    })).join('')}</ol></section>`;
    return K.shell('browse', `<h1 class="l1">Start an ear drama</h1>${grp('radio', 'Radio plays')}${grp('stage', 'Stage plays')}`);
  }

  function createPart() {
    const p = ED.play, cast = Object.fromEntries(ED.production.cast.map((c) => [c.part, c]));
    const roles = [...p.roles].sort((a, b) => b.words - a.words);
    const rows = roles.map((r) => {
      const c = cast[r.name];
      const state = c && c.by ? (c.done === c.lines ? `Recorded · ${e(c.by)}` : `${e(c.by)} · ${c.done} of ${c.lines}`) : '';
      return `<li class="log-row part">
        <span class="log-left l6">${shortMin(r.words)}</span>
        <span class="log-body"><span class="l3">${e(r.name)}</span><span class="l5">${r.lines} line${r.lines === 1 ? '' : 's'}${state ? ` · ${state}` : ''}</span></span>
        <span></span>
        ${c && c.by ? '<span></span>' : `<a class="btn btn-way small" href="?s=create-record">Take part</a>`}
      </li>`;
    }).join('');
    const words = p.roles.reduce((a, r) => a + r.words, 0);
    return K.shell('library', `
      <header class="card-head plain"><h1 class="l1">${e(p.title)}</h1><p class="l5">${e(K.author(p.authors[0]))} · ${K.aboutMin(words)} · ${p.roles.length} parts</p></header>
      <label class="name"><span class="l5">Your name</span><input value="" placeholder=""></label>
      <section class="sheet"><ol class="log">${rows}</ol></section>
      <div class="actions"><a class="btn btn-primary" href="?s=production">${I.play}Listen through</a><button class="btn btn-way">Invite</button></div>`);
  }

  function createRecord() {
    const L = ED.play.lines;
    const mine = L.map((l, i) => [l, i]).filter(([l, i]) => l.role === 'VOICE' && i > 0 && L[i - 1].parts[0].say);
    const [line, i] = mine[1] || mine[0];
    const say = (l) => l.parts.map((x) => x.say || '').join(' ');
    const n = L.filter((l) => l.role === 'VOICE').indexOf(line) + 1;
    return `<div class="prompter">
      <div class="np-top"><a class="icon-btn" href="?s=create-part" aria-label="Close">${I.down}</a><span class="l3">VOICE</span><span class="l5">${n} of 7</span></div>
      <p class="cue"><span class="l5">${e(L[i - 1].role)}</span>${e(say(L[i - 1]))}</p>
      <p class="mine">${e(say(line))}</p>
      <p class="cue next"><span class="l5">${e(L[i + 1].role)}</span>${e(say(L[i + 1]))}</p>
      <div class="rec-row">
        <button class="icon-btn" aria-label="Previous line">${I.back}</button>
        <button class="rec" aria-label="Start recording">${I.mic}</button>
        <a class="btn btn-ink-outline" href="?s=production">Keep</a>
      </div>
    </div>`;
  }

  function production() {
    const p = ED.play, pr = ED.production;
    const cast = pr.cast.filter((c) => c.by);
    return K.shell('library', `
      <article class="listing">
        <p class="l5 kicker">${K.fmtDate(pr.recorded[0], 'md')}–${K.fmtDate(pr.recorded[1], 'medium').replace('October ', '')}</p>
        <h1 class="date-big">${e(p.title)}</h1>
        <p class="l5">${e(K.author(p.authors[0]))} · ${cast.length} parts recorded by ${new Set(cast.map((c) => c.by)).size}</p>
        <div class="actions"><a class="btn btn-primary" href="?s=now-playing">${I.play}Listen through</a><button class="btn btn-way">Listen together</button><button class="icon-btn" aria-label="Share">${I.share}</button></div>
        <section class="sheet"><h2 class="l2">Cast</h2>
          <ol class="log">${cast.map((c) => `<li class="log-row part"><span class="log-left"></span><span class="log-body"><span class="l3">${e(c.part)}</span><span class="l5">${e(c.by)} · ${c.done} lines</span></span><span></span><span></span></li>`).join('')}</ol>
        </section>
        <p class="l5 rights">Script: <a href="${e(p.source.url)}">${e(p.source.name)}</a>, which says “${e(p.rights.evidence[0].claim)}” · <a href="#">On archive.org</a></p>
      </article>`);
  }

  const R = {
    home, browse, 'series-rich': seriesRich, 'series-sparse': seriesSparse,
    'episode-rich': () => episode(ED.suspenseRich, 'Suspense', ED.sameNight, (r) => /suspense/i.test(r.seriesName)),
    'episode-bare': () => episode(ED.bare, ED.bareSeries.name, ED.sameNightBare, (r) => r.id === ED.bare.id || r.title === ED.bare.title),
    'now-playing': nowPlaying, 'create-pick': createPick, 'create-part': createPart, 'create-record': createRecord, production,
  };
  K.boot((s) => (R[s] || home)());
})();
