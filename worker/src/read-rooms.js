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
import MANIFEST from "./castable-manifest.json";
import { castHash } from "./plays-manifest.js";
import { parseCast } from "./plays-relay.js";
import { json, problem, readJson, limited } from "./http.js";
import { randomToken, sha256Hex } from "./jwt.js";
import { authenticate } from "./auth.js";
import * as P from "./read-protocol.js";
import { assignmentRows, seatKeyOpens, seatsOf } from "./plays-seats.js";

/** Tables that hold no person's rows; test/account.test.js checks they have no user_id. */
export const READ_ANONYMOUS_TABLES = ["read_rooms"];

export const KEY_HEADER = "x-read-key";

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
};

const refuse = (error, detail) => problem(STATUS[error] || 400, error, detail);

function newCode() {
  const bytes = new Uint8Array(P.CODE_LENGTH);
  crypto.getRandomValues(bytes);
  return P.codeFromBytes(bytes);
}

async function newMember(role, seat, now) {
  const key = randomToken(24);
  return { member: { id: randomToken(12), key_hash: await sha256Hex(key), role, seat, joined_at: now, seen_at: now }, key };
}

async function memberByKey(members, key) {
  if (typeof key !== "string" || !/^[A-Za-z0-9_-]{16,64}$/.test(key)) return null;
  const hash = await sha256Hex(key);
  return members.find((m) => m.key_hash === hash) || null;
}

const snapshot = (w, memberId, now) => P.joinSnapshot(w.room, w.cast, w.members, memberId, now);

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
    const refusal = P.joinRefusal(w.room, w.members, { role, seat }, now);
    if (refusal) return { error: refusal };
    const { member, key } = await newMember(role, null, now);
    let members = [...w.members, member];
    if (seat !== null) {
      const t = P.takeSeat(w.room, members, member.id, seat, want.move === true, now);
      if (t.error) return { error: t.error };
      members = t.members;
    }
    const room = { ...w.room, generation: w.room.generation + 1, touched_at: now };
    return { world: { ...w, room, members }, member, key, changed: true };
  },

  /** A member's message: settle, apply, settle. `changed` means every member gets a new snapshot. */
  send(world, memberId, msg, now) {
    const before = P.settle(world.room, world.members, now);
    const r = P.applyMessage({ room: before.room, cast: world.cast, members: before.members }, memberId, msg, now);
    if (r.error) return r;
    const after = P.settle(r.room, r.members, now);
    return { world: { ...world, room: after.room, members: after.members }, changed: r.changed || before.changed || after.changed, reply: r.reply };
  },

  /** A class room's seat changes hands only with that seat's key; null when `msg` may go on. */
  async guard(env, world, msg) {
    if (world.room.kind !== "class" || !msg || msg.type !== "seat") return null;
    return (await seatKeyOpens(env, world.room.class_id, msg.seat, msg.seat_key)) ? null : "seat_key_required";
  },

  async member(env, world, key) {
    const me = await memberByKey(world.members, key);
    if (!me) return { error: "not_a_member" };
    if (await limited(env.READ_MEMBER_LIMITER, me.id)) return { error: "rate_limited" };
    return { me };
  },
};

/** POST /v1/read: checks the script and the class, then hands the room to a transport. */
async function createInput(request, env) {
  const { body, error } = await readJson(request, 1024 * 1024);
  if (error) return { response: error };
  const entry = typeof body.script_id === "string" && Object.hasOwn(MANIFEST.scripts, body.script_id) ? MANIFEST.scripts[body.script_id] : null;
  if (!entry) return { response: problem(422, "not_castable") };
  if (body.script_revision !== entry.revision) return { response: problem(409, "revision_mismatch", entry.revision) };
  const cast = parseCast(body.cast);
  if (!cast) return { response: problem(400, "bad_request", "cast") };
  if ((await castHash(cast)) !== entry.cast) return { response: problem(422, "cast_mismatch") };
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
      const p = typeof body.production_id === "string" ? await env.DB.prepare("SELECT class_id, script_id FROM play_productions WHERE id = ?1").bind(body.production_id).first() : null;
      if (!p || p.class_id !== body.class_id || p.script_id !== body.script_id) return { response: problem(404, "no_such_production") };
      body.assignments = await assignmentRows(env, body.production_id);
    }
  }
  const input = {
    kind: body.kind,
    script_id: body.script_id,
    script_revision: entry.revision,
    mode: body.mode,
    production_id: body.production_id,
    class_id: body.class_id,
    owner_name: body.owner_name,
    seats: body.seats,
    assignments: body.assignments,
  };
  return { input, cast };
}

// ---------------------------------------------------------------------------
// Transport 1: the Durable Object.

const CAST_CHUNK = 2000;

export class ReadRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.world = null;
    ctx.blockConcurrencyWhile(async () => {
      this.world = await this.load();
    });
  }

  async load() {
    const room = await this.ctx.storage.get("room");
    if (!room) return null;
    const members = (await this.ctx.storage.get("members")) || [];
    const chunks = (await this.ctx.storage.get("cast_chunks")) || 0;
    const cast = [];
    for (let i = 0; i < chunks; i++) cast.push(...((await this.ctx.storage.get(`cast:${i}`)) || []));
    return { room, cast, members };
  }

  async save(world, { withCast = false } = {}) {
    this.world = world;
    const entries = { room: world.room, members: world.members };
    if (withCast) {
      const n = Math.ceil(world.cast.length / CAST_CHUNK);
      entries.cast_chunks = n;
      for (let i = 0; i < n; i++) entries[`cast:${i}`] = world.cast.slice(i * CAST_CHUNK, (i + 1) * CAST_CHUNK);
    }
    await this.ctx.storage.put(entries);
    await this.schedule(world);
  }

  /** One alarm: the next leader check for an adult room, else the idle end. */
  async schedule(world) {
    let at = world.room.touched_at + P.ROOM_IDLE_MS;
    if (world.room.kind === "adult") {
      const leader = world.members.find((m) => m.id === world.room.leader);
      if (leader && !this.connected().has(leader.id)) at = Math.min(at, leader.seen_at + P.LEADER_GONE_MS + 1);
    }
    await this.ctx.storage.setAlarm(at);
  }

  connected() {
    const ids = new Set();
    for (const ws of this.ctx.getWebSockets()) {
      const a = ws.deserializeAttachment();
      if (a && a.member) ids.add(a.member);
    }
    return ids;
  }

  /** Members with an open socket are present now. */
  refresh(world, now) {
    const on = this.connected();
    return { ...world, members: world.members.map((m) => (on.has(m.id) ? { ...m, seen_at: now } : m)) };
  }

  broadcast(world, now) {
    for (const ws of this.ctx.getWebSockets()) {
      const a = ws.deserializeAttachment();
      if (!a || !a.member) continue;
      try {
        ws.send(JSON.stringify(snapshot(world, a.member, now)));
      } catch {}
    }
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
  }

  /** Applies a member's message and fans the result out; the caller gets its reply or refusal. */
  async apply(memberId, msg, now) {
    const r = engine.send(this.refresh(this.world, now), memberId, msg, now);
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

    if (op === "create") {
      if (this.world) return problem(409, "code_in_use");
      const { input, cast, code } = await request.json();
      const made = await engine.create({ ...input, code }, cast, now);
      if (made.error) return refuse(made.error);
      await this.save(made.world, { withCast: true });
      return json({ ...snapshot(made.world, made.member.id, now), member_key: made.key, transport: "socket" });
    }

    if (!this.world) return refuse("no_such_room");
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

    if (op === "poll") {
      const w = this.refresh(this.world, now);
      const me = w.members.find((m) => m.id === auth.me.id);
      if (now - me.seen_at > P.SEEN_REFRESH_MS || P.settle(w.room, w.members, now).changed) {
        const r = engine.send(w, auth.me.id, { type: "ping" }, now);
        await this.save(r.world);
        if (r.changed) this.broadcast(r.world, now);
        return json(snapshot(r.world, auth.me.id, now));
      }
      return json(snapshot(w, auth.me.id, now));
    }

    if (op === "send") {
      const msg = await request.json();
      const guarded = await engine.guard(this.env, this.world, msg);
      if (guarded) return refuse(guarded);
      const r = await this.apply(auth.me.id, msg, now);
      if (r.error) return refuse(r.error, r.detail);
      const out = r.world.room.ended ? { ended: true } : snapshot(r.world, auth.me.id, now);
      return json(r.reply ? { ...out, reply: r.reply } : out);
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
    if (!this.world) return;
    const now = Date.now();
    if (P.roomExpired(this.world.room, now)) return this.end(now);
    const w = this.refresh(this.world, now);
    const s = P.settle(w.room, w.members, now);
    const world = { ...w, room: s.room, members: s.members };
    await this.save(world);
    if (s.changed) this.broadcast(world, now);
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
  return stub(env, code).fetch(`https://read-room/${op}`, {
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
      if (P.roomExpired(loaded.world.room, now)) {
        await d1.remove(env, code);
        return { error: "room_ended" };
      }
      const r = await fn(loaded.world);
      if (r.error || !r.world) return r;
      if (!r.changed && !r.touch) return r;
      if (r.world.room.ended) {
        await d1.remove(env, code);
        return r;
      }
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

  async poll(env, code, key, now) {
    const loaded = await d1.load(env, code);
    if (!loaded) return refuse("no_such_room");
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
    const auth = await engine.member(env, loaded.world, key);
    if (auth.error) return refuse(auth.error);
    const guarded = await engine.guard(env, loaded.world, msg);
    if (guarded) return refuse(guarded);
    const r = await d1.update(env, code, now, async (world) => engine.send(world, auth.me.id, msg, now));
    if (r.error) return refuse(r.error, r.detail);
    const out = r.world.room.ended ? { ended: true } : snapshot(r.world, auth.me.id, now);
    return json(r.reply ? { ...out, reply: r.reply } : out);
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
    const r = await stub(env, code).fetch("https://read-room/create", {
      method: "POST",
      body: JSON.stringify({ input: made.input, cast: made.cast, code }),
    });
    if (r.status === 409 && (await r.clone().json()).error === "code_in_use") continue;
    return r;
  }
  return problem(503, "no_free_code");
}

/** /v1/read and /v1/read/{code}[/join|/send|/socket] */
export async function handleReadRooms(url, request, env, ip) {
  const now = Date.now();
  const method = request.method;
  if (url.pathname === "/v1/read" || url.pathname === "/v1/read/") {
    return method === "POST" ? createRoom(request, env, ip, now) : problem(405, "method_not_allowed");
  }
  const m = /^\/v1\/read\/([^/]+)(?:\/(join|send|socket))?$/.exec(url.pathname);
  if (!m) return problem(404, "not_found");
  let raw;
  try {
    raw = decodeURIComponent(m[1]);
  } catch {
    return problem(400, "bad_code");
  }
  const code = P.normalizeCode(raw);
  if (!code) return problem(400, "bad_code");
  const action = `${method} ${m[2] || ""}`;
  if (!["POST join", "POST send", "GET socket", "GET "].includes(action)) return problem(405, "method_not_allowed");

  let body;
  if (method === "POST") {
    const read = await readJson(request, 8 * 1024);
    if (read.error) return read.error;
    body = read.body;
  }
  if (action === "POST join" && (await limited(env.READ_JOIN_LIMITER, ip))) return problem(429, "rate_limited");

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

/** The cron sweep: D1 rooms past their idle limit are deleted. Object rooms end on their own alarm. */
export async function sweepReadRooms(env, now = Date.now()) {
  await env.DB.prepare("DELETE FROM read_rooms WHERE touched_at < ?1").bind(now - P.ROOM_IDLE_MS).run();
}
