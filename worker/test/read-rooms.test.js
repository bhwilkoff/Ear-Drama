// Read rooms (Decision 082, R3c §8.1 T1-T3): the pure protocol against its
// golden cases, the Durable Object over sockets and HTTP, the D1 polling
// fallback, and the limits a classroom behind one address needs.
import { describe, expect, it } from "vitest";
import { createExecutionContext, createScheduledController, runInDurableObject, waitOnExecutionContext } from "cloudflare:test";
import worker from "../src/index.js";
import { call, env, installProviderKeys, signIn } from "./helpers.js";
import { cast, script, order, linesFor } from "./plays-helpers.js";
import golden from "./read-golden.json";
import protocolSource from "../src/read-protocol.js?raw";
import * as P from "../src/read-protocol.js";
import * as Room from "../src/room-protocol.js";

const body = (over = {}) => ({
  script_id: script.id,
  script_revision: script.revision,
  cast: cast.map(([id, part]) => ({ id, part })),
  ...over,
});
const NO_DO = { READ_ROOMS: undefined };

const read = (method, path, { key, body: b, ip, envOverride, headers, token, origin } = {}) =>
  call(method, `/v1/read${path}`, { body: b, ip, envOverride, token, origin, headers: { ...(key ? { "x-read-key": key } : {}), ...headers } });

async function open(over = {}, opts = {}) {
  const r = await read("POST", "", { body: body(over), ...opts });
  expect(r.status, await r.clone().text()).toBe(200);
  return r.json();
}

async function enter(code, want = {}, opts = {}) {
  const r = await read("POST", `/${code}/join`, { body: want, ...opts });
  expect(r.status, await r.clone().text()).toBe(200);
  return r.json();
}

const send = async (code, key, msg, opts = {}) => read("POST", `/${code}/send`, { key, body: msg, ...opts });
const poll = async (code, key, opts = {}) => (await read("GET", `/${code}`, { key, ...opts })).json();

/** A socket to a room, opened as a browser on eardrama.org would (through the CORS path), with its messages queued for `next()`. */
async function socket(code, key) {
  const r = await read("GET", `/${code}/socket`, { headers: { upgrade: "websocket" }, origin: "https://eardrama.org" });
  expect(r.status).toBe(101);
  const ws = r.webSocket;
  expect(ws).toBeTruthy();
  ws.accept();
  const inbox = [];
  const waiting = [];
  ws.addEventListener("message", (e) => {
    const m = JSON.parse(e.data);
    if (waiting.length) waiting.shift()(m);
    else inbox.push(m);
  });
  let closed = null;
  ws.addEventListener("close", (e) => (closed = e.code));
  const next = () =>
    inbox.length
      ? Promise.resolve(inbox.shift())
      : new Promise((resolve, reject) => {
          waiting.push(resolve);
          setTimeout(() => reject(new Error("no message within 3 s")), 3000);
        });
  /** The next message matching `pred`, skipping presence snapshots on the way. */
  const until = async (pred) => {
    for (let i = 0; i < 20; i++) {
      const m = await next();
      if (pred(m)) return m;
    }
    throw new Error("no matching message");
  };
  if (key) ws.send(JSON.stringify({ type: "hello", key }));
  return { ws, next, until, send: (m) => ws.send(JSON.stringify(m)), closed: () => closed };
}

const speaking = order.filter((p) => p.startsWith("role:"));

describe("read protocol (T1): rules against the shared golden cases", () => {
  it("imports nothing and names no transport", () => {
    expect(protocolSource).not.toMatch(/^\s*import\s/m);
    expect(protocolSource).not.toMatch(/\bfetch\s*\(/);
    expect(protocolSource).not.toMatch(/WebSocket|\benv\.|Date\.now|crypto\./);
  });

  it("the golden file's constants are the protocol's", () => {
    for (const [k, v] of Object.entries(golden.constants)) expect(P[k], k).toEqual(v);
  });

  for (const c of golden.cases) {
    it(`${c.fn}: ${c.note}`, () => {
      expect(JSON.parse(JSON.stringify(P[c.fn](...c.args)) ?? "null")).toStrictEqual(c.expect);
    });
  }

  it("a code means the same in a read room and a Listen Together room", () => {
    expect(P.CODE_ALPHABET).toBe(Room.CODE_ALPHABET);
    expect(P.CODE_LENGTH).toBe(Room.CODE_LENGTH);
    for (const t of ["abc-123", "o0il1z", "ab cd ef", "ABCDEU", "", "z z z z z z"]) expect(P.normalizeCode(t)).toBe(Room.normalizeCode(t));
    const bytes = [7, 250, 33, 64, 128, 1];
    expect(P.codeFromBytes(bytes)).toBe(Room.codeFromBytes(bytes));
    const samples = [{ t0: 10, server_time: 500, t1: 90 }, { t0: 100, server_time: 600, t1: 120 }];
    expect(P.clockOffset(samples)).toBe(Room.clockOffset(samples));
  });

  it("forty members is the room's size", () => {
    expect(P.MAX_MEMBERS).toBe(40);
  });
});

describe("read rooms over the Durable Object", () => {
  it("opens with a code and a leader key returned once, on the socket transport", async () => {
    const h = await open();
    expect(h.code).toMatch(new RegExp(`^[${P.CODE_ALPHABET}]{${P.CODE_LENGTH}}$`));
    expect(h.transport).toBe("socket");
    expect(h.member_key).toMatch(/^[A-Za-z0-9_-]{16,64}$/);
    expect(h.you.leads).toBe(true);
    expect(h.cursor).toBe(cast[0][0]);
    const again = await poll(h.code, h.member_key);
    expect(JSON.stringify(again)).not.toContain(h.member_key);
    expect(again).not.toHaveProperty("member_key");
    expect(JSON.stringify(again)).not.toContain("key_hash");
  });

  it("refuses a script that is not castable or a cast that does not match", async () => {
    expect((await read("POST", "", { body: body({ script_id: "nope" }) })).status).toBe(422);
    const tampered = body();
    tampered.cast[0].part = tampered.cast[0].part === "directions" ? "sound" : "directions";
    expect((await read("POST", "", { body: tampered })).status).toBe(422);
  });

  it("only the leader moves the cursor; a reader is refused; everyone reads the move", async () => {
    const h = await open();
    const g = await enter(h.code);
    expect(g.you.leads).toBe(false);
    const line = cast[3][0];
    expect((await send(h.code, g.member_key, { type: "cursor", line, base: 0 })).status).toBe(403);
    const r = await send(h.code, h.member_key, { type: "cursor", line, base: 0 });
    expect(r.status).toBe(200);
    expect((await r.json()).cursor).toBe(line);
    const seen = await poll(h.code, g.member_key);
    expect(seen.cursor).toBe(line);
    expect(seen.cursor_gen).toBe(1);
  });

  it("a member key from another room or none at all is not a member", async () => {
    const a = await open();
    const b = await open();
    expect((await read("GET", `/${a.code}`, { key: b.member_key })).status).toBe(403);
    expect((await read("GET", `/${a.code}`)).status).toBe(403);
    expect((await read("GET", "/ZZZZZZ", { key: a.member_key })).status).toBe(404);
  });

  it("over sockets: hello first, then the leader's Next reaches every member in one message", async () => {
    const h = await open();
    const g = await enter(h.code);
    const lead = await socket(h.code, h.member_key);
    const follow = await socket(h.code, g.member_key);
    await lead.until((m) => m.type === "snapshot" && m.present === 2);
    await follow.until((m) => m.type === "snapshot" && m.present === 2);
    const line = cast[1][0];
    lead.send({ type: "cursor", line, base: 0 });
    const moved = await follow.until((m) => m.type === "snapshot" && m.cursor === line);
    expect(moved.cursor_gen).toBe(1);
    follow.send({ type: "ping", t0: 5 });
    const pong = await follow.until((m) => m.type === "pong");
    expect(pong.t0).toBe(5);
    expect(typeof pong.server_time).toBe("number");
    lead.ws.close();
    follow.ws.close();
  });

  it("a socket that has not said hello cannot act, and a wrong key is closed", async () => {
    const h = await open();
    const anon = await socket(h.code);
    anon.send({ type: "cursor", line: cast[1][0], base: 0 });
    expect((await anon.next()).error).toBe("hello_first");
    expect((await poll(h.code, h.member_key)).cursor).toBe(cast[0][0]);
    const bad = await socket(h.code, "x".repeat(32));
    expect((await bad.next()).error).toBe("not_a_member");
    anon.ws.close();
  });

  it(`holds ${P.MAX_MEMBERS} members and answers the next "This reading is full"`, async () => {
    const h = await open();
    for (let i = 1; i < P.MAX_MEMBERS; i++) await enter(h.code);
    const r = await read("POST", `/${h.code}/join`, { body: {} });
    expect(r.status).toBe(409);
    expect((await r.json()).error).toBe("room_full");
  });

  it("first claim wins, and the second claimant learns who holds the part", async () => {
    const h = await open();
    const a = await enter(h.code);
    const b = await enter(h.code);
    expect((await send(h.code, a.member_key, { type: "claim", part: speaking[0] })).status).toBe(200);
    const r = await send(h.code, b.member_key, { type: "claim", part: speaking[0] });
    expect(r.status).toBe(409);
    expect(await r.json()).toEqual({ error: "part_taken", detail: a.you.id });
    const s = await poll(h.code, a.member_key);
    expect(s.you.parts).toEqual([{ part: speaking[0], from: null, to: null }]);
  });

  it("a class room is opened only by the class's teacher, and its readers join by seat with the seat's key", async () => {
    installProviderKeys();
    const t = await signIn("teacher-read-1");
    const other = await signIn("someone-else-read-1");
    const c = await (await call("POST", "/v1/plays/classes", { token: t.access_token, body: { name: "Room 12" } })).json();
    const roster = (await (await call("POST", `/v1/plays/classes/${c.id}/seats`, { token: t.access_token, body: { labels: ["Lucy", "Tom"] } })).json()).seats;
    const [s1, s2] = roster.map((x) => x.id);
    const made = await call("POST", `/v1/plays/classes/${c.id}/productions`, { token: t.access_token, body: body() });
    expect(made.status).toBe(201);
    const pid = (await made.json()).id;
    expect((await call("PUT", `/v1/plays/productions/${pid}/assignments`, { token: t.access_token, body: { assignments: [{ part: speaking[0], seat: s1 }] } })).status).toBe(200);
    const seatKey = async (seat, move) => {
      const r = await call("POST", "/v1/plays/seat/claim", { body: { code: c.code, seat, move } });
      expect(r.status, await r.clone().text()).toBe(201);
      return (await r.json()).seat_key;
    };
    const lucyKey = await seatKey(s1);
    const tomKey = await seatKey(s2);
    // Seats and casting in the request are ignored: the room takes the class's roster and the production's assignments.
    const klass = { kind: "class", class_id: c.id, production_id: pid, seats: [{ id: "fake", label: "Mallory" }], assignments: [] };
    expect((await read("POST", "", { body: body(klass) })).status).toBe(401);
    expect((await read("POST", "", { body: body(klass), token: other.access_token })).status).toBe(403);
    const h = await open(klass, { token: t.access_token });
    expect(h.kind).toBe("class");
    expect(h.seats.map((x) => x.label)).toEqual(["Lucy", "Tom"]);
    expect((await read("POST", `/${h.code}/join`, { body: {} })).status).toBe(400);
    const keyless = await read("POST", `/${h.code}/join`, { body: { seat: s1 } });
    expect(keyless.status).toBe(403);
    expect((await keyless.json()).error).toBe("seat_key_required");
    expect((await read("POST", `/${h.code}/join`, { body: { seat: s1, seat_key: tomKey } })).status).toBe(403);
    const lucy = await enter(h.code, { seat: s1, seat_key: lucyKey });
    expect(lucy.you.parts).toEqual([{ part: speaking[0], from: null, to: null }]);
    expect(lucy.next_mine.line).toBe(linesFor(speaking[0])[0]);
    const second = await read("POST", `/${h.code}/join`, { body: { seat: s1, seat_key: lucyKey } });
    expect((await second.json()).error).toBe("seat_in_use");
    // Move here: a second device takes the seat with a new key, and the first device's key stops opening it.
    const movedKey = await seatKey(s1, true);
    expect((await read("POST", `/${h.code}/join`, { body: { seat: s1, seat_key: lucyKey, move: true } })).status).toBe(403);
    const moved = await enter(h.code, { seat: s1, seat_key: movedKey, move: true });
    expect(moved.you.seat).toBe(s1);
    expect((await poll(h.code, lucy.member_key)).you.seat).toBe(null);
    expect((await send(h.code, lucy.member_key, { type: "claim", part: speaking[1] })).status).toBe(403);
    // Taking a seat inside the room needs that seat's key too.
    const tom = await enter(h.code, { seat: s2, seat_key: tomKey });
    const grab = await send(h.code, tom.member_key, { type: "seat", seat: s1, move: true });
    expect(grab.status).toBe(403);
    expect((await grab.json()).error).toBe("seat_key_required");
    const screen = await enter(h.code, { role: "screen" });
    expect(screen.you.role).toBe("screen");
  });

  it("a class room's production must be that class's, of the same script", async () => {
    installProviderKeys();
    const t = await signIn("teacher-read-2");
    const c = await (await call("POST", "/v1/plays/classes", { token: t.access_token, body: { name: "Room 13" } })).json();
    const loose = await (await call("POST", "/v1/plays/productions", { token: t.access_token, body: body() })).json();
    const r = await read("POST", "", { body: body({ kind: "class", class_id: c.id, production_id: loose.id }), token: t.access_token });
    expect(r.status).toBe(404);
    expect((await r.json()).error).toBe("no_such_production");
  });

  it("the leader ends the room for everyone", async () => {
    const h = await open();
    const g = await enter(h.code);
    expect((await send(h.code, g.member_key, { type: "end" })).status).toBe(403);
    expect((await send(h.code, h.member_key, { type: "end" })).status).toBe(200);
    expect((await read("GET", `/${h.code}`, { key: g.member_key })).status).toBe(410);
  });

  // 2026-11-23 the account hit its Durable Object limit: an adult room whose
  // leader left with nobody to hand the lead to set its alarm in the past,
  // and every alarm set the next one in the past again, for six hours.
  it("an adult room whose leader left alone never sets its alarm in the past", async () => {
    const h = await open();
    const room = env.READ_ROOMS.get(env.READ_ROOMS.idFromName(h.code));
    const at = await runInDurableObject(room, async (instance, ctx) => {
      const gone = Date.now() - P.LEADER_GONE_MS - 60_000;
      instance.world = { ...instance.world, members: instance.world.members.map((m) => ({ ...m, seen_at: gone })) };
      await instance.alarm();
      return ctx.storage.getAlarm();
    });
    expect(at).toBeGreaterThan(Date.now() + 60_000);
  });
});

describe("the D1 polling fallback", () => {
  it("opens on polling when the Worker has no Durable Object, and refuses a socket", async () => {
    const h = await open({}, { envOverride: NO_DO });
    expect(h.transport).toBe("poll");
    const row = await env.DB.prepare("SELECT room, members FROM read_rooms WHERE code = ?1").bind(h.code).first();
    expect(row).toBeTruthy();
    expect(row.members).not.toContain(h.member_key);
    // With the binding back, the room is still found in D1 and still polled.
    expect((await poll(h.code, h.member_key)).code).toBe(h.code);
    expect((await read("GET", `/${h.code}/socket`, { headers: { upgrade: "websocket" } })).status).toBe(409);
  });

  it("two claims at once: exactly one wins", async () => {
    const h = await open({}, { envOverride: NO_DO });
    const a = await enter(h.code, {}, { envOverride: NO_DO });
    const b = await enter(h.code, {}, { envOverride: NO_DO });
    const rs = await Promise.all([a, b].map((m) => send(h.code, m.member_key, { type: "claim", part: speaking[0] }, { envOverride: NO_DO })));
    expect(rs.map((r) => r.status).sort()).toEqual([200, 409]);
  });

  it("the hourly sweep deletes idle rooms", async () => {
    const h = await open({}, { envOverride: NO_DO });
    await env.DB.prepare("UPDATE read_rooms SET touched_at = touched_at - ?2 WHERE code = ?1").bind(h.code, P.ROOM_IDLE_MS + 1000).run();
    const ctx = createExecutionContext();
    await worker.scheduled(createScheduledController({ cron: "23 * * * *" }), env, ctx);
    await waitOnExecutionContext(ctx);
    expect(await env.DB.prepare("SELECT 1 FROM read_rooms WHERE code = ?1").bind(h.code).first()).toBeNull();
  });
});

/**
 * T2: one script of messages through both transports. Member ids are random,
 * so each snapshot is compared with ids replaced by the script's names.
 */
describe("T2: both transports carry the same messages to the same state", () => {
  async function run(envOverride) {
    const o = envOverride ? { envOverride } : {};
    const host = await open({}, o);
    const ann = await enter(host.code, {}, o);
    const bob = await enter(host.code, {}, o);
    const tv = await enter(host.code, { role: "screen" }, o);
    const who = { [host.you.id]: "host", [ann.you.id]: "ann", [bob.you.id]: "bob", [tv.you.id]: "tv" };
    const k = { host: host.member_key, ann: ann.member_key, bob: bob.member_key, tv: tv.member_key };
    const lines = cast.map((l) => l[0]);
    const script = [
      ["ann", { type: "claim", part: speaking[0] }],
      ["bob", { type: "claim", part: speaking[0] }],
      ["bob", { type: "claim", part: speaking[1] }],
      ["tv", { type: "claim", part: speaking[1] }],
      ["host", { type: "cursor", line: lines[2], base: 0 }],
      ["host", { type: "cursor", line: lines[2], base: 0 }],
      ["host", { type: "cursor", line: lines[5], base: 0 }],
      ["ann", { type: "cursor", line: lines[6], base: 1 }],
      ["host", { type: "mode", mode: "record" }],
      ["host", { type: "lock", locked: true }],
      ["host", { type: "lead", to: "tv" }],
      ["host", { type: "lead", to: "ann" }],
      ["ann", { type: "cursor", line: lines[4], base: 1 }],
      ["bob", { type: "release", part: speaking[1] }],
    ];
    const ids = Object.fromEntries(Object.entries(who).map(([id, name]) => [name, id]));
    const statuses = [];
    for (const [name, msg] of script) {
      const m = msg.type === "lead" ? { ...msg, to: ids[msg.to] } : msg;
      const r = await send(host.code, k[name], m, o);
      statuses.push([r.status, r.status === 200 ? null : (await r.json()).error]);
    }
    const late = await read("POST", `/${host.code}/join`, { body: {}, ...o });
    statuses.push([late.status, (await late.json()).error]);
    const final = await poll(host.code, k.bob, o);
    const name = (id) => who[id] || id;
    return {
      statuses,
      state: {
        mode: final.mode,
        cursor: final.cursor,
        cursor_gen: final.cursor_gen,
        generation: final.generation,
        locked: final.locked,
        leader: name(final.leader),
        claims: Object.fromEntries(Object.entries(final.claims).map(([p, id]) => [p, name(id)])),
        members: final.members.map((m) => ({ ...m, id: name(m.id) })),
        you: { ...final.you, id: name(final.you.id) },
        next_mine: final.next_mine,
        reads_now: { ...final.reads_now, holder: name(final.reads_now.holder), members: final.reads_now.members.map(name) },
        present: final.present,
      },
    };
  }

  it("the Durable Object and D1 polling end in the same state after the same script", async () => {
    const socketRun = await run(null);
    const pollRun = await run(NO_DO);
    expect(socketRun.statuses).toEqual(pollRun.statuses);
    expect(socketRun.state).toEqual(pollRun.state);
    // The script did something: a refusal for each rule it crossed, and a moved room.
    expect(socketRun.statuses.map((s) => s[1])).toEqual([
      null,
      "part_taken",
      null,
      "readers_only",
      null,
      null,
      "stale",
      "leader_only",
      null,
      null,
      "screens_do_not_lead",
      null,
      null,
      null,
      "joining_locked",
    ]);
    expect(socketRun.state).toMatchObject({ mode: "record", cursor: cast[4][0], leader: "ann", locked: true });
  });
});

describe("T3: a classroom behind one address", () => {
  it("forty members from one address read without a 429, and the 61st join in a minute is refused", async () => {
    const ip = "203.0.113.40";
    const h = await open({}, { ip });
    const keys = [];
    for (let i = 1; i < P.MAX_MEMBERS; i++) keys.push((await enter(h.code, {}, { ip })).member_key);
    // 40 members polling 16 times each: past the Worker-wide 600 a minute, never a 429.
    let limitedCount = 0;
    for (let round = 0; round < 16; round++) {
      const rs = await Promise.all([h.member_key, ...keys].map((key) => read("GET", `/${h.code}`, { key, ip })));
      limitedCount += rs.filter((r) => r.status === 429).length;
    }
    expect(limitedCount).toBe(0);
  }, 60_000);

  it("the 61st join from one address in a minute is refused", async () => {
    // Miniflare's rate-limit windows are aligned to the wall clock (epoch = floor(now / period)), so
    // 61 joins that straddle a minute boundary reset the count and this test failed under load
    // (2026-11-19 mutation run). Start the joins at the top of a window so all 61 land in one.
    const intoMinute = Date.now() % 60_000;
    if (intoMinute > 15_000) await new Promise((r) => setTimeout(r, 60_000 - intoMinute + 50));
    const ip = "203.0.113.42";
    const first = await open({}, { ip });
    for (let i = 1; i < P.MAX_MEMBERS; i++) await enter(first.code, {}, { ip });
    const second = await open({}, { ip });
    for (let i = P.MAX_MEMBERS; i <= 60; i++) await enter(second.code, {}, { ip });
    const r = await read("POST", `/${second.code}/join`, { body: {}, ip });
    expect(r.status).toBe(429);
  }, 120_000);

  it("one member key is limited on its own, so one device cannot use up the class's share", async () => {
    const ip = "203.0.113.41";
    const h = await open({}, { ip });
    const other = await enter(h.code, {}, { ip });
    let status = 200;
    for (let i = 0; i < 130 && status !== 429; i++) status = (await read("GET", `/${h.code}`, { key: h.member_key, ip })).status;
    expect(status).toBe(429);
    expect((await read("GET", `/${h.code}`, { key: other.member_key, ip })).status).toBe(200);
  }, 60_000);
});
