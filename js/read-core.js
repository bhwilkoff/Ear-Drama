/**
 * Reading together on the web (WEB-DESIGN §4.17, PLAYS-DESIGN §12): a PORT of the client side of
 * worker/src/read-protocol.js, not a re-derivation. Codes, the clock, who holds a line, a member's
 * next line, and the leader-gone rule are the protocol's own; js/read.test.js golden-checks each
 * against worker/test/read-golden.json, the file every client port reads, so they cannot drift.
 *
 * Also the casting board's arithmetic (PLAYS-DESIGN §12.4): facts per part, totals per seat,
 * Fill evenly and Split by scene, each a deterministic proposal the teacher accepts or edits.
 * The app never suggests who should read what.
 *
 * Pure: no network, no clock, no DOM. Every function takes its inputs.
 * Shapes: cast is [[lineId, part], ...] in script order; a room is the protocol's room (or one
 * rebuilt from a snapshot by roomOf).
 */
const ReadCore = (() => {
  'use strict';

  const PROTOCOL_VERSION = 1;
  const CODE_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  const CODE_LENGTH = 6;
  const MAX_MEMBERS = 40;
  const MEMBER_GONE_MS = 2 * 60 * 1000;
  const LEADER_GONE_MS = 2 * 60 * 1000;
  const POLL_MS = 1000;
  const MODES = ['read', 'rehearse', 'record'];
  /** PLAYS-DESIGN §12.6: a polled cursor slower than this shows "Slow connection" (a warning). */
  const SLOW_MS = 2000;

  function normalizeCode(typed) {
    if (typeof typed !== 'string') return null;
    let out = '';
    for (const ch of typed.toUpperCase()) {
      if (ch === ' ' || ch === '-' || ch === '_') continue;
      if (ch === 'I' || ch === 'L') { out += '1'; continue; }
      if (ch === 'O') { out += '0'; continue; }
      if (!CODE_ALPHABET.includes(ch)) return null;
      out += ch;
    }
    return out.length === CODE_LENGTH ? out : null;
  }

  function codeFromBytes(bytes) {
    let out = '';
    for (let i = 0; i < CODE_LENGTH; i++) out += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
    return out;
  }

  /** Cristian's algorithm: the sample with the smallest round trip wins, never an average. */
  function clockOffset(samples) {
    let best = null;
    for (const s of samples) {
      const rtt = s.t1 - s.t0;
      if (!(rtt >= 0)) continue;
      if (!best || rtt < best.rtt) best = { rtt, offset: s.server_time - (s.t0 + s.t1) / 2 };
    }
    return best ? best.offset : null;
  }

  function indexOf(cast, lineId) {
    for (let i = 0; i < cast.length; i++) if (cast[i][0] === lineId) return i;
    return -1;
  }

  const liveMembers = (members, now) => members.filter((m) => now - m.seen_at <= MEMBER_GONE_MS);
  const isLive = (m, now) => !!m && now - m.seen_at <= MEMBER_GONE_MS;
  const byJoined = (a, b) => a.joined_at - b.joined_at || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

  function canLead(room, memberId) { return !!memberId && room.leader === memberId; }

  function partsOf(room, member) {
    if (!member) return [];
    if (room.kind === 'class') {
      if (!member.seat) return [];
      return room.assignments.filter((a) => a.seat === member.seat).map((a) => ({ part: a.part, from: a.from, to: a.to }));
    }
    return Object.keys(room.claims).filter((p) => room.claims[p] === member.id).sort()
      .map((part) => ({ part, from: null, to: null }));
  }

  function assignmentFor(room, cast, i) {
    const part = cast[i][1];
    for (const a of room.assignments) {
      if (a.part !== part) continue;
      const lo = a.from === null ? 0 : indexOf(cast, a.from);
      const hi = a.to === null ? cast.length - 1 : indexOf(cast, a.to);
      if (i >= lo && i <= hi) return a;
    }
    return null;
  }

  function whoReads(room, cast, members, lineId, now) {
    const i = indexOf(cast, lineId);
    if (i < 0) return null;
    const part = cast[i][1];
    if (room.kind === 'class') {
      const a = assignmentFor(room, cast, i);
      const seat = a ? a.seat : null;
      const ids = seat ? liveMembers(members, now).filter((m) => m.seat === seat).map((m) => m.id) : [];
      return { part, seat, members: ids };
    }
    const holder = room.claims[part] || null;
    const ids = holder && isLive(members.find((m) => m.id === holder), now) ? [holder] : [];
    return { part, seat: null, holder, members: ids };
  }

  function holds(room, cast, member, i) {
    if (!member) return false;
    if (room.kind === 'class') {
      const a = assignmentFor(room, cast, i);
      return !!a && !!member.seat && a.seat === member.seat;
    }
    return room.claims[cast[i][1]] === member.id;
  }

  function nextMine(room, cast, member, cursor) {
    const start = Math.max(0, indexOf(cast, cursor));
    for (let i = start; i < cast.length; i++) {
      if (holds(room, cast, member, i)) return { line: cast[i][0], in: i - start };
    }
    return null;
  }

  /* ---- T5: names, the receiver, Record in the room (the protocol's own, golden-checked) ---- */

  const NAME_MAX = 40;
  /** An adult's name on join: trimmed, at most 40, no control characters; null for none, false refused. */
  function cleanName(room, raw) {
    if (raw === undefined || raw === null || (typeof raw === 'string' && !raw.trim())) return null;
    if (room.kind === 'class') return null;
    if (typeof raw !== 'string' || /[\u0000-\u001f\u007f]/.test(raw)) return false;
    const name = raw.trim();
    return name.length > NAME_MAX ? false : name;
  }

  /** Whose device receives the room's takes: a class's teacher whoever leads, an adult room's leader. */
  function receiverOf(room) { return room.kind === 'class' ? room.owner : room.leader; }

  /** Whether a member may send a take of a line: a refusal code or null (any held line, in Record mode). */
  function recordRefusal(room, cast, member, lineId) {
    if (room.ended) return 'room_ended';
    if (room.mode !== 'record') return 'not_recording';
    if (!member || member.role !== 'reader') return 'readers_only';
    const i = indexOf(cast, lineId);
    if (i < 0) return 'no_such_line';
    if (member.id === receiverOf(room)) return 'receiver_records_here';
    if (!holds(room, cast, member, i)) return 'not_your_line';
    return null;
  }

  function leaderName(room, members) {
    const lead = members.find((m) => m.id === room.leader);
    const seat = lead && lead.seat ? room.seats.find((s) => s.id === lead.seat) : null;
    if (seat) return seat.label;
    if (room.leader === room.owner && room.owner_name) return room.owner_name;
    return (lead && lead.name) || null;
  }

  function leaderGone(room, members, now) {
    const leader = members.find((m) => m.id === room.leader);
    if (leader && now - leader.seen_at <= LEADER_GONE_MS) return { leader: room.leader, waiting: false };
    if (room.kind === 'class') return { leader: room.leader, waiting: true };
    const next = liveMembers(members, now).filter((m) => m.id !== room.leader && m.role === 'reader').sort(byJoined);
    return next.length ? { leader: next[0].id, waiting: false } : { leader: room.leader, waiting: true };
  }

  /* ---- The client's own rules over a snapshot ---- */

  /** The room as the protocol's functions read it, rebuilt from a snapshot (no keys ever travel). */
  function roomOf(snap) {
    return {
      kind: snap.kind, mode: snap.mode, cursor: snap.cursor, cursor_gen: snap.cursor_gen, generation: snap.generation,
      leader: snap.leader, claims: snap.claims || {}, seats: snap.seats || [], assignments: snap.assignments || [],
      done: snap.done || [], locked: !!snap.locked, ended: !!snap.ended,
      owner: snap.receiver && snap.kind === 'class' ? snap.receiver : undefined,
    };
  }

  /** A snapshot replaces the one in hand only when it is as new or newer (a slow poll never rewinds the cursor). */
  function newer(prev, snap) {
    if (!snap || snap.type !== 'snapshot') return false;
    if (!prev || prev.code !== snap.code) return true;
    return snap.generation > prev.generation
      || (snap.generation === prev.generation && (snap.server_time || 0) >= (prev.server_time || 0));
  }

  /** The cast sheet a room checks, from a script's cast sheet ([{ id, part }]). */
  const castOf = (sheet) => sheet.map((l) => [l.id, l.part]);

  /** Every line index the member reads (their parts, or their seat's ranges). */
  function mineIndexes(room, cast, member) {
    const out = [];
    for (let i = 0; i < cast.length; i++) if (holds(room, cast, member, i)) out.push(i);
    return out;
  }

  /** The leader's Next and Back: the line after or before the cursor, or null at either end. */
  function step(cast, cursor, delta) {
    const i = indexOf(cast, cursor);
    const j = i + delta;
    return i < 0 || j < 0 || j >= cast.length ? null : cast[j][0];
  }

  /** Rehearse's Again: the start of the scene the cursor is in (`starts` are scene heading indexes). */
  function sceneStart(cast, cursor, starts) {
    const i = Math.max(0, indexOf(cast, cursor));
    let at = 0;
    for (const s of starts) if (s <= i && s >= at) at = s;
    return cast[at] ? cast[at][0] : null;
  }

  /**
   * "Next: you, in 3 lines" (a fact): what a reader's own device says about their next line.
   * Null when nothing of theirs is left.
   */
  function nextLine(next) {
    if (!next) return null;
    if (next.in === 0) return 'Your line';
    return next.in === 1 ? 'Next: you, in 1 line' : `Next: you, in ${next.in} lines`;
  }

  /** The label of whoever a class room waits for, or null for "the teacher" (the owner leads). */
  function waitingFor(snap) {
    if (snap.leader_name) return snap.leader_name;
    const m = (snap.members || []).find((x) => x.id === snap.leader);
    const seat = m && m.seat ? (snap.seats || []).find((s) => s.id === m.seat) : null;
    return seat ? seat.label : null;
  }

  /** Who reads a line, by name: a seat's label, or the name an adult gave; null when nobody named holds it. */
  function readerName(snap, reads) {
    if (!reads) return null;
    if (reads.seat) { const s = (snap.seats || []).find((x) => x.id === reads.seat); return s ? s.label : null; }
    const id = reads.holder || (reads.members && reads.members[0]);
    const m = id && (snap.members || []).find((x) => x.id === id);
    return (m && m.name) || null;
  }

  /**
   * Record in the room (PLAYS-DESIGN §12.10 item 1): whether this device opens its microphone now.
   * Only in Record mode, on a line this member holds that is at the cursor and not done, never on the
   * receiving device (it records only in One microphone), and not twice for the same arming:
   * `justDid` is the line this device last recorded, cleared once the room marks it done or moves on.
   */
  function shouldRecord(snap, cast, justDid) {
    if (!snap || snap.ended || snap.mode !== 'record' || !snap.you || snap.you.role !== 'reader') return false;
    if (snap.you.receives) return false;
    const room = roomOf(snap);
    const i = indexOf(cast, snap.cursor);
    if (i < 0 || !holds(room, cast, snap.you, i)) return false;
    if ((snap.done || []).includes(snap.cursor)) return false;
    return justDid !== snap.cursor;
  }

  /** `justDid` after a snapshot: kept while the line stays at the cursor and undone, else cleared. */
  function settleJustDid(snap, justDid) {
    if (!justDid || !snap) return justDid;
    if (snap.cursor !== justDid || (snap.done || []).includes(justDid)) return null;
    return justDid;
  }

  /**
   * The receiver's Takes sheet (item 4): each speaking line in script order with its state, and the
   * counts per reader. `arrived` is a Set of line ids with a take on this device; `speaking(part)`
   * says which parts speak. States: recorded, away (done, the take not here), waiting, open.
   */
  function takeRows(snap, cast, arrived, speaking) {
    const room = roomOf(snap);
    const done = new Set(snap.done || []);
    const rows = [];
    const counts = new Map();
    for (let i = 0; i < cast.length; i++) {
      const [line, part] = cast[i];
      if (!speaking(part)) continue;
      const who = whoReads(room, cast, (snap.members || []).map((m) => ({ ...m, seen_at: m.live ? 0 : -Infinity })), line, 0);
      const key = room.kind === 'class' ? (who.seat ? `seat:${who.seat}` : null) : (who.holder ? `member:${who.holder}` : null);
      const state = arrived.has(line) ? 'recorded' : done.has(line) ? 'away' : key ? 'waiting' : 'open';
      rows.push({ line, part, state, seat: who.seat || null, holder: who.holder || null });
      if (key) {
        const c = counts.get(key) || { key, seat: who.seat || null, holder: who.holder || null, lines: 0, recorded: 0 };
        c.lines += 1;
        if (state === 'recorded') c.recorded += 1;
        counts.set(key, c);
      }
    }
    return { rows, counts: [...counts.values()] };
  }

  /** The refusal words for a Worker code (PLAYS-DESIGN §12.6); one line under the action, never an explanation. */
  const REFUSALS = {
    bad_code: 'That is not a reading code.',
    no_such_room: 'No reading with that code.',
    room_ended: 'This reading has ended.',
    room_full: 'This reading is full.',
    joining_locked: 'Joining is locked.',
    seat_in_use: 'Someone is already in on another device.',
    seat_key_required: 'Pick your name again.',
    seat_required: 'Pick your name.',
    part_taken: 'Someone holds that part.',
    leader_only: 'Only the leader moves the reading.',
    stale: 'The reading moved on.',
    rate_limited: 'Too many tries. Try again in a minute.',
    offline: 'You are offline.',
    not_configured: 'Not available yet.',
    class_not_found: 'No class has that code.',
    revision_mismatch: 'This play has changed since it was cast.',
    not_castable: 'This play cannot be read together.',
    bad_name: 'That name is not allowed.',
    no_such_pair: 'No screen shows that code.',
    pair_expired: 'That code has expired.',
    not_recording: 'The reading is not recording.',
    not_your_line: 'That line is someone else\'s.',
    school_consent_required: 'Waits for the school\'s consent.',
  };
  const refusal = (code) => REFUSALS[code] || 'Ear Drama could not be reached.';

  /* ---- The casting board (PLAYS-DESIGN §12.4) ---- */

  /**
   * Facts from the script per part: lines, words, scenes it speaks in, its longest speech in words.
   * `words[i]` is line i's word count; `starts` are the scene heading indexes.
   */
  function partFacts(cast, words, starts) {
    const sceneOf = (i) => { let s = -1; for (const k of starts) if (k <= i) s = k; return s; };
    const by = new Map();
    cast.forEach(([, part], i) => {
      const f = by.get(part) || { part, lines: 0, words: 0, scenes: new Set(), longest: 0, first: i };
      f.lines += 1;
      f.words += words[i] || 0;
      f.longest = Math.max(f.longest, words[i] || 0);
      f.scenes.add(sceneOf(i));
      by.set(part, f);
    });
    return [...by.values()].map((f) => ({ part: f.part, lines: f.lines, words: f.words, scenes: f.scenes.size, longest: f.longest, first: f.first }));
  }

  /** Lines and words per seat under a casting (a range counts only its own lines). */
  function seatTotals(cast, words, assignments, seats) {
    const room = { kind: 'class', assignments: assignments.map((a) => ({ from: null, to: null, ...a })) };
    const out = new Map(seats.map((s) => [s.id, { seat: s.id, lines: 0, words: 0 }]));
    for (let i = 0; i < cast.length; i++) {
      const a = assignmentFor(room, cast, i);
      const t = a && out.get(a.seat);
      if (t) { t.lines += 1; t.words += words[i] || 0; }
    }
    return [...out.values()];
  }

  /**
   * Fill evenly: every part nobody holds yet goes, largest by words first, to the seat with the
   * fewest words so far (ties: fewest lines, then the roster's order). `parts` are partFacts rows
   * of the parts to cast; the casting already made is kept. Deterministic, and only a proposal.
   */
  function fillEvenly(parts, seats, assignments, cast, words) {
    if (!seats.length) return assignments.slice();
    const held = new Set(assignments.map((a) => a.part));
    const totals = new Map(seatTotals(cast, words, assignments, seats).map((t) => [t.seat, t]));
    const order = new Map(seats.map((s, i) => [s.id, i]));
    const out = assignments.slice();
    const open = parts.filter((p) => !held.has(p.part))
      .sort((a, b) => b.words - a.words || b.lines - a.lines || a.first - b.first);
    for (const p of open) {
      const seat = seats.map((s) => totals.get(s.id))
        .sort((a, b) => a.words - b.words || a.lines - b.lines || order.get(a.seat) - order.get(b.seat))[0];
      out.push({ part: p.part, seat: seat.seat, from: null, to: null });
      seat.words += p.words;
      seat.lines += p.lines;
    }
    return out;
  }

  /**
   * Split by scene: a part's lines grouped at scene boundaries, as ranges `{ from, to, lines }` of
   * line ids of that part, in script order. The teacher gives each range a seat.
   */
  function sceneRanges(cast, part, starts) {
    const out = [];
    let cur = null;
    let scene = null;
    for (let i = 0; i < cast.length; i++) {
      const s = starts.filter((k) => k <= i).pop();
      if (cast[i][1] !== part) continue;
      if (!cur || s !== scene) { cur = { from: cast[i][0], to: cast[i][0], lines: 0, scene: s === undefined ? -1 : s }; out.push(cur); scene = s; }
      cur.to = cast[i][0];
      cur.lines += 1;
    }
    return out;
  }

  /** The casting the Worker takes: a whole part as `{ part, seat }`, a range with its `from` and `to`. */
  function toWire(assignments) {
    return assignments.map((a) => (a.from || a.to ? { part: a.part, seat: a.seat, from: a.from, to: a.to } : { part: a.part, seat: a.seat }));
  }

  return {
    PROTOCOL_VERSION, CODE_ALPHABET, CODE_LENGTH, MAX_MEMBERS, MEMBER_GONE_MS, LEADER_GONE_MS, POLL_MS, MODES, SLOW_MS,
    normalizeCode, codeFromBytes, clockOffset, canLead, partsOf, whoReads, nextMine, leaderGone, liveMembers,
    NAME_MAX, cleanName, receiverOf, recordRefusal, leaderName, readerName, shouldRecord, settleJustDid, takeRows,
    roomOf, newer, castOf, mineIndexes, step, sceneStart, nextLine, waitingFor, refusal,
    partFacts, seatTotals, fillEvenly, sceneRanges, toWire,
  };
})();
if (typeof module !== 'undefined') module.exports = ReadCore;
