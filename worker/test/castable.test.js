// What a production, a class production and a read room may be made from (R4-0): any play of
// the published library or of the bundle, and what may be published. The library is a fixture
// served by a stand-in for the site; nothing here reaches the network or the live catalog.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { call, env, installProviderKeys, signIn } from "./helpers.js";
import { cast, catalog, castOf, claim, consent, createBody, invite, record, script, seedChosen, wav } from "./plays-helpers.js";
import { LIBRARY, bodyFor, fakeLibrary, fixturePlay, rowOf } from "./library-helpers.js";
import { runArchive } from "../src/plays-archive.js";

const KEYS = { IA_S3_ACCESS_KEY: "TESTIAACCESS", IA_S3_SECRET_KEY: "TESTIASECRET" };
const ia = { ...env, ...KEYS };
// A production or a room costs a limiter count; these tests ask for many of each.
const NO_LIMIT = { USER_LIMITER: undefined };

let library;
let archive;
beforeEach(async () => {
  await env.DB.prepare("DELETE FROM play_archive_jobs").run();
  library = fakeLibrary();
  archive = [];
  installProviderKeys({
    extra: async (url, init) => {
      const host = new URL(url).hostname;
      if (host === "s3.us.archive.org" || host === "archive.org") {
        archive.push({ method: init?.method || "GET", url: String(url), headers: init?.headers || {} });
        if (init?.body instanceof ReadableStream) await new Response(init.body).arrayBuffer();
        return Response.json({ over_limit: 0, success: true });
      }
      return await library.handle(url, init);
    },
  });
  vi.spyOn(console, "log").mockImplementation(() => {});
});
afterEach(() => vi.restoreAllMocks());

let n = 0;
const person = (label) => signIn(`castable-${label}-${n++}`);
const make = (s, body) => call("POST", "/v1/plays/productions", { token: s.access_token, body, envOverride: NO_LIMIT });
const room = (body, token) => call("POST", "/v1/read", { body, token });
const produced = async (s) => (await env.DB.prepare("SELECT COUNT(*) AS n FROM play_productions WHERE user_id = ?1").bind(s.user_id).first()).n;
const errorOf = async (r) => [r.status, (await r.json()).error];
const job = (pid) => env.DB.prepare("SELECT * FROM play_archive_jobs WHERE production_id = ?1").bind(pid).first();
const files = async (pid) => (await env.DB.prepare("SELECT * FROM play_archive_files WHERE production_id = ?1 ORDER BY seq").bind(pid).all()).results;
const setPart = (pid, part, status, userId) =>
  env.DB.prepare(
    "INSERT INTO play_parts (production_id, part, status, user_id, claimed_at) VALUES (?1, ?2, ?3, ?4, ?5) ON CONFLICT (production_id, part) DO UPDATE SET status = excluded.status",
  )
    .bind(pid, part, status, userId, Date.now())
    .run();
const publish = (s, pid) => call("POST", `/v1/plays/productions/${pid}/publish`, { token: s.access_token, envOverride: KEYS });
const take = wav(48000);
const sendLine = (s, pid, line) =>
  call("PUT", `/v1/plays/productions/${pid}/archive/files/${line}`, {
    token: s.access_token,
    body: take,
    envOverride: KEYS,
    headers: { "content-length": String(take.length) },
  });

/** A complete production of `play` (its row as served now), every line the director's, consented. */
async function complete(play, label = "done") {
  const s = await person(label);
  const r = await make(s, bodyFor(play, { display_name: "Pat" }));
  expect(r.status, await r.clone().text()).toBe(201);
  const p = await r.json();
  for (const part of new Set(castOf(play).map(([, x]) => x))) {
    if (part.startsWith("role:")) await seedChosen(p.id, s.user_id, castOf(play).filter(([, x]) => x === part).map(([id]) => id), part);
    await setPart(p.id, part, part.startsWith("role:") ? "done" : "silent", s.user_id);
  }
  expect((await consent(s, p.id)).status).toBe(204);
  return { s, p };
}

describe("any play of the published library", () => {
  it("makes a production, with the title of the library's row and nothing of the client's", async () => {
    const play = fixturePlay();
    await library.put(play);
    const s = await person("make");
    const r = await make(s, bodyFor(play, { title: "Mine", rights: { bucket: "x" }, publishable: false, source: "https://evil.example/" }));
    expect(r.status, await r.clone().text()).toBe(201);
    expect(await r.json()).toMatchObject({ scriptID: play.id, scriptRevision: play.revision, title: play.title });
  });

  it("makes a class production", async () => {
    const play = fixturePlay();
    await library.put(play);
    const t = await person("teacher");
    const c = await (await call("POST", "/v1/plays/classes", { token: t.access_token, body: { name: "Room 9" } })).json();
    const r = await call("POST", `/v1/plays/classes/${c.id}/productions`, { token: t.access_token, body: bodyFor(play) });
    expect(r.status, await r.clone().text()).toBe(201);
    expect(await r.json()).toMatchObject({ scriptID: play.id, class_id: c.id });
  });

  it("opens a read room", async () => {
    const play = fixturePlay();
    await library.put(play);
    const r = await room(bodyFor(play));
    expect(r.status, await r.clone().text()).toBe(200);
    expect(await r.json()).toMatchObject({ cursor: "L0001" });
  });

  it("CONTROL: a bundled play needs no read of the library, and works with the site down", async () => {
    library.state.answer = () => {
      throw new Error("down");
    };
    const s = await person("bundled");
    expect((await make(s, createBody())).status).toBe(201);
    expect((await room({ script_id: script.id, script_revision: script.revision, cast: cast.map(([id, part]) => ({ id, part })) })).status).toBe(200);
    expect(library.requests).toEqual([]);
  });

  it("a cast sheet that is not the library's is refused, for a production and a room", async () => {
    const play = fixturePlay();
    await library.put(play);
    const other = bodyFor(play);
    other.cast[1].part = "role:BEN";
    const s = await person("cast");
    expect(await errorOf(await make(s, other))).toEqual([422, "cast_mismatch"]);
    expect(await errorOf(await room(other))).toEqual([422, "cast_mismatch"]);
    expect(await produced(s)).toBe(0);
  });

  it("a play the library does not hold is not castable", async () => {
    const play = fixturePlay();
    const s = await person("missing");
    expect(await errorOf(await make(s, bodyFor(play)))).toEqual([422, "not_castable"]);
    expect(await errorOf(await room(bodyFor(play)))).toEqual([422, "not_castable"]);
    expect(library.requests.length).toBe(2);
  });

  it("another revision is refused with the library's own", async () => {
    const play = fixturePlay();
    await library.put(play);
    const s = await person("rev");
    const old = bodyFor(play, { script_revision: "0123456789ab" });
    const r = await make(s, old);
    expect(r.status).toBe(409);
    expect(await r.json()).toEqual({ error: "revision_mismatch", detail: play.revision });
    expect(await errorOf(await room(old))).toEqual([409, "revision_mismatch"]);
    library.requests.length = 0;
    for (const bad of ["", "../../x", undefined, 7]) expect((await make(s, bodyFor(play, { script_revision: bad }))).status).toBe(409);
    expect(library.requests).toEqual([]);
    expect(await produced(s)).toBe(0);
  });

  it("the bundle's revision and the library's newer one are both made, each with its own cast sheet only", async () => {
    const newer = fixturePlay({ id: script.id });
    await library.put(newer);
    const s = await person("both");
    expect((await make(s, createBody())).status).toBe(201);
    expect((await make(s, bodyFor(newer))).status).toBe(201);
    expect(await errorOf(await make(s, createBody({ cast: bodyFor(newer).cast })))).toEqual([422, "cast_mismatch"]);
    expect(await errorOf(await make(s, bodyFor(newer, { cast: createBody().cast })))).toEqual([422, "cast_mismatch"]);
  });

  it("a bundled play the library has dropped is refused at any other revision with the bundle's", async () => {
    const s = await person("dropped");
    const r = await make(s, createBody({ script_revision: "0123456789ab" }));
    expect(r.status).toBe(409);
    expect(await r.json()).toEqual({ error: "revision_mismatch", detail: script.revision });
  });

  it("asks the site for one row, by a safe id, and follows no redirect", async () => {
    const play = fixturePlay();
    await library.put(play);
    const s = await person("url");
    expect((await make(s, bodyFor(play))).status).toBe(201);
    expect(library.requests.map((r) => r.url)).toEqual([`${LIBRARY}/castable/${play.id}.json?r=${play.revision}`]);
    expect(library.requests[0].init.redirect).toBe("manual");
    expect(library.requests[0].init.signal).toBeInstanceOf(AbortSignal);
    library.requests.length = 0;
    for (const id of ["../scripts/gut-1", "gut-1/../../x", "gut-1?x", "gut-1#", "gut-1.json", "own-1", "own-0f8e2c1a-0000-4000-8000-000000000000", "__proto__", "", 7, null, "GUT-1", "gut-1\n"]) {
      expect(await errorOf(await make(s, bodyFor(play, { script_id: id }))), String(id)).toEqual([422, "not_castable"]);
      expect(await errorOf(await room(bodyFor(play, { script_id: id }))), String(id)).toEqual([422, "not_castable"]);
    }
    expect(library.requests).toEqual([]);
  });

  it("a malformed cast sheet or name never costs a read of the library", async () => {
    const play = fixturePlay();
    const s = await person("cheap");
    expect((await make(s, bodyFor(play, { cast: [] }))).status).toBe(400);
    expect((await make(s, bodyFor(play, { display_name: "http://spam.example" }))).status).toBe(422);
    expect((await room(bodyFor(play, { cast: "x" }))).status).toBe(400);
    expect(library.requests).toEqual([]);
  });
});

describe("when the library cannot be read", () => {
  const faults = {
    "a network failure": () => {
      throw new Error("down");
    },
    "a 500": () => new Response("oops", { status: 500 }),
    "a redirect": () => new Response(null, { status: 302, headers: { location: "https://evil.example/row.json" } }),
    "a page that is not JSON": () => new Response("<!doctype html>", { status: 200 }),
    "JSON that is not an object": () => Response.json([]),
  };
  for (const [what, answer] of Object.entries(faults)) {
    it(`${what} is a clear refusal, and nothing is made`, async () => {
      const play = fixturePlay();
      library.state.answer = answer;
      const s = await person("fault");
      expect(await errorOf(await make(s, bodyFor(play)))).toEqual([503, "library_unavailable"]);
      expect(await errorOf(await room(bodyFor(play)))).toEqual([503, "library_unavailable"]);
      expect(await produced(s)).toBe(0);
    });
  }

  it("a body too large to be a row is never used, however good its fields", async () => {
    const play = fixturePlay();
    await library.put(play, { pad: "x".repeat(70_000) });
    const s = await person("large");
    expect(await errorOf(await make(s, bodyFor(play)))).toEqual([503, "library_unavailable"]);
  });

  it("a row that is not this play's, or is missing a field, is never used", async () => {
    const play = fixturePlay();
    const good = await rowOf(play);
    const s = await person("shape");
    const bad = [
      { id: "gut-1" },
      { format: 2 },
      { revision: "zz" },
      { cast: "abc" },
      { cast: undefined },
      { title: "" },
      { title: 5 },
      { lines: 0 },
      { source: 7 },
      { source: "javascript:alert(1)" },
      { rights: null },
      { rights: { bucket: 1, evidence: [] } },
      { rights: { bucket: "script_source_cleared", evidence: [{ claim: 1 }] } },
      { publishable: "yes" },
    ];
    for (const over of bad) {
      library.rows.set(play.id, { ...good, ...over });
      expect(await errorOf(await make(s, bodyFor(play))), JSON.stringify(over)).toEqual([503, "library_unavailable"]);
    }
    expect(await produced(s)).toBe(0);
    library.rows.set(play.id, good);
    expect((await make(s, bodyFor(play))).status).toBe(201);
  });

  it("a bundled play at a revision nobody here knows waits for the library rather than guess", async () => {
    library.state.answer = () => new Response("oops", { status: 502 });
    const s = await person("unknown-rev");
    expect(await errorOf(await make(s, createBody({ script_revision: "0123456789ab" })))).toEqual([503, "library_unavailable"]);
  });

  it("a failure is not remembered: the next ask reads again", async () => {
    const play = fixturePlay();
    const s = await person("again");
    library.state.answer = () => new Response("oops", { status: 500 });
    expect((await make(s, bodyFor(play))).status).toBe(503);
    library.state.answer = null;
    expect((await make(s, bodyFor(play))).status).toBe(422);
    await library.put(play);
    expect((await make(s, bodyFor(play))).status).toBe(201);
  });
});

describe("requests stay bounded (free plan)", () => {
  it("a revision once read is kept, so the site is asked once; another revision is asked for itself", async () => {
    const play = fixturePlay();
    await library.put(play);
    const s = await person("cache");
    expect((await make(s, bodyFor(play))).status).toBe(201);
    expect((await make(s, bodyFor(play))).status).toBe(201);
    expect((await room(bodyFor(play))).status).toBe(200);
    expect(library.requests.length).toBe(1);
    const refreshed = { ...play, revision: "00000000beef" };
    await library.put(refreshed);
    expect((await make(s, bodyFor(refreshed))).status).toBe(201);
    expect(library.requests.length).toBe(2);
  });

  it("a kept row is checked again before it is used", async () => {
    const play = fixturePlay();
    const { cacheKey } = await import("../src/plays-castable.js");
    const forged = await rowOf(play, { cast: "0".repeat(64), rights: { bucket: 9 } });
    await caches.default.put(cacheKey(play.id, play.revision), Response.json(forged, { headers: { "cache-control": "max-age=60" } }));
    await library.put(play);
    const s = await person("kept");
    expect((await make(s, bodyFor(play))).status).toBe(201);
    expect(library.requests.length).toBe(1);
  });

  it("everything after a production is made, and every poll of a room, reads the library never", async () => {
    const play = fixturePlay();
    await library.put(play);
    const { s, p } = await complete(play, "quiet");
    const h = await (await room(bodyFor(play))).json();
    library.requests.length = 0;
    await record(s, p.id);
    await invite(s, p.id);
    expect((await call("GET", `/v1/read/${h.code}`, { headers: { "x-read-key": h.member_key } })).status).toBe(200);
    expect((await publish(s, p.id)).status).toBe(201);
    await runArchive(ia, Date.now(), 1000);
    for (const f of await files(p.id)) expect((await sendLine(s, p.id, f.line_id)).status).toBe(200);
    await call("GET", "/v1/plays/finished");
    expect(library.requests).toEqual([]);
  });
});

describe("a play that leaves the library, or changes there, breaks no production already made", () => {
  it("its invite, its record and its archive.org item keep the row it was made from", async () => {
    const play = fixturePlay();
    await library.put(play);
    const { s, p } = await complete(play, "gone");
    library.rows.clear();
    library.state.answer = () => new Response("gone", { status: 500 });
    const inv = await invite(s, p.id);
    const open = await (await call("GET", "/v1/plays/open/invite", { headers: { "x-invite": inv.token } })).json();
    expect(open).toMatchObject({ title: play.title, source: play.source.url });
    expect((await claim(s, p.id, "role:ANNA")).status).toBe(409);
    expect((await publish(s, p.id)).status).toBe(201);
    await runArchive(ia, Date.now(), 1000);
    for (const f of await files(p.id)) expect((await sendLine(s, p.id, f.line_id)).status).toBe(200);
    expect((await job(p.id)).status).toBe("published");
    const first = archive.find((r) => r.method === "PUT");
    expect(first.headers["x-archive-meta-title"]).toBe(`${play.title} (Ear Drama recording)`);
    expect(first.headers["x-archive-meta-source"]).toBe(play.source.url);
    expect(first.headers["x-archive-meta-rights"]).toContain("Public domain in the USA.");
    const listed = (await (await call("GET", "/v1/plays/finished")).json()).productions.find((x) => x.id === p.id);
    expect(listed).toMatchObject({ source: play.source.url, script_id: play.id });
    expect(listed).not.toHaveProperty("script_row");
  });

  it("its director's room, and its class's, open at its own revision; nobody else's do", async () => {
    const play = fixturePlay();
    await library.put(play);
    const d = await person("dir");
    const t = await person("teach");
    const p = await (await make(d, bodyFor(play))).json();
    const c = await (await call("POST", "/v1/plays/classes", { token: t.access_token, body: { name: "Room 3" } })).json();
    const k = await (await call("POST", `/v1/plays/classes/${c.id}/productions`, { token: t.access_token, body: bodyFor(play) })).json();
    // The library moves on, and nothing is left of the old row but the productions' own.
    const newer = { ...play, revision: "00000000cafe", lines: play.lines.slice(0, 2) };
    await library.put(newer);
    const { cacheKey } = await import("../src/plays-castable.js");
    await caches.default.delete(cacheKey(play.id, play.revision));
    const attached = bodyFor(play, { production_id: p.id });
    const klass = bodyFor(play, { kind: "class", class_id: c.id, production_id: k.id });
    library.requests.length = 0;
    expect((await room(attached, d.access_token)).status).toBe(200);
    expect((await room(klass, t.access_token)).status).toBe(200);
    expect(library.requests).toEqual([]);
    expect((await room(attached)).status).toBe(401);
    expect((await room(attached, t.access_token)).status).toBe(404);
    expect((await room(klass, d.access_token)).status).toBe(403);
    expect(await errorOf(await room(bodyFor(play)))).toEqual([409, "revision_mismatch"]);
    // The cast sheet is still checked, against the production's own row.
    expect(await errorOf(await room({ ...attached, cast: bodyFor(newer).cast }, d.access_token))).toEqual([422, "cast_mismatch"]);
    // Another play's production does not lend its row.
    const other = fixturePlay();
    await library.put(other);
    expect(await errorOf(await room(bodyFor(other, { production_id: p.id }), d.access_token))).toEqual([404, "no_such_production"]);
  });

  it("a production made before rows were kept still publishes from the bundle's row", async () => {
    const small = [...catalog.scripts].sort((a, b) => a.lines.length - b.lines.length)[0];
    const { s, p } = await complete(small, "legacy");
    await env.DB.prepare("UPDATE play_productions SET script_row = NULL, script_revision = 'older' WHERE id = ?1").bind(p.id).run();
    const inv = await invite(s, p.id);
    expect((await (await call("GET", "/v1/plays/open/invite", { headers: { "x-invite": inv.token } })).json()).source).toBe(small.source.url);
    expect((await publish(s, p.id)).status).toBe(201);
    await runArchive(ia, Date.now(), 1000);
    expect((await job(p.id)).status).toBe("uploading");
  });
});

describe("only a publishable manifest row reaches archive.org", () => {
  const unpublishable = {
    "a row that is not publishable": { publishable: false },
    "a row whose rights bucket is not castable, whatever it says": { rights: { bucket: "own", evidence: [] }, publishable: true },
  };
  for (const [what, over] of Object.entries(unpublishable)) {
    it(`${what}: publish is refused and writes no job`, async () => {
      const play = fixturePlay();
      await library.put(play, over);
      const { s, p } = await complete(play, "no");
      expect(await errorOf(await publish(s, p.id))).toEqual([422, "script_not_publishable"]);
      expect(await job(p.id)).toBeNull();
      await runArchive(ia, Date.now(), 1000);
      expect(archive).toEqual([]);
    });
  }

  /** A production whose script no row vouches for: made, then its row taken away. */
  async function rowless(label) {
    const play = fixturePlay();
    await library.put(play);
    const t = await complete(play, label);
    const drop = () => env.DB.prepare("UPDATE play_productions SET script_row = NULL WHERE id = ?1").bind(t.p.id).run();
    return { ...t, play, drop };
  }

  it("a script in no manifest is refused at publish", async () => {
    const { s, p, drop } = await rowless("none");
    await drop();
    expect(await errorOf(await publish(s, p.id))).toEqual([422, "script_not_publishable"]);
    expect(await job(p.id)).toBeNull();
  });

  it("a stored row that is not whole is no row", async () => {
    const { s, p } = await rowless("broken");
    for (const row of ['{"title":"x","publishable":true}', "{"]) {
      await env.DB.prepare("UPDATE play_productions SET script_row = ?2 WHERE id = ?1").bind(p.id, row).run();
      expect(await errorOf(await publish(s, p.id))).toEqual([422, "script_not_publishable"]);
      expect((await call("GET", `/v1/plays/productions/${p.id}`, { token: s.access_token })).status).toBe(200);
    }
  });

  it("a job already queued fails with the reason, uploads nothing, and is not picked again", async () => {
    const { s, p, drop } = await rowless("queued");
    expect((await publish(s, p.id)).status).toBe(201);
    await drop();
    await runArchive(ia, Date.now(), 1000);
    expect(await job(p.id)).toMatchObject({ status: "failed", reason: "script_not_publishable" });
    expect(await files(p.id)).toEqual([]);
    const at = (await job(p.id)).updated_at;
    await runArchive(ia, Date.now() + 3600_000, 1000);
    expect((await job(p.id)).updated_at).toBe(at);
    expect(archive).toEqual([]);
    expect((await record(s, p.id)).archive).toMatchObject({ status: "failed", reason: "script_not_publishable" });
    expect(await errorOf(await publish(s, p.id))).toEqual([422, "script_not_publishable"]);
  });

  it("a line sent for a job laid out earlier is refused, uploads nothing, and the job says why", async () => {
    const { s, p, drop } = await rowless("sending");
    expect((await publish(s, p.id)).status).toBe(201);
    await runArchive(ia, Date.now(), 1000);
    await drop();
    const [f] = await files(p.id);
    expect(await errorOf(await sendLine(s, p.id, f.line_id))).toEqual([422, "script_not_publishable"]);
    expect(archive).toEqual([]);
    expect(await job(p.id)).toMatchObject({ status: "failed", reason: "script_not_publishable" });
  });

  it("a first upload whose lines are all sent is not finished by the cron", async () => {
    const { s, p, drop } = await rowless("sent");
    expect((await publish(s, p.id)).status).toBe(201);
    await runArchive(ia, Date.now(), 1000);
    await env.DB.prepare("UPDATE play_archive_files SET state = 'sent' WHERE production_id = ?1").bind(p.id).run();
    await drop();
    await runArchive(ia, Date.now(), 1000);
    expect(await job(p.id)).toMatchObject({ status: "failed", reason: "script_not_publishable", item_url: null });
    expect(archive).toEqual([]);
  });

  it("removals asked of an unfinished item are carried out before it ends, over as many runs as they take", async () => {
    const { s, p, drop } = await rowless("removing");
    expect((await publish(s, p.id)).status).toBe(201);
    await runArchive(ia, Date.now(), 1000);
    await env.DB.prepare("UPDATE play_archive_files SET state = 'remove' WHERE production_id = ?1").bind(p.id).run();
    await drop();
    await runArchive(ia, Date.now(), 1);
    expect(archive.map((x) => x.method)).toEqual(["DELETE"]);
    expect((await job(p.id)).status).toBe("uploading");
    await runArchive(ia, Date.now(), 1);
    expect(archive.map((x) => x.method)).toEqual(["DELETE", "DELETE"]);
    expect((await files(p.id)).map((f) => f.state)).toEqual(["removed", "removed"]);
    await runArchive(ia, Date.now(), 1);
    expect(await job(p.id)).toMatchObject({ status: "failed", reason: "script_not_publishable" });
  });

  it("on a published item, a line can still be taken off and the credits rewritten, and nothing is sent", async () => {
    const { s, p, drop } = await rowless("published");
    expect((await publish(s, p.id)).status).toBe(201);
    await runArchive(ia, Date.now(), 1000);
    const laid = await files(p.id);
    for (const f of laid) expect((await sendLine(s, p.id, f.line_id)).status).toBe(200);
    await drop();
    archive.length = 0;
    const r = await call("POST", `/v1/plays/productions/${p.id}/archive/lines/${laid[0].line_id}/remove`, { token: s.access_token, body: {}, envOverride: KEYS });
    expect(r.status).toBe(202);
    await env.DB.prepare("UPDATE play_archive_jobs SET credits = NULL WHERE production_id = ?1").bind(p.id).run();
    await runArchive(ia, Date.now(), 1000);
    expect(archive.map((x) => x.method)).toEqual(["DELETE", "POST"]);
    expect((await files(p.id))[0].state).toBe("removed");
    expect(await job(p.id)).toMatchObject({ status: "published" });
    // A replacement's file is a new upload, so it is refused; the item stays published.
    await env.DB.prepare("UPDATE play_archive_files SET state = 'pending' WHERE production_id = ?1 AND line_id = ?2").bind(p.id, laid[1].line_id).run();
    archive.length = 0;
    expect(await errorOf(await sendLine(s, p.id, laid[1].line_id))).toEqual([422, "script_not_publishable"]);
    expect(archive).toEqual([]);
    expect(await job(p.id)).toMatchObject({ status: "published" });
  });
});
