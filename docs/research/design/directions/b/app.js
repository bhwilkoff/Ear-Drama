/* Direction B, The Company: find by who. Every face is a served portrait
   (Decision 069); every heading names a data rule or a real title. */
(function () {
  'use strict';
  const K = window.EDK;
  const ED = K.ED;
  const esc = K.esc;
  const n = (x) => Number(x).toLocaleString('en-US');

  // D1a names "Bud Collyer" a duplicate of "Clayton 'Bud' Collyer": keep the first.
  const voices = (() => {
    const seen = new Set(); const out = [];
    for (const p of ED.faces) {
      const k = p.art && p.art.url;
      if (seen.has(k)) continue;
      seen.add(k); out.push(p);
    }
    return out;
  })();

  const card = (s, big = false) => `<div class="b-card${big ? ' big' : ''}" data-genre="${esc(s.genre || '')}">
      <span class="b-card-name">${esc(s.name)}</span>
      <span class="b-card-meta">${esc([K.genreName(s.genre), s.core ? K.coreYears(s.core) : ''].filter(Boolean).join(' · '))}</span>
    </div>`;

  const face = (p, size, href = '#') => `<a class="b-face" href="${href}">
      ${K.faceCrop(p.art, size, 'round') || K.tile(p.name, null, '', size, 'round')}
      <span class="b-face-name">${esc(p.name)}</span>
      ${p.episodes ? `<span class="b-face-n l6">${n(p.episodes)}</span>` : ''}
    </a>`;

  const playBtn = (len, href = '?s=now-playing') => `<a class="btn btn-primary" href="${href}">${K.I.play}Play${len ? ` · ${K.mins(len)}` : ''}</a>`;
  const rights = `<p class="l5 b-rights">${esc(ED.rightsLines.unclaimed)}</p>`;
  const mini = `<span class="ed-crop-wrap">${K.faceCrop(ED.suspenseRich.credits[0].art, 40)}</span>
    <span class="b-mini-txt"><span class="l3">The Black Curtain</span><span class="l5">Suspense</span></span>
    <span class="icon-btn icon-btn-primary b-mini-play">${K.I.pause}</span>`;

  /* ---------- Home ---------- */
  function home() {
    const shows = ED.popular.filter((s) => s.art).slice(0, 12);
    return K.shell('home', `
      <h1 class="l1 b-h1">Home</h1>
      <section class="b-sec">
        <h2 class="l2">Most heard</h2>
        <div class="b-wall">${voices.slice(0, 20).map((p) => face(p, 76)).join('')}</div>
        <a class="b-more" href="?s=browse">All voices</a>
      </section>
      <section class="b-sec">
        <h2 class="l2">Most downloaded</h2>
        <ul class="b-shows-small">${shows.map((s) => `<li><a href="?s=series-rich">${K.tile(s.name, s.art, s.genre, 56)}
          <span><span class="l3">${esc(s.name)}</span><span class="l5">${esc(s.star)} · ${n(s.episodes)} episodes</span></span></a></li>`).join('')}</ul>
      </section>`, { player: mini });
  }

  /* ---------- Browse ---------- */
  function browse() {
    const t = ED.tiers;
    const grid = ED.popular.map((s) => `<li><a href="?s=series-rich" class="b-show">
        ${s.art ? `<span class="b-show-art">${K.print(s.art, 400, 320)}</span>` : card(s)}
        ${s.art ? `<span class="l3">${esc(s.name)}</span>` : ''}
        <span class="l5">${esc((s.art ? [s.star, K.coreYears(s.core), `${n(s.episodes)} episodes`] : [`${n(s.episodes)} episodes`]).filter(Boolean).join(' · '))}</span>
      </a></li>`).join('');
    return K.shell('browse', `
      <h1 class="l1 b-h1">Browse</h1>
      <div class="b-seg" role="tablist"><a role="tab" href="#">Voices</a><a role="tab" aria-selected="true" class="on" href="?s=browse">Shows</a></div>
      <p class="b-count"><span class="l3">${n(t.shows)} shows</span> <a href="?s=series-sparse" class="l5">${n(t.singles)} single recordings</a></p>
      <ul class="b-grid">${grid}</ul>`);
  }

  /* ---------- Series ---------- */
  const seriesHead = (s, facts) => `<header class="b-head" data-genre="${esc(s.genre || '')}">
      <h1 class="b-head-name">${esc(s.name)}</h1>
      <p class="l5">${facts.filter(Boolean).map(esc).join(' · ')}</p>
    </header>
    <div class="b-actions"><a class="btn btn-way" href="#">Follow</a></div>`;
  const topbar = (href, label) => `<div class="b-top"><a class="b-back" href="${href}">${K.I.back}${esc(label)}</a><a class="icon-btn" href="#" aria-label="Share">${K.I.share}</a></div>`;
  function seriesRich() {
    const s = ED.suspense;
    const count = new Map();
    for (const e of s.season) for (const f of e.faces || []) {
      const c = count.get(f.name) || { name: f.name, art: f.art, episodes: 0 };
      c.episodes++; count.set(f.name, c);
    }
    const heard = [...count.values()].sort((a, b) => b.episodes - a.episodes).slice(0, 6);
    const regular = new Set(heard.filter((p) => p.episodes >= s.season.length / 4).map((p) => p.name));
    const rows = s.season.map((e) => {
      const f = (e.faces || []).find((x) => !regular.has(x.name));
      return `<li><a href="?s=episode-rich" class="b-ep">
        <span class="l6 b-ep-date">${esc(e.date)}</span>
        <span class="b-ep-title">${esc(e.title || `No. ${e.num}`)}</span>
        <span class="b-ep-guest">${f ? `${K.faceCrop(f.art, 32, 'round') || ''}<span class="l5">${esc(f.name)}</span>` : ''}</span>
        <span class="l5 b-ep-len">${K.mins(e.length)}</span>
      </a></li>`;
    }).join('');
    return K.shell('browse', `
      ${topbar('?s=browse', 'Browse')}
      ${seriesHead(s, [K.genreName(s.genre), s.networks, K.coreYears(s.core), `${n(s.episodes)} episodes`])}
      <section class="b-sec">
        <h2 class="l2">Heard most · 1943–44</h2>
        <div class="b-wall b-wall-row">${heard.map((p) => face(p, 64)).join('')}</div>
      </section>
      <section class="b-sec">
        <div class="b-scope">${s.seasons.slice(2, 8).map((x) => `<a href="#" class="${x === '1943-44' ? 'on' : ''}">${x}</a>`).join('')}<a href="#">All seasons</a></div>
        <ol class="b-eps">${rows}</ol>
      </section>`, { player: mini });
  }

  function seriesSparse() {
    const s = ED.sparse;
    const rows = s.episodes.map((e) => `<li><a href="?s=episode-bare" class="b-ep b-ep-sparse">
        <span class="l6 b-ep-date">No. ${esc(e.num)}</span>
        <span class="b-ep-title">${esc(e.title || `No. ${e.num}`)}</span>
        <span class="l5 b-ep-len">${K.mins(e.length)}</span>
        <span class="play-dot">${K.I.play}</span>
      </a></li>`).join('');
    return K.shell('browse', `
      ${topbar('?s=browse', 'Browse')}
      ${seriesHead(s, [K.genreName(s.genre), s.networks, `${s.episodes.length} episodes`])}
      <section class="b-sec"><ol class="b-eps">${rows}</ol></section>`);
  }

  /* ---------- Episode ---------- */
  function creditsBlock(credits) {
    const g = K.creditGroups(credits);
    return Object.entries(g).filter(([, v]) => v.length).map(([k, v]) => `<h3 class="l3 b-cr-h">${k}</h3>
      <ul class="b-cr">${v.map((c) => `<li>${c.art ? K.faceCrop(c.art, 32, 'round') : '<span class="b-cr-slot"></span>'}
        <a href="#">${esc(c.name)}</a><span class="l5">${esc(c.character ? `as ${c.character}` : c.roles.filter((r) => r !== 'cast').join(', '))}</span></li>`).join('')}</ul>`).join('');
  }

  function episodeRich() {
    const e = ED.suspenseRich;
    const faces = K.facesOf(e.credits, 3);
    return K.shell('browse', `
      ${topbar('?s=series-rich', 'Suspense')}
      <div class="b-detail">
        <div class="b-detail-main">
          <div class="b-onair">${faces.map((c) => `<figure><a href="#">${K.print(c.art, 150, 104)}</a><figcaption class="l5">${esc(c.name)}</figcaption></figure>`).join('')}</div>
          <a class="l3" href="?s=series-rich">Suspense</a>
          <h1 class="l1 b-ep-h1">${esc(e.title)}</h1>
          <p class="b-line">${K.eventLine(e).map(esc).join(' · ')}</p>
          <div class="b-actions">${playBtn(e.length)}<a class="btn btn-way" href="#">${K.I.queue}Add to queue</a></div>
        </div>
        <div class="b-detail-side">
          <details class="b-disc"><summary class="l3">Cast and credits <span class="l5">${e.credits.length}</span></summary>${creditsBlock(e.credits)}</details>
          <details class="b-disc"><summary class="l3">Copies <span class="l5">${e.recordings.length}</span></summary>
            <ul class="b-copies">${e.recordings.map((r) => `<li class="l5">${K.mins(r.length)} · ${esc(r.format)} · <a href="#">Source</a></li>`).join('')}</ul></details>
          ${rights}
        </div>
      </div>`);
  }

  function episodeBare() {
    const e = ED.bare;
    const s = ED.bareSeries;
    return K.shell('browse', `
      ${topbar('#', s.name)}
      <div class="b-detail">
        <div class="b-detail-main">
          <div class="b-bare-head">${card({ name: s.name, genre: s.genre, core: [1945, 1945] }, true)}</div>
          <a class="l3" href="#">${esc(s.name)}</a>
          <h1 class="l1 b-ep-h1">${esc(e.title)}</h1>
          <p class="b-line">${K.eventLine(e).map(esc).join(' · ')}</p>
          <div class="b-actions">${playBtn(e.length)}<a class="btn btn-way" href="#">${K.I.queue}Add to queue</a></div>
        </div>
        <div class="b-detail-side">${rights}</div>
      </div>`);
  }

  /* ---------- Now Playing ---------- */
  function nowPlaying() {
    const e = ED.suspenseRich;
    const star = e.credits[0];
    const faces = K.facesOf(e.credits, 6);
    return `<div class="b-np">
      <div class="b-np-top"><a href="?s=episode-rich" class="icon-btn" aria-label="Close">${K.I.down}</a></div>
      <div class="b-np-body">
        <div class="b-np-art"><figure>${K.print(star.art, 300, 300)}<figcaption class="l5">${esc(star.name)}</figcaption></figure></div>
        <div class="b-np-ctl">
          <a class="l3" href="?s=series-rich">Suspense</a>
          <h1 class="l1">${esc(e.title)}</h1>
          <p class="b-line">${K.eventLine(e).map(esc).join(' · ')}</p>
          <div class="b-scrub"><span style="width:38%"></span></div>
          <div class="b-scrub-t l6"><span>11:24</span><span>−18:26</span></div>
          <div class="b-transport"><button class="icon-btn" aria-label="Back 15 seconds">${K.I.r15}</button>
            <button class="b-np-play" aria-label="Pause">${K.I.pause}</button>
            <button class="icon-btn" aria-label="Forward 30 seconds">${K.I.f30}</button></div>
          <div class="b-opts"><button class="l5">1×</button><button aria-label="Sleep timer">${K.I.moon}</button><button aria-label="More">${K.I.more}</button></div>
        </div>
      </div>
      <section class="b-sec b-np-who"><h2 class="l2">On the air</h2>
        <div class="b-wall b-wall-row">${faces.map((p) => face(p, 64)).join('')}</div></section>
    </div>`;
  }

  /* ---------- Create ---------- */
  function createPick() {
    const plays = [...ED.plays].sort((a, b) => (a.kind === 'radio' ? 0 : 1) - (b.kind === 'radio' ? 0 : 1) || a.words - b.words);
    return K.shell('library', `
      <h1 class="l1 b-h1">Start an ear drama</h1>
      <ul class="b-plays">${plays.map((p) => `<li><a href="?s=create-part">
        ${K.tile(p.title, null, '', 56)}
        <span><span class="l3">${esc(p.title)}</span>
        <span class="l5">${esc([K.author(p.authors[0]), `${p.parts} parts`, K.aboutMin(p.words)].filter(Boolean).join(' · '))}</span></span>
        <span class="b-chev">${K.I.chev}</span></a></li>`).join('')}</ul>`);
  }

  // Fixture cast from D1c (Pat, Sam, Ada): not real people.
  const castOf = (part) => ED.production.cast.find((c) => c.part === part);
  const avatar = (name, size = 36) => `<span class="b-av" style="width:${size}px;height:${size}px">${esc(name.charAt(0))}</span>`;

  function createPart() {
    const p = ED.play;
    const roles = [...p.roles].sort((a, b) => b.words - a.words);
    return K.shell('library', `
      <a class="b-back" href="?s=create-pick">${K.I.back}Plays</a>
      <h1 class="l1">${esc(p.title)}</h1>
      <p class="l5">${esc(K.author(p.authors[0]))} · ${roles.length} parts · ${K.aboutMin(roles.reduce((a, r) => a + r.words, 0))}</p>
      <label class="b-name"><span class="l5">Your name</span><input value="" placeholder="Name in the credits"></label>
      <ul class="b-parts">${roles.map((r) => {
        const c = castOf(r.part || r.name);
        const by = c && c.by;
        return `<li class="b-part${by ? ' taken' : ''}">
          <span class="b-part-name">${esc(r.name)}</span>
          <span class="l5">${K.aboutMin(r.words)} · ${r.lines} line${r.lines === 1 ? '' : 's'}</span>
          ${by ? `<span class="b-part-by">${avatar(by, 28)}<span class="l5">${esc(by)}${c.done < c.lines ? ` · ${c.done} of ${c.lines}` : ''}</span></span>`
               : `<a class="btn btn-way b-take" href="?s=create-record">Take part</a>`}
        </li>`;
      }).join('')}</ul>`);
  }

  function createRecord() {
    const L = ED.play.lines.filter((l) => l.parts && l.parts[0] && l.parts[0].say && l.parts[0].say.trim());
    let i = L.findIndex((l, j) => l.role === 'VOICE' && j > 0 && castOf(L[j - 1].role) && castOf(L[j - 1].role).by);
    if (i < 0) i = L.findIndex((l) => l.role === 'VOICE');
    const cue = L[i - 1], mine = L[i], next = L[i + 1];
    const opp = castOf(cue.role);
    const mineCount = ED.play.roles.find((r) => r.name === 'VOICE').lines;
    return `<div class="b-rec">
      <div class="b-rec-top"><a class="icon-btn" href="?s=create-part" aria-label="Close">${K.I.down}</a>
        <span class="l3">VOICE</span><span class="l5">1 of ${mineCount}</span></div>
      <p class="b-with l5">With ${ED.production.cast.filter((c) => c.by).map((c) => c.by).filter((v, i, a) => a.indexOf(v) === i).map((b) => `${avatar(b, 24)} ${esc(b)}`).join(' ')}</p>
      <div class="b-prompter">
        <p class="b-cue"><span class="l5">${esc(cue.role)}${opp && opp.by ? ` · ${esc(opp.by)}` : ''}</span>${esc(cue.parts[0].say)}</p>
        <p class="b-mine"><span class="l5">VOICE · You</span>${esc(mine.parts[0].say)}</p>
        ${next ? `<p class="b-cue"><span class="l5">${esc(next.role)}</span>${esc(next.parts[0].say)}</p>` : ''}
      </div>
      <div class="b-rec-ctl">
        <button class="icon-btn" aria-label="Previous line">${K.I.back}</button>
        <button class="b-rec-btn" aria-label="Start recording">${K.I.mic}</button>
        <a class="btn btn-ink-outline" href="?s=production">Keep</a>
      </div>
    </div>`;
  }

  /* ---------- Production ---------- */
  function production() {
    const p = ED.play, pr = ED.production;
    const ev = p.rights.evidence[0];
    const cast = pr.cast.filter((c) => c.by && c.done === c.lines);
    return K.shell('library', `
      <a class="b-back" href="#">${K.I.back}Library</a>
      <header class="b-bill">
        <p class="l5">Ear drama</p>
        <h1 class="b-bill-title">${esc(p.title)}</h1>
        <p class="l3">${esc(K.author(p.authors[0]))}</p>
        <p class="l5">Recorded ${K.fmtDate(pr.recorded[0], 'md')}–${K.fmtDate(pr.recorded[1], 'md').split(' ')[1]}, 2026</p>
        <div class="b-actions b-bill-act"><a class="btn btn-primary" href="#">${K.I.play}Listen through</a><a class="btn btn-way" href="#">Listen together</a><a class="icon-btn" href="#" aria-label="Share">${K.I.share}</a></div>
      </header>
      <section class="b-sec b-bill-cast"><h2 class="l2">Cast</h2>
        <ul>${cast.map((c) => `<li><span class="b-part-name">${esc(c.part)}</span><span class="b-dots"></span><span class="b-bill-by">${avatar(c.by, 28)}${esc(c.by)}</span></li>`).join('')}</ul></section>
      <section class="b-sec l5 b-source">Script: <a href="${esc(p.source.url)}">${esc(p.source.name)}</a>. ${esc(p.source.name)}'s claim: <a href="${esc(ev.src)}">${esc(ev.claim)}</a></section>`);
  }

  const R = { home, browse, 'series-rich': seriesRich, 'series-sparse': seriesSparse, 'episode-rich': episodeRich,
    'episode-bare': episodeBare, 'now-playing': nowPlaying, 'create-pick': createPick, 'create-part': createPart,
    'create-record': createRecord, production };
  K.boot((s) => (R[s] || home)());
  // The screenshot harness grows the iframe after load; lazy images below 812 px would never start.
  document.querySelectorAll("img[loading=lazy]").forEach((im) => { im.loading = "eager"; });
})();
