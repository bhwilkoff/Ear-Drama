/**
 * Read rooms over two transports (Decision 082, PLAYS-DESIGN §12).
 *
 * Every rule lives in read-protocol.js. This file carries it:
 *
 * - `ReadRoom`, a Durable Object per room (SQLite-backed, on the free plan),
 *   holding the room in memory and its members' sockets through the
 *   hibernation API. A cursor move is one message in and one snapshot out per
 *   member: one round trip, no polling, and presence costs no D1 write.
 *   The same object answers HTTP polls, so a TV browser or a network that
 *   blocks WebSockets joins the same room with the same messages.
 * - D1 polling (`read_rooms`), the fallback when the Worker has no Durable
 *   Object binding: the same routes and messages, one row per room.
 *
 * NO AUDIO. A read room carries a place in a script and who holds what. Takes
 * pass through the Worker to the leader's device and are deleted on arrival
 * (T2), never stored in the object, D1, or KV (owner ruling 2026-11-19:
 * "We are using archive.org for storage, not cloudflare.").
 *
 * NO ACCOUNT to read. A member is a random id and a random key, returned
 * once, stored only as its SHA-256 (Listen Together's pattern, rooms.js). A
 * class room is opened by its teacher's account; its seats are the class's
 * roster and its casting the class production's assignments, both read from
 * D1 when the room opens, never taken from the request. A seat joins, or
 * moves to a seat, only with that seat's key (plays-seats.js).
 *
 * LIMITS by member, not by address (a class sits behind one school address):
 * read routes skip the Worker-wide address floor and use READ_IP_LIMITER, set
 * for 40 pollers; joins keep a per-address floor of 60 a minute against code
 * guessing; every message is counted per member key.
 */

import { DurableObject } from "cloudflare:workers";
import { castable, madeFrom } from "./plays-castable.js";
import { isOwn, newPersonRefusal, sendScript } from "./plays-own.js";
import { castHash } from "./plays-manifest.js";
import { canonicalCast, cutRange, parseCast, rangeOf } from "./plays-relay.js";
import { json, problem, readJson, limited } from "./http.js";
import { randomToken, sha256Hex } from "./jwt.js";
import { authenticate } from "./auth.js";
import * as P from "./read-protocol.js";
import { assignmentRows, seatKeyOpens, seatsOf } from "./plays-seats.js";
import { nameRefusal } from "./plays-names.js";
import { parseTakeMeta, passThrough, production, receiveTake } from "./plays.js";
import { pickup } from "./take-relay.js";

/** Tables that hold no person's rows; test/account.test.js checks they have no user_id. */
export const READ_ANONYMOUS_TABLES = ["read_rooms", "read_pairs", "read_room_objects"];

export const KEY_HEADER = "x-read-key";
export const PAIR_KEY_HEADER = "x-pair-key";
/** A TV's pairing code lives this long (Decision 082, tvOS-DESIGN §4.13): long enough to walk to a laptop. */
export const PAIR_TTL_MS = 10 * 60 * 1000;
/** An ended room answers "This reading has ended" (410) this long, then "No reading with that code" (404). */
export const ENDED_KEPT_MS = P.ROOM_IDLE_MS;

const STATUS = {
  room_full: 409,
  joining_locked: 409,
  part_taken: 409,
  seat_in_use: 409,
  seat_key_required: 403,
  stale: 409,
  room_ended: 410,
  no_such_room: 404,
  not_a_member: 403,
  leader_only: 403,
  not_your_line: 403,
  not_your_part: 403,
  readers_only: 403,
  screens_do_not_lead: 403,
  class_leads_are_seats: 403,
  class_assignments_only: 403,
  rate_limited: 429,
  not_recording: 409,
  receiver_records_here: 409,
  receivers_only: 403,
  school_consent_required: 403,
  no_such_member: 404,
  no_such_pair: 404,
  pair_expired: 410,
  bad_name: 422,
};

const refuse = (error, detail) => problem(STATUS[error] || 400, error, detail);

function newCode() {
  const bytes = new Uint8Array(P.CODE_LENGTH);
  crypto.getRandomValues(bytes);
  return P.codeFromBytes(bytes);
}

async function newMember(role, seat, now, name = null) {
  const key = randomToken(24);
  return { member: { id: randomToken(12), key_hash: await sha256Hex(key), role, seat, name, joined_at: now, seen_at: now }, key };
}

async function memberByKey(members, key) {
  if (typeof key !== "string" || !/^[A-Za-z0-9_-]{16,64}$/.test(key)) return null;
  const hash = await sha256Hex(key);
  return members.find((m) => m.key_hash === hash) || null;
}

const snapshot = (w, memberId, now) => P.joinSnapshot(w.room, w.cast, w.members, memberId, now);

const isIn = (w, memberId) => w.members.some((m) => m.id === memberId);

/** The answer to a message sent over HTTP; someone who left gets no snapshot of the room. */
function sent(r, memberId, now) {
  if (r.world.room.ended) return json({ ended: true });
  if (!isIn(r.world, memberId)) return json({ left: true });
  const out = snapshot(r.world, memberId, now);
  return json(r.reply ? { ...out, reply: r.reply } : out);
}

/**
 * THE ENGINE both transports share: a store loads and saves `{ room, cast,
 * members }`; these turn a request into protocol calls. `refresh(world, now)`
 * marks members whose socket is open as present (the object's hook).
 */
const engine = {
  async create(input, cast, now) {
    const { member, key } = await newMember("reader", null, now);
    const made = P.newRoom(input, cast, member.id, now);
    if (made.error) return { error: made.error };
    return { world: { room: made.room, cast, members: [member] }, member, key };
  },

  async join(env, world, want, now) {
    const s = P.settle(world.room, world.members, now);
    const w = { ...world, room: s.room, members: s.members };
    const role = want.role === undefined ? "reader" : want.role;
    const seat = want.seat === undefined ? null : want.seat;
    if (seat !== null && w.room.kind === "class" && !(await seatKeyOpens(env, w.room.class_id, seat, want.seat_key))) return { error: "seat_key_required" };
    const refusal = P.joinRefusal(w.room, w.members, { role, seat, paired: want.paired === true }, now);
    if (refusal) return { error: refusal };
    const name = role === "reader" ? P.cleanName(w.room, want.name) : null;
    if (name === false || (name && nameRefusal(name))) return { error: "bad_name" };
    const { member, key } = await newMember(role, null, now, name);
    let members = [...w.members, member];
    if (seat !== null) {
      const t = P.takeSeat(w.room, members, member.id, seat, want.move === true, now);
      if (t.error) return { error: t.error };
      members = t.members;
    }
    const room = { ...w.room, generation: w.room.generation + 1, touched_at: now };
    return { world: { ...w, room, members }, member, key, changed: true };
  },

  /**
   * A member's message: settle, apply, settle. `changed` means every member gets a new snapshot.
   * `diag` (the READ_DIAG var, set only in a local `wrangler dev`) logs each cursor-moving message and its result.
   */
  send(world, memberId, msg, now, diag = false) {
    const before = P.settle(world.room, world.members, now);
    const r = P.applyMessage({ room: before.room, cast: world.cast, members: before.members }, memberId, msg, now);
    if (diag && msg && msg.type !== "ping") {
      const was = before.room;
      const got = r.error ? `refused ${r.error}` : `cursor ${r.room.cursor} gen ${r.room.cursor_gen} done ${r.room.done.length}`;
      console.log(`[readdiag] worker ${msg.type} by ${memberId} line ${msg.line ?? "-"} base ${msg.base ?? "-"} at cursor ${was.cursor} gen ${was.cursor_gen} -> ${got}`);
    }
    if (r.error) return r;
    const after = P.settle(r.room, r.members, now);
    return { world: { ...world, room: after.room, members: after.members }, changed: r.changed || before.changed || after.changed, reply: r.reply };
  },

  /** A class room's seat changes hands only with that seat's key; null when `msg` may go on. */
  async guard(env, world, msg) {
    if (world.room.kind !== "class" || !msg || msg.type !== "seat") return null;
    return (await seatKeyOpens(env, world.room.class_id, msg.seat, msg.seat_key)) ? null : "seat_key_required";
  },

  /**
   * Record in the room (T5): whether this member may send a take of `line`, and where it goes:
   * the room's production (a row is written, the teacher's account) or, with none, the room's own
   * relay. Never the audio itself: the caller pipes it.
   */
  take(world, me, line, now) {
    const refusal = P.recordRefusal(world.room, world.cast, me, line);
    if (refusal) return { error: refusal };
    const who = P.whoReads(world.room, world.cast, world.members, line, now);
    // An adult room's reader has no account: the take is credited to the name they gave on joining, never to the leader (§12.11).
    const credit = world.room.kind === "class" ? null : me.name || "A reader";
    return { ok: true, part: who.part, seat: world.room.kind === "class" ? me.seat : null, member: me.id, credit, ...relayOf(world.room) };
  },

  /** The room's receiving device asks for the next take (the leader's, or a class's teacher's). */
  inbox(world, me) {
    if (P.receiverOf(world.room) !== me.id) return { error: "receivers_only" };
    return { ok: true, ...relayOf(world.room) };
  },

  async member(env, world, key) {
    const me = await memberByKey(world.members, key);
    if (!me) return { error: "not_a_member" };
    if (await limited(env.READ_MEMBER_LIMITER, me.id)) return { error: "rate_limited" };
    return { me };
  },
};

/** Where a room's takes pass: its production's relay (a row per take), or the room's own. */
function relayOf(room) {
  return { code: room.code, kind: room.kind, production_id: room.production_id, class_id: room.class_id, relay: room.production_id || `read:${room.code}` };
}

/** POST /v1/read: checks the script and the class, then hands the room to a transport. */
async function createInput(request, env) {
  const { body, error } = await readJson(request, 1024 * 1024);
  if (error) return { response: error };
  const cast = parseCast(body.cast);
  if (!cast) return { response: problem(400, "bad_request", "cast") };
  // Every device in the room reads the opener's name, so it passes the same filter as a name given on joining.
  if (nameRefusal(body.owner_name)) return { response: refuse("bad_name") };
  // A production's room opens at the production's own revision, whatever the library holds now.
  let made = null;
  let own = null;
  let prod = null;
  if (body.kind === "class") {
    // A class room is its teacher's: the account that owns the class opens it.
    const auth = await authenticate(request, env);
    if (auth.error) return { response: auth.error };
    const c = typeof body.class_id === "string" ? await env.DB.prepare("SELECT user_id FROM play_classes WHERE id = ?1").bind(body.class_id).first() : null;
    if (!c) return { response: problem(404, "no_such_class") };
    if (c.user_id !== auth.userId) return { response: problem(403, "teacher_only") };
    // The roster and the casting are the class's own (T2), never the request's.
    body.seats = (await seatsOf(env, body.class_id)).map((s) => ({ id: s.id, label: s.label }));
    if (body.production_id !== undefined) {
      const p = typeof body.production_id === "string" ? await env.DB.prepare("SELECT id, class_id, script_id, script_revision, script_row, cast_sheet, scene_range FROM play_productions WHERE id = ?1").bind(body.production_id).first() : null;
      if (!p || p.class_id !== body.class_id || p.script_id !== body.script_id) return { response: problem(404, "no_such_production") };
      body.assignments = await assignmentRows(env, body.production_id);
      made = madeFrom(p);
      prod = p;
      if (isOwn(p)) own = p;
    }
  }
  if (body.kind !== "class" && body.production_id !== undefined) {
    // An adult production's room is its director's: only they attach one, so no stranger writes takes into a production (§12.11).
    const auth = await authenticate(request, env);
    if (auth.error) return { response: auth.error };
    const p = typeof body.production_id === "string" ? await env.DB.prepare("SELECT id, user_id, class_id, script_id, script_revision, script_row, cast_sheet, scene_range FROM play_productions WHERE id = ?1").bind(body.production_id).first() : null;
    if (!p || p.class_id || p.user_id !== auth.userId || p.script_id !== body.script_id) return { response: problem(404, "no_such_production") };
    made = madeFrom(p);
    prod = p;
    if (isOwn(p)) own = p;
  }
  const found = own ? await ownRoom(env, body, own, cast) : await castable(env, body.script_id, body.script_revision, made);
  if (found.refusal) return { response: found.refusal };
  if (!own && (await castHash(cast)) !== found.row.cast) return { response: problem(422, "cast_mismatch") };
  let range = null;
  let kept = cast;
  const asked = body.range !== undefined && body.range !== null;
  const held = prod ? rangeOf(prod) : null;
  if (asked && own) return { response: problem(400, "bad_range") };
  if (asked) {
    const cut = cutRange(body.range, cast);
    if (!cut) return { response: problem(400, "bad_range") };
    range = cut.range;
    kept = cut.slice;
  }
  if (held) {
    if (range && (range.from !== held.from || range.to !== held.to)) return { response: problem(409, "range_mismatch") };
    if (!range) {
      const cut = cutRange(held, cast);
      if (!cut) return { response: problem(409, "range_mismatch") };
      range = cut.range;
      kept = cut.slice;
    }
  }
  const input = {
    kind: body.kind,
    script_id: body.script_id,
    script_revision: found.row.revision,
    mode: body.mode,
    production_id: body.production_id,
    class_id: body.class_id,
    owner_name: body.owner_name,
    seats: body.seats,
    assignments: body.assignments,
    range,
  };
  return { input, cast: kept };
}

/**
 * A room on an own script carries the production that holds it (Decision 088.4), so no one without
 * an account posts text to us or reads one by its id; without a production it is `not_castable`.
 */
async function ownRoom(env, body, p, cast) {
  const refusal = await newPersonRefusal(env, p);
  if (refusal) return { refusal };
  if (body.script_revision !== p.script_revision) return { refusal: problem(409, "revision_mismatch", p.script_revision) };
  if (canonicalCast(cast) !== canonicalCast(JSON.parse(p.cast_sheet))) return { refusal: problem(422, "cast_mismatch") };
  return { row: { revision: p.script_revision } };
}

// ---------------------------------------------------------------------------
// Transport 1: the Durable Object.

const CAST_CHUNK = 2000;
const MIN_ALARM_MS = 5 * 1000;
/** An alarm sets its successor at least this far out: a loop nobody has thought of costs 1,440 wakes a day, not 57,000 an hour. */
const ALARM_TO_ALARM_MS = 60 * 1000;
/** How long the sweep waits before it looks at a room's object again. */
const OBJECT_CHECK_MS = P.ROOM_IDLE_MS + 60 * 60 * 1000;
const OBJECT_CHECKS_PER_SWEEP = 40;
/** A poll at the room's generation waits this long for a change (the free plan counts requests, not waiting). */
export const LONG_POLL_MS = 20 * 1000;

/**
 * Whether stored members differ from these in anything worth a write: a member in or out, a seat,
 * a name, or a seen_at more than SEEN_REFRESH_MS apart. Presence moves every message; storing it
 * each time would write a row per member per cursor move.
 */
function membersDiffer(stored, next) {
  if (stored === next) return false;
  if (!stored || stored.length !== next.length) return true;
  for (let i = 0; i < next.length; i++) {
    const { seen_at: a, ...x } = stored[i];
    const { seen_at: b, ...y } = next[i];
    if (Math.abs(a - b) > P.SEEN_REFRESH_MS || JSON.stringify(x) !== JSON.stringify(y)) return true;
  }
  return false;
}

export class ReadRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.world = null;
    this.endedAt = null;
    /** The members as stored, the alarm as set, the polls waiting, and when each poller last asked. */
    this.stored = null;
    this.alarmAt = null;
    this.parked = new Set();
    this.polled = new Map();
    ctx.blockConcurrencyWhile(async () => {
      this.world = await this.load();
      if (!this.world) this.endedAt = (await this.ctx.storage.get("ended_at")) || null;
      this.alarmAt = await this.ctx.storage.getAlarm();
    });
  }

  async load() {
    const room = await this.ctx.storage.get("room");
    if (!room) return null;
    const members = (await this.ctx.storage.get("members")) || [];
    this.stored = members;
    const chunks = (await this.ctx.storage.get("cast_chunks")) || 0;
    const cast = [];
    for (let i = 0; i < chunks; i++) cast.push(...((await this.ctx.storage.get(`cast:${i}`)) || []));
    return { room, cast, members };
  }

  async save(world, { withCast = false } = {}) {
    this.world = world;
    const entries = { room: world.room };
    const members = withCast || membersDiffer(this.stored, world.members);
    if (members) entries.members = world.members;
    if (withCast) {
      const n = Math.ceil(world.cast.length / CAST_CHUNK);
      entries.cast_chunks = n;
      for (let i = 0; i < n; i++) entries[`cast:${i}`] = world.cast.slice(i * CAST_CHUNK, (i + 1) * CAST_CHUNK);
    }
    try {
      await this.ctx.storage.put(entries);
    } catch (e) {
      // The account's daily rows are used up (2026-11-23): a reading under way goes on from memory. A new
      // room has nothing to go on from, so createRoom opens it on D1 instead.
      if (withCast) {
        this.world = null;
        throw e;
      }
      console.log("read room: storage refused a save", String(e));
      return;
    }
    if (members) this.stored = world.members;
    await this.schedule(world);
  }

  /**
   * One alarm: the next leader check for an adult room, else the idle end. Set only when none is
   * set or this one is sooner: a later one is the idle end moving out, and alarm() checks again
   * when the earlier one fires, so a cursor move sets nothing.
   */
  async schedule(world, floor = MIN_ALARM_MS) {
    const now = Date.now();
    let at = world.room.touched_at + P.ROOM_IDLE_MS;
    if (world.room.kind === "adult") {
      const leader = world.members.find((m) => m.id === world.room.leader);
      const check = leader ? leader.seen_at + P.LEADER_GONE_MS + 1 : 0;
      // A check already past has run: with nobody to hand the lead to, the next join reschedules.
      if (check > now && !this.connected().has(leader.id)) at = Math.min(at, check);
    }
    // Never in the past: an alarm that sets its successor in the past fires without end.
    at = Math.max(at, now + floor);
    if (this.alarmAt !== null && this.alarmAt <= at) return;
    await this.setAlarm(at);
  }

  /** Remembered only once storage has it, so a refused alarm is asked for again; sweepReadRooms covers the rest. */
  async setAlarm(at) {
    try {
      await this.ctx.storage.setAlarm(at);
      this.alarmAt = at;
    } catch (e) {
      this.alarmAt = null;
      console.log("read room: storage refused an alarm", String(e));
    }
  }

  /** Members with an open socket or a poll waiting in the room. */
  connected() {
    const ids = new Set();
    for (const ws of this.ctx.getWebSockets()) {
      const a = ws.deserializeAttachment();
      if (a && a.member) ids.add(a.member);
    }
    for (const p of this.parked) ids.add(p.member);
    return ids;
  }

  /** Members connected are present now; a poller between polls was present when it last asked. */
  refresh(world, now) {
    const on = this.connected();
    return {
      ...world,
      members: world.members.map((m) => {
        if (on.has(m.id)) return m.seen_at === now ? m : { ...m, seen_at: now };
        const asked = this.polled.get(m.id);
        return asked > m.seen_at ? { ...m, seen_at: asked } : m;
      }),
    };
  }

  /**
   * A poll at the room's generation waits here until broadcast() or end() answers it, or
   * LONG_POLL_MS passes. `held_ms` lets the client take the wait out of its clock sample.
   */
  park(member, since) {
    return new Promise((resolve) => {
      const p = { member };
      p.answer = () => {
        if (!this.parked.delete(p)) return;
        clearTimeout(p.timer);
        const now = Date.now();
        this.polled.set(member, now);
        if (!this.world) return resolve(refuse(this.endedAt ? "room_ended" : "no_such_room"));
        if (!isIn(this.world, member)) return resolve(refuse("not_a_member"));
        resolve(json({ ...snapshot(this.refresh(this.world, now), member, now), held_ms: now - since }));
      };
      p.timer = setTimeout(p.answer, LONG_POLL_MS);
      this.parked.add(p);
    });
  }

  /** A member who left or was removed hears nothing more; their close then writes nothing. */
  drop(ws) {
    ws.serializeAttachment({ member: null });
    try {
      ws.send(JSON.stringify({ type: "error", error: "not_a_member" }));
      ws.close(4003, "not_a_member");
    } catch {}
  }

  answerParked() {
    for (const p of [...this.parked]) p.answer();
  }

  broadcast(world, now) {
    for (const ws of this.ctx.getWebSockets()) {
      const a = ws.deserializeAttachment();
      if (!a || !a.member) continue;
      if (!isIn(world, a.member)) {
        this.drop(ws);
        continue;
      }
      try {
        ws.send(JSON.stringify(snapshot(world, a.member, now)));
      } catch {}
    }
    this.answerParked();
  }

  async end(now) {
    for (const ws of this.ctx.getWebSockets()) {
      try {
        ws.close(4000, "room_ended");
      } catch {}
    }
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
    this.world = null;
    this.stored = null;
    // Only the fact that it ended stays, so its code answers "This reading has ended" rather than "No reading with that code".
    this.endedAt = now;
    this.answerParked();
    this.polled.clear();
    await this.ctx.storage.put("ended_at", now);
    await this.setAlarm(now + ENDED_KEPT_MS);
  }

  /** Applies a member's message and fans the result out; the caller gets its reply or refusal. */
  async apply(memberId, msg, now) {
    const r = engine.send(this.refresh(this.world, now), memberId, msg, now, this.env.READ_DIAG === "1");
    if (r.error) return r;
    // A socket member's presence is its open socket, so a ping writes nothing.
    if (r.changed) {
      await this.save(r.world);
      this.broadcast(r.world, now);
    }
    if (r.world.room.ended) await this.end(now);
    return r;
  }

  async fetch(request) {
    const now = Date.now();
    const url = new URL(request.url);
    const op = url.pathname.slice(1);

    if (op === "sweep") return json(await this.sweep(now));

    if (op === "create") {
      if (this.world || this.endedAt) return problem(409, "code_in_use");
      const { input, cast, code } = await request.json();
      const made = await engine.create({ ...input, code }, cast, now);
      if (made.error) return refuse(made.error);
      await this.save(made.world, { withCast: true });
      return json({ ...snapshot(made.world, made.member.id, now), member_key: made.key, transport: "socket" });
    }

    if (!this.world) return refuse(this.endedAt ? "room_ended" : "no_such_room");
    if (P.roomExpired(this.world.room, now)) {
      await this.end(now);
      return refuse("room_ended");
    }

    if (op === "join") {
      const want = await request.json();
      const r = await engine.join(this.env, this.refresh(this.world, now), want, now);
      if (r.error) return refuse(r.error);
      await this.save(r.world);
      this.broadcast(r.world, now);
      return json({ ...snapshot(r.world, r.member.id, now), member_key: r.key, transport: "socket" });
    }

    if (op === "socket") {
      if (request.headers.get("upgrade") !== "websocket") return problem(426, "upgrade_required");
      const pair = new WebSocketPair();
      // The key arrives in the first message ("hello"), never in the URL.
      this.ctx.acceptWebSocket(pair[1]);
      pair[1].serializeAttachment({ member: null });
      return new Response(null, { status: 101, webSocket: pair[0] });
    }

    const auth = await engine.member(this.env, this.world, request.headers.get(KEY_HEADER));
    if (auth.error) return refuse(auth.error);

    if (op === "take") {
      const { line } = await request.json();
      const r = engine.take(this.refresh(this.world, now), auth.me, line, now);
      return r.error ? refuse(r.error) : json(r);
    }

    if (op === "inbox") {
      const r = engine.inbox(this.world, auth.me);
      return r.error ? refuse(r.error) : json(r);
    }

    if (op === "script") return json({ ok: true, ...relayOf(this.world.room) });

    if (op === "leads") {
      const room = this.world.room;
      return P.canLead(room, auth.me.id) || room.owner === auth.me.id ? json({ ok: true }) : refuse("leader_only");
    }

    if (op === "poll") {
      // Asking is presence, kept in memory like an open socket: a poll writes only when the room settles differently.
      this.polled.set(auth.me.id, now);
      let w = this.refresh(this.world, now);
      const s = P.settle(w.room, w.members, now);
      if (s.changed) {
        w = { ...w, room: s.room, members: s.members };
        await this.save(w);
        this.broadcast(w, now);
      }
      const gen = Number(url.searchParams.get("gen"));
      if (!url.searchParams.has("gen") || !Number.isInteger(gen) || gen < w.room.generation || w.room.ended) return json(snapshot(w, auth.me.id, now));
      return this.park(auth.me.id, now);
    }

    if (op === "send") {
      const msg = await request.json();
      const guarded = await engine.guard(this.env, this.world, msg);
      if (guarded) return refuse(guarded);
      const r = await this.apply(auth.me.id, msg, now);
      return r.error ? refuse(r.error, r.detail) : sent(r, auth.me.id, now);
    }

    return problem(404, "not_found");
  }

  async webSocketMessage(ws, data) {
    const now = Date.now();
    let msg;
    try {
      msg = JSON.parse(typeof data === "string" ? data : new TextDecoder().decode(data));
    } catch {
      return ws.send(JSON.stringify({ type: "error", error: "bad_message" }));
    }
    if (!this.world) return ws.close(4004, "no_such_room");
    const a = ws.deserializeAttachment() || {};

    if (!a.member) {
      if (!msg || msg.type !== "hello") return ws.send(JSON.stringify({ type: "error", error: "hello_first" }));
      const auth = await engine.member(this.env, this.world, msg.key);
      if (auth.error) {
        ws.send(JSON.stringify({ type: "error", error: auth.error }));
        return ws.close(4003, auth.error);
      }
      ws.serializeAttachment({ member: auth.me.id });
      const w = this.refresh(this.world, now);
      const s = P.settle(w.room, w.members, now);
      const world = { ...w, room: s.room, members: s.members };
      await this.save(world);
      this.broadcast(world, now);
      return;
    }

    if (await limited(this.env.READ_MEMBER_LIMITER, a.member)) return ws.send(JSON.stringify({ type: "error", error: "rate_limited" }));
    const guarded = await engine.guard(this.env, this.world, msg);
    if (guarded) return ws.send(JSON.stringify({ type: "error", error: guarded }));
    const r = await this.apply(a.member, msg, now);
    if (r.error) return ws.send(JSON.stringify({ type: "error", error: r.error, detail: r.detail }));
    if (r.reply) ws.send(JSON.stringify(r.reply));
  }

  async webSocketClose(ws) {
    const a = ws.deserializeAttachment() || {};
    if (!this.world || !a.member) return;
    const now = Date.now();
    // Present until now; the 2-minute clock for leaving starts here.
    const members = this.world.members.map((m) => (m.id === a.member ? { ...m, seen_at: now } : m));
    const world = { ...this.world, members };
    await this.save(world);
    this.broadcast(world, now);
  }

  async webSocketError(ws) {
    await this.webSocketClose(ws);
  }

  async alarm() {
    this.alarmAt = null;
    if (!this.world) {
      if (this.endedAt) {
        await this.ctx.storage.deleteAll();
        this.endedAt = null;
      }
      return;
    }
    const now = Date.now();
    if (P.roomExpired(this.world.room, now)) return this.end(now);
    const w = this.refresh(this.world, now);
    const s = P.settle(w.room, w.members, now);
    const world = { ...w, room: s.room, members: s.members };
    if (!s.changed) {
      // Nothing settled differently: no write, only the next alarm.
      this.world = world;
      return this.schedule(world, ALARM_TO_ALARM_MS);
    }
    await this.save(world);
    this.broadcast(world, now);
  }

  /**
   * The hourly sweep's visit: what this room's own alarm would have done. Cloudflare drops an alarm
   * that fails its retries, and while storage refuses writes every alarm fails, so a room could keep
   * its members past the six hours it promises (one did, 2026-11-23). Nothing happens to a live room.
   */
  async sweep(now) {
    if (this.world) {
      if (P.roomExpired(this.world.room, now)) await this.end(now);
      else if (this.alarmAt === null) await this.schedule(this.world);
    } else if (this.endedAt && now - this.endedAt >= ENDED_KEPT_MS) {
      await this.ctx.storage.deleteAll();
      this.endedAt = null;
    }
    return { gone: !this.world && !this.endedAt };
  }
}

function stub(env, code) {
  return env.READ_ROOMS.get(env.READ_ROOMS.idFromName(code));
}

function forward(env, code, op, request, body) {
  const headers = new Headers();
  const key = request.headers.get(KEY_HEADER);
  if (key) headers.set(KEY_HEADER, key);
  if (op === "socket") headers.set("upgrade", request.headers.get("upgrade") || "");
  const search = op === "poll" ? new URL(request.url).search : "";
  return stub(env, code).fetch(`https://read-room/${op}${search}`, {
    method: body === undefined ? "GET" : "POST",
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

// ---------------------------------------------------------------------------
// Transport 2: D1 polling.

const d1 = {
  async load(env, code) {
    const row = await env.DB.prepare("SELECT * FROM read_rooms WHERE code = ?1").bind(code).first();
    if (!row) return null;
    return { world: { room: JSON.parse(row.room), cast: JSON.parse(row.cast_sheet), members: JSON.parse(row.members) }, version: row.version };
  },

  /** Writes only if nobody wrote since the load; false means load again and retry. */
  async save(env, code, world, version) {
    const r = await env.DB.prepare("UPDATE read_rooms SET room = ?2, members = ?3, version = version + 1, touched_at = ?4 WHERE code = ?1 AND version = ?5")
      .bind(code, JSON.stringify(world.room), JSON.stringify(world.members), world.room.touched_at, version)
      .run();
    return r.meta.changes === 1;
  },

  async remove(env, code) {
    await env.DB.prepare("DELETE FROM read_rooms WHERE code = ?1").bind(code).run();
  },

  /** Load, change, save, retrying when another request wrote first: the server stays the arbiter. */
  async update(env, code, now, fn) {
    for (let attempt = 0; attempt < 5; attempt++) {
      const loaded = await d1.load(env, code);
      if (!loaded) return { error: "no_such_room" };
      if (loaded.world.room.ended) return { error: "room_ended" };
      if (P.roomExpired(loaded.world.room, now)) {
        await d1.remove(env, code);
        return { error: "room_ended" };
      }
      const r = await fn(loaded.world);
      if (r.error || !r.world) return r;
      if (!r.changed && !r.touch) return r;
      // An ended room's row stays until the sweep, so its code answers "This reading has ended".
      if (await d1.save(env, code, r.world, loaded.version)) return r;
    }
    return { error: "busy" };
  },

  async create(env, input, cast, now) {
    for (let attempt = 0; attempt < 10; attempt++) {
      const code = newCode();
      const made = await engine.create({ ...input, code }, cast, now);
      if (made.error) return refuse(made.error);
      try {
        await env.DB.prepare("INSERT INTO read_rooms (code, cast_sheet, room, members, version, touched_at) VALUES (?1, ?2, ?3, ?4, 1, ?5)")
          .bind(code, JSON.stringify(cast), JSON.stringify(made.world.room), JSON.stringify(made.world.members), now)
          .run();
      } catch (e) {
        if (String(e).includes("UNIQUE")) continue;
        throw e;
      }
      return json({ ...snapshot(made.world, made.member.id, now), member_key: made.key, transport: "poll" });
    }
    return problem(503, "no_free_code");
  },

  async join(env, code, want, now) {
    let joined;
    const r = await d1.update(env, code, now, async (world) => {
      const j = await engine.join(env, world, want, now);
      if (!j.error) joined = j;
      return j;
    });
    if (r.error) return refuse(r.error);
    return json({ ...snapshot(r.world, joined.member.id, now), member_key: joined.key, transport: "poll" });
  },

  /** The world for a member's key, or the refusal; for the take routes. */
  async world(env, code, key) {
    const loaded = await d1.load(env, code);
    if (!loaded) return { error: "no_such_room" };
    if (loaded.world.room.ended) return { error: "room_ended" };
    const auth = await engine.member(env, loaded.world, key);
    if (auth.error) return auth;
    return { world: loaded.world, me: auth.me };
  },

  async poll(env, code, key, now) {
    const loaded = await d1.load(env, code);
    if (!loaded) return refuse("no_such_room");
    if (loaded.world.room.ended) return refuse("room_ended");
    const auth = await engine.member(env, loaded.world, key);
    if (auth.error) return refuse(auth.error);
    const w = loaded.world;
    // A read is presence too, written only when the last one is stale.
    if (now - auth.me.seen_at > P.SEEN_REFRESH_MS || P.settle(w.room, w.members, now).changed) {
      const r = await d1.update(env, code, now, async (world) => ({ ...engine.send(world, auth.me.id, { type: "ping" }, now), touch: true }));
      if (r.error) return refuse(r.error);
      return json(snapshot(r.world, auth.me.id, now));
    }
    return json(snapshot(w, auth.me.id, now));
  },

  async send(env, code, key, msg, now) {
    const loaded = await d1.load(env, code);
    if (!loaded) return refuse("no_such_room");
    if (loaded.world.room.ended) return refuse("room_ended");
    const auth = await engine.member(env, loaded.world, key);
    if (auth.error) return refuse(auth.error);
    const guarded = await engine.guard(env, loaded.world, msg);
    if (guarded) return refuse(guarded);
    const r = await d1.update(env, code, now, async (world) => engine.send(world, auth.me.id, msg, now, env.READ_DIAG === "1"));
    return r.error ? refuse(r.error, r.detail) : sent(r, auth.me.id, now);
  },
};

// ---------------------------------------------------------------------------
// Routes.

async function createRoom(request, env, ip, now) {
  if (await limited(env.READ_CREATE_LIMITER, ip)) return problem(429, "rate_limited");
  const made = await createInput(request, env);
  if (made.response) return made.response;
  if (!env.READ_ROOMS) return d1.create(env, made.input, made.cast, now);
  for (let attempt = 0; attempt < 10; attempt++) {
    const code = newCode();
    if (await env.DB.prepare("SELECT 1 FROM read_rooms WHERE code = ?1").bind(code).first()) continue;
    let r;
    try {
      r = await stub(env, code).fetch("https://read-room/create", {
        method: "POST",
        body: JSON.stringify({ input: made.input, cast: made.cast, code }),
      });
    } catch (e) {
      // The object cannot store a room (the account's daily limit): the same reading over D1 polling.
      console.log("read room: object unavailable, opening on D1", String(e));
      return d1.create(env, made.input, made.cast, now);
    }
    if (r.status === 409 && (await r.clone().json()).error === "code_in_use") continue;
    if (r.ok) {
      await env.DB.prepare("INSERT OR REPLACE INTO read_room_objects (code, check_at) VALUES (?1, ?2)").bind(code, now + OBJECT_CHECK_MS).run();
    }
    return r;
  }
  return problem(503, "no_free_code");
}

/** A member's standing in a room, for the take and pairing routes: the transport's own answer. */
async function ask(env, code, op, request, body, now) {
  const inD1 = await env.DB.prepare("SELECT 1 FROM read_rooms WHERE code = ?1").bind(code).first();
  if (inD1 || !env.READ_ROOMS) {
    const w = await d1.world(env, code, request.headers.get(KEY_HEADER));
    if (w.error) return { error: w.error };
    if (op === "take") return engine.take(w.world, w.me, body.line, now);
    if (op === "inbox") return engine.inbox(w.world, w.me);
    if (op === "script") return { ok: true, ...relayOf(w.world.room) };
    return P.canLead(w.world.room, w.me.id) || w.world.room.owner === w.me.id ? { ok: true } : { error: "leader_only" };
  }
  const r = await forward(env, code, op, request, body);
  const out = await r.json();
  return r.ok ? out : { error: out.error || "no_such_room" };
}

/** Whether an under-13 class may send a seat's voice (Decision 059: only under the school's consent). */
async function classVoiceAllowed(env, classId) {
  const c = await env.DB.prepare(
    "SELECT c.under13, sc.class_id AS consent FROM play_classes c LEFT JOIN play_school_consents sc ON sc.class_id = c.id WHERE c.id = ?1",
  )
    .bind(classId)
    .first();
  return !!c && (!c.under13 || !!c.consent);
}

/**
 * PUT /v1/read/{code}/takes/{takeId} (T5, Record in the room): a reader's take of a line they hold
 * passes through to the room's receiving device. A room with a production writes the take's row
 * there (a class's takes are the teacher's account's, credited to the seat); without one the take
 * crosses the room's own relay and nothing is written. The audio is never kept (Decision 082).
 */
async function roomTake(request, env, code, takeId, now) {
  const meta = parseTakeMeta(request.headers.get("x-take"));
  if (!meta) return problem(400, "bad_request", "x-take must be the take's fields as JSON");
  const check = await ask(env, code, "take", request, { line: meta.lineID }, now);
  if (check.error) return refuse(check.error);
  if (await limited(env.PLAY_UPLOAD_LIMITER, `read:${code}:${check.member}`)) return problem(429, "rate_limited");
  if (meta.part !== undefined && meta.part !== check.part) return problem(422, "line_is_another_part", check.part);
  const room = { ...meta, capture: "room" };
  const who = { userId: null, seatId: check.seat, sender: `read:${code}:${check.member}`, direct: false, member: check.member, credit: check.credit };
  if (!check.production_id) return passThrough(env, request, check.relay, takeId, room, check.part, who);
  const p = await production(env, check.production_id);
  if (!p) return refuse("no_such_room");
  if (check.class_id && !(await classVoiceAllowed(env, check.class_id))) return refuse("school_consent_required");
  return receiveTake(env, request, p, takeId, room, check.part, { ...who, userId: p.user_id }, now);
}

/** GET /v1/read/{code}/takes/inbox: the receiving device's pickup, a long poll answered with the next take. */
async function roomInbox(request, env, code, now) {
  const check = await ask(env, code, "inbox", request, undefined, now);
  if (check.error) return refuse(check.error);
  return pickup(env, check.relay);
}

/** GET /v1/read/{code}/script: an own script's text, to a member of a room that carries its production. */
async function roomScript(request, env, code, now) {
  const check = await ask(env, code, "script", request, undefined, now);
  if (check.error) return refuse(check.error);
  const p = check.production_id
    ? await env.DB.prepare("SELECT id, script_id, script_revision, title FROM play_productions WHERE id = ?1").bind(check.production_id).first()
    : null;
  if (!p) return problem(404, "no_script");
  return sendScript(request, env, p, { newPerson: true });
}

/* ---- Pairing a TV (T5; tvOS-DESIGN §4.13, ANDROID-DESIGN's TV panel rule) ---- */

/**
 * POST /v1/read/pair: a TV asks for a pairing code to show. It gets the code and a key, the key
 * stored only as its hash; the TV never types. The code works for PAIR_TTL_MS, once.
 */
async function newPair(env, ip, now) {
  if (await limited(env.READ_CREATE_LIMITER, ip)) return problem(429, "rate_limited");
  const key = randomToken(24);
  const hash = await sha256Hex(key);
  for (let attempt = 0; attempt < 10; attempt++) {
    const code = newCode();
    try {
      await env.DB.prepare("INSERT INTO read_pairs (code, key_hash, room, created_at, expires_at) VALUES (?1, ?2, NULL, ?3, ?4)")
        .bind(code, hash, now, now + PAIR_TTL_MS)
        .run();
    } catch (e) {
      if (String(e).includes("UNIQUE")) continue;
      throw e;
    }
    return json({ pair_code: code, pair_key: key, expires_at: now + PAIR_TTL_MS, server_time: now }, 201);
  }
  return problem(503, "no_free_code");
}

/**
 * GET /v1/read/pair/{code} with `x-pair-key`: the TV waits. Until a leader attaches it, `{ paired:
 * false }`; then the TV joins that room as its screen (past a lock: the leader let it in) and gets
 * the snapshot with its member key, and the pairing is gone.
 */
async function pairPoll(request, env, code, now) {
  const row = await env.DB.prepare("SELECT * FROM read_pairs WHERE code = ?1").bind(code).first();
  const key = request.headers.get(PAIR_KEY_HEADER);
  if (!row || typeof key !== "string" || (await sha256Hex(key)) !== row.key_hash) return refuse("no_such_pair");
  if (row.expires_at <= now) {
    await env.DB.prepare("DELETE FROM read_pairs WHERE code = ?1").bind(code).run();
    return refuse("pair_expired");
  }
  if (!row.room) return json({ paired: false, expires_at: row.expires_at, server_time: now });
  await env.DB.prepare("DELETE FROM read_pairs WHERE code = ?1").bind(code).run();
  const want = { role: "screen", paired: true };
  const inD1 = await env.DB.prepare("SELECT 1 FROM read_rooms WHERE code = ?1").bind(row.room).first();
  if (inD1 || !env.READ_ROOMS) return d1.join(env, row.room, want, now);
  return forward(env, row.room, "join", new Request("https://read-room/"), want);
}

/** POST /v1/read/{room}/pair { code }: the leader attaches the TV showing `code` to this room. */
async function attachPair(request, env, room, body, now) {
  const code = P.normalizeCode(body && body.code);
  if (!code) return refuse("no_such_pair");
  const lead = await ask(env, room, "leads", request, undefined, now);
  if (lead.error) return refuse(lead.error);
  const row = await env.DB.prepare("SELECT expires_at, room FROM read_pairs WHERE code = ?1").bind(code).first();
  if (!row || row.room) return refuse("no_such_pair");
  if (row.expires_at <= now) return refuse("pair_expired");
  const r = await env.DB.prepare("UPDATE read_pairs SET room = ?2 WHERE code = ?1 AND room IS NULL AND expires_at > ?3").bind(code, room, now).run();
  if (!r.meta.changes) return refuse("no_such_pair");
  return json({ paired: true, pair_code: code, room });
}

/** /v1/read, /v1/read/pair[/{code}], and /v1/read/{code}[/join|/send|/socket|/pair|/script|/takes/inbox|/takes/{id}] */
export async function handleReadRooms(url, request, env, ip) {
  const now = Date.now();
  const method = request.method;
  if (url.pathname === "/v1/read" || url.pathname === "/v1/read/") {
    return method === "POST" ? createRoom(request, env, ip, now) : problem(405, "method_not_allowed");
  }
  if (url.pathname === "/v1/read/pair") return method === "POST" ? newPair(env, ip, now) : problem(405, "method_not_allowed");
  const pm = /^\/v1\/read\/pair\/([^/]+)$/.exec(url.pathname);
  if (pm) {
    if (method !== "GET") return problem(405, "method_not_allowed");
    const code = P.normalizeCode(pm[1]);
    return code ? pairPoll(request, env, code, now) : refuse("no_such_pair");
  }
  const m = /^\/v1\/read\/([^/]+)(?:\/(join|send|socket|pair|script|takes\/inbox|takes\/[^/]+))?$/.exec(url.pathname);
  if (!m) return problem(404, "not_found");
  let raw;
  try {
    raw = decodeURIComponent(m[1]);
  } catch {
    return problem(400, "bad_code");
  }
  const code = P.normalizeCode(raw);
  if (!code) return problem(400, "bad_code");
  const sub = m[2] || "";
  if (sub === "takes/inbox") return method === "GET" ? roomInbox(request, env, code, now) : problem(405, "method_not_allowed");
  if (sub === "script") return method === "GET" ? roomScript(request, env, code, now) : problem(405, "method_not_allowed");
  if (sub.startsWith("takes/")) {
    if (method !== "PUT") return problem(405, "method_not_allowed");
    let takeId;
    try {
      takeId = decodeURIComponent(sub.slice("takes/".length));
    } catch {
      return problem(400, "bad_request", "take id");
    }
    return roomTake(request, env, code, takeId, now);
  }
  const action = `${method} ${sub}`;
  if (!["POST join", "POST send", "POST pair", "GET socket", "GET "].includes(action)) return problem(405, "method_not_allowed");

  let body;
  if (method === "POST") {
    const read = await readJson(request, 8 * 1024);
    if (read.error) return read.error;
    body = read.body;
  }
  if ((action === "POST join" || action === "POST pair") && (await limited(env.READ_JOIN_LIMITER, ip))) return problem(429, "rate_limited");
  if (action === "POST pair") return attachPair(request, env, code, body, now);
  // Only a pairing lets a screen past a lock; a join cannot claim one.
  if (action === "POST join" && body && typeof body === "object") delete body.paired;

  const inD1 = await env.DB.prepare("SELECT 1 FROM read_rooms WHERE code = ?1").bind(code).first();
  if (inD1 || !env.READ_ROOMS) {
    if (action === "GET socket") return inD1 ? problem(409, "poll_only") : refuse("no_such_room");
    if (action === "POST join") return d1.join(env, code, body, now);
    if (action === "POST send") return d1.send(env, code, request.headers.get(KEY_HEADER), body, now);
    return d1.poll(env, code, request.headers.get(KEY_HEADER), now);
  }
  const op = { "POST join": "join", "POST send": "send", "GET socket": "socket", "GET ": "poll" }[action];
  return forward(env, code, op, request, body);
}

/**
 * The cron sweep: D1 rooms past their idle limit are deleted. Object rooms end on their own alarm, and
 * the sweep visits each one due, in case its alarm was lost; a visit that fails is made again next hour.
 */
export async function sweepReadRooms(env, now = Date.now()) {
  await env.DB.prepare("DELETE FROM read_rooms WHERE touched_at < ?1").bind(now - P.ROOM_IDLE_MS).run();
  await env.DB.prepare("DELETE FROM read_pairs WHERE expires_at < ?1").bind(now).run();
  if (!env.READ_ROOMS) return;
  const due = await env.DB.prepare("SELECT code FROM read_room_objects WHERE check_at < ?1 ORDER BY check_at LIMIT ?2").bind(now, OBJECT_CHECKS_PER_SWEEP).all();
  for (const { code } of due.results) {
    let gone;
    try {
      gone = (await (await stub(env, code).fetch("https://read-room/sweep")).json()).gone;
    } catch (e) {
      console.log("read room: sweep visit failed", String(e));
      continue;
    }
    if (gone) await env.DB.prepare("DELETE FROM read_room_objects WHERE code = ?1").bind(code).run();
    else await env.DB.prepare("UPDATE read_room_objects SET check_at = ?2 WHERE code = ?1").bind(code, now + OBJECT_CHECK_MS).run();
  }
}
