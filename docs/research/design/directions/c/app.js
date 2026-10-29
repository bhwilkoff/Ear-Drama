/* Direction C, The Sleeve: one cover per screen, then the item's story in
   chapters made only of data. Every word is a real title, a datum, or a label. */
(function () {
  'use strict';
  const K = window.EDK;
  const { ED, esc, fmtDate, mins, I } = K;
  const n = (x) => x.toLocaleString('en-US');

  /* ---- pieces ---- */
  // The typographic card as a cover: the name set large on the genre hue.
  function card(name, genre, facts = [], cls = '', tag = 'span') {
    return `<div class="c-card ${cls}" data-genre="${esc(genre || '')}">
      <${tag} class="c-card-name">${esc(name)}</${tag}>
      ${facts.length ? `<span class="c-card-facts">${facts.map(esc).join(' · ')}</span>` : ''}
    </div>`;
  }
  const chapter = (title, body, cls = '') =>
    `<section class="c-ch ${cls}"><h2 class="c-ch-h">${esc(title)}</h2>${body}</section>`;
  const playBtn = (sec, href = '?s=now-playing') =>
    `<a class="btn btn-primary" href="${href}">${I.play}Play${sec ? ` · ${mins(sec)}` : ''}</a>`;
  const peakYear = (hist) => Object.entries(hist).sort((a, b) => b[1] - a[1])[0];
  const yearsOf = (hist) => Object.keys(hist).map(Number).sort((a, b) => a - b);
  const bigStrip = (hist, genre, w) => K.runStrip(hist, { from: 1930, to: 1962, w, h: 64, genre });
  const stripAxis = () => `<div class="c-axis l6"><span>1930</span><span>1940</span><span>1950</span><span>1962</span></div>`;
  const rights = () => `<p class="l5 c-rights">${esc(ED.rightsLines.unclaimed)}</p>`;
  const back = (href, label) => `<a class="c-back" href="${href}">${I.back}<span>${esc(label)}</span></a>`;
  const mini = () => `${K.faceCrop(ED.suspenseRich.credits[0].art, 40) || ''}<span class="c-mini-t"><span class="l3">The Black Curtain</span><span class="l5">Suspense</span></span><span class="icon-btn icon-btn-primary">${I.pause}</span>`;

  // A track listing: number or date, title, length, a play dot.
  function tracks(rows, { faces = false, href = "?s=episode-rich" } = {}) {
    // A guest is a face heard on under a quarter of the listed rows; regulars are not repeated.
    const heard = {};
    for (const e of rows) for (const f of e.faces || []) heard[f.name] = (heard[f.name] || 0) + 1;
    rows = rows.map((e) => ({ ...e, faces: (e.faces || []).filter((f) => heard[f.name] < rows.length * 0.25) }));
    return `<ol class="c-tracks">${rows.map((e, i) => {
      const lead = e.date ? `<span class="l6 c-tk-d">${esc(e.date)}</span>` : `<span class="l6 c-tk-d">No. ${esc(e.num != null ? e.num : i + 1)}</span>`;
      const guest = faces && e.faces && e.faces[0] ? `<span class="c-tk-g">${K.faceCrop(e.faces[0].art, 28, 'round') || ''}<span class="l5">${esc(e.faces[0].name)}</span></span>` : '';
      return `<li><a href="${href}" class="c-tk">${lead}<span class="c-tk-t"><span>${esc(e.title)}</span>${guest}</span><span class="l5 c-tk-l">${mins(e.length)}</span><span class="play-dot">${I.play}</span></a></li>`;
    }).join('')}</ol>`;
  }

  /* ---- Home: a few features, each a cover ---- */
  function home() {
    const night = ED.evening.years.find((y) => y.evening === '1939-10-29');
    const listing = night.slots.filter((s) => s.length_min > 0);
    // Merge runs of gaps into one row (R9 draws the gap, once).
    const rows = [];
    for (const s of listing) {
      const last = rows[rows.length - 1];
      if (!s.episode && last && !last.episode) { last.et_end = s.et_end; continue; }
      rows.push({ ...s });
    }
    const log = rows.map((s) => s.episode
      ? `<li class="c-log-on"><span class="l6">${K.clock(s.et_start)}</span><a href="?s=episode-rich"><span class="l3">${esc(s.episode.series)}</span><span class="l5">${esc(s.episode.title.replace(/\s*\(OTR\)$/, ''))}</span></a></li>`
      : `<li class="c-log-gap"><span class="l6">${K.clock(s.et_start)}</span><span class="l5">${K.clock(s.et_start)}–${K.clock(s.et_end)} not surviving</span></li>`).join('');

    const s = ED.suspense;
    const conrad = ED.faces.find((p) => p.name === 'William Conrad');
    const leads = ED.popular.filter((x) => x.star === 'William Conrad');
    const play = ED.play;
    const words = play.roles.reduce((a, r) => a + r.words, 0);
    const pk = peakYear(s.hist);

    const f1 = `<article class="c-feat">
      <div class="c-feat-cover">${card('October 29, 1939', 'comedy', [], 'c-card-date', 'h2')}</div>
      <div class="c-feat-body">
        <p class="l5">Sunday · ${esc(night.network)} · ${esc(night.station)} · ET</p>
        <ol class="c-log">${log}</ol>
        <div class="c-acts">${playBtn(listing.find((x) => x.episode).episode.length_s)}<a class="btn btn-way" href="#">${I.stations}Stations</a></div>
      </div></article>`;
    const f2 = `<article class="c-feat">
      <div class="c-feat-cover"><a href="?s=series-rich">${card('Suspense', 'mystery', [], '', 'h2')}</a></div>
      <div class="c-feat-body" data-genre="mystery">
        <p class="l5">${K.coreYears(s.core)} · CBS ·${n(s.episodes)} episodes · most in ${pk[0]}</p>
        <div class="c-stripwrap">${bigStrip(s.hist, 'mystery', 320)}${stripAxis()}</div>
        <div class="c-acts">${playBtn(1800)}<a class="btn btn-way" href="?s=series-rich">Follow</a></div>
      </div></article>`;
    const f3 = `<article class="c-feat">
      <div class="c-feat-cover c-feat-print">${K.print(conrad.art, 300, 340)}<p class="l5">${esc(conrad.name)}</p></div>
      <div class="c-feat-body">
        <h2 class="l2">${esc(conrad.name)}</h2>
        <p class="l5">${n(conrad.episodes)} episodes</p>
        <ul class="c-leads">${leads.map((x) => `<li><a href="?s=series-rich">${K.tile(x.name, x.art, x.genre, 44)}<span><span class="l3">${esc(x.name)}</span><span class="l5">${K.coreYears(x.core)} · ${n(x.episodes)} episodes</span></span></a></li>`).join('')}</ul>
      </div></article>`;
    const f4 = `<article class="c-feat">
      <div class="c-feat-cover"><a href="?s=create-part">${card(play.title, '', [], 'c-card-play', 'h2')}</a></div>
      <div class="c-feat-body">
        <p class="l5">${esc(K.author(play.authors[0]))} ·${play.roles.length} parts · ${K.aboutMin(words)}</p>
        <div class="c-acts"><a class="btn btn-ink-outline" href="?s=create-part">Take part</a></div>
      </div></article>`;
    return K.shell('home', `<h1 class="l1 c-h1">Home</h1><div class="c-feats">${f1}${f2}${f3}${f4}</div>`, { player: mini() });
  }

  /* ---- Browse: a contents page ---- */
  function browse() {
    const by = {};
    for (const c of ED.field) by[c.genre] = (by[c.genre] || 0) + c.shows;
    const order = Object.entries(by).sort((a, b) => b[1] - a[1]);
    const dec = {};
    for (const c of ED.field) dec[c.decade] = (dec[c.decade] || 0) + c.shows;
    const t = ED.tiers;
    const genres = order.map(([g, c]) => `<li data-genre="${g}"><a href="#"><span class="c-g-name">${esc(K.genreName(g))}</span><span class="l6">${c}</span></a></li>`).join('')
      + `<li><a href="#"><span class="c-g-name c-g-none">Unsorted</span><span class="l6">${ED.fieldUnsorted}</span></a></li>`;
    const decades = Object.keys(dec).sort().map((d) => `<li><a href="#"><span class="c-d-name">${d}s</span><span class="l6">${dec[d]}</span></a></li>`).join('');
    const shows = ED.popular.slice(0, 16).map((s) => `<li><a href="?s=${s.key === 'suspense' ? 'series-rich' : 'series-rich'}" data-genre="${esc(s.genre || '')}">
        ${s.art ? K.faceCrop(s.art, 64) || K.tile(s.name, null, s.genre, 64) : K.tile(s.name, null, s.genre, 64)}
        <span class="c-sh-t"><span class="l3">${esc(s.name)}</span><span class="l5">${K.coreYears(s.core)} · ${n(s.episodes)}</span>${K.runStrip(s.hist, { w: 110, h: 12, genre: s.genre })}</span></a></li>`).join('');
    return K.shell('browse', `<h1 class="l1 c-h1">Browse</h1>
      <p class="c-tally"><span class="c-tally-n">${n(t.shows)}</span> shows<span class="muted"> · </span><a href="?s=series-sparse">${n(t.singles)} single recordings</a><span class="muted"> · </span><a href="?s=series-sparse">${n(t.small)} small series</a></p>
      <div class="c-contents">
        ${chapter('Genre', `<ol class="c-genres">${genres}</ol>`)}
        ${chapter('Decade', `<ol class="c-decades">${decades}</ol>`)}
      </div>
      ${chapter('Most downloaded', `<ol class="c-shows">${shows}</ol>`)}`);
  }

  /* ---- Series ---- */
  function seriesRich() {
    const s = ED.suspense;
    const yrs = yearsOf(s.hist);
    const pk = peakYear(s.hist);
    const firstSeason = s.season.filter((e) => e.date);
    const runFacts = `<dl class="c-facts">
      <div><dt class="l5">First dated</dt><dd class="l6">${esc(s.first)}</dd></div>
      <div><dt class="l5">Most in</dt><dd class="l6">${pk[0]} · ${pk[1]}</dd></div>
      <div><dt class="l5">Last dated</dt><dd class="l6">${esc(s.last)}</dd></div>
    </dl>`;
    const season = firstSeason.slice(0, 14);
    return K.shell('browse', `${back('?s=browse', 'Browse')}
      <div class="c-page">
        <div class="c-cover">${card('Suspense', 'mystery', [K.coreYears(s.core), 'CBS', `${n(s.episodes)} episodes`], 'c-card-xl')}
          <div class="c-acts">${playBtn(firstSeason[0].length)}<a class="btn btn-way" href="#">Follow</a><a class="icon-btn" href="#" aria-label="Share">${I.share}</a></div>
          <p class="l5 c-genre-link"><a href="?s=browse">Mystery</a></p>
        </div>
        <div class="c-chapters">
          ${chapter('The run', `<div class="c-stripwrap" data-genre="mystery">${bigStrip(s.hist, 'mystery', 340)}${stripAxis()}</div>${runFacts}`)}
          ${chapter('1943–44', `${tracks(season, { faces: true })}<p class="c-more"><a href="#">All ${s.season.length} in 1943–44</a> · <a href="#">${yrs.length} years</a></p>`)}
        </div>
      </div>`);
  }
  function seriesSparse() {
    const s = ED.sparse;
    return K.shell('browse', `${back('?s=browse', 'Browse')}
      <div class="c-page">
        <div class="c-cover">${card(s.name, s.genre, [s.networks, `${s.episodes.length} episodes`], 'c-card-xl')}
          <div class="c-acts">${playBtn(s.episodes[0].length, '?s=now-playing')}<a class="btn btn-way" href="#">Follow</a><a class="icon-btn" href="#" aria-label="Share">${I.share}</a></div>
          <p class="l5 c-genre-link"><a href="?s=browse">${esc(K.genreName(s.genre))}</a></p>
        </div>
        <div class="c-chapters">
          ${chapter('Undated', tracks(s.episodes, { href: '?s=episode-bare' }))}
        </div>
      </div>`);
  }

  /* ---- Episode ---- */
  function sameNight(list, selfId, selfTitle) {
    const all = list.filter((r) => r.id !== selfId && r.title !== selfTitle);
    const rows = all.filter((r) => r.show !== false);
    const rest = all.length - rows.length;
    return `<ol class="c-night">${rows.map((r) => `<li><a href="?s=episode-rich"><span class="l3">${esc(r.seriesName)}</span><span class="l5">${esc(r.title)}</span></a><span class="l5">${mins(r.length)}</span></li>`).join('')}</ol>${rest ? `<p class="c-more"><a href="#">${rest} single recording${rest > 1 ? 's' : ''}</a></p>` : ''}`;
  }
  function booklet(credits) {
    const g = K.creditGroups(credits);
    return Object.entries(g).filter(([, v]) => v.length).map(([h, v]) => `<div class="c-bk-g"><h3 class="l5">${h}</h3><ul>${v.map((e) =>
      `<li><a href="#">${esc(e.name)}</a><span class="l5">${e.character ? `as ${esc(e.character)}` : esc(e.roles.join(', '))}</span></li>`).join('')}</ul></div>`).join('');
  }
  function episodeRich() {
    const e = ED.suspenseRich;
    const face = e.credits.find((c) => c.person === e.star) || e.credits[0];
    const faces = K.facesOf(e.credits, 3);
    return K.shell('browse', `${back('?s=series-rich', 'Suspense')}
      <div class="c-page">
        <div class="c-cover">
          <figure class="c-figure">${K.print(face.art, 300, 300)}<figcaption class="l5">${esc(face.name)}</figcaption></figure>
        </div>
        <div class="c-chapters">
          <p class="c-series"><a href="?s=series-rich">Suspense</a></p>
          <h1 class="l1 c-title">${esc(e.title)}</h1>
          <p class="c-event">${K.eventLine(e).map(esc).join(' · ')}</p>
          <div class="c-acts">${playBtn(e.length)}<a class="btn btn-way" href="#">${I.queue}Add to queue</a><a class="icon-btn" href="#" aria-label="Share">${I.share}</a></div>
          ${chapter('On the air', `<ul class="c-faces">${faces.map((c) => `<li><a href="#">${K.faceCrop(c.art, 72, 'round')}<span class="l5">${esc(c.name)}</span></a></li>`).join('')}</ul>`)}
          ${chapter(fmtDate(e.date, 'medium'), sameNight(ED.sameNight, e.id, e.title))}
          <details class="c-det"><summary>Cast and credits</summary>${booklet(e.credits)}</details>
          <details class="c-det"><summary>Automatic transcript</summary><p class="l5"><a href="${esc(e.transcript)}">archive.org</a></p></details>
          <details class="c-det"><summary>${e.recordings.length} copies</summary><ol class="c-copies">${e.recordings.map((r) => `<li><span class="l6">${mins(r.length)}</span><span class="l5">${esc(r.format)}</span><a class="l5" href="#">Source</a></li>`).join('')}</ol></details>
          ${rights()}
        </div>
      </div>`);
  }
  function episodeBare() {
    const e = ED.bare;
    return K.shell('browse', `${back('?s=browse', ED.bareSeries.name)}
      <div class="c-page">
        <div class="c-cover">${card(ED.bareSeries.name, 'news', [fmtDate(e.date, 'year')], 'c-card-xl')}</div>
        <div class="c-chapters">
          <p class="c-series"><a href="#">${esc(ED.bareSeries.name)}</a></p>
          <h1 class="l1 c-title">${esc(e.title)}</h1>
          <p class="c-event">${esc(fmtDate(e.date, 'long'))}</p>
          <div class="c-acts">${playBtn(e.length)}<a class="btn btn-way" href="#">${I.queue}Add to queue</a><a class="icon-btn" href="#" aria-label="Share">${I.share}</a></div>
          ${chapter(fmtDate(e.date, 'medium'), sameNight(ED.sameNightBare, e.id, e.title))}
          ${rights()}
        </div>
      </div>`);
  }

  /* ---- Now Playing ---- */
  function nowPlaying() {
    const e = ED.suspenseRich;
    const face = e.credits[0];
    const faces = K.facesOf(e.credits, 3);
    return `<div class="c-np">
      <div class="c-np-top"><a class="icon-btn" href="?s=episode-rich" aria-label="Close">${I.down}</a></div>
      <div class="c-np-grid">
        <div class="c-np-art">${K.print(face.art, 360, 340)}<p class="l5">${esc(face.name)}</p></div>
        <div class="c-np-ctl">
          <p class="c-series"><a href="?s=series-rich">Suspense</a></p>
          <h1 class="l1">${esc(e.title)}</h1>
          <p class="c-event">${K.eventLine(e).map(esc).join(' · ')}</p>
          <div class="c-scrub"><span class="c-scrub-bar"><span style="width:38%"></span></span><span class="l6">11:21</span><span class="l6">−18:29</span></div>
          <div class="c-transport"><button class="icon-btn" aria-label="Back 15 seconds">${I.r15}</button><button class="c-big icon-btn-primary" aria-label="Pause">${I.pause}</button><button class="icon-btn" aria-label="Forward 30 seconds">${I.f30}</button></div>
          <div class="c-opts"><button class="l5">1×</button><button aria-label="Sleep timer">${I.moon}<span class="l5">Sleep</span></button><button aria-label="More">${I.more}</button></div>
        </div>
      </div>
      <div class="c-np-page2">
        ${chapter('On the air', `<ul class="c-faces">${faces.map((c) => `<li>${K.faceCrop(c.art, 64, 'round')}<span class="l5">${esc(c.name)}</span></li>`).join('')}</ul>`)}
        <details class="c-det" open><summary>Cast and credits</summary>${booklet(e.credits)}</details>
      </div>
    </div>`;
  }

  /* ---- Create ---- */
  function createPick() {
    const plays = [...ED.plays].sort((a, b) => (a.kind === b.kind ? a.words - b.words : a.kind === 'radio' ? -1 : 1));
    const items = plays.map((p) => `<li><a href="?s=create-part">${card(p.title, '', [p.authors[0] ? K.author(p.authors[0]) : ''].filter(Boolean), 'c-card-sm')}
      <span class="l5">${p.parts} parts · ${K.aboutMin(p.words)}</span></a></li>`).join('');
    return K.shell('browse', `${back('?s=browse', 'Browse')}<h1 class="l1 c-h1">Plays</h1><ol class="c-plays">${items}</ol>`);
  }
  function createPart() {
    const p = ED.play;
    const by = Object.fromEntries(ED.production.cast.map((c) => [c.part, c]));
    const page = p.lines.filter((l) => l.parts[0].say).slice(0, 6).map((l) => `<p><span class="c-spk">${esc(l.role)}</span> ${esc(l.parts[0].say)}</p>`).join('');
    const parts = [...p.roles].sort((a, b) => b.words - a.words).map((r) => {
      const c = by[r.name];
      const who = c && c.by ? `<span class="l5">${esc(c.by)}${c.done < c.lines ? ` · ${c.done} of ${c.lines}` : ''}</span>` : '';
      const act = c && c.by ? (c.done >= c.lines ? `<span class="c-done">${I.check}</span>` : '') : `<a class="btn btn-ink-outline c-take" href="?s=create-record">Take part</a>`;
      return `<li><span class="c-part"><span class="l3">${esc(r.name)}</span><span class="l5">${r.lines} lines · ${K.aboutMin(r.words)}</span>${who}</span>${act}</li>`;
    }).join('');
    const words = p.roles.reduce((a, r) => a + r.words, 0);
    return K.shell('library', `${back('?s=create-pick', 'Plays')}
      <div class="c-page">
        <div class="c-cover">${card(p.title, '', [K.author(p.authors[0]), `${p.roles.length} parts`, K.aboutMin(words)], 'c-card-xl')}
          <div class="c-script">${page}</div>
        </div>
        <div class="c-chapters">
          <label class="c-name"><span class="l5">Your name</span><input value="" placeholder="Name"></label>
          ${chapter('Parts', `<ol class="c-cast">${parts}</ol>`)}
          <div class="c-acts"><a class="btn btn-primary" href="?s=production">${I.play}Listen through</a><a class="btn btn-way" href="#">Invite</a></div>
          <p class="l5 c-rights">${esc(p.rights.evidence[0].claim)} <a href="${esc(p.rights.evidence[0].src)}">${esc(p.source.name)}</a></p>
        </div>
      </div>`);
  }
  function createRecord() {
    const L = ED.play.lines;
    const i = L.findIndex((l) => l.role === 'VOICE');
    const said = (l) => l.parts[0] && l.parts[0].say;
    const cue = L.slice(0, i).reverse().find(said), mine = L[i], next = L.slice(i + 1).find(said);
    const voiceLines = ED.play.roles.find((r) => r.name === 'VOICE').lines;
    return `<div class="c-rec">
      <div class="c-np-top"><a class="icon-btn" href="?s=create-part" aria-label="Close">${I.down}</a><span class="l3">VOICE</span><span class="l5">${voiceLines} lines to go</span></div>
      <div class="c-prompt">
        <p class="c-cue"><span class="c-spk">${esc(cue.role)}</span> ${esc(cue.parts[0].say || '')}</p>
        <p class="c-mine">${esc(mine.parts[0].say)}</p>
        <p class="c-cue"><span class="c-spk">${esc(next.role)}</span> ${esc(next.parts[0].say)}</p>
      </div>
      <div class="c-rec-ctl">
        <button class="icon-btn" aria-label="Previous line">${I.back}</button>
        <button class="c-recbtn" aria-label="Start recording">${I.mic}</button>
        <button class="btn btn-ink-outline">Keep</button>
      </div>
    </div>`;
  }

  /* ---- The shared production page ---- */
  function production() {
    const p = ED.play, pr = ED.production;
    const done = pr.cast.filter((c) => c.by && c.done >= c.lines);
    const names = [...new Set(done.map((c) => c.by))];
    const list = done.map((c, i) => `<li><span class="l6">${i + 1}</span><span class="l3">${esc(c.part)}</span><span>${esc(c.by)}</span><span class="l5">${c.lines} lines</span></li>`).join('');
    return K.shell('library', `
      <div class="c-page">
        <div class="c-cover"><div class="c-poster">
          <span class="c-poster-t">${esc(p.title)}</span>
          <span class="c-poster-a">${esc(K.author(p.authors[0]))}</span>
          <span class="c-poster-c">${names.map(esc).join(' · ')}</span>
        </div></div>
        <div class="c-chapters">
          <h1 class="l1 c-title">${esc(p.title)}</h1>
          <p class="c-event">Recorded ${esc(fmtDate(pr.recorded[0], 'md'))}–${K.fmtDate(pr.recorded[1], 'medium').replace(/^\w+ /, '')}</p>
          <div class="c-acts"><a class="btn btn-primary" href="?s=now-playing">${I.play}Listen through</a><a class="btn btn-way" href="#">Listen together</a><a class="icon-btn" href="#" aria-label="Share">${I.share}</a></div>
          ${chapter('Cast', `<ol class="c-tracklist">${list}</ol>`)}
          ${chapter('Script', `<p class="l5">${esc(K.author(p.authors[0]))} · <a href="${esc(p.source.url)}">${esc(p.source.name)}</a></p><p class="l5">${esc(p.rights.evidence[0].claim)} (<a href="${esc(p.rights.evidence[0].src)}">${esc(p.source.name)}</a>)</p><p class="l5"><a href="#">On archive.org</a></p>`)}
        </div>
      </div>`);
  }

  const R = { home, browse, 'series-rich': seriesRich, 'series-sparse': seriesSparse, 'episode-rich': episodeRich,
    'episode-bare': episodeBare, 'now-playing': nowPlaying, 'create-pick': createPick, 'create-part': createPart,
    'create-record': createRecord, production };
  K.boot((s) => (R[s] || home)());
})();
