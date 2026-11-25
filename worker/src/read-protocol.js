/**
 * Reading together: the read room's protocol and arbiter (Decision 082,
 * PLAYS-DESIGN §12, research R3c §3.1 and §5.3).
 *
 * PURE. This file imports nothing and touches no network, clock, or store:
 * every function takes `now` and returns a value. Two transports carry it
 * (read-rooms.js): a Durable Object per room over sockets, and D1 polling
 * for a client or a Worker without one. The clients port these rules and are
 * held to them by read-golden.json (AGENTS.md "Shared data": protocol and
 * arbiter with no networking import, each transport a thin adapter).
 *
 * A read room is a place in a script, not a place in an audio file. Its state
 * is the cursor (a line id and a generation), the mode, who leads, and who
 * holds which part. A person always moves the play on: nothing here advances
 * on a timer or by listening to the room, and no audio passes through it.
 *
 * Codes, member keys, the clock and presence come from Listen Together
 * (room-protocol.js) and are copied with their constants, so a code read
 * aloud means the same thing in both (a test checks the two agree).
 *
 * Shapes:
 *   cast    [[lineId, part], ...] in script order (plays-relay.js parseCast)
 *   member  { id, role: "reader" | "screen", seat: string | null, name: string | null, joined_at, seen_at }
 *   room    see newRoom
 */

export const PROTOCOL_VERSION = 1;

export const CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
export const CODE_LENGTH = 6;

/** A class of 30 plus a teacher, an aide and a screen, with room to spare (R3c §5.3). */
export const MAX_MEMBERS = 40;
/** Silent this long and a member has left; a socket's close starts the same clock. */
export const MEMBER_GONE_MS = 2 * 60 * 1000;
/** An adult room's leader gone this long hands the lead to the longest present (Decision 065's rule). */
export const LEADER_GONE_MS = 2 * 60 * 1000;
/** A member silent this long is forgotten (its key stops working) unless it leads, owns, or holds a part. */
export const MEMBER_FORGET_MS = 30 * 60 * 1000;
/** A polled member's read refreshes its presence only when older than this. */
export const SEEN_REFRESH_MS = 20 * 1000;
/** A room with no change for this long is over. */
export const ROOM_IDLE_MS = 6 * 60 * 60 * 1000;
/**
 * The polling transport's least gap between two polls' starts. Each poll is a long poll the room
 * holds until a change or 20 s (read-rooms.js LONG_POLL_MS), so a lit line arrives at once.
 */
export const POLL_MS = 1000;

export const MODES = ["read", "rehearse", "record"];
export const KINDS = ["adult", "class"];
export const ROLES = ["reader", "screen"];
export const MAX_SEATS = 64;

const SEAT_ID = /^[A-Za-z0-9_-]{1,32}$/;
/** An adult reader's own name on join (optional): "Waiting for Ann" (T5). A class's names are its seats. */
export const NAME_MAX = 40;

/**
 * An adult reader's name as given on join: trimmed, at most NAME_MAX, no control
 * characters. Null for none; `false` for a name that is refused. A class room
 * takes no name (its seats are the names the teacher typed). The transport also
 * runs plays-names.js's word filter.
 */
export function cleanName(room, raw) {
  if (raw === undefined || raw === null || (typeof raw === "string" && !raw.trim())) return null;
  if (room.kind === "class") return null;
  if (typeof raw !== "string" || /[\u0000-\u001f\u007f]/.test(raw)) return false;
  const name = raw.trim();
  return name.length > NAME_MAX ? false : name;
}

/** The same normalization on every stack, or a code read aloud reaches different rooms. */
export function normalizeCode(typed) {
  if (typeof typed !== "string") return null;
  let out = "";
  for (const ch of typed.toUpperCase()) {
    if (ch === " " || ch === "-" || ch === "_") continue;
    if (ch === "I" || ch === "L") {
      out += "1";
      continue;
    }
    if (ch === "O") {
      out += "0";
      continue;
    }
    if (!CODE_ALPHABET.includes(ch)) return null;
    out += ch;
  }
  return out.length === CODE_LENGTH ? out : null;
}

/** Bytes from a CSPRNG in, a code out. 256 is a multiple of 32, so `b % 32` is unbiased. */
export function codeFromBytes(bytes) {
  let out = "";
  for (let i = 0; i < CODE_LENGTH; i++) out += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
  return out;
}

/**
 * THE CLOCK (Cristian's algorithm), as room-protocol.js. Each sample is
 * `{ t0, server_time, t1 }`; the smallest round trip wins. The T4 gate
 * (Decision 082) measures cursor delay with this offset on every device.
 */
export function clockOffset(samples) {
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

function partSet(cast) {
  return new Set(cast.map((l) => l[1]));
}

export function liveMembers(members, now) {
  return members.filter((m) => now - m.seen_at <= MEMBER_GONE_MS);
}

function isLive(member, now) {
  return !!member && now - member.seen_at <= MEMBER_GONE_MS;
}

function byJoined(a, b) {
  return a.joined_at - b.joined_at || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
}

function cleanSeats(raw) {
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw) || raw.length > MAX_SEATS) return null;
  const out = [];
  const ids = new Set();
  for (const s of raw) {
    if (!s || typeof s.id !== "string" || !SEAT_ID.test(s.id) || ids.has(s.id)) return null;
    if (typeof s.label !== "string" || s.label.trim().length < 1 || s.label.length > 40 || /[\u0000-\u001f\u007f]/.test(s.label)) return null;
    ids.add(s.id);
    out.push({ id: s.id, label: s.label.trim() });
  }
  return out;
}

/**
 * A class's casting: each assignment gives a part (or a scene range of it,
 * `from` and `to` being line ids of that part) to a seat. Two assignments may
 * not cover the same line.
 */
export function cleanAssignments(raw, cast, seats) {
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw) || raw.length > 500) return null;
  const parts = partSet(cast);
  const seatIds = new Set(seats.map((s) => s.id));
  const out = [];
  const covered = new Set();
  for (const a of raw) {
    if (!a || typeof a.part !== "string" || !parts.has(a.part) || !seatIds.has(a.seat)) return null;
    const from = a.from === undefined || a.from === null ? null : a.from;
    const to = a.to === undefined || a.to === null ? null : a.to;
    const lo = from === null ? 0 : indexOf(cast, from);
    const hi = to === null ? cast.length - 1 : indexOf(cast, to);
    if (lo < 0 || hi < 0 || lo > hi) return null;
    if ((from !== null && cast[lo][1] !== a.part) || (to !== null && cast[hi][1] !== a.part)) return null;
    for (let i = lo; i <= hi; i++) {
      if (cast[i][1] !== a.part) continue;
      if (covered.has(i)) return null;
      covered.add(i);
    }
    out.push({ part: a.part, seat: a.seat, from, to });
  }
  return out;
}

/**
 * A new room. `input` is `{ code, kind, script_id, script_revision, mode?,
 * production_id?, class_id?, seats?, assignments? }`; the transport has
 * already checked the cast against the castable manifest. The creator is the
 * first member, the owner, and the leader.
 */
export function newRoom(input, cast, creatorId, now) {
  if (!input || typeof input !== "object") return { error: "bad_room" };
  const kind = input.kind === undefined ? "adult" : input.kind;
  if (!KINDS.includes(kind)) return { error: "bad_kind" };
  const mode = input.mode === undefined ? "read" : input.mode;
  if (!MODES.includes(mode)) return { error: "bad_mode" };
  if (!Array.isArray(cast) || cast.length < 1) return { error: "bad_cast" };
  const seats = cleanSeats(input.seats);
  if (!seats) return { error: "bad_seats" };
  if (kind === "adult" && (seats.length || input.assignments)) return { error: "adult_rooms_have_no_seats" };
  if (kind === "class" && typeof input.class_id !== "string") return { error: "class_id_required" };
  const assignments = cleanAssignments(input.assignments, cast, seats);
  if (!assignments) return { error: "bad_assignments" };
  return {
    room: {
      v: PROTOCOL_VERSION,
      code: input.code,
      kind,
      script_id: input.script_id,
      script_revision: input.script_revision,
      production_id: typeof input.production_id === "string" ? input.production_id : null,
      class_id: kind === "class" ? input.class_id : null,
      mode,
      cursor: cast[0][0],
      cursor_gen: 0,
      generation: 1,
      owner: creatorId,
      leader: creatorId,
      locked: false,
      read_open: false,
      owner_name: typeof input.owner_name === "string" && input.owner_name.trim() ? input.owner_name.trim().slice(0, 40) : null,
      claims: {},
      seats,
      assignments,
      done: [],
      ended: false,
      created_at: now,
      touched_at: now,
    },
  };
}

/** Only the leader moves the cursor, changes the mode, or calls Again. */
export function canLead(room, memberId) {
  return !!memberId && room.leader === memberId;
}

/** What a member holds: an adult's claimed parts, or a seat's assignments (with ranges). */
export function partsOf(room, member) {
  if (!member) return [];
  if (room.kind === "class") {
    if (!member.seat) return [];
    return room.assignments.filter((a) => a.seat === member.seat).map((a) => ({ part: a.part, from: a.from, to: a.to }));
  }
  return Object.keys(room.claims)
    .filter((p) => room.claims[p] === member.id)
    .sort()
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

/**
 * Who reads a line: its part, the seat it is assigned to (class), and the
 * present members holding it. Null for a line not in the script.
 */
export function whoReads(room, cast, members, lineId, now) {
  const i = indexOf(cast, lineId);
  if (i < 0) return null;
  const part = cast[i][1];
  if (room.kind === "class") {
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
  if (room.kind === "class") {
    const a = assignmentFor(room, cast, i);
    return !!a && !!member.seat && a.seat === member.seat;
  }
  return room.claims[cast[i][1]] === member.id;
}

function held(room, cast, i) {
  return room.kind === "class" ? !!assignmentFor(room, cast, i) : !!room.claims[cast[i][1]];
}

/**
 * A member's next line at or after the cursor: `{ line, in }`, `in` being how
 * many lines away it is (0: it is the line now). Null when none is left.
 */
export function nextMine(room, cast, member, cursor) {
  const start = Math.max(0, indexOf(cast, cursor));
  for (let i = start; i < cast.length; i++) {
    if (holds(room, cast, member, i)) return { line: cast[i][0], in: i - start };
  }
  return null;
}

/**
 * LEADER GONE. A class room holds still for its leader (the teacher or the
 * seat they chose), never passing the lead to a random student. An adult
 * room hands the lead, once the leader has been gone LEADER_GONE_MS, to the
 * reader present longest (ties by id), as Listen Together's host does.
 * Returns `{ leader, waiting }`.
 */
export function leaderGone(room, members, now) {
  const leader = members.find((m) => m.id === room.leader);
  if (leader && now - leader.seen_at <= LEADER_GONE_MS) return { leader: room.leader, waiting: false };
  if (room.kind === "class") return { leader: room.leader, waiting: true };
  const next = liveMembers(members, now)
    .filter((m) => m.id !== room.leader && m.role === "reader")
    .sort(byJoined);
  return next.length ? { leader: next[0].id, waiting: false } : { leader: room.leader, waiting: true };
}

/**
 * CLAIMS. In an adult room the first claim of a part wins and the arbiter is
 * the server: a part someone holds answers `part_taken` with who holds it.
 * In a class room parts come only from the teacher's assignments.
 */
export function claimInRoom(room, cast, member, part) {
  if (room.kind === "class") return { error: "class_assignments_only" };
  if (!member || member.role !== "reader") return { error: "readers_only" };
  if (typeof part !== "string" || !partSet(cast).has(part)) return { error: "no_such_part" };
  const holder = room.claims[part];
  if (holder && holder !== member.id) return { error: "part_taken", detail: holder };
  if (holder === member.id) return { room, changed: false };
  return { room: { ...room, claims: { ...room.claims, [part]: member.id } }, changed: true };
}

/** Whether a new member may join: a refusal string or null. */
export function joinRefusal(room, members, want, now) {
  if (room.ended) return "room_ended";
  if (liveMembers(members, now).length >= MAX_MEMBERS) return "room_full";
  const role = want && want.role !== undefined ? want.role : "reader";
  if (!ROLES.includes(role)) return "bad_role";
  // A screen the leader paired (T5) was let in by the leader's own act, so a lock does not hold it out.
  if (room.locked && !(role === "screen" && want.paired === true)) return "joining_locked";
  const seat = want && want.seat !== undefined && want.seat !== null ? want.seat : null;
  if (room.kind === "adult" && seat !== null) return "adult_rooms_have_no_seats";
  if (room.kind === "class" && role === "reader" && !room.seats.some((s) => s.id === seat)) return "seat_required";
  if (role === "screen" && seat !== null) return "screens_hold_no_seat";
  return null;
}

/**
 * THE CURSOR. The leader proposes a line; `base` is the cursor generation the
 * leader last saw. A move from the current generation applies and bumps it.
 * A move whose line is already the cursor is a repeat (a retried Next) and
 * changes nothing. Any other move from an old generation is `stale`: the
 * leader's device resyncs from the snapshot rather than jumping the room.
 */
export function applyCursor(room, cast, memberId, msg, now) {
  if (!canLead(room, memberId)) return { error: "leader_only" };
  if (!msg || typeof msg.line !== "string" || indexOf(cast, msg.line) < 0) return { error: "no_such_line" };
  if (msg.line === room.cursor) return { room, changed: false };
  if (msg.base !== room.cursor_gen) return { error: "stale", detail: room.cursor_gen };
  return {
    room: { ...room, cursor: msg.line, cursor_gen: room.cursor_gen + 1, generation: room.generation + 1, touched_at: now },
    changed: true,
  };
}

/**
 * RECORD MODE: the reader whose line it is ends it (their take ended on its
 * silence or their tap). The line is marked done and the cursor moves to the
 * next line someone holds; lines nobody holds are skipped and stay open.
 * A take that ends after the leader moved the cursor away still made a take:
 * its line is marked done and the cursor stays where the leader put it, so
 * the line does not open a microphone again when the cursor comes back (T7c:
 * the leader's press racing a take reopened the line, two takes of one line).
 * The leader's Again reopens a done line on purpose.
 */
function lineDone(room, cast, members, member, msg, now) {
  if (room.mode !== "record") return { error: "not_recording" };
  const i = msg ? indexOf(cast, msg.line) : -1;
  if (i < 0) return { error: "no_such_line" };
  if (!holds(room, cast, member, i)) return { error: "not_your_line" };
  if (msg.line !== room.cursor) {
    if (room.done.includes(msg.line)) return { room, changed: false };
    return { room: { ...room, done: [...room.done, msg.line], generation: room.generation + 1, touched_at: now }, changed: true };
  }
  if (msg.base !== room.cursor_gen) return { error: "stale", detail: room.cursor_gen };
  let next = i;
  for (let j = i + 1; j < cast.length; j++) {
    if (held(room, cast, j)) {
      next = j;
      break;
    }
  }
  const done = room.done.includes(msg.line) ? room.done : [...room.done, msg.line];
  const moved = next !== i;
  return {
    room: {
      ...room,
      done,
      cursor: cast[next][0],
      cursor_gen: moved ? room.cursor_gen + 1 : room.cursor_gen,
      generation: room.generation + 1,
      touched_at: now,
    },
    changed: true,
  };
}

function again(room, cast, memberId, msg, now) {
  if (!canLead(room, memberId)) return { error: "leader_only" };
  if (room.mode !== "record") return { error: "not_recording" };
  if (!msg || indexOf(cast, msg.line) < 0) return { error: "no_such_line" };
  if (msg.line === room.cursor && !room.done.includes(msg.line)) return { room, changed: false };
  if (msg.base !== room.cursor_gen) return { error: "stale", detail: room.cursor_gen };
  const moved = msg.line !== room.cursor;
  return {
    room: {
      ...room,
      done: room.done.filter((l) => l !== msg.line),
      cursor: msg.line,
      cursor_gen: moved ? room.cursor_gen + 1 : room.cursor_gen,
      generation: room.generation + 1,
      touched_at: now,
    },
    changed: true,
  };
}

/** Handing the lead: the leader or the owner may; class rooms hand only to the owner or a seat. */
function lead(room, members, memberId, msg, now) {
  if (memberId !== room.leader && memberId !== room.owner) return { error: "leader_only" };
  const to = members.find((m) => m.id === (msg && msg.to));
  if (!to || !isLive(to, now)) return { error: "no_such_member" };
  if (to.role === "screen") return { error: "screens_do_not_lead" };
  if (room.kind === "class" && to.id !== room.owner && !to.seat) return { error: "class_leads_are_seats" };
  if (to.id === room.leader) return { room, changed: false };
  return { room: { ...room, leader: to.id, generation: room.generation + 1, touched_at: now }, changed: true };
}

/**
 * Two devices on one seat: the second is refused with `seat_in_use` unless it
 * asks to move, and then the first device leaves the seat.
 */
export function takeSeat(room, members, memberId, seat, move, now) {
  if (room.kind !== "class") return { error: "adult_rooms_have_no_seats" };
  if (!room.seats.some((s) => s.id === seat)) return { error: "no_such_seat" };
  const me = members.find((m) => m.id === memberId);
  if (!me || me.role !== "reader") return { error: "readers_only" };
  const other = liveMembers(members, now).find((m) => m.seat === seat && m.id !== memberId);
  if (other && !move) return { error: "seat_in_use" };
  return {
    members: members.map((m) => (m.id === memberId ? { ...m, seat } : m.seat === seat ? { ...m, seat: null } : m)),
    changed: true,
  };
}

/**
 * A member out of the room: their row and so their key, and the parts they claimed, which open again. A class's
 * lead comes back to its teacher; an adult room's passes on in `settle`.
 */
function without(room, members, id, now) {
  const claims = Object.fromEntries(Object.entries(room.claims).filter(([, holder]) => holder !== id));
  const leader = room.kind === "class" && room.leader === id ? room.owner : room.leader;
  return {
    room: { ...room, claims, leader, generation: room.generation + 1, touched_at: now },
    members: members.filter((m) => m.id !== id),
    changed: true,
  };
}

/** Whether a member may remove another: an adult room's leader or opener; in a class only its teacher, never a student who leads. */
export function canRemove(room, memberId) {
  if (!memberId) return false;
  return memberId === room.owner || (room.kind === "adult" && memberId === room.leader);
}

/**
 * REMOVE (App Store guideline 1.2; PLAYS-DESIGN §12.13). The removed member's key stops working at once and joining
 * locks: the code is still on their screen, so a removal that left the door open would keep nobody out.
 */
function remove(room, members, memberId, msg, now) {
  if (!canRemove(room, memberId)) return { error: "leader_only" };
  const id = msg.member;
  if (id === memberId || id === room.owner || !members.some((m) => m.id === id)) return { error: "no_such_member" };
  const out = without(room, members, id, now);
  return { ...out, room: { ...out.room, leader: out.room.leader === id ? memberId : out.room.leader, locked: true } };
}

/** LEAVE. A class's teacher keeps their place (the room holds still for them); a room its last reader leaves is over. */
function leave(room, members, memberId, now) {
  if (room.kind === "class" && memberId === room.owner) return { room, changed: false };
  const out = without(room, members, memberId, now);
  return out.members.some((m) => m.role === "reader") ? out : { ...out, room: { ...out.room, ended: true } };
}

/**
 * THE ARBITER. One message from one member; returns the next room and members,
 * a reply for the sender when there is one, or a refusal. The transports
 * persist what comes back and send each member its snapshot when `changed`.
 */
export function applyMessage(world, memberId, msg, now) {
  const { room, cast, members } = world;
  if (room.ended) return { error: "room_ended" };
  const me = members.find((m) => m.id === memberId);
  if (!me) return { error: "not_a_member" };
  if (!msg || typeof msg !== "object" || typeof msg.type !== "string") return { error: "bad_message" };
  const seen = members.map((m) => (m.id === memberId ? { ...m, seen_at: now } : m));
  const out = (r) => (r.error ? r : { room: r.room || room, members: r.members || seen, changed: !!r.changed, reply: r.reply });

  switch (msg.type) {
    case "ping":
      return out({ reply: { type: "pong", t0: msg.t0, server_time: now } });
    case "cursor":
      return out(applyCursor(room, cast, memberId, msg, now));
    case "line-done":
      return out(lineDone(room, cast, seen, me, msg, now));
    case "again":
      return out(again(room, cast, memberId, msg, now));
    case "mode":
      if (!canLead(room, memberId)) return { error: "leader_only" };
      if (!MODES.includes(msg.mode)) return { error: "bad_mode" };
      if (msg.mode === room.mode) return out({});
      return out({ room: { ...room, mode: msg.mode, generation: room.generation + 1, touched_at: now }, changed: true });
    case "claim":
      return out(claimInRoom(room, cast, me, msg.part));
    case "release": {
      if (room.claims[msg.part] !== memberId) return { error: "not_your_part" };
      const claims = { ...room.claims };
      delete claims[msg.part];
      return out({ room: { ...room, claims, generation: room.generation + 1, touched_at: now }, changed: true });
    }
    case "lead":
      return out(lead(room, seen, memberId, msg, now));
    case "lock":
      if (memberId !== room.leader && memberId !== room.owner) return { error: "leader_only" };
      if (typeof msg.locked !== "boolean") return { error: "bad_message" };
      if (msg.locked === room.locked) return out({});
      return out({ room: { ...room, locked: msg.locked, generation: room.generation + 1, touched_at: now }, changed: true });
    case "seat": {
      const r = takeSeat(room, seen, memberId, msg.seat, msg.move === true, now);
      if (r.error) return r;
      return out({ room: { ...room, generation: room.generation + 1, touched_at: now }, members: r.members, changed: true });
    }
    case "remove":
      return out(remove(room, seen, memberId, msg, now));
    case "leave":
      return out(leave(room, seen, memberId, now));
    case "read-open":
      if (!canLead(room, memberId)) return { error: "leader_only" };
      if (typeof msg.open !== "boolean") return { error: "bad_message" };
      if (msg.open === room.read_open) return out({});
      return out({ room: { ...room, read_open: msg.open, generation: room.generation + 1, touched_at: now }, changed: true });
    case "end":
      if (memberId !== room.leader && memberId !== room.owner) return { error: "leader_only" };
      return out({ room: { ...room, ended: true, generation: room.generation + 1, touched_at: now }, changed: true });
    default:
      return { error: "bad_message" };
  }
}

/**
 * Presence and the leader, settled at `now`: an adult room's lead moves when
 * its leader has been gone long enough. A device that dropped keeps its place
 * (and its key rejoins) for MEMBER_FORGET_MS, longer while it holds a part;
 * a class seat stays assigned in the room whichever device holds it.
 */
export function settle(room, members, now) {
  const g = leaderGone(room, members, now);
  const claimed = new Set(Object.values(room.claims));
  const keep = members.filter(
    (m) => now - m.seen_at <= MEMBER_FORGET_MS || m.id === g.leader || m.id === room.owner || claimed.has(m.id),
  );
  const changed = g.leader !== room.leader || keep.length !== members.length;
  const next = g.leader !== room.leader ? { ...room, leader: g.leader, generation: room.generation + 1 } : room;
  return { room: next, members: keep, waiting: g.waiting, changed };
}

export function roomExpired(room, now) {
  return now - room.touched_at > ROOM_IDLE_MS;
}

/**
 * The message every member reads: the room in public form and the member's
 * own place in it. No key and no key hash, ever. A late joiner reads the
 * same snapshot: the cursor, their parts, their next line.
 */
/** Whoever leads, by the name the room knows: a seat's label, the owner's own name, or the name an adult gave on join; else null. */
export function leaderName(room, members) {
  const lead = members.find((m) => m.id === room.leader);
  const seat = lead && lead.seat ? room.seats.find((s) => s.id === lead.seat) : null;
  if (seat) return seat.label;
  if (room.leader === room.owner && room.owner_name) return room.owner_name;
  return (lead && lead.name) || null;
}

/**
 * RECORD IN THE ROOM (T5, PLAYS-DESIGN §12.3 mode 3). Whose device receives the
 * room's takes: a class's teacher (the owner) whoever leads, since a seat that
 * leads is a student director and the takes are the teacher's (§12.4); an adult
 * room's leader. A take passes through the Worker to this device and is kept
 * nowhere on the way (§12.5).
 */
export function receiverOf(room) {
  return room.kind === "class" ? room.owner : room.leader;
}

/**
 * Whether a member may send a take of a line now: a refusal string or null.
 * Only in Record mode, only a reader, and only a line they hold (an adult's
 * claimed part, a seat's assignment with its range). Any held line, not only
 * the cursor's: a line passed while a device was away records later (§12.6).
 * The receiver's own device records into itself and sends nothing.
 */
export function recordRefusal(room, cast, member, lineId) {
  if (room.ended) return "room_ended";
  if (room.mode !== "record") return "not_recording";
  if (!member || member.role !== "reader") return "readers_only";
  const i = indexOf(cast, lineId);
  if (i < 0) return "no_such_line";
  if (member.id === receiverOf(room)) return "receiver_records_here";
  if (!holds(room, cast, member, i)) return "not_your_line";
  return null;
}

export function joinSnapshot(room, cast, members, memberId, now) {
  const me = members.find((m) => m.id === memberId) || null;
  const live = liveMembers(members, now);
  return {
    v: PROTOCOL_VERSION,
    type: "snapshot",
    code: room.code,
    kind: room.kind,
    mode: room.mode,
    script_id: room.script_id,
    script_revision: room.script_revision,
    production_id: room.production_id,
    class_id: room.class_id,
    cursor: room.cursor,
    cursor_gen: room.cursor_gen,
    generation: room.generation,
    locked: room.locked,
    ended: room.ended,
    leader: room.leader,
    leader_name: leaderName(room, members),
    read_open: !!room.read_open,
    waiting_for_leader: leaderGone(room, members, now).waiting,
    you: me
      ? { id: me.id, role: me.role, seat: me.seat, name: me.name || null, leads: canLead(room, me.id), owner: room.owner === me.id, receives: receiverOf(room) === me.id, parts: partsOf(room, me) }
      : null,
    next_mine: me ? nextMine(room, cast, me, room.cursor) : null,
    reads_now: whoReads(room, cast, members, room.cursor, now),
    members: members.map((m) => ({ id: m.id, role: m.role, seat: m.seat, name: m.name || null, live: live.includes(m) })),
    receiver: receiverOf(room),
    present: live.length,
    claims: room.claims,
    seats: room.seats,
    assignments: room.assignments,
    done: room.done,
    server_time: now,
  };
}
