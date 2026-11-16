/**
 * The studio inside the reader, without a DOM (PLAYS-DESIGN §2.9, WEB-DESIGN §4.16 item 14;
 * Decision 076 S3): which of my lines is current, how each of the three modes moves it, the take
 * state each of my lines shows, a line's takes (choose, delete an unchosen one, record again),
 * Delete unused takes for the part, the line the studio opens at, and the production the reader's
 * Record continues. It drives the shipped RecordingSession and never records or plays itself.
 * Tests: js/studio.test.js.
 */
const StudioCore = (() => {
  'use strict';
  const C = PlaysCore;

  /** The line a studio opens at: the one asked for when it is the part's, else the first with no usable take. */
  function startLine(p, script, part, ask) {
    const mine = C.linesFor(script, part).map(l => l.id);
    if (!mine.length) return null;
    if (ask && mine.includes(ask)) return ask;
    return mine.find(id => !C.usableTake(p, id)) || mine[0];
  }

  /** What a line of mine shows beside its speaker (§2.9 rule 3): none, its takes with the chosen one, or the flag. */
  function lineState(p, lineID) {
    const takes = C.takesFor(p, lineID);
    const chosen = C.chosenTake(p, lineID);
    if (!takes.length) return { state: 'none', takes: 0, chosen: 0 };
    return { state: chosen && chosen.bleed ? 'flagged' : 'chosen', takes: takes.length, chosen: chosen ? takes.indexOf(chosen) + 1 : 0 };
  }

  /**
   * Where the reader's Record records (§2.9 rule 1): this device's newest unshared production of the
   * play in which the part is recording; else the newest where it is open and no other part records
   * (the part is taken); else a new production.
   */
  function productionFor(productions, isShared, script, part) {
    const own = productions.filter(p => p.scriptID === script.id && !isShared(p.id)).sort((a, b) => b.created - a.created);
    const going = own.find(p => C.stateOf(p, part).status === 'recording');
    if (going) return { id: going.id, take: false };
    const open = own.find(p => C.stateOf(p, part).status === 'open' && !C.current(p, script));
    if (open) return { id: open.id, take: true };
    return { make: true };
  }

  /**
   * One studio: `session` (a started or starting RecordingSession), the script as cast, the part,
   * the store. `line` is a line to open at. Set `onChange` to repaint and `onFollow(lineID)` to have
   * the reader follow the line being heard or recorded.
   */
  function create({ session, script, part, store, line = null }) {
    const mine = C.linesFor(script, part).map(l => l.id);
    const at = (id) => script.lines.findIndex(l => l.id === id);
    const st = {
      mine,
      current: startLine(session.production, script, part, line),
      onChange: null,
      onFollow: null,
    };
    const changed = () => { if (st.onChange) st.onChange(st); };
    const locked = () => session.isBusy() || !!session.run || session.phase.kind === 'runReview';
    const pid = () => session.production.id;
    const refresh = () => { session.production = store.production(pid()) || session.production; };

    /** My first line at or after a script line (the run's next line of mine). */
    const mineFrom = (lineID) => { const k = at(lineID); return mine.find(id => at(id) >= k) || null; };

    session.onPhase = (s) => {
      const ph = s.phase;
      if (!ph.lineID || !['cue', 'listening'].includes(ph.kind)) return;
      if (st.onFollow) st.onFollow(ph.lineID);
      // During a run, and whenever the microphone is open, the current line is the line being recorded or my next one.
      if (s.run || ph.kind === 'listening') {
        const next = ph.kind === 'listening' && mine.includes(ph.lineID) ? ph.lineID : mineFrom(ph.lineID);
        if (next) st.current = next;
      }
    };

    /** A tap on one of my lines makes it current (refused while busy or in a run). */
    st.select = (id) => {
      if (!mine.includes(id) || locked()) return false;
      st.current = id;
      changed();
      return true;
    };

    /** Next and Previous: my next or previous line from the current one, never wrapping. */
    st.move = (delta) => {
      if (locked() || !mine.length) return false;
      let i = mine.indexOf(st.current);
      if (i < 0) {
        const from = mineFrom(st.current || mine[0]);
        i = from ? mine.indexOf(from) - (delta > 0 ? 1 : 0) : mine.length - 1;
      }
      const to = mine[Math.max(0, Math.min(mine.length - 1, i + delta))];
      if (to === st.current) return false;
      st.current = to;
      changed();
      return true;
    };

    /**
     * The one round control (Space): in Run through, start a run from the current line or pause it;
     * otherwise stop listening, cancel a cue, or record the current line.
     */
    st.primary = async () => {
      const ph = session.phase;
      if (!session.started || !st.current) return;
      if (session.mode === 'run') {
        if (ph.kind === 'runReview') return;
        if (session.run) { session.pause(); return; }
        // A single take outside a run (Again on a line gone back to) stops or cancels like Line by line.
        if (ph.kind === 'listening') { session.stopListening(); return; }
        if (ph.kind === 'cue') { session.cancel(); return; }
        if (!session.isBusy()) await session.runThrough(st.current);
        return;
      }
      if (ph.kind === 'listening') session.stopListening();
      else if (ph.kind === 'cue') session.cancel();
      else if (!session.isBusy()) await session.record(st.current);
    };

    /** Record again (R): a new take of the current line, chosen at once; every older take stays. */
    st.again = async (lineID = st.current) => {
      if (!session.started || session.isBusy() || !lineID) return;
      if (!session.run) st.current = lineID;
      await session.record(lineID);
    };

    /** Keep (Return): Step's review moves to my next line and waits; a run's review keeps the run. */
    st.keep = () => {
      const ph = session.phase;
      if (ph.kind === 'review') {
        session.phase = { kind: 'idle' };
        const i = mine.indexOf(st.current);
        if (i >= 0 && i + 1 < mine.length) st.current = mine[i + 1];
        changed();
      } else if (ph.kind === 'runReview') session.keepRun();
    };

    st.lineState = (id) => lineState(session.production, id);
    st.takes = (id = st.current) => C.takesFor(session.production, id);
    st.choose = (t) => { if (!session.isBusy()) session.choose(t); };

    /** Deletes one unchosen take and its file (the person's act); false when refused. */
    st.deleteTake = async (t) => {
      if (session.isBusy()) return false;
      const done = await store.deleteTake(pid(), t.id);
      refresh();
      changed();
      return done;
    };

    /** This part's unchosen takes, and Delete unused takes for the part; returns how many went. */
    st.unused = () => C.unusedTakes(session.production).filter(t => mine.includes(t.lineID));
    st.deleteUnused = async () => {
      if (locked()) return 0;
      const n = await store.discardUnusedTakes(pid(), mine);
      refresh();
      changed();
      return n;
    };

    /** How many of my lines have a usable take. */
    st.kept = () => mine.length - C.missingLines(session.production, script, part).length;

    return st;
  }

  /**
   * Who holds each part someone else has in a shared production: { part id: name }. The name is the
   * one the holder chose for the part, else their name among the members. Open and silent parts and
   * this person's own are left out.
   */
  function heldBy(rec, me) {
    const out = {};
    if (!rec || !rec.parts) return out;
    for (const [id, s] of Object.entries(rec.parts)) {
      if (!s || !['recording', 'done'].includes(s.status) || !s.user_id || s.user_id === me) continue;
      const m = (rec.members || []).find(x => x.user_id === s.user_id);
      const name = String(s.performer || (m && m.display_name) || '').trim();
      if (name) out[id] = name;
    }
    return out;
  }

  return { heldBy, startLine, lineState, productionFor, create };
})();
