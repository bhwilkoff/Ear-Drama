/**
 * Shared plays, phase 2 (LOOP-PLAN M8, PLAYS-DESIGN §11.7, WEB-DESIGN §4.10a):
 * a production in this browser, linked to its record on the Worker. No DOM;
 * js/plays-ui.js draws it; js/plays-share.test.js runs it against a stub Worker.
 *
 * The Worker is the arbiter (C7): who holds which part, which take is chosen.
 * Any open part may be claimed while none records; `next` is only the
 * suggestion. Nothing here decides a claim; it asks and shows the answer.
 * Takes are recorded in this browser exactly as phase 1 records them, then
 * uploaded: only the chosen take of each line of a part this person holds,
 * never one the bleed check flagged (it holds the device voice, §5). A take
 * reaches only the members, so uploading asks no consent (Decision 072); the
 * CC0 consent comes before Publish, and both wait for the owner's words.
 */
const PlaysShare = (() => {
  'use strict';
  const C = PlaysCore;
  const INVITE_KEY = 'ed.invite';
  const clone = (o) => JSON.parse(JSON.stringify(o));

  /** The cast sheet the Worker checks against its manifest: every line in script order. */
  const castSheet = (script) => script.lines.map(l => ({ id: l.id, part: C.linePart(l) }));

  const isMine = (rec, part, me) => {
    const s = rec.parts[part];
    return !!s && s.status === 'recording' && !!me && s.user_id === me;
  };
  const recordingPart = (rec) => Object.keys(rec.parts).find(k => rec.parts[k].status === 'recording') || null;
  const myParts = (rec, me) => Object.keys(rec.parts).filter(k => isMine(rec, k, me));
  /** The owner's switch (Decision 066, P1): false until the take store exists. */
  const uploadsOpen = (rec) => !!rec && rec.uploads !== false;
  /** Any open part may be taken while no part records (C7). */
  const canClaim = (rec, part) => !recordingPart(rec) && (!rec.parts[part] || rec.parts[part].status === 'open');
  /** Speaking lines with no chosen take this person can see. */
  const unvoiced = (rec, script) => C.speechLineIDs(script).filter(id => !rec.chosen[id]);
  /**
   * TODO(M8-consent-screen): Publish sends the play beyond its members, so it
   * waits for the CC0 consent screen, whose words are the owner's (Decisions
   * 059 and 072, PLAYS-DESIGN §11.7 rule 6). Flip only with that screen.
   */
  const PUBLISH_OPEN = false;
  const complete = (rec, script) => !recordingPart(rec)
    && Object.values(rec.parts).every(s => s.status === 'done' || s.status === 'silent')
    && unvoiced(rec, script).length === 0;

  /**
   * The local record follows the Worker's parts: only this person's live claim
   * records here (so the phase 1 recorder opens for it); done and silent come
   * across with the performer's name; anyone else's claim is open here.
   */
  function mirror(local, rec, me) {
    const n = clone(local);
    n.parts = {};
    for (const [id, s] of Object.entries(rec.parts)) {
      const st = s.status === 'recording' ? (s.user_id === me ? 'recording' : 'open') : s.status;
      n.parts[id] = s.performer && st !== 'open' ? { status: st, performer: s.performer } : { status: st };
    }
    return n;
  }
  async function follow(store, localId, rec, me) {
    const local = store.production(localId);
    const n = mirror(local, rec, me);
    if (C.stableStringify(n) !== C.stableStringify(local)) await store.save(n);
    return n;
  }

  /** The chosen take of each line of a part this person holds that the Worker does not have yet. */
  function pending(local, script, rec, me) {
    const onServer = new Set(rec.takes.map(t => t.id));
    const out = [];
    for (const part of myParts(rec, me)) {
      for (const l of C.linesFor(script, part)) {
        const t = C.chosenTake(local, l.id);
        if (t && !onServer.has(t.id)) out.push(t);
      }
    }
    return out;
  }

  /** The take's fields as the Worker reads them from `x-take` (docs/WORKER.md). */
  function metaOf(t) {
    const m = { lineID: t.lineID, part: t.part, file: t.file, created: t.created, frames: t.frames,
                sampleRate: t.sampleRate, capture: t.capture || 'direct', heard: t.heard || {}, peak: t.peak || 0,
                bleed: !!t.bleed };
    if (typeof t.loudness === 'number' && isFinite(t.loudness)) m.loudness = t.loudness;
    return m;
  }

  /**
   * Uploads this person's pending takes to the members (Decision 072: no
   * consent is asked; `GET /consent` is read only for the owner's switch).
   * Returns { sent, flagged, stopped?: 'uploads_off', error? }.
   */
  async function upload({ api, store, local, script, rec, me }) {
    const link = store.share(local.id);
    const todo = pending(local, script, rec, me);
    const flagged = todo.filter(t => t.bleed).length;
    const send = todo.filter(t => !t.bleed);
    let sent = 0;
    if (!send.length) return { sent, flagged };
    if (!uploadsOpen(rec)) return { sent, flagged, stopped: 'uploads_off' };
    try {
      const consent = await api.consent();
      if (consent.uploads === false) return { sent, flagged, stopped: 'uploads_off' };
      for (const t of send) {
        const bytes = await store.readTake(local.id, t.file);
        try {
          await api.upload(link.pid, t.id, bytes, metaOf(t));
          sent++;
        } catch (e) {
          if (e.code === 'take_exists') continue;
          throw e;
        }
      }
      // The person's own choice of take wins on the Worker too.
      const fresh = await api.get(link.pid);
      for (const part of myParts(fresh, me)) {
        for (const l of C.linesFor(script, part)) {
          const mine = local.chosen[l.id];
          if (mine && fresh.chosen[l.id] !== mine && fresh.takes.some(t => t.id === mine)) await api.choose(link.pid, mine);
        }
      }
    } catch (error) {
      return { sent, flagged, error };
    }
    return { sent, flagged };
  }

  /**
   * The chosen take of each line as this browser should play it: the Worker's
   * for every line, except a line of a part this person holds, where their own
   * choice stands until it is uploaded. A line the Worker no longer shows
   * (blocked, reported) has none.
   */
  function mergedChosen(local, script, rec, me) {
    const out = { ...rec.chosen };
    for (const part of myParts(rec, me)) {
      for (const l of C.linesFor(script, part)) if (local.chosen[l.id]) out[l.id] = local.chosen[l.id];
    }
    return out;
  }

  /** The other members' chosen takes this browser lacks. */
  function missingHere(local, rec) {
    const have = new Set(local.takes.map(t => t.id));
    return Object.values(rec.chosen).filter(id => !have.has(id) && rec.takes.some(t => t.id === id));
  }

  /** True when this browser already holds and plays exactly what the Worker shows. */
  const inStep = (local, script, rec, me) => !missingHere(local, rec).length
    && C.stableStringify(mergedChosen(local, script, rec, me)) === C.stableStringify(local.chosen);

  /**
   * Brings the chosen takes of the other members into this browser, so the
   * phase 1 listen-through can play the whole play. Only takes the Worker shows
   * this person arrive (blocked and reported ones never do).
   */
  async function bringHome({ api, store, localId, rec, script, me }) {
    const add = [];
    for (const takeId of missingHere(store.production(localId), rec)) {
      const t = rec.takes.find(x => x.id === takeId);
      const file = `m-${takeId}.wav`;
      await store.importTake(localId, file, await api.audio(rec.id, takeId));
      const take = { id: t.id, lineID: t.lineID, part: t.part, file, created: t.created, frames: t.frames,
                     sampleRate: t.sampleRate, capture: t.capture, heard: t.heard || {}, peak: t.peak || 0, bleed: false };
      if (typeof t.loudness === 'number') take.loudness = t.loudness;
      add.push(take);
    }
    const n = clone(store.production(localId));
    n.takes.push(...add);
    const chosen = mergedChosen(n, script, rec, me);
    if (C.stableStringify(chosen) !== C.stableStringify(n.chosen)) n.listenedThrough = false;
    n.chosen = chosen;
    await store.save(n);
    return add.length;
  }

  /** Publish for the director of a complete play, only once the consent screen ships (rule 9). */
  const canPublish = (rec, script, me, open = PUBLISH_OPEN) =>
    open && !!me && rec.director === me && !rec.archive && complete(rec, script);

  /** "Share this production": the Worker makes the record; the caller directs it. */
  async function share({ api, store, local, script, displayName }) {
    const name = (displayName || '').trim();
    const rec = await api.create({ script_id: script.id, script_revision: script.revision, cast: castSheet(script),
                                   ...(name ? { display_name: name } : {}) });
    await store.setShare(local.id, { pid: rec.id });
    return rec;
  }

  /** The production in this browser for a shared one, made from the bundle's script on first open. */
  async function localFor(store, pid, script) {
    let local = store.findShared(pid);
    if (!local) {
      if (!script) throw Object.assign(new Error('revision_mismatch'), { code: 'revision_mismatch' });
      local = await store.create(script);
      await store.setShare(local.id, { pid });
    }
    return local;
  }

  /** The bundle's script for a shared production, only at the revision it was cast from. */
  const scriptFor = (scripts, scriptID, revision) =>
    (scripts || []).find(x => x.id === scriptID && x.revision === revision) || null;

  /** Joins by an invite and claims `part`; makes the production in this browser on the first join. */
  async function join({ api, store, token, part, displayName, script }) {
    const name = (displayName || '').trim();
    const rec = await api.joinByInvite(token, part, name || undefined);
    return { rec, local: await localFor(store, rec.id, script) };
  }

  /**
   * Library's Ear dramas (Decision 068): this browser's productions, then the
   * shared ones this person is in that this browser has not opened yet, newest first.
   */
  function libraryRows(store, remote) {
    const rows = store.productions.map(p => ({ local: p, pid: (store.share(p.id) || {}).pid || null }));
    const here = new Set(rows.map(r => r.pid).filter(Boolean));
    for (const r of remote || []) if (!here.has(r.id)) rows.push({ local: null, pid: r.id, remote: r });
    const when = (r) => (r.local ? r.local.created + 978307200 : (r.remote.updated_at || 0) / 1000);
    return rows.sort((a, b) => when(b) - when(a));
  }

  /* ---- Invite links (DEEP_LINKS.md): the token rides the fragment, so it never reaches a server log ---- */

  /** `https://eardrama.org/invite#{token}`, the twin of `eardrama://invite#{token}` (DEEP_LINKS.md). */
  function inviteLink(token, origin = 'https://eardrama.org') {
    return `${String(origin).replace(/\/+$/, '')}/invite#${token}`;
  }
  const TOKEN = /^[A-Za-z0-9_-]{43}$/;
  /** The token from /invite#{token}, or from the #invite={token} the 404 forwarder leaves. */
  function inviteToken(loc) {
    const hash = String(loc.hash || '').replace(/^#/, '');
    const named = new URLSearchParams(hash).get('invite');
    if (named && TOKEN.test(named)) return named;
    if (/\/invite\/?$/.test(String(loc.pathname || '')) && TOKEN.test(hash)) return hash;
    return null;
  }
  function pendingInvite() {
    try { return sessionStorage.getItem(INVITE_KEY); } catch { return null; }
  }
  function holdInvite(token) {
    try { if (token) sessionStorage.setItem(INVITE_KEY, token); else sessionStorage.removeItem(INVITE_KEY); } catch { /* this page only */ }
  }

  /* ---- One plain line for each refusal (AGENTS.md: a refusal, a warning, or a fact) ---- */

  const LINES = {
    storage_not_configured: 'Uploads are off.',
    uploads_off: 'Uploads are off.',
    not_open: 'This part is taken.',
    no_such_part: 'This part is not in the play.',
    line_is_another_part: 'This part is not yours to record.',
    unsupported_audio: 'A take could not be read.',
    audio_mismatch: 'A take could not be read.',
    bleed_flagged: 'A take holds the device voice. Re-take it with headphones.',
    consent_required: 'Agree to the consent before uploading.',
    consent_version_mismatch: 'The consent changed. Read it again.',
    not_your_claim: 'This part is not yours to record.',
    not_your_part: 'Only its performer or the director can open this part.',
    lines_missing: null,
    speaking_part_needs_a_voice: 'A speaking part needs a voice.',
    not_finished: 'This part is not finished.',
    invite_not_found: 'This invite does not work.',
    not_found: 'This production is not shared with you.',
    no_such_take: 'This take is not available.',
    incomplete: 'Every part must be done or left silent first.',
    reported_take: 'A chosen take has been reported.',
    consent_missing: 'Not every performer has agreed to the consent.',
    school_consent_required: 'This class needs its school\'s consent before anyone can join.',
    class_not_found: 'No class has that code.',
    you_teach_this_class: 'You teach this class.',
    revision_mismatch: 'This play has changed since it was cast.',
    not_castable: 'This play cannot be shared.',
    cast_mismatch: 'This play cannot be shared.',
    production_full: 'This production is full.',
    too_many_productions: 'You have too many shared productions.',
    too_many_takes: 'This line has too many takes.',
    take_too_long: 'A take is too long.',
    too_large: 'A take is too long.',
    director_only: 'Only the director can do that.',
    name_too_long: 'That name is too long.',
    name_has_link: 'A name cannot hold a link.',
    name_not_allowed: 'That name is not allowed.',
    name_reserved: 'That name is not allowed.',
    bad_name: 'That name is not allowed.',
    rate_limited: 'Too many tries. Try again in a minute.',
  };
  function line(err) {
    if (!err) return '';
    const code = err.code || '';
    if (code === 'another_part_is_recording') return `${C.partTitle(err.detail)} is still recording.`;
    if (code === 'lines_missing') {
      const n = Array.isArray(err.detail) ? err.detail.length : 0;
      return n === 1 ? '1 line still needs a take.' : `${n} lines still need a take.`;
    }
    if (LINES[code]) return LINES[code];
    if (err.kind === 'rate_limited') return LINES.rate_limited;
    if (err.kind === 'offline') return 'You are offline.';
    if (err.kind === 'not_configured') return 'Not available yet.';
    if (err.kind === 'unauthorized') return 'Sign in again.';
    return 'Ear Drama could not be reached.';
  }

  return {
    PUBLISH_OPEN, canPublish, castSheet, isMine, recordingPart, myParts, uploadsOpen, canClaim, unvoiced, complete, mirror, follow, pending, metaOf,
    upload, mergedChosen, missingHere, inStep, bringHome, share, join, localFor, scriptFor, libraryRows, inviteLink, inviteToken, pendingInvite, holdInvite, line,
  };
})();
