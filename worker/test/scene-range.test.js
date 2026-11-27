// One scene of a catalog play (docs/PLAYS-DESIGN.md section 2.12): the range a production and a read
// room may carry, the cast sheet cut to it, and the refusals. The client sends the WHOLE cast sheet;
// the Worker keeps the slice from `from` through `to`, so every rule that reads the cast covers only
// the range.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { call, env, installProviderKeys, signIn } from "./helpers.js";
import { cast, castOf, claim, consent, createBody, firstPart, invite, partAction, record, script, seedChosen } from "./plays-helpers.js";
import { castParts, linesOf } from "../src/plays-relay.js";

const NO_LIMIT = { USER_LIMITER: undefined, PLAY_JOIN_LIMITER: undefined, READ_CREATE_LIMITER: undefined };
const NO_DO = { ...NO_LIMIT, READ_ROOMS: undefined };

beforeEach(() => {
  installProviderKeys();
  vi.spyOn(console, "log").mockImplementation(() => {});
});
afterEach(() => vi.restoreAllMocks());

let n = 0;
const person = (label) => signIn(`range-${label}-${n++}`);
const make = (s, over) => call("POST", "/v1/plays/productions", { token: s.access_token, body: createBody(over), envOverride: NO_LIMIT });
const errorOf = async (r) => [r.status, (await r.json()).error];
const made = async (r) => {
  expect(r.status, await r.clone().text()).toBe(201);
  return r.json();
};

// The first speaking part's first line starts the range; it ends at the first line of a part that has not spoken yet.
const parts = castParts(cast);
const startAt = cast.findIndex(([, p]) => p === firstPart);
const seen = new Set();
let endAt = startAt;
for (let i = startAt; i < cast.length; i++) {
  seen.add(cast[i][1]);
  if (seen.size > 2) break;
  endAt = i;
}
const FROM = cast[startAt][0];
const TO = cast[endAt][0];
const RANGE = { from: FROM, to: TO };
const slice = cast.slice(startAt, endAt + 1);
const sliceParts = castParts(slice).map((p) => p.id);
const lastLine = cast[cast.length - 1][0];

describe("the fixture", () => {
  it("is a range with fewer parts than the whole play", () => {
    expect(sliceParts.length).toBeGreaterThan(0);
    expect(sliceParts.length).toBeLessThan(parts.length);
  });
});

describe("a production of one scene", () => {
  it("keeps the slice as its cast sheet and its range in the record", async () => {
    const s = await person("slice");
    const p = await made(await make(s, { range: RANGE, display_name: "Dir" }));
    expect(p.range).toEqual(RANGE);
    expect(Object.keys(p.parts)).toEqual(sliceParts);
    const row = await env.DB.prepare("SELECT cast_sheet, scene_range FROM play_productions WHERE id = ?1").bind(p.id).first();
    expect(JSON.parse(row.cast_sheet)).toEqual(slice);
    expect(JSON.parse(row.scene_range)).toEqual(RANGE);
    expect(p.next).toBe(sliceParts[0]);
  });

  it("checks the cast hash over the whole cast: a sheet already cut to the range is cast_mismatch", async () => {
    const s = await person("hash");
    const cut = slice.map(([id, part]) => ({ id, part }));
    expect(await errorOf(await make(s, { range: RANGE, cast: cut }))).toEqual([422, "cast_mismatch"]);
  });

  it("claim, next and silent cover only the parts in the range", async () => {
    const s = await person("parts");
    const p = await made(await make(s, { range: RANGE, display_name: "Dir" }));
    const outside = parts.map((x) => x.id).find((id) => !sliceParts.includes(id));
    expect(outside).toBeTruthy();
    expect((await claim(s, p.id, outside)).status).not.toBe(200);
    expect((await claim(s, p.id, firstPart)).status).toBe(200);
    expect((await consent(s, p.id)).status).toBe(204);
  });

  it("finishing a part needs only its lines inside the range", async () => {
    const s = await person("finish");
    const p = await made(await make(s, { range: RANGE, display_name: "Dir" }));
    expect((await claim(s, p.id, firstPart)).status).toBe(200);
    expect((await consent(s, p.id)).status).toBe(204);
    const inside = linesOf(slice, firstPart);
    const all = linesOf(cast, firstPart);
    expect(inside.length).toBeLessThanOrEqual(all.length);
    await seedChosen(p.id, s.user_id, inside.slice(1), firstPart);
    const short = await partAction(s, p.id, firstPart, "done");
    expect(short.status).toBe(409);
    expect((await short.json()).detail).toEqual([inside[0]]);
    await seedChosen(p.id, s.user_id, [inside[0]], firstPart);
    const done = await partAction(s, p.id, firstPart, "done");
    expect(done.status, await done.clone().text()).toBe(200);
    expect((await done.json()).next).toBe(sliceParts[1] ?? null);
    const after = await record(s, p.id);
    expect(after.parts[firstPart].status).toBe("done");
    expect(after.range).toEqual(RANGE);
  });

  it("an invite view carries the range and the range's parts", async () => {
    const s = await person("invite");
    const p = await made(await make(s, { range: RANGE, display_name: "Dir" }));
    const inv = await invite(s, p.id);
    const viewer = await person("viewer");
    const view = await (await call("POST", "/v1/plays/invites/view", { token: viewer.access_token, body: { token: inv.token } })).json();
    expect(view.range).toEqual(RANGE);
    expect(view.parts.map((x) => x.id)).toEqual(sliceParts);
    const open = await (await call("GET", "/v1/plays/open/invite", { headers: { "x-invite": inv.token } })).json();
    expect(open.range).toEqual(RANGE);
    expect(open.parts.map((x) => x.id)).toEqual(sliceParts);
  });

  it("an old production has no range key in any response", async () => {
    const s = await person("old");
    const p = await made(await make(s, { display_name: "Dir" }));
    expect("range" in p).toBe(false);
    expect("range" in (await record(s, p.id))).toBe(false);
    expect(Object.keys(p.parts)).toEqual(parts.map((x) => x.id));
    const inv = await invite(s, p.id);
    const viewer = await person("viewer");
    const view = await (await call("POST", "/v1/plays/invites/view", { token: viewer.access_token, body: { token: inv.token } })).json();
    expect("range" in view).toBe(false);
    expect("range" in (await (await call("GET", "/v1/plays/open/invite", { headers: { "x-invite": inv.token } })).json())).toBe(false);
    // A null range is the whole play too.
    const whole = await made(await make(s, { range: null }));
    expect("range" in whole).toBe(false);
    expect(Object.keys(whole.parts)).toEqual(parts.map((x) => x.id));
  });

  it("a class production takes a range too", async () => {
    const t = await person("teacher");
    const c = await (await call("POST", "/v1/plays/classes", { token: t.access_token, body: { name: "Room 3" } })).json();
    const r = await call("POST", `/v1/plays/classes/${c.id}/productions`, { token: t.access_token, body: createBody({ range: RANGE }), envOverride: NO_LIMIT });
    const p = await made(r);
    expect(p.range).toEqual(RANGE);
    expect(Object.keys(p.parts)).toEqual(sliceParts);
  });
});

describe("bad ranges", () => {
  it("refuses a range with a malformed shape, an unknown id, or the wrong order, as bad_range", async () => {
    const s = await person("bad");
    const bad = [
      "L0001",
      [FROM, TO],
      { from: FROM },
      { from: 3, to: TO },
      { from: FROM, to: "L9999" },
      { from: "L9999", to: TO },
      { from: TO, to: FROM },
      {},
    ];
    for (const range of bad) expect(await errorOf(await make(s, { range })), JSON.stringify(range)).toEqual([400, "bad_range"]);
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM play_productions WHERE user_id = ?1").bind(s.user_id).first()).toEqual({ n: 0 });
  });

  it("allows one line, and the whole cast, as a range", async () => {
    const s = await person("edges");
    const one = await made(await make(s, { range: { from: FROM, to: FROM } }));
    expect(Object.keys(one.parts)).toEqual(castParts(cast.slice(startAt, startAt + 1)).map((x) => x.id));
    const all = await made(await make(s, { range: { from: cast[0][0], to: lastLine } }));
    expect(Object.keys(all.parts)).toEqual(parts.map((x) => x.id));
  });

  it("refuses a range on an own script", async () => {
    const s = await person("own");
    const own = { own: true, title: "The Pipes", script_id: `own-${crypto.randomUUID()}`, script_revision: "0123456789ab", cast: [{ id: "L0001", part: "directions" }, { id: "L0002", part: "role:ANNA" }] };
    const r = await call("POST", "/v1/plays/productions", { token: s.access_token, body: { ...own, range: { from: "L0001", to: "L0002" } }, envOverride: NO_LIMIT });
    expect(await errorOf(r)).toEqual([400, "bad_range"]);
    const plain = await call("POST", "/v1/plays/productions", { token: s.access_token, body: own, envOverride: NO_LIMIT });
    expect(plain.status, await plain.clone().text()).toBe(201);
  });
});

describe("the heading", () => {
  it("composes the title as the play's, a comma, and the heading", async () => {
    const s = await person("title");
    const p = await made(await make(s, { range: RANGE, heading: "  Scene II " }));
    expect(p.title).toBe(`${script.title}, Scene II`);
    const plain = await made(await make(s, { range: RANGE }));
    expect(plain.title).toBe(script.title);
    expect((await made(await make(s, { range: RANGE, heading: null }))).title).toBe(script.title);
  });

  it("is ignored without a range, even a refused one", async () => {
    const s = await person("ignored");
    const p = await made(await make(s, { heading: "www.example.com" }));
    expect(p.title).toBe(script.title);
    expect("range" in p).toBe(false);
  });

  it("passes the title filter and is 1 to 80 characters", async () => {
    const s = await person("filter");
    for (const heading of ["Scene www.example.com", "visit https://x.example", "", "   ", "x".repeat(81), 7, ["Scene"]]) {
      expect(await errorOf(await make(s, { range: RANGE, heading })), JSON.stringify(heading)).toEqual([422, "bad_name"]);
    }
    const edge = await made(await make(s, { range: RANGE, heading: "x".repeat(80) }));
    expect(edge.title).toBe(`${script.title}, ${"x".repeat(80)}`);
  });
});

describe("a read room of one scene", () => {
  const room = (body, token, envOverride = {}) => call("POST", "/v1/read", { body: { ...createBody(), ...body }, token, envOverride });
  const snapshotOf = async (code, key, envOverride = {}) => {
    const r = await call("POST", `/v1/read/${code}/join`, { body: {}, envOverride, headers: key ? { "x-read-key": key } : {} });
    expect(r.status, await r.clone().text()).toBe(200);
    return r.json();
  };

  for (const [name, over] of [["the Durable Object", {}], ["the D1 fallback", NO_DO]]) {
    it(`takes the range from the request and carries it in the snapshot (${name})`, async () => {
      const r = await room({ range: RANGE }, undefined, over);
      expect(r.status, await r.clone().text()).toBe(200);
      const opened = await r.json();
      const snap = await snapshotOf(opened.code, opened.key, over);
      expect(snap.range).toEqual(RANGE);
      expect(snap.cursor).toBe(FROM);
    });

    it(`a room with no range carries none in its snapshot (${name})`, async () => {
      const opened = await (await room({}, undefined, over)).json();
      const snap = await snapshotOf(opened.code, opened.key, over);
      expect("range" in snap).toBe(false);
      expect(snap.cursor).toBe(cast[0][0]);
    });
  }

  it("refuses a bad range, and a range on an own script", async () => {
    for (const range of [{ from: TO, to: FROM }, { from: FROM }, "L0002", { from: FROM, to: "L9999" }]) {
      expect(await errorOf(await room({ range })), JSON.stringify(range)).toEqual([400, "bad_range"]);
    }
    const s = await person("ownroom");
    const own = { own: true, title: "The Pipes", script_id: `own-${crypto.randomUUID()}`, script_revision: "0123456789ab", cast: [{ id: "L0001", part: "directions" }, { id: "L0002", part: "role:ANNA" }] };
    const p = await made(await call("POST", "/v1/plays/productions", { token: s.access_token, body: own, envOverride: NO_LIMIT }));
    await env.DB.prepare("UPDATE play_scripts SET bytes = 1, body = 'x' WHERE production_id = ?1").bind(p.id).run();
    const r = await call("POST", "/v1/read", {
      token: s.access_token,
      body: { script_id: own.script_id, script_revision: own.script_revision, cast: own.cast, production_id: p.id, range: { from: "L0001", to: "L0002" } },
    });
    expect(await errorOf(r)).toEqual([400, "bad_range"]);
  });

  it("takes the production's range, and refuses a different one", async () => {
    const s = await person("roomprod");
    const p = await made(await make(s, { range: RANGE, display_name: "Dir" }));
    const inherited = await room({ production_id: p.id }, s.access_token);
    expect(inherited.status, await inherited.clone().text()).toBe(200);
    const opened = await inherited.json();
    expect((await snapshotOf(opened.code, opened.key)).range).toEqual(RANGE);
    expect((await room({ production_id: p.id, range: RANGE }, s.access_token)).status).toBe(200);
    const other = { from: FROM, to: FROM };
    expect(await errorOf(await room({ production_id: p.id, range: other }, s.access_token))).toEqual([409, "range_mismatch"]);
    // A production with no range does not lend one, and a range on it is the request's own.
    const whole = await made(await make(s, { display_name: "Dir" }));
    const plain = await (await room({ production_id: whole.id }, s.access_token)).json();
    expect("range" in (await snapshotOf(plain.code, plain.key))).toBe(false);
    const scoped = await (await room({ production_id: whole.id, range: RANGE }, s.access_token)).json();
    expect((await snapshotOf(scoped.code, scoped.key)).range).toEqual(RANGE);
  });
});
