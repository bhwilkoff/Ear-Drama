import { describe, expect, it } from "vitest";
import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import worker from "../src/index.js";
import { call, env } from "./helpers.js";
import protocolSource from "../src/room-protocol.js?raw";
import {
  CODE_ALPHABET,
  CODE_LENGTH,
  MAX_MEMBERS,
  MEMBER_GONE_MS,
  ROOM_IDLE_MS,
  applyHostState,
  clockOffset,
  cleanCopy,
  correction,
  expectedPosition,
  nextHost,
  normalizeCode,
  pollInterval,
} from "../src/room-protocol.js";

const COPY = { archive_id: "OTRR_Suspense_Singles", file: "Suspense 48-03-11 The Lodger.mp3" };
const STATE = { episode_id: "suspense|1948-03-11", ...COPY, position: 12, playing: true, rate: 1 };

const room = (method, path, key, body, opts = {}) =>
  call(method, `/v1/rooms${path}`, { body, headers: key ? { "x-room-key": key } : {}, ...opts });

async function open(state = STATE) {
  const r = await room("POST", "", null, { state });
  expect(r.status).toBe(200);
  return r.json();
}

async function enter(code) {
  const r = await room("POST", `/${code}/join`);
  expect(r.status).toBe(200);
  return r.json();
}

const read = async (code, key) => (await room("GET", `/${code}`, key)).json();

async function quiet(key, ms) {
  const { sha256Hex } = await import("../src/jwt.js");
  await env.DB.prepare("UPDATE room_members SET seen_at = seen_at - ?2 WHERE key_hash = ?1").bind(await sha256Hex(key), ms).run();
}

describe("rooms: create and join", () => {
  it("a room opens with a six-character code and a host key returned once", async () => {
    const h = await open();
    expect(h.code).toMatch(new RegExp(`^[${CODE_ALPHABET}]{${CODE_LENGTH}}$`));
    expect(h.role).toBe("host");
    expect(h.member_key).toMatch(/^[A-Za-z0-9_-]{16,64}$/);
    expect(h.state).toMatchObject(STATE);
    expect(h.generation).toBe(1);
    const again = await read(h.code, h.member_key);
    expect(again).not.toHaveProperty("member_key");
    expect(JSON.stringify(again)).not.toContain(h.member_key);
  });

  it("the key is stored only as its hash", async () => {
    const h = await open();
    const rows = (await env.DB.prepare("SELECT * FROM room_members WHERE code = ?1").bind(h.code).all()).results;
    expect(JSON.stringify(rows)).not.toContain(h.member_key);
  });

  it("joining by the code, however it was heard, gives a guest the host's copy", async () => {
    const h = await open();
    const spoken = h.code.toLowerCase().replace(/0/g, "o").replace(/1/g, "l");
    const g = await enter(`${spoken.slice(0, 3)}-${spoken.slice(3)}`);
    expect(g.code).toBe(h.code);
    expect(g.role).toBe("guest");
    expect(g.members).toBe(2);
    expect(g.state).toMatchObject({ episode_id: STATE.episode_id, archive_id: COPY.archive_id, file: COPY.file });
    expect(g.member_key).not.toBe(h.member_key);
  });

  it("a room needs no account", async () => {
    const r = await room("POST", "", null, { state: STATE });
    expect(r.status).toBe(200);
  });

  it("a room cannot open without the copy, or with a copy that is a path or URL", async () => {
    const bad = [
      { episode_id: "x|1" },
      { episode_id: "x|1", archive_id: "item", file: "../other/file.mp3" },
      { episode_id: "x|1", archive_id: "item", file: "/etc/passwd" },
      { episode_id: "x|1", archive_id: "https://evil.example", file: "a.mp3" },
      { episode_id: "x|1", archive_id: "item", file: "a\\b.mp3" },
      { ...STATE, rate: 3 },
      { ...STATE, position: -1 },
    ];
    for (const state of bad) expect((await room("POST", "", null, { state })).status, JSON.stringify(state)).toBe(400);
  });

  it("a wrong or missing code is refused", async () => {
    expect((await room("POST", "/ABC/join")).status).toBe(400);
    expect((await room("POST", "/ABCDEU/join")).status).toBe(400);
    const r = await room("POST", "/ZZZZZZ/join");
    expect([404, 200]).toContain(r.status); // a random hit is possible in principle; a miss is 404
  });
});

describe("rooms: the host is the arbiter", () => {
  it("a guest cannot set state, and the room is unchanged", async () => {
    const h = await open();
    const g = await enter(h.code);
    const r = await room("PUT", `/${h.code}/state`, g.member_key, { position: 999, playing: false });
    expect(r.status).toBe(403);
    expect((await r.json()).error).toBe("host_only");
    const now = await read(h.code, h.member_key);
    expect(now.generation).toBe(1);
    expect(now.state.playing).toBe(true);
  });

  it("no key, or a key from another room, is not a member", async () => {
    const h = await open();
    const other = await open();
    expect((await room("GET", `/${h.code}`)).status).toBe(403);
    expect((await room("PUT", `/${h.code}/state`, other.member_key, { playing: false })).status).toBe(403);
    expect((await room("PUT", `/${h.code}/state`, "x".repeat(32), { playing: false })).status).toBe(403);
  });

  it("CONTROL: the host's write reaches the guest, stamped by the server", async () => {
    const h = await open();
    const g = await enter(h.code);
    const before = Date.now();
    const w = await room("PUT", `/${h.code}/state`, h.member_key, { position: 300, playing: false, rate: 1.5 });
    expect(w.status).toBe(200);
    const s = await read(h.code, g.member_key);
    expect(s.generation).toBe(2);
    expect(s.state).toMatchObject({ position: 300, playing: false, rate: 1.5, ...COPY });
    expect(s.state.updated_at).toBeGreaterThanOrEqual(before);
    expect(s.server_time).toBeGreaterThanOrEqual(s.state.updated_at);
  });

  it("the client cannot set the clock or the generation", async () => {
    const h = await open();
    await room("PUT", `/${h.code}/state`, h.member_key, { position: 5, updated_at: 1, generation: 99 });
    const s = await read(h.code, h.member_key);
    expect(s.generation).toBe(2);
    expect(s.state.updated_at).toBeGreaterThan(1000);
  });

  it("a new episode must name its copy; guests then follow the new copy", async () => {
    const h = await open();
    const g = await enter(h.code);
    const no = await room("PUT", `/${h.code}/state`, h.member_key, { episode_id: "suspense|1948-03-18", position: 0 });
    expect(no.status).toBe(400);
    const next = { episode_id: "suspense|1948-03-18", archive_id: "SuspenseOTR", file: "48-03-18.mp3", position: 0 };
    expect((await room("PUT", `/${h.code}/state`, h.member_key, next)).status).toBe(200);
    expect((await read(h.code, g.member_key)).state).toMatchObject(next);
  });

  it("an update that leaves out the copy keeps it", async () => {
    const h = await open();
    await room("PUT", `/${h.code}/state`, h.member_key, { playing: false });
    expect((await read(h.code, h.member_key)).state).toMatchObject(COPY);
  });
});

describe("rooms: leaving and host handoff", () => {
  it("when the host leaves, the member there longest becomes host and can drive", async () => {
    const h = await open();
    const g1 = await enter(h.code);
    const g2 = await enter(h.code);
    const { sha256Hex } = await import("../src/jwt.js");
    const order = [[h, 0], [g2, 1], [g1, 2]]; // g2 joined before g1, so g2 takes over
    for (const [m, i] of order) {
      await env.DB.prepare("UPDATE room_members SET joined_at = joined_at - ?2 WHERE key_hash = ?1")
        .bind(await sha256Hex(m.member_key), 30000 - i * 1000)
        .run();
    }
    const left = await room("POST", `/${h.code}/leave`, h.member_key);
    expect(await left.json()).toEqual({ left: true, room_ended: false });
    const a = await read(h.code, g2.member_key);
    expect(a).toMatchObject({ role: "host", members: 2 });
    expect((await read(h.code, g1.member_key)).role).toBe("guest");
    expect((await room("PUT", `/${h.code}/state`, g2.member_key, { playing: false })).status).toBe(200);
    expect((await room("PUT", `/${h.code}/state`, g1.member_key, { playing: true })).status).toBe(403);
    expect((await room("GET", `/${h.code}`, h.member_key)).status).toBe(403);
    expect((await read(h.code, g1.member_key)).state).toMatchObject({ playing: false, ...COPY });
  });

  it("a host who goes quiet is replaced on the next read", async () => {
    const h = await open();
    const g = await enter(h.code);
    await quiet(h.member_key, MEMBER_GONE_MS + 1000);
    const s = await read(h.code, g.member_key);
    expect(s.role).toBe("host");
    expect(s.members).toBe(1);
    expect((await room("GET", `/${h.code}`, h.member_key)).status).toBe(403);
  });

  it("CONTROL: a host who is merely slow stays host", async () => {
    const h = await open();
    const g = await enter(h.code);
    await quiet(h.member_key, MEMBER_GONE_MS - 5000);
    expect((await read(h.code, g.member_key)).role).toBe("guest");
    expect((await read(h.code, h.member_key)).role).toBe("host");
  });

  it("a guest leaving leaves the host in charge", async () => {
    const h = await open();
    const g = await enter(h.code);
    await room("POST", `/${h.code}/leave`, g.member_key);
    const s = await read(h.code, h.member_key);
    expect(s).toMatchObject({ role: "host", members: 1 });
  });

  it("the last one out ends the room, and its rows go with it", async () => {
    const h = await open();
    const r = await (await room("POST", `/${h.code}/leave`, h.member_key)).json();
    expect(r).toEqual({ left: true, room_ended: true });
    expect((await room("POST", `/${h.code}/join`)).status).toBe(404);
    expect(await env.DB.prepare("SELECT code FROM rooms WHERE code = ?1").bind(h.code).first()).toBeNull();
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM room_members WHERE code = ?1").bind(h.code).first()).n).toBe(0);
  });

  it("only the host can end the room", async () => {
    const h = await open();
    const g = await enter(h.code);
    expect((await room("DELETE", `/${h.code}`, g.member_key)).status).toBe(403);
    expect((await room("DELETE", `/${h.code}`, h.member_key)).status).toBe(200);
    expect((await room("GET", `/${h.code}`, g.member_key)).status).toBe(404);
  });
});

describe("rooms: size and expiry", () => {
  it(`a room holds ${MAX_MEMBERS} members and refuses the next`, async () => {
    const h = await open();
    for (let i = 1; i < MAX_MEMBERS; i++) await enter(h.code);
    const r = await room("POST", `/${h.code}/join`);
    expect(r.status).toBe(409);
    expect((await r.json()).error).toBe("room_full");
  });

  it("a member who went quiet frees a place", async () => {
    const h = await open();
    const keys = [];
    for (let i = 1; i < MAX_MEMBERS; i++) keys.push((await enter(h.code)).member_key);
    await quiet(keys[0], MEMBER_GONE_MS + 1000);
    expect((await room("POST", `/${h.code}/join`)).status).toBe(200);
  });

  it("a room idle past its limit is ended and deleted on the next read", async () => {
    const h = await open();
    const g = await enter(h.code);
    await env.DB.prepare("UPDATE rooms SET touched_at = touched_at - ?2 WHERE code = ?1").bind(h.code, ROOM_IDLE_MS + 1000).run();
    expect((await room("GET", `/${h.code}`, g.member_key)).status).toBe(410);
    expect(await env.DB.prepare("SELECT code FROM rooms WHERE code = ?1").bind(h.code).first()).toBeNull();
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM room_members WHERE code = ?1").bind(h.code).first()).n).toBe(0);
  });

  it("CONTROL: a room just inside its limit is still live", async () => {
    const h = await open();
    await env.DB.prepare("UPDATE rooms SET touched_at = touched_at - ?2 WHERE code = ?1").bind(h.code, ROOM_IDLE_MS - 60000).run();
    expect((await room("GET", `/${h.code}`, h.member_key)).status).toBe(200);
  });

  it("the sweep deletes idle rooms, quiet members, and empty rooms, and keeps live ones", async () => {
    const idle = await open();
    const empty = await open();
    const live = await open();
    const liveGuest = await enter(live.code);
    const quietGuest = await enter(live.code);
    await env.DB.prepare("UPDATE rooms SET touched_at = touched_at - ?2 WHERE code = ?1").bind(idle.code, ROOM_IDLE_MS + 1000).run();
    await quiet(empty.member_key, MEMBER_GONE_MS + 1000);
    await quiet(quietGuest.member_key, MEMBER_GONE_MS + 1000);
    const ctx = createExecutionContext();
    await worker.scheduled(createScheduledController(), env, ctx);
    await waitOnExecutionContext(ctx);
    const has = async (code) => !!(await env.DB.prepare("SELECT code FROM rooms WHERE code = ?1").bind(code).first());
    expect(await has(idle.code)).toBe(false);
    expect(await has(empty.code)).toBe(false);
    expect(await has(live.code)).toBe(true);
    expect((await read(live.code, liveGuest.member_key)).members).toBe(2);
    expect((await room("GET", `/${live.code}`, quietGuest.member_key)).status).toBe(403);
    const orphans = await env.DB.prepare("SELECT COUNT(*) AS n FROM room_members WHERE code NOT IN (SELECT code FROM rooms)").first();
    expect(orphans.n).toBe(0);
  });
});

describe("rooms: abuse limits", () => {
  const deny = { limit: async () => ({ success: false }) };
  const allow = { limit: async () => ({ success: true }) };

  it("creating is limited per address", async () => {
    const r = await room("POST", "", null, { state: STATE }, { envOverride: { ROOM_CREATE_LIMITER: deny } });
    expect(r.status).toBe(429);
  });

  it("joining is limited per address, keyed by the address", async () => {
    const h = await open();
    const seen = [];
    const spy = { limit: async ({ key }) => (seen.push(key), { success: false }) };
    const r = await room("POST", `/${h.code}/join`, null, undefined, { ip: "198.51.100.9", envOverride: { ROOM_JOIN_LIMITER: spy } });
    expect(r.status).toBe(429);
    expect(seen).toEqual(["198.51.100.9"]);
  });

  it("each member is limited by its own id, not its address", async () => {
    const h = await open();
    const seen = [];
    const spy = { limit: async ({ key }) => (seen.push(key), { success: false }) };
    const r = await room("GET", `/${h.code}`, h.member_key, undefined, { envOverride: { ROOM_MEMBER_LIMITER: spy } });
    expect(r.status).toBe(429);
    const id = (await env.DB.prepare("SELECT host_member FROM rooms WHERE code = ?1").bind(h.code).first()).host_member;
    expect(seen).toEqual([id]);
  });

  it("every room route has a per-address floor", async () => {
    expect((await room("POST", "/ABCDEF/join", null, undefined, { envOverride: { ROOM_LIMITER: deny } })).status).toBe(429);
  });

  it("CONTROL: with every room limiter allowing, the same calls pass", async () => {
    const over = { ROOM_LIMITER: allow, ROOM_CREATE_LIMITER: allow, ROOM_JOIN_LIMITER: allow, ROOM_MEMBER_LIMITER: allow };
    const r = await room("POST", "", null, { state: STATE }, { envOverride: over });
    expect(r.status).toBe(200);
    const h = await r.json();
    expect((await room("POST", `/${h.code}/join`, null, undefined, { envOverride: over })).status).toBe(200);
  });

  it("the real binding counts: the 21st join attempt a minute from one address is refused", async () => {
    let last;
    for (let i = 0; i < 21; i++) last = await room("POST", "/ZZZZZZ/join", null, undefined, { ip: "192.0.2.88" });
    expect(last.status).toBe(429);
  });

  it("CORS lets eardrama.org send the room key", async () => {
    const pre = await call("OPTIONS", "/v1/rooms/ABCDEF", { origin: "https://eardrama.org" });
    expect(pre.headers.get("access-control-allow-headers")).toContain("x-room-key");
  });
});

describe("room codes", () => {
  it("are random over the whole alphabet and never repeat among live rooms", async () => {
    const codes = new Set();
    const chars = new Set();
    for (let i = 0; i < 60; i++) {
      const { code } = await open();
      codes.add(code);
      for (const c of code) chars.add(c);
    }
    expect(codes.size).toBe(60);
    expect(chars.size).toBeGreaterThan(24);
    expect(CODE_ALPHABET.length ** CODE_LENGTH).toBeGreaterThanOrEqual(1e9);
  });

  it("normalize the same way on every stack", () => {
    expect(normalizeCode("ab-cd 2z")).toBe("ABCD2Z");
    expect(normalizeCode("oIl0Lo")).toBe("011010");
    expect(normalizeCode("ABCDEU")).toBeNull();
    expect(normalizeCode("ABCDE")).toBeNull();
    expect(normalizeCode("ABCDEFG")).toBeNull();
    expect(normalizeCode(42)).toBeNull();
  });
});

describe("the room protocol is pure", () => {
  it("imports nothing and names no transport", () => {
    expect(protocolSource).not.toMatch(/^\s*import\s/m);
    expect(protocolSource).not.toMatch(/\bfetch\s*\(/);
    expect(protocolSource).not.toMatch(/WebSocket|\benv\.|Date\.now|crypto\./);
  });

  it("extrapolates the host's position on the server clock", () => {
    const s = { position: 10, playing: true, rate: 1.5, updated_at: 1_000_000 };
    expect(expectedPosition(s, 1_004_000)).toBe(16);
    expect(expectedPosition({ ...s, playing: false }, 1_004_000)).toBe(10);
  });

  it("corrects drift by rate first, seeks only past two seconds, and follows pause at once", () => {
    const s = { position: 100, playing: true, rate: 1, updated_at: 0 };
    expect(correction(s, 0, { position: 100.1, playing: true })).toEqual({ action: "rate", rate: 1 });
    expect(correction(s, 0, { position: 101, playing: true })).toEqual({ action: "rate", rate: 0.97 });
    expect(correction(s, 0, { position: 99, playing: true })).toEqual({ action: "rate", rate: 1.03 });
    expect(correction(s, 0, { position: 103, playing: true })).toMatchObject({ action: "seek", position: 100 });
    expect(correction(s, 0, { position: 90, playing: true })).toMatchObject({ action: "seek", position: 100 });
    expect(correction({ ...s, playing: false }, 0, { position: 100, playing: true })).toMatchObject({ action: "pause" });
    expect(correction(s, 0, { position: 100.5, playing: false })).toMatchObject({ action: "play" });
    expect(correction({ ...s, rate: 2 }, 0, { position: 101, playing: true })).toEqual({ action: "rate", rate: 1.94 });
  });

  it("takes the clock from the fastest round trip, not the average", () => {
    const off = clockOffset([
      { t0: 0, server_time: 5000, t1: 800 },
      { t0: 1000, server_time: 5550, t1: 1100 },
      { t0: 2000, server_time: 7000, t1: 2900 },
    ]);
    expect(off).toBe(4500);
    expect(clockOffset([])).toBeNull();
  });

  it("polls fast while the room changes and slows when it is still", () => {
    expect(pollInterval(0, 30_000)).toBe(2000);
    expect(pollInterval(0, 61_000)).toBe(10_000);
  });

  it("hands the room to the longest-present live member", () => {
    const now = 1_000_000;
    const members = [
      { id: "host", joined_at: 1, seen_at: now },
      { id: "b", joined_at: 3, seen_at: now },
      { id: "a", joined_at: 2, seen_at: now - MEMBER_GONE_MS - 1 },
      { id: "c", joined_at: 3, seen_at: now },
    ];
    expect(nextHost(members, "host", now)).toBe("b");
    expect(nextHost([members[0]], "host", now)).toBeNull();
  });

  it("refuses a copy that could leave archive.org's item", () => {
    expect(cleanCopy("item", "dir/file.mp3")).toEqual({ archive_id: "item", file: "dir/file.mp3" });
    for (const f of ["../x.mp3", "a/../../x", "./x", "a//b", "/x", "a\\b", "a\nb", ""]) expect(cleanCopy("item", f), f).toBeNull();
    expect(cleanCopy("a/b", "x.mp3")).toBeNull();
  });

  it("the arbiter keeps the playhead moving through a write that leaves it out", () => {
    const cur = { episode_id: "e", archive_id: "i", file: "f", position: 10, playing: true, rate: 1, updated_at: 0, generation: 3 };
    const { state } = applyHostState(cur, { playing: false }, 5000);
    expect(state).toMatchObject({ position: 15, playing: false, generation: 4, updated_at: 5000 });
  });

  it("the arbiter stamps the clock and the generation itself", () => {
    const cur = { episode_id: "e", archive_id: "i", file: "f", position: 10, playing: false, rate: 1, updated_at: 0, generation: 3 };
    const { state } = applyHostState(cur, { position: 20, updated_at: 1, generation: 99 }, 5000);
    expect(state).toMatchObject({ updated_at: 5000, generation: 4 });
  });
});
