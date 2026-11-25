/**
 * Casting an episode by ear (WEB-DESIGN §4.22, PLAYS-DESIGN §13 item 10; Decision 088.3): the automatic
 * transcript in lines, the episode playing in the app's own player, the line being said lit, and a tap
 * on a part for who is saying it. What a tap does is EarCore's; what is kept is OwnScripts'.
 *
 * The page proposes no speaker and keeps no sound. Its one audio element is Player's, held to this
 * episode while the page is open (Player.hold); leaving lets go, and what is playing plays on.
 */
const EarUI = (() => {
  'use strict';
  const O = OwnCore;
  const E = EarCore;
  const SPEED_KEY = 'ed.ear.speed';
  const SITE = 'https://eardrama.org';
  const PLAY = 'M8 5v14l11-7z';
  const PAUSE = 'M7 5h4v14H7zm6 0h4v14h-4z';
  const BACK = 'M12 5V2L7 6l5 4V7a6 6 0 1 1-6 6H4a8 8 0 1 0 8-8z';

  let h = null;
  let kit = null;
  let seq = 0;
  /** The page open now: `{ leave() }`. */
  let page = null;

  const $ = (id) => document.getElementById(id);
  const store = () => OwnScripts.shared();
  const num = new Intl.NumberFormat('en-US');
  const hueAt = (name, parts) => EarCore.hueOf(name, parts);
  const still = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
  function path(d, cls) {
    const ns = 'http://www.w3.org/2000/svg';
    const s = document.createElementNS(ns, 'svg');
    s.setAttribute('viewBox', '0 0 24 24');
    s.setAttribute('aria-hidden', 'true');
    if (cls) s.setAttribute('class', cls);
    const p = document.createElementNS(ns, 'path');
    p.setAttribute('d', d);
    s.append(p);
    return s;
  }
  function clock(s) {
    const t = Math.max(0, Math.floor(s || 0));
    const m = Math.floor(t / 60) % 60, sec = String(t % 60).padStart(2, '0'), hr = Math.floor(t / 3600);
    return hr ? `${hr}:${String(m).padStart(2, '0')}:${sec}` : `${m}:${sec}`;
  }
  const speedWas = () => { try { return Number(localStorage.getItem(SPEED_KEY)) || E.SPEED; } catch { return E.SPEED; } };
  const speedIs = (x) => { try { localStorage.setItem(SPEED_KEY, String(x)); } catch { /* kept for this page only */ } };

  /* ---- The door (§4.5): Record this on an episode with a transcript and no script ---- */

  /** This device's script of an episode, by the id it has now or one it had when the casting began. */
  async function kept(id) {
    const rows = (await store().list()).filter(r => r.episode);
    if (!rows.length) return null;
    const mine = rows.find(r => r.episode === id);
    if (mine) return mine;
    const fwd = await API.forwarding().catch(() => null);
    return (fwd && rows.find(r => fwd.resolve(r.episode) === id)) || null;
  }
  /**
   * Puts Record this in `box` once it is sure to open: the transcript's times were read, or the casting
   * was begun on this device. Nothing otherwise, and nothing is said: 88% of episodes have no transcript.
   */
  async function door(box, d, helpers) {
    if (!d.transcript || !d.recordings.length) return;
    try {
      if (!(await kept(d.id).catch(() => null)) && E.refusalOf(O.fromCues(await API.transcriptCues(d.transcript)))) return;
    } catch { return; }
    if (!box.isConnected) return;
    box.append(helpers.el('span', { class: 'start-drama' }, helpers.el('a', { class: 'btn btn-accent ear-drama-only', href: `?cast=${encodeURIComponent(d.id)}` }, 'Record this')));
    box.hidden = false;
  }

  /* ---- The page ---- */

  /** A state in the page's own bar: on a phone the tab bar is away, so there is always a way out. */
  function state(body, id, box) {
    body.replaceChildren(h.el('div', { class: 'os ec' },
      kit.bar({ out: 'close', outLabel: 'Close', onOut: () => kit.goBack(`?item=${encodeURIComponent(id)}`), titles: h.el('p', { class: 'body-strong rd-title' }, 'Record this'), primary: null }),
      h.el('div', { class: 'ec-state' }, box)));
  }

  async function open(body, my, id) {
    $('own-h').textContent = 'Record this';
    h.setTitle('Record this');
    if (document.documentElement.classList.contains('tv')) { h.navigate(`?item=${encodeURIComponent(id)}`, true); return; }
    state(body, id, h.stateBox('loading'));
    let d, rec, doc, seriesName = null, taken = [], cues = null;
    try {
      d = await API.episodeDetail(id);
      if (!d || !d.recordings.length) throw new API.DataError('missing', id);
      const [row, s] = await Promise.all([kept(d.id), API.seriesPage(d.series).catch(() => null)]);
      seriesName = s ? s.name : d.series;
      rec = row ? await store().get(row.id) : null;
      if (rec && rec.shared) { if (my === seq) h.navigate(`?play=${encodeURIComponent(rec.id)}`, true); return; }
      if (!rec && d.script && (await API.castableScripts().catch(() => [])).some(x => x.id === d.script)) {
        h.navigate(`?play=${encodeURIComponent(d.script)}`, true);
        return;
      }
      if (rec) {
        doc = rec.doc;
        taken = await store().takes(rec.id);
      } else {
        // The episode is in the catalog, so a transcript that is not there did not load.
        cues = await API.transcriptCues(d.transcript).catch(e => { throw e.kind === 'offline' ? e : new API.DataError('error', String(e.message)); });
        doc = O.fromCues(cues);
        if (E.refusalOf(doc)) throw new API.DataError('error', d.transcript);
      }
    } catch (err) {
      if (my !== seq) return;
      console.error(err);
      state(body, id, h.stateBox(h.problem(err), { retry: () => open(body, my, id) }));
      return;
    }
    if (my !== seq) return;
    if (d.id !== id) history.replaceState(history.state, '', `?cast=${encodeURIComponent(d.id)}`);
    draw(body, my, { d, rec, doc, seriesName, taken, cues });
  }

  function draw(body, my, { d, rec, doc, seriesName, taken, cues }) {
    const title = h.shownTitle(d, seriesName);
    h.setTitle(title);
    $('own-h').textContent = title;
    const first = d.recordings[0];
    // The default copy is the one the transcript was made from: a fall to another copy would put every time off, so none is offered.
    const copy = first.url;
    const card = () => ({ id: d.id, title, series: d.series, seriesName, date: d.date, network: d.network || null, alts: [],
                          url: copy, length: first.length || d.length, li: d.li, ltp: d.ltp });

    const S = E.session({ doc, names: rec ? rec.extras || [] : [], takes: taken });
    const P = { rec, nodes: new Map(), drawn: new Map(), hues: new Map(), cur: doc.lines[0].k, lit: -1, place: E.placeOf(rec && rec.ear, doc), sample: null, mine: false, loading: false };
    const follow = ReaderCore.alongFollow();
    const audio = Player.audio;
    /** The player is on this episode's own copy: its clock is this page's. */
    const here = () => !!Player.current && Player.current.id === d.id && Player.current.url === copy;
    const playing = () => here() && !audio.paused && !audio.ended;
    /** The place being cast; a line played on its own is not it. */
    const nowMs = () => (P.sample ? P.sample.back.ms : here() && !P.loading ? Math.round(audio.currentTime * 1000) : P.place);

    /* ---- What stands on the page ---- */

    const titleText = h.el('span', { class: 'body-strong rd-title' }, title);
    const where = h.el('span', { class: 'caption tabular rd-where' });
    const titleBtn = h.el('button', { type: 'button', class: 'os-title-btn', onclick: () => titleSheet() }, titleText, where);
    const undoBtn = h.el('button', { type: 'button', class: 'icon-btn rd-icon', 'aria-label': 'Undo', title: 'Undo', onclick: () => undo() }, kit.svg('undo'));
    const doneBtn = h.el('button', { type: 'button', class: 'btn os-next', onclick: () => finish() }, 'Done');
    const problem = h.el('div', { class: 'os-problem', role: 'alert', hidden: true });
    const note = h.el('p', { class: 'caption ec-note', role: 'status', hidden: true });
    const list = h.el('div', { class: 'ec-list', role: 'list', 'aria-label': 'Lines' });
    const scroller = h.el('div', { class: 'os-scroll' }, h.el('div', { class: 'os-page ec-page' },
      h.el('p', { class: 'caption ec-auto' }, API.transcriptLabel), list));
    const backBtn = h.el('button', { type: 'button', class: 'btn ec-back-line', hidden: true, onclick: () => refollow() }, 'Back to the line');
    const parts = h.el('div', { class: 'ec-parts', role: 'group', 'aria-label': 'Parts' });
    const addBtn = h.el('button', { type: 'button', class: 'os-chip os-plain ec-verb', dataset: { do: 'add' }, onclick: () => newPart() }, kit.svg('plus'), 'Part');
    const outBtn = h.el('button', { type: 'button', class: 'os-chip os-plain ec-verb', dataset: { do: 'out' }, onclick: () => press(() => S.leaveOut(), 'Left out') }, 'Leave out');
    const timeText = h.el('span', { class: 'caption tabular ec-time' });
    const rewind = h.el('button', { type: 'button', class: 'icon-btn', 'aria-label': `Back ${E.BACK_S} seconds`, title: `Back ${E.BACK_S} seconds`, onclick: () => back() }, path(BACK));
    const playBtn = h.el('button', { type: 'button', class: 'icon-btn icon-btn-primary ec-play', 'aria-label': 'Play', onclick: () => toggle() }, path(PLAY, 'i-play'), path(PAUSE, 'i-pause'));
    const speed = h.el('select', { class: 'ec-speed', 'aria-label': 'Speed', onchange: () => setSpeed(Number(speed.value)) },
      Player.SPEEDS.map(x => h.el('option', { value: String(x) }, `${x}×`)));
    const box = h.el('div', { class: 'ec-dock-parts' }, parts, h.el('div', { class: 'ec-verbs' }, addBtn, outBtn));
    const dock = h.el('aside', { class: 'ec-dock', 'aria-label': 'Casting' },
      box,
      h.el('div', { class: 'ec-transport' }, timeText, rewind, playBtn, speed));
    const sheets = h.el('div');
    // A press that leaves the keyboard where it was, so Space goes on meaning play (§4.22 item 5).
    dock.addEventListener('mousedown', (e) => { if (e.target.closest('button')) e.preventDefault(); });
    body.replaceChildren(h.el('div', { class: 'os ec' },
      kit.bar({ out: 'close', outLabel: 'Close', onOut: () => kit.goBack(`?item=${encodeURIComponent(d.id)}`), titles: titleBtn, tools: [undoBtn], primary: doneBtn }),
      problem, note, h.el('div', { class: 'ec-body' }, h.el('div', { class: 'ec-lines' }, scroller, backBtn), dock), sheets));

    /* ---- What is kept: begun at the first change, never by looking ---- */

    function record() {
      if (!P.rec) {
        P.rec = store().begin({ title, doc: S.doc, episode: { id: d.id, url: SITE + API.shareLink('episode', d.id) }, ear: { sig: E.signature(cues), copy, place: 0 } });
      }
      P.rec.doc = S.doc;
      P.rec.extras = S.names.slice();
      P.rec.ear = { ...P.rec.ear, place: Math.round(nowMs()) };
      return P.rec;
    }
    let gone = false;
    async function write() {
      if (gone) return true;
      try {
        await store().keep(record());
        if (saying === 'keep') say(null);
        if (navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(() => {});
        return true;
      } catch (err) {
        if (my !== seq) { console.error(err); return false; }
        say(kit.notKept(err), () => write());
        return false;
      }
    }
    const save = kit.later(write, 350);
    let saying = null;
    /** A failure of the page, with its way on; null takes it away. `of` is what failed: keeping, or the audio. */
    function say(words, again = null, of = 'keep') {
      saying = words ? of : null;
      problem.hidden = !words;
      problem.replaceChildren(...(words ? [h.el('span', { class: 'body' }, words), again ? h.el('button', { type: 'button', class: 'btn', onclick: again }, 'Try again') : null].filter(Boolean) : []));
    }

    /* ---- Drawing: only what changed ---- */

    function paintLines() {
      const keep = new Set();
      let prev = null;
      for (const r of E.rows(S.doc)) {
        keep.add(r.k);
        let n = P.nodes.get(r.k);
        if (!n) {
          n = h.el('div', { role: 'listitem', class: 'ec-item', dataset: { k: String(r.k) } });
          P.nodes.set(r.k, n);
          if (prev) prev.after(n); else list.prepend(n);
        }
        prev = n;
        const out = r.who === O.OUT;
        const name = typeof r.who === 'string' ? r.who : null;
        const hue = name ? P.hues.get(name) || 'none' : '';
        const key = [out ? '-' : name || '', r.named, hue, r.kind, r.text].join('\u0001');
        if (P.drawn.get(r.k) === key) continue;
        P.drawn.set(r.k, key);
        const label = out ? 'Left out' : name;
        n.className = `ec-item${name || out || r.kind !== 'open' ? '' : ' ec-uncast'}${out ? ' ec-out' : ''}${r.kind === 'direction' || r.kind === 'sound' ? ' ec-aside' : ''}`;
        n.replaceChildren(h.el('div', { class: 'ec-line', role: 'button', tabindex: r.k === P.cur ? '0' : '-1', dataset: { open: String(r.k), ...(hue ? { hue } : {}) } },
          r.named ? h.el('span', { class: 'rd-name' }, label) : label ? h.el('span', { class: 'sr-only' }, label) : null,
          h.el('span', { class: 'ec-words' }, r.text)));
      }
      for (const [k, n] of P.nodes) if (!keep.has(k)) { n.remove(); P.nodes.delete(k); P.drawn.delete(k); }
      if (!keep.has(P.cur)) setCur(S.doc.lines[0].k);
      P.lit = -1;
    }
    function paintParts() {
      const ps = S.parts();
      P.hues = new Map(ps.map(p => [p.name, hueAt(p.name, ps)]));
      const who = S.lit ? S.who(S.lit) : null;
      box.classList.toggle('ec-many', ps.length > 4);
      const had = parts.contains(document.activeElement) ? document.activeElement.dataset : null;
      parts.replaceChildren(...ps.map((p, i) => h.el('div', { class: 'ec-part', dataset: { hue: hueAt(p.name, ps) } },
        h.el('button', { type: 'button', class: 'ec-who', dataset: { part: p.name }, 'aria-pressed': String(p.name === who),
          'aria-label': p.name, 'aria-keyshortcuts': i < 9 ? String(i + 1) : null, onclick: () => give(p.name) },
          h.el('span', { class: 'ec-num caption tabular', 'aria-hidden': 'true' }, i < 9 ? String(i + 1) : ''),
          h.el('span', { class: 'pl-face', dataset: { hue: hueAt(p.name, ps) }, 'aria-hidden': 'true' }, p.name.charAt(0)),
          h.el('i', { class: 'os-dot', 'aria-hidden': 'true' }),
          h.el('span', { class: 'ec-name' }, h.el('span', { class: 'body-strong' }, p.name),
            h.el('span', { class: 'caption tabular ec-n' }, p.lines === 1 ? '1 line' : `${num.format(p.lines)} lines`))),
        h.el('button', { type: 'button', class: 'icon-btn ec-hear', 'aria-label': `Hear ${p.name}`, title: `Hear ${p.name}`, disabled: !p.lines, dataset: { hear: p.name }, onclick: () => hearPart(p.name) }, path(PLAY)))));
      if (had && (had.part || had.hear)) {
        const b = [...parts.querySelectorAll('button')].find(x => (had.part ? x.dataset.part === had.part : x.dataset.hear === had.hear));
        if (b) b.focus();
      }
      outBtn.setAttribute('aria-pressed', String(who === O.OUT));
    }
    /** After any change of the cast. */
    function paint() {
      paintParts();
      paintLines();
      const n = S.count();
      where.textContent = kit.castLine(n);
      titleBtn.setAttribute('aria-label', `${title}, ${where.textContent}`);
      titleBtn.disabled = !P.rec || P.rec.done;
      undoBtn.disabled = !S.canUndo();
      light();
    }
    /** The outline, the pressed part, the scroll: what a new lit line changes and nothing else. */
    function light() {
      const lit = P.sample ? P.sample.k : S.lit;
      if (P.lit !== lit) {
        const was = P.nodes.get(P.lit);
        if (was) was.classList.remove('ec-lit');
        list.querySelectorAll('.ec-lit').forEach(x => x.classList.remove('ec-lit'));
        const n = P.nodes.get(lit);
        if (n) n.classList.add('ec-lit');
        P.lit = lit;
        if (!P.sample) {
          follow.line(lit || null);
          if (lit && follow.following) bring(n);
        }
      }
      const who = S.lit ? S.who(S.lit) : null;
      parts.querySelectorAll('[data-part]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.part === who)));
      outBtn.setAttribute('aria-pressed', String(who === O.OUT));
      outBtn.disabled = !S.lit;
      showPart();
    }
    /** The speaker's own chip, when the parts are more than the dock shows. */
    function showPart() {
      const b = parts.querySelector('[aria-pressed="true"]');
      if (!b || parts.scrollHeight <= parts.clientHeight + 1) return;
      const s = parts.getBoundingClientRect(), r = b.getBoundingClientRect();
      if (r.top < s.top) parts.scrollTop += r.top - s.top;
      else if (r.bottom > s.bottom) parts.scrollTop += r.bottom - s.bottom;
    }
    function bring(n) {
      if (!n) return;
      const s = scroller.getBoundingClientRect(), r = n.getBoundingClientRect();
      const top = scroller.scrollTop + r.top - s.top - Math.max(8, (s.height - r.height) * 0.42);
      scroller.scrollTo({ top, behavior: still() || Math.abs(top - scroller.scrollTop) > s.height * 2 ? 'auto' : 'smooth' });
    }
    function paintTransport() {
      const on = playing();
      playBtn.classList.toggle('is-playing', on);
      playBtn.setAttribute('aria-label', on ? 'Pause' : 'Play');
      timeText.textContent = clock(nowMs() / 1000);
      speed.value = String(Player.nearestSpeed(here() ? audio.playbackRate : speedWas()));
      const guest = Player.following;
      for (const b of [rewind, speed]) b.disabled = guest;
    }

    /* ---- Following: a scroll of the person's own stops it ---- */

    function away() { if (S.lit && follow.away().back) backBtn.hidden = false; }
    function refollow() {
      follow.back();
      backBtn.hidden = true;
      bring(P.nodes.get(S.lit));
      focusLine(S.lit || P.cur, false);
    }
    scroller.addEventListener('wheel', away, { passive: true });
    scroller.addEventListener('touchmove', away, { passive: true });

    /* ---- The audio: told where it is, every frame while it plays ---- */

    let frame = 0;
    function sync() {
      if (P.sample) {
        if (!here() || audio.paused || audio.currentTime * 1000 >= P.sample.until) endSample();
        paintTransport();
        return;
      }
      const got = S.tick(nowMs(), playing());
      if (here() && !P.loading) P.place = nowMs();
      if (got.heard) { paint(); save(); } else if (got.moved) light();
      if (got.moved && !playing() && S.lit) { const l = S.line(S.lit); if (l) h.announce(l.text); }
      paintTransport();
    }
    function loop() {
      frame = 0;
      if (my !== seq) return;
      sync();
      if (playing()) frame = requestAnimationFrame(loop);
    }
    const run = () => { if (!frame) frame = requestAnimationFrame(loop); };
    const onSeeking = () => { if (!P.sample) S.jumped(); };
    const onSeeked = () => { sync(); };
    // A copy just loaded reads 0 until it is moved to its place (and a retry of one that failed forgets it).
    const onMeta = () => setTimeout(() => {
      if (!P.loading || my !== seq) return;
      P.loading = false;
      if (here() && !P.sample && Math.abs(audio.currentTime * 1000 - P.place) > 1500) Player.seek(P.place / 1000);
      S.jumped();
      sync();
    }, 0);
    audio.addEventListener('loadedmetadata', onMeta);
    audio.addEventListener('seeking', onSeeking);
    audio.addEventListener('seeked', onSeeked);
    // Frames stop in a hidden tab; the audio's own clock does not, and what it plays there was heard too.
    const onTime = () => { if (document.visibilityState === 'hidden') sync(); };
    audio.addEventListener('timeupdate', onTime);
    function onPlayer(kind) {
      if (kind === 'error' && here()) say(API.isOffline() ? 'You are offline.' : 'This recording did not load.', () => { say(null); start(); }, 'audio');
      if (kind === 'play' || kind === 'load') { if (here() && !Player.error && saying === 'audio') say(null); run(); }
      if (kind === 'pause' && here() && P.rec && !P.sample) save();
      paintTransport();
    }

    /** The episode on the player, at this page's place and speed. A press starts it. */
    function start() {
      if (Player.following) { say('Leave Listen together to play this.', null, 'audio'); return; }
      Player.hold(speedWas());
      if (here() && !Player.error) Player.play();
      else {
        P.loading = true;
        Player.load(card(), { at: P.place / 1000, arc: false });
      }
      P.mine = true;
      run();
    }
    function toggle() {
      if (P.sample) { endSample(); return; }
      if (playing()) Player.pause(); else start();
    }
    function back() {
      if (P.sample) { endSample(); return; }
      if (here() && !P.loading) Player.seek(audio.currentTime - E.BACK_S);
      else { P.place = Math.max(0, P.place - E.BACK_S * 1000); S.jumped(); sync(); }
    }
    function setSpeed(x) {
      speedIs(x);
      if (here()) { Player.hold(x); P.mine = true; }
      h.announce(`Speed ${x}×`);
    }
    /** Plays one line on its own, then goes back to the place it left. */
    function sample(l) {
      if (!l || !l.at) return;
      if (Player.following) { say('Leave Listen together to play this.', null, 'audio'); return; }
      const was = P.sample ? P.sample.back : { ms: nowMs(), playing: playing() };
      const [from, until] = E.spanOf(l);
      P.sample = { k: l.k, until, back: was, going: true };
      Player.hold(speedWas());
      P.mine = true;
      if (here()) { Player.seek(from / 1000); Player.play(); } else Player.load(card(), { at: from / 1000, arc: false });
      const s = P.sample;
      const wait = () => {
        if (my !== seq || P.sample !== s) return;
        if (here() && audio.currentTime * 1000 >= s.until) { endSample(); return; }
        if (audio.ended || (Player.error && here())) { endSample(); return; }
        requestAnimationFrame(wait);
      };
      requestAnimationFrame(wait);
      light();
      paintTransport();
    }
    function endSample(goOn = true) {
      const s = P.sample;
      if (!s) return;
      P.sample = null;
      P.lit = -1;
      if (here()) {
        Player.pause();
        Player.seek(s.back.ms / 1000);
        S.jumped();
        if (goOn && s.back.playing) { Player.play(); run(); }
      }
      light();
      paintTransport();
    }
    function hearPart(name) { sample(S.sample(name)); }

    /* ---- Casting ---- */

    /** One press: `does` answers a refusal or null. */
    function press(does, spoken) {
      if (P.sample) endSample();
      else sync();
      const why = does();
      if (why) { refuse(why); return false; }
      paint();
      save();
      h.announce(spoken);
      return true;
    }
    let refusing = null;
    function refuse(why) {
      const words = why === 'no_such_line' ? 'No line is lit.' : kit.say(why);
      where.textContent = words;
      where.classList.add('refusal');
      h.announce(words);
      clearTimeout(refusing);
      refusing = setTimeout(() => { where.classList.remove('refusal'); if (my === seq) where.textContent = kit.castLine(S.count()); }, 2500);
    }
    function give(name) { return press(() => S.give(name), name); }
    function undo() {
      if (!S.canUndo()) return;
      press(() => S.undo(), 'Undone');
    }
    async function finish() {
      if (P.sample) endSample(false);
      const doc = O.done(S.doc, { keepOpen: true });
      const why = O.refusalOf(O.toScript(doc, { id: P.rec ? P.rec.id : 'own-00000000-0000-4000-8000-000000000000', title, episode: { id: d.id, url: SITE } }));
      if (why) { refuse(why); return; }
      doneBtn.disabled = true;
      const before = S.doc, wasDone = !!(P.rec && P.rec.done);
      S.doc = doc;
      record().done = true;
      save.flush();
      if (!(await write())) { S.doc = before; P.rec.done = wasDone; doneBtn.disabled = false; return; }
      if (my !== seq) return;
      h.navigate(`?play=${encodeURIComponent(P.rec.id)}`, true);
    }

    /* ---- The sheets ---- */

    /** The audio waits while a sheet is open, and goes on when it closes if it was playing. */
    function sheet(label, cls, after) {
      const was = playing() && !P.sample;
      if (was) Player.pause();
      const el = h.el('dialog', { class: `os-sheet ${cls}`, 'aria-label': label });
      el.addEventListener('close', () => {
        el.remove();
        if (P.sample) endSample(false);
        if (my !== seq) return;
        after();
        if (was && el.dataset.hold !== '1') start();
      });
      el.addEventListener('click', (e) => { if (e.target === el && !el.querySelector('.os-edit')) el.close(); });
      sheets.append(el);
      return el;
    }
    /** The casting's own sheet: its title, and Delete while it is not Done. */
    function titleSheet() {
      if (!P.rec || P.rec.done) return;
      const el = sheet('Title', 'os-small', () => titleBtn.focus());
      kit.inner(el, h.el('div', { class: 'os-sheet-head' }, h.el('h2', { class: 'section-header' }, title), kit.closeBtn(el)),
        kit.deleteNotDone(P.rec, () => { gone = true; el.dataset.hold = '1'; el.close(); }));
      el.showModal();
    }
    function newPart() {
      const el = sheet('New part', 'os-small', () => {});
      const others = S.parts();
      kit.inner(el, h.el('div', { class: 'os-sheet-head' }, h.el('h2', { class: 'section-header' }, 'New part'), kit.closeBtn(el)),
        kit.nameForm({ label: 'Name', button: 'Add', max: O.MAX_PART_NAME, act: (v) => {
          const got = S.add(v);
          if (got.refusal) return kit.nameWhy(got.refusal);
          el.close();
          paint();
          save();
          h.announce(got.name);
          return null;
        } }),
        others.length ? h.el('p', { class: 'caption os-lab' }, 'Rename') : null,
        others.length ? h.el('div', { class: 'os-acts' }, others.map(p => h.el('button', { type: 'button', class: 'os-chip', dataset: { hue: hueAt(p.name, S.parts()) }, 'aria-label': `Rename ${p.name}`, onclick: () => renamePart(el, p.name) },
          h.el('i', { class: 'os-dot', 'aria-hidden': 'true' }), h.el('span', { class: 'body-strong' }, p.name)))) : null);
      el.showModal();
      el.querySelector('input').focus();
    }
    /** A part's name, while it is cast: the sheet becomes its one field. A name another part has joins the two. */
    function renamePart(el, name) {
      const form = kit.nameForm({ label: 'Name', value: name, button: 'Rename', max: O.MAX_PART_NAME, act: (v) => {
        const got = S.rename(name, v);
        if (got.refusal) return kit.nameWhy(got.refusal);
        el.close();
        paint();
        save();
        h.announce(got.name);
        return null;
      } });
      kit.inner(el, h.el('div', { class: 'os-sheet-head' }, h.el('h2', { class: 'section-header' }, name), kit.closeBtn(el)), form);
      const field = form.querySelector('input');
      field.focus();
      field.select();
    }
    const KIND_WORD = { direction: 'Direction', sound: 'Sound' };
    function lineSheet(k) {
      const l = S.line(k);
      if (!l) return;
      setCur(k);
      let back = k;
      const el = sheet('Line', 'os-line-sheet', () => focusLine(back, false));
      const err = h.el('p', { class: 'caption refusal', role: 'alert' });
      const act = (does, spoken, to) => {
        const had = new Set(S.doc.lines.map(x => x.k));
        const i = S.doc.lines.findIndex(x => x.k === k);
        const above = i > 0 ? S.doc.lines[i - 1].k : k;
        const why = does();
        if (why) { err.textContent = kit.say(why); return; }
        const made = S.doc.lines.find(x => !had.has(x.k));
        back = to === 'made' && made ? made.k : to === 'above' ? above : k;
        paint();
        save();
        h.announce(spoken);
        el.close();
      };
      const btn = (text, onclick, attrs = {}) => h.el('button', { type: 'button', class: 'btn', onclick, ...attrs }, text);
      const edit = () => {
        if (P.sample) endSample(false);
        const field = h.el('textarea', { class: 'field-input os-edit', 'aria-label': 'Words' });
        field.value = l.text;
        kit.inner(el, field, h.el('div', { class: 'os-four' },
          btn('Save', () => act(() => S.apply({ op: 'words', line: k, text: field.value }), 'Words changed'), { class: 'btn btn-primary' }), btn('Cancel', () => el.close())), err);
        field.focus();
        field.setSelectionRange(0, 0);
      };
      const top = h.el('div', { class: 'os-sheet-head os-sheet-top' }, kit.closeBtn(el));
      const hear = l.at ? btn('Hear it', () => sample(S.line(k)), { class: 'btn btn-way' }) : null;
      const from = l.at ? btn('Play from here', () => {
        if (P.sample) endSample(false);
        P.place = l.at[0];
        S.jumped();
        if (here() && !P.loading) Player.seek(l.at[0] / 1000);
        el.dataset.hold = '1';
        follow.back();
        backBtn.hidden = true;
        el.close();
        start();
        sync();
      }) : null;
      if (l.id && S.takes.has(l.id)) {
        kit.inner(el, top, h.el('p', { class: 'os-cutline' }, l.text), h.el('p', { class: 'caption refusal' }, kit.say('line_has_take')), h.el('div', { class: 'os-four' }, hear, btn('Edit words', edit), from), err);
        el.showModal();
        return;
      }
      const split = btn('Split here', () => act(() => S.apply({ op: 'split', line: k, at: cut.at() }), 'Split', 'made'), { disabled: true });
      const cut = kit.cutter(l.text, (at) => { split.disabled = at < 0; });
      const who = S.who(k);
      const chips = S.parts().map((p, i, all) => h.el('button', { type: 'button', class: 'os-chip', dataset: { hue: hueAt(p.name, all) }, 'aria-pressed': String(p.name === who), onclick: () => act(() => S.assign(k, { role: p.name }), p.name) },
        h.el('i', { class: 'os-dot', 'aria-hidden': 'true' }), h.el('span', { class: 'body-strong' }, p.name)));
      const kinds = ['direction', 'sound'].map(kind => h.el('button', { type: 'button', class: 'os-chip os-plain', 'aria-pressed': String(l.kind === kind), onclick: () => act(() => S.assign(k, kind), KIND_WORD[kind]) }, KIND_WORD[kind]));
      kit.inner(el, top, cut.node, h.el('div', { class: 'os-acts' }, chips, kinds),
        h.el('div', { class: 'os-four' }, hear, btn('Edit words', edit, { class: 'btn btn-way' }), cut.places ? split : null,
          S.doc.lines[0].k !== k ? btn('Join to line above', () => act(() => S.apply({ op: 'join', line: k }), 'Joined', 'above')) : null,
          btn('Leave out', () => act(() => S.leaveOutLine(k), 'Left out')), from), err);
      el.showModal();
      if (cut.places) cut.node.focus();
    }

    /* ---- The lines are one tab stop ---- */

    function setCur(k) {
      if (P.cur === k) return;
      for (const [x, t] of [[P.cur, -1], [k, 0]]) {
        const n = P.nodes.get(x);
        if (n) n.firstElementChild.tabIndex = t;
      }
      P.cur = k;
    }
    function focusLine(k, reveal = true) {
      const n = P.nodes.get(k);
      if (!n) return;
      setCur(k);
      n.firstElementChild.focus({ preventScroll: true });
      if (reveal) n.scrollIntoView({ block: 'nearest' });
    }
    list.addEventListener('click', (e) => {
      const l = e.target.closest('[data-open]');
      if (!l) return;
      const sel = getSelection();
      if (sel && !sel.isCollapsed && l.contains(sel.anchorNode)) return;
      lineSheet(Number(l.dataset.open));
    });
    list.addEventListener('focusin', (e) => { const l = e.target.closest('[data-open]'); if (l) setCur(Number(l.dataset.open)); });
    list.addEventListener('keydown', (e) => {
      const l = e.target.closest('[data-open]');
      if (!l || e.metaKey || e.ctrlKey || e.altKey) return;
      const i = S.doc.lines.findIndex(x => x.k === Number(l.dataset.open));
      const to = { ArrowDown: i + 1, ArrowUp: i - 1, Home: 0, End: S.doc.lines.length - 1 }[e.key];
      if (e.key === 'Enter') { e.preventDefault(); lineSheet(S.doc.lines[i].k); } else if (to !== undefined) {
        e.preventDefault();
        if (S.doc.lines[to]) { away(); focusLine(S.doc.lines[to].k); }
      }
    });

    /** 1 to 9, Space, Left, U (§4.22 item 5), before the player's own keys. A button the keyboard is on keeps its Space. */
    const onKey = (e) => {
      if (document.querySelector('dialog[open]') || e.target.closest('input, textarea, select, [contenteditable="true"]')) return;
      const key = E.keyOf(e);
      if (!key || (key.act === 'toggle' && e.target.closest('button, a'))) return;
      e.preventDefault();
      e.stopImmediatePropagation();
      if (key.act === 'toggle') { if (!e.repeat) toggle(); } else if (key.act === 'back') back();
      else if (key.act === 'undo') undo();
      else { const p = S.parts()[key.n]; if (p) give(p.name); }
    };
    document.addEventListener('keydown', onKey, true);

    /* ---- Shown ---- */

    const onShow = async () => {
      if (document.visibilityState !== 'visible') { save.flush(); return; }
      if (P.rec) try { S.takes = new Set(await store().takes(P.rec.id)); } catch (e) { console.error(e); }
      sync();
    };
    document.addEventListener('visibilitychange', onShow);
    const onHide = () => { if (P.rec) write(); };
    window.addEventListener('pagehide', onHide);
    document.body.classList.add('casting');
    if (here()) {
      P.place = nowMs();
      P.mine = true;
      Player.hold(speedWas());
      run();
    } else if (Player.current && !audio.paused && !Player.following) Player.pause();
    S.tick(P.place, false);
    paint();
    paintTransport();
    if (S.lit) bring(P.nodes.get(S.lit));
    // A kept casting keeps its own lines. When archive.org has made the transcript or the copy again since, that is said.
    if (rec && rec.ear) {
      const tell = (words) => { if (my === seq) { note.textContent = words; note.hidden = false; } };
      if (rec.ear.copy && rec.ear.copy !== copy) tell('The recording has changed. The times may be off.');
      else if (d.transcript) API.transcriptCues(d.transcript).then(c => { if (E.signature(c) !== rec.ear.sig) tell('The transcript has changed. Your lines are kept.'); }).catch(() => {});
    }
    page = { onPlayer, leave() {
      document.removeEventListener('keydown', onKey, true);
      document.removeEventListener('visibilitychange', onShow);
      window.removeEventListener('pagehide', onHide);
      audio.removeEventListener('seeking', onSeeking);
      audio.removeEventListener('seeked', onSeeked);
      audio.removeEventListener('loadedmetadata', onMeta);
      audio.removeEventListener('timeupdate', onTime);
      cancelAnimationFrame(frame);
      clearTimeout(refusing);
      sheets.querySelectorAll('dialog[open]').forEach(x => x.close());
      if (P.sample) endSample(false);
      document.body.classList.remove('casting');
      if (P.rec && !doneBtn.disabled && (save.pending() || Math.abs(P.rec.ear.place - nowMs()) > 1000)) write();
      if (P.mine) Player.release();
    } };
  }

  Player.onChange((kind) => { if (page) page.onPlayer(kind); });

  /* ---- The router's doors ---- */

  function leave() {
    seq += 1;
    const p = page;
    page = null;
    if (p) p.leave();
  }
  function render(r, helpers) {
    leave();
    h = helpers;
    kit = OwnUI.kit(helpers);
    const my = seq;
    return open($('own-body'), my, r.p.get('cast'));
  }

  return { render, leave, door };
})();
