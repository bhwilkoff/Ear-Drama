/**
 * Listen Together rooms over HTTP and D1: the transport adapter (LOOP-PLAN M6).
 *
 * Every rule lives in room-protocol.js; this file only reads and writes rows.
 * Ported from Archive Watch's together.js, and for the same reason it is
 * polling, not a socket: Durable Objects are not on Cloudflare's free plan,
 * Workers KV is eventually consistent for up to a minute (a pause would take
 * a minute to reach a guest), and D1 is strongly consistent and already bound.
 * The host writes when the state changes; members read every 2 to 10 seconds
 * and extrapolate between reads, and every read is also a clock sample.
 *
 * NO ACCOUNT. Decision 057 requires an account to record, cast, or publish a
 * shared play; listening together is none of those, and SharePlay needs no
 * account on Apple, so rooms need none here either. A member is a random id
 * and a random key, returned once, stored only as its SHA-256.
 *
 * THE CODE IS PUBLIC; CONTROL IS NOT. A code is read aloud, so knowing it lets
 * you join and listen, never drive: every state write needs the member key of
 * the current host.
 */

import { json, problem, readJson, limited } from "./http.js";
import { randomToken, sha256Hex } from "./jwt.js";
import {
  MAX_MEMBERS,
  MEMBER_GONE_MS,
  ROOM_IDLE_MS,
  SEEN_REFRESH_MS,
  applyHostState,
  codeFromBytes,
  liveMembers,
  nextHost,
  normalizeCode,
  roomExpired,
  roomSnapshot,
  CODE_LENGTH,
} from "./room-protocol.js";

/** Tables that hold no person's rows; test/account.test.js checks they have no user_id. */
export const ANONYMOUS_TABLES = ["rooms", "room_members"];

const KEY_HEADER = "x-room-key";

function rowToState(r) {
  return {
    episode_id: r.episode_id,
    archive_id: r.archive_id,
    file: r.file,
    position: r.position,
    playing: !!r.playing,
    rate: r.rate,
    updated_at: r.updated_at,
    generation: r.generation,
  };
}

function newCode() {
  const bytes = new Uint8Array(CODE_LENGTH);
  crypto.getRandomValues(bytes);
  return codeFromBytes(bytes);
}

async function newMember(code, now) {
  const key = randomToken(24);
  return { id: randomToken(12), key, hash: await sha256Hex(key), code, now };
}

function insertMember(env, m) {
  return env.DB.prepare("INSERT INTO room_members (id, code, key_hash, joined_at, seen_at) VALUES (?1, ?2, ?3, ?4, ?4)").bind(
    m.id,
    m.code,
    m.hash,
    m.now,
  );
}

function deleteRoom(env, code) {
  return env.DB.batch([
    env.DB.prepare("DELETE FROM room_members WHERE code = ?1").bind(code),
    env.DB.prepare("DELETE FROM rooms WHERE code = ?1").bind(code),
  ]);
}

/** The room and its members, or a response: 404 for no room, 410 for one past its idle limit. */
async function loadRoom(env, code, now) {
  const room = await env.DB.prepare("SELECT * FROM rooms WHERE code = ?1").bind(code).first();
  if (!room) return { error: problem(404, "no_such_room") };
  if (roomExpired(room, now)) {
    await deleteRoom(env, code);
    return { error: problem(410, "room_ended") };
  }
  const { results } = await env.DB.prepare("SELECT id, key_hash, joined_at, seen_at FROM room_members WHERE code = ?1").bind(code).all();
  return { room, members: results };
}

/**
 * Removes members who have gone quiet and hands the room on if the host is
 * among them. `presentId` is the member making this request, who is present
 * by definition. Writes only when something changed.
 */
async function settle(env, room, members, presentId, now) {
  const marked = members.map((m) => (m.id === presentId ? { ...m, seen_at: now } : m));
  const live = liveMembers(marked, now);
  const gone = marked.filter((m) => !live.includes(m));
  const writes = gone.map((m) => env.DB.prepare("DELETE FROM room_members WHERE id = ?1").bind(m.id));
  let host = room.host_member;
  if (!live.some((m) => m.id === host)) {
    host = nextHost(live, host, now);
    if (host) writes.push(env.DB.prepare("UPDATE rooms SET host_member = ?2 WHERE code = ?1").bind(room.code, host));
  }
  if (!host) {
    await deleteRoom(env, room.code);
    return { ended: true };
  }
  if (writes.length) await env.DB.batch(writes);
  return { room: { ...room, host_member: host }, live };
}

async function memberFor(request, members) {
  const key = request.headers.get(KEY_HEADER) || "";
  if (!/^[A-Za-z0-9_-]{16,64}$/.test(key)) return null;
  const hash = await sha256Hex(key);
  return members.find((m) => m.key_hash === hash) || null;
}

function snapshot(room, live, memberId, now, extra = {}) {
  return json({
    ...roomSnapshot({
      code: room.code,
      state: rowToState(room),
      role: room.host_member === memberId ? "host" : "guest",
      members: live.length,
      now,
    }),
    ...extra,
  });
}

/** POST /v1/rooms { state: { episode_id, archive_id, file, position?, playing?, rate? } } */
async function create(request, env, ip, now) {
  if (await limited(env.ROOM_CREATE_LIMITER, ip)) return problem(429, "rate_limited");
  const { body, error } = await readJson(request, 8 * 1024);
  if (error) return error;
  const result = applyHostState(null, body.state, now);
  if (result.error) return problem(400, "bad_request", result.error);
  const s = result.state;
  // A code is checked against live rooms by the primary key, and a clash is
  // retried: what keeps a guess from landing is that the live set stays small.
  for (let attempt = 0; attempt < 10; attempt++) {
    const code = newCode();
    const member = await newMember(code, now);
    try {
      await env.DB.batch([
        env.DB.prepare(
          "INSERT INTO rooms (code, episode_id, archive_id, file, position, playing, rate, updated_at, generation, host_member, created_at, touched_at) " +
            "VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?8, ?8)",
        ).bind(code, s.episode_id, s.archive_id, s.file, s.position, s.playing ? 1 : 0, s.rate, s.updated_at, s.generation, member.id),
        insertMember(env, member),
      ]);
    } catch (e) {
      if (String(e).includes("UNIQUE")) continue;
      throw e;
    }
    const room = { code, ...s, playing: s.playing ? 1 : 0, host_member: member.id };
    return snapshot(room, [member], member.id, now, { member_key: member.key });
  }
  return problem(503, "no_free_code");
}

/** POST /v1/rooms/{code}/join: the code is the whole invitation. */
async function join(env, code, ip, now) {
  if (await limited(env.ROOM_JOIN_LIMITER, ip)) return problem(429, "rate_limited");
  const loaded = await loadRoom(env, code, now);
  if (loaded.error) return loaded.error;
  const settled = await settle(env, loaded.room, loaded.members, null, now);
  if (settled.ended) return problem(410, "room_ended");
  if (settled.live.length >= MAX_MEMBERS) return problem(409, "room_full");
  const member = await newMember(code, now);
  await env.DB.batch([insertMember(env, member), env.DB.prepare("UPDATE rooms SET touched_at = ?2 WHERE code = ?1").bind(code, now)]);
  const live = [...settled.live, { id: member.id, joined_at: now, seen_at: now }];
  return snapshot(settled.room, live, member.id, now, { member_key: member.key });
}

export async function handleRooms(url, request, env, ip) {
  const now = Date.now();
  const method = request.method;
  if (url.pathname === "/v1/rooms" || url.pathname === "/v1/rooms/") {
    return method === "POST" ? create(request, env, ip, now) : problem(405, "method_not_allowed");
  }
  const m = /^\/v1\/rooms\/([^/]+)(?:\/(join|state|leave))?$/.exec(url.pathname);
  if (!m) return problem(404, "not_found");
  let raw;
  try {
    raw = decodeURIComponent(m[1]);
  } catch {
    return problem(400, "bad_code");
  }
  const code = normalizeCode(raw);
  if (!code) return problem(400, "bad_code");
  const action = `${method} ${m[2] || ""}`;

  if (action === "POST join") return join(env, code, ip, now);
  if (!["GET ", "PUT state", "POST leave", "DELETE "].includes(action)) return problem(405, "method_not_allowed");

  const loaded = await loadRoom(env, code, now);
  if (loaded.error) return loaded.error;
  const me = await memberFor(request, loaded.members);
  if (!me) return problem(403, "not_a_member");
  if (await limited(env.ROOM_MEMBER_LIMITER, me.id)) return problem(429, "rate_limited");

  const settled = await settle(env, loaded.room, loaded.members, me.id, now);
  if (settled.ended) return problem(410, "room_ended");
  const { room, live } = settled;
  const isHost = room.host_member === me.id;

  if (action === "POST leave") {
    const writes = [env.DB.prepare("DELETE FROM room_members WHERE id = ?1").bind(me.id)];
    let host = room.host_member;
    if (isHost) {
      host = nextHost(live, me.id, now);
      if (host) writes.push(env.DB.prepare("UPDATE rooms SET host_member = ?2 WHERE code = ?1").bind(code, host));
    }
    if (!host) {
      await deleteRoom(env, code);
      return json({ left: true, room_ended: true });
    }
    await env.DB.batch(writes);
    return json({ left: true, room_ended: false });
  }

  if (action === "DELETE ") {
    if (!isHost) return problem(403, "host_only");
    await deleteRoom(env, code);
    return json({ ended: true });
  }

  if (action === "PUT state") {
    if (!isHost) return problem(403, "host_only", "only the host changes what plays");
    const { body, error } = await readJson(request, 8 * 1024);
    if (error) return error;
    const result = applyHostState(rowToState(room), body, now);
    if (result.error) return problem(400, "bad_request", result.error);
    const s = result.state;
    await env.DB.batch([
      env.DB.prepare(
        "UPDATE rooms SET episode_id = ?2, archive_id = ?3, file = ?4, position = ?5, playing = ?6, rate = ?7, " +
          "updated_at = ?8, generation = ?9, touched_at = ?8 WHERE code = ?1",
      ).bind(code, s.episode_id, s.archive_id, s.file, s.position, s.playing ? 1 : 0, s.rate, s.updated_at, s.generation),
      env.DB.prepare("UPDATE room_members SET seen_at = ?2 WHERE id = ?1").bind(me.id, now),
    ]);
    return snapshot({ ...room, ...s, playing: s.playing ? 1 : 0 }, live, me.id, now);
  }

  // GET: a read is presence too, written only when the last one is stale, so
  // a 2-second poll costs a D1 write every 20 seconds at most.
  if (now - me.seen_at > SEEN_REFRESH_MS) {
    await env.DB.prepare("UPDATE room_members SET seen_at = ?2 WHERE id = ?1").bind(me.id, now).run();
  }
  return snapshot(room, live, me.id, now);
}

/** The cron sweep: idle rooms, quiet members, and rooms left with no one are deleted, not just ignored. */
export async function sweepRooms(env, now = Date.now()) {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM room_members WHERE seen_at < ?1 OR code IN (SELECT code FROM rooms WHERE touched_at < ?2)").bind(
      now - MEMBER_GONE_MS,
      now - ROOM_IDLE_MS,
    ),
    env.DB.prepare("DELETE FROM rooms WHERE touched_at < ?1 OR code NOT IN (SELECT code FROM room_members)").bind(now - ROOM_IDLE_MS),
  ]);
}
