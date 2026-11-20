// Classes that own productions, seats without accounts, assignments, review,
// progress, and the teacher's publish (Decision 082, PLAYS-DESIGN §12.4-§12.5,
// R3c §4-§5). Owner, 2026-11-19: a class owns a production, visible only to
// its seats; parts a teacher assigns may all record at once; a seat records
// without an account, its takes belonging to the teacher's account; takes pass
// through to the teacher's device; the teacher uploads the full recording under
// their name, 13+ classes only. Scripts are picked from the data, never named.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { call, env, installProviderKeys, signIn } from "./helpers.js";
import { cast, createBody, linesFor, newTakeId, order, receive, waitForReceiver, wav } from "./plays-helpers.js";
import { isSpeaking } from "../src/plays-relay.js";
import { CONSENT_VERSION } from "../src/plays.js";
import { pastedLabels, MAX_NOTE } from "../src/plays-seats.js";
import { runArchive } from "../src/plays-archive.js";
import { MAX_SEATS } from "../src/read-protocol.js";
import relaySource from "../src/take-relay.js?raw";
import playsSource from "../src/plays.js?raw";
import seatsSource from "../src/plays-seats.js?raw";
import archiveSource from "../src/plays-archive.js?raw";
import wranglerToml from "../wrangler.toml?raw";

const KEYS = { IA_S3_ACCESS_KEY: "TESTIAACCESSseat", IA_S3_SECRET_KEY: "TESTIASECRETseat" };
const noLimit = { limit: async () => ({ success: false }) };

let archive;
beforeEach(() => {
  archive = [];
  installProviderKeys({
    extra: async (url, init = {}) => {
      if (!url.startsWith("https://s3.us.archive.org")) return null;
      if (url.includes("check_limit")) return Response.json({ over_limit: 0 });
      const headers = Object.fromEntries(Object.entries(init.headers || {}).map(([k, v]) => [k.toLowerCase(), v]));
      const bytes = init.body ? (await new Response(init.body).arrayBuffer()).byteLength : 0;
      archive.push({ method: init.method, url, headers, bytes });
      return new Response(null, { status: 200 });
    },
  });
});
afterEach(() => vi.restoreAllMocks());

let n = 0;
const person = (label) => signIn(`seat-${label}-${n++}`);
const [partA, partB] = order.filter(isSpeaking);

async function klass(teacher, { under13 = false, labels = ["Lucy", "Tom", "Ana"] } = {}) {
  const c = await (await call("POST", "/v1/plays/classes", { token: teacher.access_token, body: { name: "Room 7", under13 } })).json();
  const r = await call("POST", `/v1/plays/classes/${c.id}/seats`, { token: teacher.access_token, body: { labels } });
  expect(r.status).toBe(201);
  const seats = Object.fromEntries((await r.json()).seats.map((s) => [s.label, s.id]));
  return { ...c, seats };
}

async function claimSeat(code, seat, extra = {}) {
  const r = await call("POST", "/v1/plays/seat/claim", { body: { code, seat, ...extra } });
  expect(r.status, await r.clone().text()).toBe(201);
  return (await r.json()).seat_key;
}

async function classProduction(teacher, classId, over = {}) {
  const r = await call("POST", `/v1/plays/classes/${classId}/productions`, { token: teacher.access_token, body: createBody({ display_name: "Ms. Ortiz", ...over }) });
  expect(r.status, await r.clone().text()).toBe(201);
  return r.json();
}

const assign = (teacher, pid, assignments) => call("PUT", `/v1/plays/productions/${pid}/assignments`, { token: teacher.access_token, body: { assignments } });
const seatHome = (key, over = {}) => call("GET", "/v1/plays/seat", { headers: { "x-seat-key": key }, ...over });

function seatUpload(key, pid, lineID, { id = newTakeId(), bytes = wav(4800), meta = {}, envOverride, ip } = {}) {
  const fields = { lineID, frames: bytes.length > 44 ? (bytes.length - 44) / 3 : 0, sampleRate: 48000, capture: "room", ...meta };
  return call("PUT", `/v1/plays/seat/productions/${pid}/takes/${id}`, {
    body: bytes,
    envOverride,
    ip,
    headers: { "x-seat-key": key, "content-length": String(bytes.length), "x-take": JSON.stringify(fields) },
  }).then((r) => Object.assign(r, { takeId: id }));
}

async function seatRelayed(teacher, key, pid, lineID, opts) {
  const got = receive(teacher, pid);
  await waitForReceiver(pid);
  const sent = await seatUpload(key, pid, lineID, opts);
  return [sent, await got];
}

/** A class with Lucy on part A and Tom on part B, each holding a seat key. */
async function cast2(label, opts) {
  const teacher = await person(label);
  const c = await klass(teacher, opts);
  const p = await classProduction(teacher, c.id);
  expect((await assign(teacher, p.id, [{ part: partA, seat: c.seats.Lucy }, { part: partB, seat: c.seats.Tom }])).status).toBe(200);
  const lucy = await claimSeat(c.code, c.seats.Lucy);
  const tom = await claimSeat(c.code, c.seats.Tom);
  return { teacher, c, p, lucy, tom };
}

describe("seats: names the teacher typed, no accounts", () => {
  it("the teacher pastes a list: one a line, trimmed, duplicates once, a denied name refused, and the roster shows who is claimed", async () => {
    expect(pastedLabels({ text: " Lucy \nTom\n\nlucy\tAna; Group 3" })).toEqual(["Lucy", "Tom", "Ana", "Group 3"]);
    const t = await person("paste");
    const c = await (await call("POST", "/v1/plays/classes", { token: t.access_token, body: { name: "Room 1" } })).json();
    const r = await call("POST", `/v1/plays/classes/${c.id}/seats`, { token: t.access_token, body: { text: "Lucy\nTom\nlucy\nfuck\n\nGroup 3" } });
    expect(r.status).toBe(201);
    const out = await r.json();
    expect(out.seats.map((s) => s.label)).toEqual(["Lucy", "Tom", "Group 3"]);
    expect(out.refused.map((x) => x.label)).toEqual(["fuck"]);
    // Pasting again adds only the new names.
    const again = await (await call("POST", `/v1/plays/classes/${c.id}/seats`, { token: t.access_token, body: { labels: ["Tom", "Ana"] } })).json();
    expect(again.seats.map((s) => s.label)).toEqual(["Lucy", "Tom", "Group 3", "Ana"]);
    await claimSeat(c.code, out.seats[0].id);
    const roster = (await (await call("GET", `/v1/plays/classes/${c.id}`, { token: t.access_token })).json()).seats;
    expect(roster.find((s) => s.label === "Lucy").claimed).toBe(true);
    expect(roster.find((s) => s.label === "Tom").claimed).toBe(false);
    expect(JSON.stringify(roster)).not.toContain("key");
  });

  it(`a class holds at most ${MAX_SEATS} seats, and only its teacher adds, removes, or releases them`, async () => {
    const t = await person("max");
    const other = await person("max-other");
    const c = await klass(t, { labels: ["A1"] });
    const many = Array.from({ length: MAX_SEATS }, (_, i) => `Seat ${i}`);
    const r = await call("POST", `/v1/plays/classes/${c.id}/seats`, { token: t.access_token, body: { labels: many } });
    expect(r.status).toBe(409);
    expect((await r.json()).error).toBe("too_many_seats");
    expect((await call("POST", `/v1/plays/classes/${c.id}/seats`, { token: other.access_token, body: { labels: ["X"] } })).status).toBe(403);
    expect((await call("DELETE", `/v1/plays/classes/${c.id}/seats/${c.seats.A1}`, { token: other.access_token })).status).toBe(403);
    expect((await call("POST", `/v1/plays/classes/${c.id}/seats/${c.seats.A1}/release`, { token: other.access_token })).status).toBe(403);
  });

  it("a student picks a name with the class code and gets a seat key once, stored only as its hash", async () => {
    const t = await person("claim");
    const c = await klass(t);
    const list = await (await call("POST", "/v1/plays/seat/list", { body: { code: c.code.toLowerCase() } })).json();
    expect(list.seats.map((s) => s.label)).toEqual(["Lucy", "Tom", "Ana"]);
    expect(list.seats.every((s) => s.taken === false)).toBe(true);
    const key = await claimSeat(c.code, c.seats.Lucy);
    const row = await env.DB.prepare("SELECT key_hash FROM play_class_seats WHERE class_id = ?1 AND id = ?2").bind(c.id, c.seats.Lucy).first();
    expect(row.key_hash).not.toBe(key);
    expect(row.key_hash).toMatch(/^[0-9a-f]{64}$/);
    const home = await (await seatHome(key)).json();
    expect(home.seat).toEqual({ id: c.seats.Lucy, label: "Lucy" });
    expect(home.class).toMatchObject({ id: c.id, name: "Room 7" });
    expect((await call("POST", "/v1/plays/seat/claim", { body: { code: "ZZZZZZZZ", seat: c.seats.Lucy } })).status).toBe(404);
    expect((await call("POST", "/v1/plays/seat/claim", { body: { code: c.code, seat: "nope" } })).status).toBe(404);
    expect((await seatHome("x".repeat(32))).status).toBe(401);
    expect((await call("GET", "/v1/plays/seat")).status).toBe(401);
  });

  it("a held seat is refused to a second device until it asks to Move here; then the first device's key stops working", async () => {
    const t = await person("move");
    const c = await klass(t);
    const first = await claimSeat(c.code, c.seats.Tom);
    const second = await call("POST", "/v1/plays/seat/claim", { body: { code: c.code, seat: c.seats.Tom } });
    expect(second.status).toBe(409);
    expect((await second.json()).error).toBe("seat_in_use");
    const moved = await claimSeat(c.code, c.seats.Tom, { move: true });
    expect((await seatHome(first)).status).toBe(401);
    expect((await seatHome(moved)).status).toBe(200);
  });

  it("Release lets the device go and the next one take the seat; removing a seat drops its casting", async () => {
    const { teacher, c, p, lucy } = await cast2("release");
    expect((await call("POST", `/v1/plays/classes/${c.id}/seats/${c.seats.Lucy}/release`, { token: teacher.access_token })).status).toBe(204);
    expect((await seatHome(lucy)).status).toBe(401);
    await claimSeat(c.code, c.seats.Lucy);
    expect((await call("DELETE", `/v1/plays/classes/${c.id}/seats/${c.seats.Tom}`, { token: teacher.access_token })).status).toBe(204);
    const rec = await (await call("GET", `/v1/plays/productions/${p.id}`, { token: teacher.access_token })).json();
    expect(rec.assignments.map((a) => a.seat)).toEqual([c.seats.Lucy]);
  });
});

describe("class productions and their casting", () => {
  it("only the class's teacher makes one; every seat of the class sees it without an invite, and nobody else", async () => {
    const t = await person("prod");
    const other = await person("prod-other");
    const c = await klass(t);
    expect((await call("POST", `/v1/plays/classes/${c.id}/productions`, { token: other.access_token, body: createBody() })).status).toBe(403);
    const p = await classProduction(t, c.id);
    expect(p.class_id).toBe(c.id);
    const key = await claimSeat(c.code, c.seats.Ana);
    const home = await (await seatHome(key)).json();
    expect(home.productions.map((x) => x.id)).toEqual([p.id]);
    expect((await call("GET", `/v1/plays/productions/${p.id}`, { token: other.access_token })).status).toBe(404);
    // A seat of another class does not see it.
    const elsewhere = await klass(other, { labels: ["Zed"] });
    const zed = await claimSeat(elsewhere.code, elsewhere.seats.Zed);
    expect((await (await seatHome(zed)).json()).productions).toEqual([]);
    expect((await seatUpload(zed, p.id, linesFor(partA)[0])).status).toBe(404);
  });

  it("assignments are the teacher's, for a class production, over the class's own seats, no line twice; a scene range splits a part", async () => {
    const t = await person("assign");
    const c = await klass(t);
    const p = await classProduction(t, c.id);
    const loose = await (await call("POST", "/v1/plays/productions", { token: t.access_token, body: createBody() })).json();
    expect((await assign(t, loose.id, [])).status).toBe(422);
    expect((await assign(t, p.id, [{ part: partA, seat: "not-a-seat" }])).status).toBe(422);
    expect((await assign(t, p.id, [{ part: partA, seat: c.seats.Lucy }, { part: partA, seat: c.seats.Tom }])).status).toBe(422);
    const lines = linesFor(partA);
    const mid = Math.floor(lines.length / 2);
    const split = [
      { part: partA, seat: c.seats.Lucy, to: lines[mid - 1] },
      { part: partA, seat: c.seats.Tom, from: lines[mid] },
    ];
    const r = await assign(t, p.id, split);
    expect(r.status, await r.clone().text()).toBe(200);
    // Each seat records only inside its range.
    const tom = await claimSeat(c.code, c.seats.Tom);
    const outside = await seatUpload(tom, p.id, lines[0]);
    expect(outside.status).toBe(403);
    expect((await outside.json()).error).toBe("not_assigned");
    expect((await r.json()).assignments).toEqual([
      { part: partA, from: null, to: lines[mid - 1], seat: c.seats.Lucy },
      { part: partA, from: lines[mid], to: null, seat: c.seats.Tom },
    ]);
    const student = await person("assign-student");
    expect((await call("PUT", `/v1/plays/productions/${p.id}/assignments`, { token: student.access_token, body: { assignments: [] } })).status).toBe(404);
  });
});

describe("a seat's take passes through to the teacher's device", () => {
  it("an assigned line reaches the waiting teacher byte for byte; the take is the teacher's account's, named for the seat", async () => {
    const { teacher, p, c, lucy } = await cast2("seat-take");
    const line = linesFor(partA)[0];
    const bytes = wav(9600);
    const [sent, got] = await seatRelayed(teacher, lucy, p.id, line, { bytes });
    expect(sent.status, await sent.clone().text()).toBe(201);
    expect(got.bytes).toEqual(bytes);
    expect(got.take).toMatchObject({ id: sent.takeId, lineID: line, part: partA, seat: c.seats.Lucy, capture: "room" });
    const row = await env.DB.prepare("SELECT user_id, seat_id, capture FROM play_takes WHERE id = ?1").bind(sent.takeId).first();
    expect(row).toEqual({ user_id: teacher.user_id, seat_id: c.seats.Lucy, capture: "room" });
  });

  it("only a line assigned to the seat, and nothing in a production with no assignments", async () => {
    const { teacher, c, p, lucy } = await cast2("seat-unassigned");
    const r = await seatUpload(lucy, p.id, linesFor(partB)[0]);
    expect(r.status).toBe(403);
    expect((await r.json()).error).toBe("not_assigned");
    const bare = await classProduction(teacher, c.id);
    expect((await seatUpload(lucy, bare.id, linesFor(partA)[0])).status).toBe(403);
  });

  it("is refused with 409 when the teacher's device is not receiving, and nothing is written", async () => {
    const { p, lucy } = await cast2("seat-none");
    const r = await seatUpload(lucy, p.id, linesFor(partA)[0]);
    expect(r.status).toBe(409);
    expect((await r.json()).error).toBe("nobody_receiving");
    expect(await env.DB.prepare("SELECT 1 FROM play_takes WHERE production_id = ?1").bind(p.id).first()).toBeNull();
  });

  it("every assigned part records at once: two seats' takes pass through together, claims bypassed", async () => {
    const { teacher, p, lucy, tom } = await cast2("seat-parallel");
    const gotA = receive(teacher, p.id);
    const gotB = receive(teacher, p.id);
    await waitForReceiver(p.id, 2);
    const [a, b] = await Promise.all([seatUpload(lucy, p.id, linesFor(partA)[0]), seatUpload(tom, p.id, linesFor(partB)[0])]);
    expect([a.status, b.status]).toEqual([201, 201]);
    const got = [await gotA, await gotB].map((g) => g.take.part).sort();
    expect(got).toEqual([partA, partB].sort());
    expect(await env.DB.prepare("SELECT 1 FROM play_parts WHERE production_id = ?1").bind(p.id).first()).toBeNull();
  });

  it("one take at a time from a seat: a second while the first is in flight is refused", async () => {
    const { teacher, p, lucy } = await cast2("seat-one");
    // The teacher's device takes the first pickup but has not read it yet, so the first take stays in flight.
    const first = call("GET", `/v1/plays/productions/${p.id}/takes/inbox`, { token: teacher.access_token });
    await waitForReceiver(p.id);
    const lines = linesFor(partA);
    const inFlight = seatUpload(lucy, p.id, lines[0], { bytes: wav(480000) });
    const pickup = await first;
    const again = await seatUpload(lucy, p.id, lines[1 % lines.length]);
    expect(again.status).toBe(409);
    expect((await again.json()).error).toBe("one_take_at_a_time");
    expect((await pickup.arrayBuffer()).byteLength).toBe(wav(480000).length);
    expect((await inFlight).status).toBe(201);
  });

  it("an under-13 class passes no seat's voice through until the school's consent is recorded (Decision 059)", async () => {
    const { p, lucy } = await cast2("seat-u13", { under13: true });
    const r = await seatUpload(lucy, p.id, linesFor(partA)[0]);
    expect(r.status).toBe(403);
    expect((await r.json()).error).toBe("school_consent_required");
  });

  it("the teacher's own device records any line (one microphone) and may credit it to a seat; it is recorded, not relayed", async () => {
    const { teacher, c, p } = await cast2("seat-onemic");
    const line = linesFor(partB)[0];
    const r = await call("PUT", `/v1/plays/productions/${p.id}/takes/${newTakeId()}`, {
      token: teacher.access_token,
      body: wav(4800),
      headers: { "content-length": String(wav(4800).length), "x-take": JSON.stringify({ lineID: line, frames: 4800, sampleRate: 48000, seat: c.seats.Tom, capture: "room" }) },
    });
    expect(r.status).toBe(201);
    expect(await r.json()).toMatchObject({ delivered: false, seat: c.seats.Tom });
  });
});

describe("review and progress", () => {
  it("the student chooses which take is offered; the teacher marks Approve or Again, and the note is shown to that seat only", async () => {
    const { teacher, p, lucy, tom } = await cast2("review");
    const line = linesFor(partA)[0];
    const [one] = await seatRelayed(teacher, lucy, p.id, line);
    const [two] = await seatRelayed(teacher, lucy, p.id, line);
    let home = await (await seatHome(lucy)).json();
    expect(home.productions[0].takes.map((t) => [t.id, t.chosen])).toEqual([[one.takeId, false], [two.takeId, true]]);
    const chose = await call("POST", `/v1/plays/seat/productions/${p.id}/chosen`, { headers: { "x-seat-key": lucy }, body: { take_id: one.takeId } });
    expect(chose.status).toBe(200);
    expect((await chose.json()).productions[0].takes.find((t) => t.id === one.takeId).chosen).toBe(true);
    // Tom cannot choose Lucy's take.
    expect((await call("POST", `/v1/plays/seat/productions/${p.id}/chosen`, { headers: { "x-seat-key": tom }, body: { take_id: one.takeId } })).status).toBe(404);
    const note = "Slower on the last word, please.";
    const r = await call("POST", `/v1/plays/productions/${p.id}/takes/${one.takeId}/review`, { token: teacher.access_token, body: { state: "again", note } });
    expect(r.status).toBe(200);
    home = await (await seatHome(lucy)).json();
    expect(home.productions[0].takes.find((t) => t.id === one.takeId).review).toMatchObject({ state: "again", note });
    expect(JSON.stringify(await (await seatHome(tom)).json())).not.toContain(note);
    expect((await (await call("GET", `/v1/plays/productions/${p.id}`, { token: teacher.access_token })).json()).reviews[one.takeId].state).toBe("again");
    expect((await call("POST", `/v1/plays/productions/${p.id}/takes/${one.takeId}/review`, { token: teacher.access_token, body: { state: "approved" } })).status).toBe(200);
    expect((await (await seatHome(lucy)).json()).productions[0].takes.find((t) => t.id === one.takeId).review.state).toBe("approved");
  });

  it("only the teacher reviews, with Approve or Again and a short typed note, of a take that exists", async () => {
    const { teacher, p, lucy } = await cast2("review-refuse");
    const [take] = await seatRelayed(teacher, lucy, p.id, linesFor(partA)[0]);
    const path = `/v1/plays/productions/${p.id}/takes/${take.takeId}/review`;
    const stranger = await person("review-stranger");
    expect((await call("POST", path, { token: stranger.access_token, body: { state: "approved" } })).status).toBe(404);
    expect((await call("POST", path, { token: teacher.access_token, body: { state: "great" } })).status).toBe(400);
    expect((await call("POST", path, { token: teacher.access_token, body: { state: "again", note: "x".repeat(MAX_NOTE + 1) } })).status).toBe(400);
    expect((await call("POST", `/v1/plays/productions/${p.id}/takes/${newTakeId()}/review`, { token: teacher.access_token, body: { state: "again" } })).status).toBe(404);
  });

  it("progress is counts per seat and part only: lines assigned, recorded, approved, asked again", async () => {
    const { teacher, c, p, lucy } = await cast2("progress");
    const lines = linesFor(partA);
    const [a] = await seatRelayed(teacher, lucy, p.id, lines[0]);
    await call("POST", `/v1/plays/productions/${p.id}/takes/${a.takeId}/review`, { token: teacher.access_token, body: { state: "approved" } });
    // The teacher's own take of Tom's line, credited to no seat, is not Tom's.
    const own = wav(4800);
    const t = await call("PUT", `/v1/plays/productions/${p.id}/takes/${newTakeId()}`, {
      token: teacher.access_token,
      body: own,
      headers: { "content-length": String(own.length), "x-take": JSON.stringify({ lineID: linesFor(partB)[0], frames: 4800, sampleRate: 48000 }) },
    });
    expect(t.status).toBe(201);
    const r = await call("GET", `/v1/plays/classes/${c.id}/progress`, { token: teacher.access_token });
    expect(r.status).toBe(200);
    const prog = (await r.json()).productions.find((x) => x.id === p.id);
    const lucyRow = prog.seats.find((s) => s.seat === c.seats.Lucy);
    expect(lucyRow).toEqual({ seat: c.seats.Lucy, label: "Lucy", parts: [{ part: partA, lines: lines.length, recorded: 1, approved: 1, again: 0 }] });
    expect(prog.seats.find((s) => s.seat === c.seats.Tom).parts[0]).toMatchObject({ part: partB, lines: linesFor(partB).length, recorded: 0 });
    const stranger = await person("progress-stranger");
    expect((await call("GET", `/v1/plays/classes/${c.id}/progress`, { token: stranger.access_token })).status).toBe(403);
  });
});

describe("the teacher publishes the full recording under their own name (13 and over only)", () => {
  /** Every speaking line chosen, as the teacher's device would hold them; returns the bytes per take. */
  async function whole(p, teacher) {
    const audio = new Map();
    const stmts = cast
      .filter(([, part]) => isSpeaking(part))
      .map(([line, part], i) => {
        const id = `CL-${p.id.slice(0, 8)}-${i}`;
        audio.set(id, wav(4800));
        return env.DB.prepare(
          "INSERT INTO play_takes (production_id, id, user_id, seat_id, line_id, part, file, content_type, bytes, frames, sample_rate, capture, created, uploaded_at, chosen) " +
            "VALUES (?1, ?2, ?3, NULL, ?4, ?5, ?6, 'audio/wav', ?7, 4800, 48000, 'room', 0, ?8, 1)",
        ).bind(p.id, id, teacher.user_id, line, part, `${id}.wav`, wav(4800).length, Date.now());
      });
    for (let i = 0; i < stmts.length; i += 100) await env.DB.batch(stmts.slice(i, i + 100));
    return audio;
  }
  const publish = (s, pid, body) => call("POST", `/v1/plays/productions/${pid}/publish`, { token: s.access_token, envOverride: KEYS, body });
  const agree = (s, pid) => call("POST", `/v1/plays/productions/${pid}/consent`, { token: s.access_token, body: { version: CONSENT_VERSION } });

  it("an under-13 class never publishes: refused with its own code, whatever else is in order", async () => {
    const { teacher, p } = await cast2("pub-u13", { under13: true });
    await whole(p, teacher);
    expect((await agree(teacher, p.id)).status).toBe(204);
    const r = await publish(teacher, p.id);
    expect(r.status).toBe(403);
    expect((await r.json()).error).toBe("under_13_never_published");
  });

  it("needs every speaking line, the teacher's own CC0 consent at the current version, and a name to credit", async () => {
    const { teacher, p } = await cast2("pub-gates");
    const open = await publish(teacher, p.id);
    expect(open.status).toBe(409);
    expect((await open.json()).error).toBe("incomplete");
    await whole(p, teacher);
    const missing = await publish(teacher, p.id);
    expect(missing.status).toBe(409);
    expect(await missing.json()).toEqual({ error: "consent_missing", detail: [teacher.user_id] });
    expect((await agree(teacher, p.id)).status).toBe(204);
    await env.DB.prepare("UPDATE play_members SET display_name = '' WHERE production_id = ?1").bind(p.id).run();
    const unnamed = await publish(teacher, p.id);
    expect(unnamed.status).toBe(422);
    expect((await unnamed.json()).error).toBe("credit_name_required");
    expect((await publish(teacher, p.id, { credit_name: "fuck" })).status).toBe(422);
    const ok = await publish(teacher, p.id, { credit_name: "Ms. Ortiz" });
    expect(ok.status, await ok.clone().text()).toBe(201);
  });

  it("the item carries the teacher's chosen name and no seat's name; the teacher's device sends each line", { timeout: 60_000 }, async () => {
    const { teacher, p } = await cast2("pub-ok");
    const audio = await whole(p, teacher);
    expect((await agree(teacher, p.id)).status).toBe(204);
    expect((await publish(teacher, p.id, { credit_name: "Ms. Ortiz" })).status).toBe(201);
    await runArchive({ ...env, ...KEYS }, Date.now(), 1000);
    const { results: files } = await env.DB.prepare("SELECT line_id, take_id FROM play_archive_files WHERE production_id = ?1 ORDER BY seq").bind(p.id).all();
    for (const f of files) {
      const bytes = audio.get(f.take_id);
      const r = await call("PUT", `/v1/plays/productions/${p.id}/archive/files/${encodeURIComponent(f.line_id)}`, {
        token: teacher.access_token,
        body: bytes,
        envOverride: { ...KEYS, USER_LIMITER: undefined },
        headers: { "content-length": String(bytes.length) },
      });
      expect(r.status, await r.clone().text()).toBe(200);
    }
    const first = archive.find((x) => x.method === "PUT");
    const meta = JSON.stringify(first.headers);
    expect(first.headers["x-archive-meta01-creator"]).toBe("Ms. Ortiz");
    for (const label of ["Lucy", "Tom", "Ana"]) expect(meta).not.toContain(label);
    expect((await env.DB.prepare("SELECT status FROM play_archive_jobs WHERE production_id = ?1").bind(p.id).first()).status).toBe("published");
  });
});

describe("nothing at rest (owner 2026-11-19: \"We are using archive.org for storage, not cloudflare.\")", () => {
  it("no route, table or binding stores take audio: no R2 binding, no object key, and the relay never touches its storage", () => {
    expect(wranglerToml).not.toMatch(/^\s*\[\[r2_buckets\]\]/m);
    expect(wranglerToml).not.toMatch(/^\s*\[\[kv_namespaces\]\]/m);
    expect(relaySource).not.toMatch(/\.storage\.\w/);
    for (const src of [relaySource, playsSource, seatsSource, archiveSource]) expect(src).not.toMatch(/env\.TAKES\b/);
  });

  it("the take table holds a take's fields only", async () => {
    const cols = (await env.DB.prepare("PRAGMA table_info(play_takes)").all()).results.map((c) => [c.name, c.type]);
    expect(cols.map(([name]) => name)).not.toContain("object_key");
    expect(cols.filter(([, type]) => type === "BLOB")).toEqual([]);
  });
});

describe("limits by seat, never only by address", () => {
  it("each seat counts on its own, so a class behind one address is not one person; picking a seat has an address floor", async () => {
    const { teacher, p, lucy, tom, c } = await cast2("limits");
    const keys = [];
    const spy = { limit: async ({ key }) => (keys.push(key), { success: true }) };
    expect((await seatHome(lucy, { envOverride: { SEAT_LIMITER: spy }, ip: "203.0.113.9" })).status).toBe(200);
    expect((await seatHome(tom, { envOverride: { SEAT_LIMITER: spy }, ip: "203.0.113.9" })).status).toBe(200);
    expect(keys).toEqual([`${c.id}:${c.seats.Lucy}`, `${c.id}:${c.seats.Tom}`]);
    expect((await seatHome(lucy, { envOverride: { SEAT_LIMITER: noLimit } })).status).toBe(429);
    expect((await call("POST", "/v1/plays/seat/claim", { body: { code: c.code, seat: c.seats.Ana }, envOverride: { SEAT_JOIN_LIMITER: noLimit } })).status).toBe(429);
    expect((await call("POST", "/v1/plays/seat/list", { body: { code: c.code }, envOverride: { SEAT_JOIN_LIMITER: noLimit } })).status).toBe(429);
    const uploads = [];
    const upSpy = { limit: async ({ key }) => (uploads.push(key), { success: false }) };
    expect((await seatUpload(lucy, p.id, linesFor(partA)[0], { envOverride: { PLAY_UPLOAD_LIMITER: upSpy } })).status).toBe(429);
    expect(uploads).toEqual([`seat:${c.id}:${c.seats.Lucy}`]);
    void teacher;
  });
});

describe("class read rooms on the D1 polling transport hold the same seat-key rule", () => {
  it("a seat joins a polled class room only with its key", async () => {
    const { teacher, c, p, lucy } = await cast2("poll-seat");
    const NO_DO = { READ_ROOMS: undefined };
    const opened = await call("POST", "/v1/read", {
      token: teacher.access_token,
      envOverride: NO_DO,
      body: { ...createBody(), kind: "class", class_id: c.id, production_id: p.id },
    });
    expect(opened.status, await opened.clone().text()).toBe(200);
    const room = await opened.json();
    expect(room.transport).toBe("poll");
    expect((await call("POST", `/v1/read/${room.code}/join`, { envOverride: NO_DO, body: { seat: c.seats.Lucy } })).status).toBe(403);
    const ok = await call("POST", `/v1/read/${room.code}/join`, { envOverride: NO_DO, body: { seat: c.seats.Lucy, seat_key: lucy } });
    expect(ok.status).toBe(200);
    expect((await ok.json()).you.parts).toEqual([{ part: partA, from: null, to: null }]);
  });
});

describe("published works stay (owner 2026-10-29): a class going does not take its published production", () => {
  it("the teacher's account deletion removes the class; its published production stays listed, detached from the class", async () => {
    const { teacher, c, p } = await cast2("class-goes");
    const now = Date.now();
    await env.DB.batch([
      env.DB.prepare(
        "INSERT INTO play_archive_jobs (production_id, user_id, status, take_ids, created_at, updated_at, item_url, published_at) VALUES (?1, ?2, 'published', '[]', ?3, ?3, ?4, ?3)",
      ).bind(p.id, teacher.user_id, now, `https://archive.org/details/eardrama-${p.id.toLowerCase()}`),
      env.DB.prepare(
        "INSERT INTO play_archive_files (production_id, line_id, seq, part, take_id, name, state, updated_at) VALUES (?1, ?2, 1, ?3, 'T-kept', '0001-A.wav', 'sent', ?4)",
      ).bind(p.id, linesFor(partA)[0], partA, now),
    ]);
    expect((await call("GET", `/v1/plays/finished/${p.id}`)).status).toBe(200);
    expect((await call("DELETE", "/v1/account", { token: teacher.access_token })).status).toBe(200);
    expect(await env.DB.prepare("SELECT id FROM play_classes WHERE id = ?1").bind(c.id).first()).toBeNull();
    const row = await env.DB.prepare("SELECT class_id FROM play_productions WHERE id = ?1").bind(p.id).first();
    expect(row).not.toBeNull();
    expect(row.class_id).toBeNull();
    const listed = await (await call("GET", "/v1/plays/finished?limit=50")).json();
    expect(listed.productions.map((x) => x.id)).toContain(p.id);
    expect((await call("GET", `/v1/plays/finished/${p.id}`)).status).toBe(200);
  });
});
