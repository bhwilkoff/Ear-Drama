// T6 (Decision 082, PLAYS-DESIGN §12.11): Relay across time and the consent rule. A sender asks
// whether the receiving device is there before it sends; a take passes through and is kept nowhere;
// an adult room's anonymous reader is credited by the name they gave, never the leader, and a
// production with a line by a maker who has not consented cannot publish, and says who.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { call, env, installProviderKeys, signIn } from "./helpers.js";
import { cast, createBody, createProduction, linesFor, newTakeId, order, receive, record, seedChosen, wav, waitForReceiver, claim, consent } from "./plays-helpers.js";

const IA_KEYS = { IA_S3_ACCESS_KEY: "test-ia-access", IA_S3_SECRET_KEY: "test-ia-secret" };
const speaking = order.filter((p) => p.startsWith("role:"));
const flush = () => new Promise((r) => setTimeout(r, 20));

beforeEach(() => {
  installProviderKeys();
});
afterEach(() => vi.restoreAllMocks());

let n = 0;
const person = (label) => signIn(`relay-${label}-${n++}`);
const ok = async (r) => {
  expect(r.status, await r.clone().text()).toBeLessThan(300);
  return r.json();
};

async function classWithSeat(label) {
  const t = await person(`${label}-t`);
  const c = await ok(await call("POST", "/v1/plays/classes", { token: t.access_token, body: { name: "Room 3" } }));
  const seats = (await ok(await call("POST", `/v1/plays/classes/${c.id}/seats`, { token: t.access_token, body: { labels: ["Lucy"] } }))).seats;
  const p = await ok(await call("POST", `/v1/plays/classes/${c.id}/productions`, { token: t.access_token, body: createBody({ display_name: "Ms. Ortiz" }) }));
  expect((await call("PUT", `/v1/plays/productions/${p.id}/assignments`, { token: t.access_token, body: { assignments: [{ part: speaking[0], seat: seats[0].id }] } })).status).toBe(200);
  const key = (await ok(await call("POST", "/v1/plays/seat/claim", { body: { code: c.code, seat: seats[0].id } }))).seat_key;
  return { t, c, p, key, seat: seats[0].id };
}

const seatReceiver = (key, pid) => call("GET", `/v1/plays/seat/productions/${pid}/receiver`, { headers: { "x-seat-key": key } });

describe("is the receiver here? (a sender asks before it sends; nothing is stored)", () => {
  it("a seat is told whether the teacher's app is open, and the teacher's chosen name", async () => {
    const { t, p, key } = await classWithSeat("seat");
    expect(await ok(await seatReceiver(key, p.id))).toEqual({ receiving: false, name: "Ms. Ortiz" });
    const got = receive(t, p.id);
    await waitForReceiver(p.id);
    expect(await ok(await seatReceiver(key, p.id))).toEqual({ receiving: true, name: "Ms. Ortiz" });
    // The pickup ends quietly after its wait; a device seen in the last seconds still counts as here.
    void got;
  });

  it("is refused without a seat key, and for another class's production", async () => {
    const a = await classWithSeat("a");
    const b = await classWithSeat("b");
    expect((await call("GET", `/v1/plays/seat/productions/${a.p.id}/receiver`)).status).toBe(401);
    expect((await seatReceiver(b.key, a.p.id)).status).toBe(404);
  });

  it("a member of an adult production asks the same, and a stranger gets nothing", async () => {
    const director = await person("dir");
    const p = await createProduction(director, { display_name: "Ann Director" });
    const actor = await person("actor");
    const inv = await ok(await call("POST", `/v1/plays/productions/${p.id}/invites`, { token: director.access_token, body: {} }));
    expect((await call("POST", "/v1/plays/invites/claim", { token: actor.access_token, body: { token: inv.token, part: speaking[1], display_name: "Bo" } })).status).toBe(200);
    const ask = (s) => call("GET", `/v1/plays/productions/${p.id}/receiver`, { token: s.access_token });
    expect(await ok(await ask(actor))).toEqual({ receiving: false, name: "Ann Director" });
    const got = receive(director, p.id);
    await waitForReceiver(p.id);
    expect((await ok(await ask(actor))).receiving).toBe(true);
    void got;
    expect((await ask(await person("stranger"))).status).toBe(404);
  });

  it("the seat's take waits on its device while nobody receives, then passes through once the teacher's app is open", async () => {
    const { t, p, key } = await classWithSeat("later");
    const line = linesFor(speaking[0])[0];
    const bytes = wav(4800);
    const put = (id) => call("PUT", `/v1/plays/seat/productions/${p.id}/takes/${id}`, {
      body: bytes,
      headers: { "x-seat-key": key, "content-length": String(bytes.length), "x-take": JSON.stringify({ lineID: line, frames: 4800, sampleRate: 48000, capture: "direct" }) },
    });
    const id = newTakeId();
    const refused = await put(id);
    expect(refused.status).toBe(409);
    expect((await refused.json()).error).toBe("nobody_receiving");
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM play_takes WHERE id = ?1").bind(id).first()).toEqual({ n: 0 });
    await flush();
    // The teacher's app has been away longer than the grace; it comes back.
    const got = receive(t, p.id);
    await waitForReceiver(p.id);
    const sent = await put(id);
    expect(sent.status, await sent.clone().text()).toBe(201);
    const arrived = await got;
    expect(arrived.take).toMatchObject({ id, lineID: line });
    expect(arrived.bytes.length).toBe(bytes.length);
    const progress = await ok(await call("GET", `/v1/plays/classes/${(await ok(await call("GET", "/v1/plays/classes", { token: t.access_token }))).teaching[0].id}/progress`, { token: t.access_token }));
    const mine = progress.productions[0].seats[0].parts.find((x) => x.part === speaking[0]);
    expect(mine.recorded).toBe(1);
  });
});

describe("consent: credit the maker, never the leader (adult rooms and productions)", () => {
  const read = (method, path, { key, body, token, headers } = {}) =>
    call(method, `/v1/read${path}`, { body, token, headers: { ...(key ? { "x-read-key": key } : {}), ...headers } });

  async function adultRoom(label) {
    const director = await person(label);
    const p = await createProduction(director, { display_name: "Dee" });
    expect((await claim(director, p.id, speaking[0])).status).toBe(200);
    expect((await consent(director, p.id)).status).toBe(204);
    const room = await ok(await read("POST", "", { token: director.access_token, body: { script_id: p.scriptID, script_revision: p.scriptRevision, cast: cast.map(([id, part]) => ({ id, part })), production_id: p.id } }));
    return { director, p, room };
  }

  async function annRecords(room, name = "Ann") {
    const ann = await ok(await read("POST", `/${room.code}/join`, { body: name ? { name } : {} }));
    expect((await read("POST", `/${room.code}/send`, { key: ann.member_key, body: { type: "claim", part: speaking[1] } })).status).toBe(200);
    expect((await read("POST", `/${room.code}/send`, { key: room.member_key, body: { type: "mode", mode: "record" } })).status).toBe(200);
    return ann;
  }

  it("only the production's director opens a room on it", async () => {
    const director = await person("own");
    const p = await createProduction(director);
    const body = { script_id: p.scriptID, script_revision: p.scriptRevision, cast: cast.map(([id, part]) => ({ id, part })), production_id: p.id };
    expect((await read("POST", "", { body })).status).toBe(401);
    expect((await read("POST", "", { token: (await person("other")).access_token, body })).status).toBe(404);
    expect((await read("POST", "", { token: director.access_token, body })).status).toBe(200);
  });

  it("an anonymous reader's take is the maker's by name: the row keeps the name, the leader's device receives it, and the leader is not the performer", async () => {
    const { director, p, room } = await adultRoom("credit");
    const ann = await annRecords(room, "Ann");
    const line = linesFor(speaking[1])[0];
    const got = receive(director, p.id);
    await waitForReceiver(p.id);
    const id = newTakeId();
    const bytes = wav(4800);
    const r = await read("PUT", `/${room.code}/takes/${id}`, {
      key: ann.member_key,
      body: bytes,
      headers: { "content-length": String(bytes.length), "x-take": JSON.stringify({ lineID: line, frames: 4800, sampleRate: 48000 }) },
    });
    expect(r.status, await r.clone().text()).toBe(201);
    const arrived = await got;
    expect(arrived.take).toMatchObject({ id, lineID: line, credit: "Ann" });
    expect(await env.DB.prepare("SELECT user_id, credit FROM play_takes WHERE id = ?1").bind(id).first()).toEqual({ user_id: director.user_id, credit: "Ann" });
    const rec = await record(director, p.id);
    expect(rec.credits).toEqual([{ name: "Ann", lines: 1, consented: false }]);
    expect(rec.members.find((m) => m.user_id === director.user_id).performer).toBe(false);
    expect(rec.takes.find((t) => t.id === id).credit).toBe("Ann");
  });

  it("a reader who gave no name is credited as a reader, still never the leader", async () => {
    const { director, p, room } = await adultRoom("noname");
    const ann = await annRecords(room, "");
    const got = receive(director, p.id);
    await waitForReceiver(p.id);
    const bytes = wav(4800);
    const id = newTakeId();
    const r = await read("PUT", `/${room.code}/takes/${id}`, {
      key: ann.member_key,
      body: bytes,
      headers: { "content-length": String(bytes.length), "x-take": JSON.stringify({ lineID: linesFor(speaking[1])[0], frames: 4800, sampleRate: 48000 }) },
    });
    expect(r.status).toBe(201);
    expect((await got).take.credit).toBe("A reader");
  });

  async function completeWithCredit(label) {
    const director = await person(label);
    const p = await createProduction(director, { display_name: "Dee" });
    expect((await consent(director, p.id)).status).toBe(204);
    for (const part of order) {
      if (speaking.includes(part)) await seedChosen(p.id, director.user_id, linesFor(part), part);
      await env.DB.prepare("INSERT INTO play_parts (production_id, part, status, user_id, claimed_at) VALUES (?1, ?2, ?3, ?4, ?5) ON CONFLICT (production_id, part) DO UPDATE SET status = excluded.status")
        .bind(p.id, part, speaking.includes(part) ? "done" : "silent", director.user_id, Date.now())
        .run();
    }
    return { director, p };
  }
  const publish = (s, pid) => call("POST", `/v1/plays/productions/${pid}/publish`, { token: s.access_token, envOverride: IA_KEYS });

  it("Publish lists who still must consent: a credited maker blocks it by name, and the lines of an account that consented do not", async () => {
    const { director, p } = await completeWithCredit("gate");
    const line = linesFor(speaking[1])[0];
    await env.DB.prepare("UPDATE play_takes SET credit = 'Ann' WHERE production_id = ?1 AND line_id = ?2").bind(p.id, line).run();
    const r = await publish(director, p.id);
    expect(r.status).toBe(409);
    expect(await r.json()).toEqual({ error: "consent_missing", detail: [], credits: ["Ann"] });
    // Ann re-records her line under her own account and consents: the credit goes with the replaced take.
    await env.DB.prepare("UPDATE play_takes SET credit = NULL WHERE production_id = ?1").bind(p.id).run();
    expect((await publish(director, p.id)).status).toBe(201);
  });

  it("the credit is not a way to publish: it never counts as the leader's consent", async () => {
    const { director, p } = await completeWithCredit("nocount");
    await env.DB.prepare("UPDATE play_takes SET credit = 'Ann' WHERE production_id = ?1", ).bind(p.id).run();
    const r = await publish(director, p.id);
    expect(r.status).toBe(409);
    expect((await r.json()).credits).toEqual(["Ann"]);
  });
});
