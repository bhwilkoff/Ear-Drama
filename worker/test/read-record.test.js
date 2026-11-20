// T5 (Decision 082, PLAYS-DESIGN §12.3 mode 3, §12.5, §12.6): Record in the room
// (a reader's take passes through the Worker to the room's receiving device, kept
// nowhere), names on join, a room that ended or never was, and pairing a TV.
import { describe, expect, it } from "vitest";
import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import worker from "../src/index.js";
import { call, env, installProviderKeys, signIn } from "./helpers.js";
import { cast, script, order, linesFor, wav, newTakeId, waitForReceiver } from "./plays-helpers.js";
import { PAIR_TTL_MS } from "../src/read-rooms.js";

const NO_DO = { READ_ROOMS: undefined };
const speaking = order.filter((p) => p.startsWith("role:"));
const body = (over = {}) => ({ script_id: script.id, script_revision: script.revision, cast: cast.map(([id, part]) => ({ id, part })), ...over });
const read = (method, path, { key, body: b, envOverride, headers, token, ip } = {}) =>
  call(method, `/v1/read${path}`, { body: b, envOverride, token, ip, headers: { ...(key ? { "x-read-key": key } : {}), ...headers } });
const ok = async (r) => {
  expect(r.status, await r.clone().text()).toBeLessThan(300);
  return r.json();
};
const open = (over = {}, opts = {}) => read("POST", "", { body: body(over), ...opts }).then(ok);
const enter = (code, want = {}, opts = {}) => read("POST", `/${code}/join`, { body: want, ...opts }).then(ok);
const send = (code, key, msg, opts = {}) => read("POST", `/${code}/send`, { key, body: msg, ...opts });
const errorOf = async (r) => (await r.json()).error;

function sendTake(code, key, lineID, { id = newTakeId(), bytes = wav(4800), meta = {}, envOverride } = {}) {
  const fields = { lineID, frames: (bytes.length - 44) / 3, sampleRate: 48000, ...meta };
  return read("PUT", `/${code}/takes/${id}`, {
    key,
    envOverride,
    body: bytes,
    headers: { "content-length": String(bytes.length), "x-take": JSON.stringify(fields) },
  }).then((r) => Object.assign(r, { takeId: id }));
}

function inbox(code, key, opts = {}) {
  return read("GET", `/${code}/takes/inbox`, { key, ...opts }).then(async (r) => {
    const bytes = r.status === 200 ? new Uint8Array(await r.arrayBuffer()) : null;
    return { status: r.status, take: r.headers.get("x-take") ? JSON.parse(r.headers.get("x-take")) : null, bytes, error: r.status >= 400 ? (await r.clone().json().catch(() => ({}))).error : null };
  });
}

/** An adult room in Record mode: the host leads and receives; Ann holds the first part. */
async function adultRecording(opts = {}) {
  const h = await open({}, opts);
  const ann = await enter(h.code, { name: "Ann" }, opts);
  expect((await send(h.code, ann.member_key, { type: "claim", part: speaking[0] }, opts)).status).toBe(200);
  expect((await send(h.code, h.member_key, { type: "mode", mode: "record" }, opts)).status).toBe(200);
  return { h, ann };
}

for (const [label, opts] of [["the Durable Object", {}], ["D1 polling", { envOverride: NO_DO }]]) {
  describe(`Record in the room over ${label}`, () => {
    it("a reader's take of their own line reaches the leader's device byte for byte, credited to them, and nothing is kept", async () => {
      const { h, ann } = await adultRecording(opts);
      const line = linesFor(speaking[0])[0];
      const bytes = wav(9600);
      const got = inbox(h.code, h.member_key, opts);
      await waitForReceiver(`read:${h.code}`);
      const sent = await sendTake(h.code, ann.member_key, line, { bytes, ...opts });
      expect(sent.status, await sent.clone().text()).toBe(201);
      const take = await got;
      expect(take.status).toBe(200);
      expect(take.bytes).toEqual(bytes);
      expect(take.take).toMatchObject({ id: sent.takeId, lineID: line, part: speaking[0], capture: "room", member: ann.you.id });
      // An adult room with no production writes no row: the take lives on the leader's device only.
      expect(await env.DB.prepare("SELECT 1 FROM play_takes WHERE id = ?1").bind(sent.takeId).first()).toBeNull();
    });

    it("only a line the reader holds, only in Record mode, only while the leader's device receives", async () => {
      const { h, ann } = await adultRecording(opts);
      const theirs = linesFor(speaking[1])[0];
      const mine = linesFor(speaking[0])[0];
      const other = await sendTake(h.code, ann.member_key, theirs, opts);
      expect(other.status).toBe(403);
      expect(await errorOf(other)).toBe("not_your_line");
      // A take the bleed check flagged holds the device voice, which never leaves the device.
      const bleed = await sendTake(h.code, ann.member_key, mine, { meta: { bleed: true }, ...opts });
      expect(bleed.status).toBe(422);
      expect(await errorOf(bleed)).toBe("bleed_flagged");
      const nobody = await sendTake(h.code, ann.member_key, mine, opts);
      expect(nobody.status).toBe(409);
      expect(await errorOf(nobody)).toBe("nobody_receiving");
      expect((await send(h.code, h.member_key, { type: "mode", mode: "read" }, opts)).status).toBe(200);
      const table = await sendTake(h.code, ann.member_key, mine, opts);
      expect(table.status).toBe(409);
      expect(await errorOf(table)).toBe("not_recording");
      // The leader's own device records into itself; a stranger's key is no member.
      expect(await errorOf(await sendTake(h.code, "x".repeat(32), mine, opts))).toBe("not_a_member");
    });

    it("only the receiving device holds the room's pickup", async () => {
      const { h, ann } = await adultRecording(opts);
      const r = await inbox(h.code, ann.member_key, opts);
      expect(r.status).toBe(403);
      expect(r.error).toBe("receivers_only");
    });

    it("names on join travel with members, and a refused name is refused", async () => {
      const { h, ann } = await adultRecording(opts);
      const snap = await (await read("GET", `/${h.code}`, { key: h.member_key, ...opts })).json();
      expect(snap.members.find((m) => m.id === ann.you.id).name).toBe("Ann");
      expect(snap.you.receives).toBe(true);
      expect(snap.receiver).toBe(h.you.id);
      expect((await read("POST", `/${h.code}/join`, { body: { name: "fuck" }, ...opts })).status).toBe(422);
      expect((await read("POST", `/${h.code}/join`, { body: { name: "x".repeat(41) }, ...opts })).status).toBe(422);
    });

    it("an ended reading says so; a code that never was says that", async () => {
      const h = await open({}, opts);
      const g = await enter(h.code, {}, opts);
      expect((await send(h.code, h.member_key, { type: "end" }, opts)).status).toBe(200);
      const after = await read("GET", `/${h.code}`, { key: g.member_key, ...opts });
      expect(after.status).toBe(410);
      expect(await errorOf(after)).toBe("room_ended");
      const late = await read("POST", `/${h.code}/join`, { body: {}, ...opts });
      expect(late.status).toBe(410);
      const never = await read("POST", "/ZZZZZZ/join", { body: {}, ...opts });
      expect(never.status).toBe(404);
      expect(await errorOf(never)).toBe("no_such_room");
    });
  });
}

describe("Record in the room in a class", () => {
  async function classRoom(label, { under13 = false } = {}) {
    installProviderKeys();
    const t = await signIn(`teacher-rec-${label}`);
    const c = await (await call("POST", "/v1/plays/classes", { token: t.access_token, body: { name: "Room 9", under13 } })).json();
    const roster = (await (await call("POST", `/v1/plays/classes/${c.id}/seats`, { token: t.access_token, body: { labels: ["Lucy", "Tom"] } })).json()).seats;
    const [lucySeat] = roster.map((x) => x.id);
    const p = await (await call("POST", `/v1/plays/classes/${c.id}/productions`, { token: t.access_token, body: body() })).json();
    expect((await call("PUT", `/v1/plays/productions/${p.id}/assignments`, { token: t.access_token, body: { assignments: [{ part: speaking[0], seat: lucySeat }] } })).status).toBe(200);
    const seatKey = (await (await call("POST", "/v1/plays/seat/claim", { body: { code: c.code, seat: lucySeat } })).json()).seat_key;
    const h = await open({ kind: "class", class_id: c.id, production_id: p.id, mode: "record" }, { token: t.access_token });
    const lucy = await enter(h.code, { seat: lucySeat, seat_key: seatKey });
    return { t, c, p, h, lucy, lucySeat };
  }

  it("a seat's take reaches the teacher's device and is written as the teacher's, credited to the seat", async () => {
    const { t, p, h, lucy, lucySeat } = await classRoom("pass");
    const line = linesFor(speaking[0])[0];
    const got = inbox(h.code, h.member_key);
    await waitForReceiver(p.id);
    const sent = await sendTake(h.code, lucy.member_key, line);
    expect(sent.status, await sent.clone().text()).toBe(201);
    const take = await got;
    expect(take.take).toMatchObject({ id: sent.takeId, lineID: line, seat: lucySeat, capture: "room", member: lucy.you.id });
    const row = await env.DB.prepare("SELECT user_id, seat_id, capture FROM play_takes WHERE id = ?1").bind(sent.takeId).first();
    expect(row).toEqual({ user_id: t.user_id, seat_id: lucySeat, capture: "room" });
  });

  it("the teacher receives even while a seat leads, and the seat that leads does not", async () => {
    const { h, lucy } = await classRoom("lead");
    expect((await send(h.code, h.member_key, { type: "lead", to: lucy.you.id })).status).toBe(200);
    const r = await inbox(h.code, lucy.member_key);
    expect(r.status).toBe(403);
    const snap = await (await read("GET", `/${h.code}`, { key: h.member_key })).json();
    expect(snap.you.receives).toBe(true);
  });

  it("an under-13 class sends no seat's voice until the school's consent", async () => {
    const { p, h, lucy } = await classRoom("u13", { under13: true });
    const got = inbox(h.code, h.member_key);
    await waitForReceiver(p.id);
    const r = await sendTake(h.code, lucy.member_key, linesFor(speaking[0])[0]);
    expect(r.status).toBe(403);
    expect(await errorOf(r)).toBe("school_consent_required");
    void got;
  });
});

describe("pairing a TV to a reading", () => {
  const pair = () => read("POST", "/pair").then(ok);
  const waitOn = (code, key) => read("GET", `/pair/${code}`, { headers: { "x-pair-key": key } });

  it("the TV shows a code, the leader types it, and the TV joins as the screen, even past a lock", async () => {
    const h = await open();
    expect((await send(h.code, h.member_key, { type: "lock", locked: true })).status).toBe(200);
    const tv = await pair();
    expect(tv.pair_code).toMatch(/^[0-9A-Z]{6}$/);
    expect(tv.expires_at - tv.server_time).toBe(PAIR_TTL_MS);
    expect(await (await waitOn(tv.pair_code, tv.pair_key)).json()).toMatchObject({ paired: false });
    // A reader cannot attach a screen; the leader can, typed in lower case with a space.
    const g = await read("POST", `/${h.code}/join`, { body: {} });
    expect(g.status).toBe(409);
    const typed = `${tv.pair_code.slice(0, 3).toLowerCase()} ${tv.pair_code.slice(3)}`;
    const attached = await read("POST", `/${h.code}/pair`, { key: h.member_key, body: { code: typed } });
    expect(attached.status, await attached.clone().text()).toBe(200);
    const joined = await (await waitOn(tv.pair_code, tv.pair_key)).json();
    expect(joined.you.role).toBe("screen");
    expect(joined.code).toBe(h.code);
    expect(typeof joined.member_key).toBe("string");
    // Used once.
    expect((await waitOn(tv.pair_code, tv.pair_key)).status).toBe(404);
  });

  it("only the leader attaches; a wrong key, an expired code, and a join claiming a pairing are refused", async () => {
    const h = await open();
    const reader = await enter(h.code);
    const tv = await pair();
    const r = await read("POST", `/${h.code}/pair`, { key: reader.member_key, body: { code: tv.pair_code } });
    expect(r.status).toBe(403);
    expect((await waitOn(tv.pair_code, "y".repeat(32))).status).toBe(404);
    await env.DB.prepare("UPDATE read_pairs SET expires_at = ?2 WHERE code = ?1").bind(tv.pair_code, Date.now() - 1).run();
    const late = await read("POST", `/${h.code}/pair`, { key: h.member_key, body: { code: tv.pair_code } });
    expect(late.status).toBe(410);
    expect(await errorOf(late)).toBe("pair_expired");
    expect((await waitOn(tv.pair_code, tv.pair_key)).status).toBe(410);
    expect((await send(h.code, h.member_key, { type: "lock", locked: true })).status).toBe(200);
    const sneak = await read("POST", `/${h.code}/join`, { body: { role: "screen", paired: true } });
    expect(sneak.status).toBe(409);
    expect(await errorOf(sneak)).toBe("joining_locked");
  });

  it("the TV's own code requests are limited per address, and the sweep deletes expired codes", async () => {
    const tv = await pair();
    await env.DB.prepare("UPDATE read_pairs SET expires_at = ?2 WHERE code = ?1").bind(tv.pair_code, Date.now() - 1).run();
    const ctx = createExecutionContext();
    await worker.scheduled(createScheduledController({ cron: "23 * * * *" }), env, ctx);
    await waitOnExecutionContext(ctx);
    expect(await env.DB.prepare("SELECT 1 FROM read_pairs WHERE code = ?1").bind(tv.pair_code).first()).toBeNull();
    const busy = await read("POST", "/pair", { envOverride: { READ_CREATE_LIMITER: { limit: async () => ({ success: false }) } } });
    expect(busy.status).toBe(429);
  });
});
