// Plays that need no account (owner, 2026-10-29): an open invite's read and the
// finished listing (src/plays-open.js). Scripts come from the real castable file,
// picked from its data; no test names a production or counts the catalog.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import worker from "../src/index.js";
import { call, env, installProviderKeys, signIn } from "./helpers.js";
import { createProduction, firstPart, invite, linesFor, newTakeId, script, secondPart, wav } from "./plays-helpers.js";
import { EXPIRED_INVITE_KEPT_MS, sweepPlays } from "../src/plays.js";
import { FINISHED_DEFAULT, FINISHED_MAX } from "../src/plays-open.js";
import { itemUrl } from "../src/plays-archive.js";
import MANIFEST from "../src/castable-manifest.json";

beforeEach(() => {
  installProviderKeys();
});
afterEach(() => vi.restoreAllMocks());

let n = 0;
const person = (label) => signIn(`open-${label}-${n++}`);
const DAY = 24 * 60 * 60 * 1000;
const asViewer = (token) => ({ headers: { "x-invite": token } });
const open = (token, over = {}) => call("GET", "/v1/plays/open/invite", { ...asViewer(token), ...over });
const noLimit = { limit: async () => ({ success: false }) };

const setPart = (pid, part, status, userId) =>
  env.DB.prepare(
    "INSERT INTO play_parts (production_id, part, status, user_id, claimed_at) VALUES (?1, ?2, ?3, ?4, ?5) ON CONFLICT (production_id, part) DO UPDATE SET status = excluded.status, user_id = excluded.user_id",
  )
    .bind(pid, part, status, userId, Date.now())
    .run();

/** A take row for `line`, its audio in the bucket; chosen unless said otherwise. */
async function seedTake(pid, userId, line, part, { chosen = 1, bytes = wav(4800) } = {}) {
  const id = newTakeId();
  const key = `plays/${pid}/${id}`;
  await env.TAKES.put(key, bytes, { httpMetadata: { contentType: "audio/wav" } });
  await env.DB.prepare(
    "INSERT INTO play_takes (production_id, id, user_id, line_id, part, file, object_key, content_type, bytes, frames, sample_rate, capture, created, uploaded_at, chosen) " +
      "VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 'audio/wav', ?8, 4800, 48000, 'direct', 0, ?9, ?10)",
  )
    .bind(pid, id, userId, line, part, `${id}.wav`, key, bytes.length, Date.now(), chosen)
    .run();
  return id;
}

/** A production: Pat directs and holds the first part, Zoë holds the second; each has a chosen take; one open invite. */
async function setup(label) {
  const director = await person(`${label}-dir`);
  const zoe = await person(`${label}-zoe`);
  const p = await createProduction(director, { display_name: "Pat" });
  await env.DB.prepare("INSERT INTO play_members (production_id, user_id, display_name, joined_at) VALUES (?1, ?2, 'Zoë', ?3)")
    .bind(p.id, zoe.user_id, Date.now() + 1)
    .run();
  await setPart(p.id, firstPart, "done", director.user_id);
  await setPart(p.id, secondPart, "recording", zoe.user_id);
  const patLine = linesFor(firstPart)[0];
  const zoeLine = linesFor(secondPart)[0];
  const patTake = await seedTake(p.id, director.user_id, patLine, firstPart);
  const zoeTake = await seedTake(p.id, zoe.user_id, zoeLine, secondPart);
  const inv = await invite(director, p.id);
  return { director, zoe, p, inv, patLine, zoeLine, patTake, zoeTake };
}

const report = (reporter, pid, fields) =>
  env.DB.prepare(
    "INSERT INTO play_reports (id, user_id, production_id, target_user_id, take_id, reason, created_at, status) VALUES (?1, ?2, ?3, ?4, ?5, 'offensive', ?6, ?7)",
  )
    .bind(newTakeId(), reporter.user_id, pid, fields.target ?? null, fields.take ?? null, Date.now(), fields.status ?? "open")
    .run();

describe("an open invite is read without an account", () => {
  it("shows the play, its parts and states, who is in by chosen name, and the takes", async () => {
    const t = await setup("view");
    const r = await open(t.inv.token);
    expect(r.status).toBe(200);
    const v = await r.json();
    expect(v).toMatchObject({ id: t.p.id, title: t.p.title, scriptID: script.id, scriptRevision: script.revision });
    expect(v.source).toBe(MANIFEST.scripts[script.id].source);
    const mine = Object.fromEntries(v.parts.map((x) => [x.id, x]));
    expect(mine[firstPart]).toMatchObject({ status: "done", performer: "Pat" });
    expect(mine[secondPart]).toMatchObject({ status: "recording", performer: "Zoë" });
    expect(v.parts.some((x) => x.status === "open")).toBe(true);
    expect(v.members).toEqual([
      { name: "Pat", director: true },
      { name: "Zoë", director: false },
    ]);
    expect(v.takes.map((x) => x.id).sort()).toEqual([t.patTake, t.zoeTake].sort());
    expect(v.chosen).toEqual({ [t.patLine]: t.patTake, [t.zoeLine]: t.zoeTake });
    expect(v.expires_at).toBe(t.inv.expires_at);
  });

  it("names no account: no user id leaves the Worker", async () => {
    const t = await setup("ids");
    const text = await (await open(t.inv.token)).text();
    for (const id of [t.director.user_id, t.zoe.user_id]) expect(text).not.toContain(id);
  });

  it("plays a take's audio without an account, and says how long a cache may keep it", async () => {
    const t = await setup("audio");
    const r = await call("GET", `/v1/plays/open/invite/takes/${t.patTake}/audio`, asViewer(t.inv.token));
    expect(r.status).toBe(200);
    expect(r.headers.get("content-type")).toBe("audio/wav");
    expect(r.headers.get("cache-control")).toBe("private, max-age=300");
    expect((await r.arrayBuffer()).byteLength).toBe(wav(4800).length);
    const view = (await (await open(t.inv.token)).json()).takes.find((x) => x.id === t.patTake);
    expect(view.audio).toBe(`/v1/plays/open/invite/takes/${t.patTake}/audio`);
  });

  it("sends cache headers on the read", async () => {
    const t = await setup("cache");
    expect((await open(t.inv.token)).headers.get("cache-control")).toBe("private, max-age=30");
  });

  it("shows only each line's chosen take, never an older one", async () => {
    const t = await setup("older");
    const older = await seedTake(t.p.id, t.director.user_id, t.patLine, firstPart, { chosen: 0 });
    const v = await (await open(t.inv.token)).json();
    expect(v.takes.map((x) => x.id)).not.toContain(older);
    expect((await call("GET", `/v1/plays/open/invite/takes/${older}/audio`, asViewer(t.inv.token))).status).toBe(404);
  });

  it("does not make the viewer a member or claim anything", async () => {
    const t = await setup("readonly");
    const before = await env.DB.prepare("SELECT (SELECT COUNT(*) FROM play_members) AS m, (SELECT COUNT(*) FROM play_parts) AS p").first();
    await open(t.inv.token);
    expect(await env.DB.prepare("SELECT (SELECT COUNT(*) FROM play_members) AS m, (SELECT COUNT(*) FROM play_parts) AS p").first()).toEqual(before);
  });

  it("reads the token from the header only, never the path or the query", async () => {
    const t = await setup("header");
    expect((await call("GET", `/v1/plays/open/invite?token=${t.inv.token}`)).status).toBe(404);
    expect((await call("GET", `/v1/plays/open/invite/${t.inv.token}`)).status).toBe(404);
  });
});

describe("an open invite cannot contribute", () => {
  it("anyone can read but nothing writes without an account", async () => {
    const t = await setup("nowrite");
    const token = t.inv.token;
    const pid = encodeURIComponent(t.p.id);
    const attempts = [
      ["POST", "/v1/plays/invites/claim", { token, part: secondPart }],
      ["POST", "/v1/plays/invites/view", { token }],
      ["POST", `/v1/plays/productions/${pid}/claim`, { part: secondPart }],
      ["PUT", `/v1/plays/productions/${pid}/takes/${newTakeId()}`, wav(4800)],
      ["POST", "/v1/plays/reports", { production_id: t.p.id, take_id: t.patTake, reason: "offensive" }],
      ["POST", "/v1/plays/blocks", { user_id: t.zoe.user_id }],
      ["GET", `/v1/plays/productions/${pid}`, undefined],
      ["POST", "/v1/plays/open/invite", {}],
      ["PUT", "/v1/plays/open/invite", {}],
      ["DELETE", "/v1/plays/open/invite", undefined],
    ];
    for (const [method, path, body] of attempts) {
      const r = await call(method, path, { body, ...asViewer(token) });
      expect(r.status, `${method} ${path}`).toBe(401);
    }
    expect((await open(token)).status).toBe(200);
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM play_reports").first()).toEqual({ n: 0 });
  });
});

describe("what an anonymous viewer never hears", () => {
  const hearable = async (t, id) => {
    const listed = (await (await open(t.inv.token)).json()).takes.some((x) => x.id === id);
    const played = (await call("GET", `/v1/plays/open/invite/takes/${id}/audio`, asViewer(t.inv.token))).status === 200;
    expect(listed).toBe(played);
    return listed;
  };

  it("a reported take is hidden from the list and refused as audio, whoever reported it", async () => {
    const t = await setup("reported");
    expect(await hearable(t, t.zoeTake)).toBe(true);
    await report(t.director, t.p.id, { take: t.zoeTake, target: t.zoe.user_id });
    expect(await hearable(t, t.zoeTake)).toBe(false);
    expect(await hearable(t, t.patTake)).toBe(true);
  });

  it("a report stays in force after it is closed", async () => {
    const t = await setup("closed");
    await report(t.director, t.p.id, { take: t.zoeTake, target: t.zoe.user_id, status: "closed" });
    expect(await hearable(t, t.zoeTake)).toBe(false);
  });

  it("a person an open report names has no take heard", async () => {
    const t = await setup("member");
    await report(t.director, t.p.id, { target: t.zoe.user_id });
    expect(await hearable(t, t.zoeTake)).toBe(false);
    expect(await hearable(t, t.patTake)).toBe(true);
  });

  it("a person the inviter blocked, or who blocked the inviter, has no take heard", async () => {
    const a = await setup("blocked");
    await env.DB.prepare("INSERT INTO play_blocks (user_id, blocked_id, created_at) VALUES (?1, ?2, ?3)").bind(a.director.user_id, a.zoe.user_id, Date.now()).run();
    expect(await hearable(a, a.zoeTake)).toBe(false);
    expect(await hearable(a, a.patTake)).toBe(true);
    const b = await setup("blockedby");
    await env.DB.prepare("INSERT INTO play_blocks (user_id, blocked_id, created_at) VALUES (?1, ?2, ?3)").bind(b.zoe.user_id, b.director.user_id, Date.now()).run();
    expect(await hearable(b, b.zoeTake)).toBe(false);
  });
});

describe("an invite that no longer works", () => {
  it("an unknown token is a plain 404", async () => {
    await setup("unknown");
    for (const token of ["x".repeat(43), "short", undefined]) expect((await open(token ?? "")).status).toBe(404);
  });

  it("a revoked invite answers 410, for the read and for the audio", async () => {
    const t = await setup("revoked");
    const r = await call("DELETE", `/v1/plays/productions/${t.p.id}/invites/${t.inv.id}`, { token: t.director.access_token });
    expect(r.status).toBe(204);
    const gone = await open(t.inv.token);
    expect(gone.status).toBe(410);
    expect(await gone.json()).toEqual({ error: "invite_gone" });
    expect((await call("GET", `/v1/plays/open/invite/takes/${t.patTake}/audio`, asViewer(t.inv.token))).status).toBe(410);
  });

  it("an expired invite answers 410, and a month later is forgotten (404)", async () => {
    const t = await setup("expired");
    await env.DB.prepare("UPDATE play_invites SET expires_at = ?2 WHERE id = ?1").bind(t.inv.id, Date.now() - DAY).run();
    expect((await open(t.inv.token)).status).toBe(410);
    expect((await call("GET", `/v1/plays/open/invite/takes/${t.patTake}/audio`, asViewer(t.inv.token))).status).toBe(410);
    await sweepPlays(env);
    expect((await open(t.inv.token)).status).toBe(410);
    await env.DB.prepare("UPDATE play_invites SET expires_at = ?2 WHERE id = ?1").bind(t.inv.id, Date.now() - EXPIRED_INVITE_KEPT_MS - DAY).run();
    await sweepPlays(env);
    expect((await open(t.inv.token)).status).toBe(404);
  });

  it("the hourly cron still sweeps expired invites", async () => {
    const t = await setup("cron");
    await env.DB.prepare("UPDATE play_invites SET expires_at = ?2 WHERE id = ?1").bind(t.inv.id, Date.now() - EXPIRED_INVITE_KEPT_MS - DAY).run();
    const ctx = createExecutionContext();
    await worker.scheduled(createScheduledController({ cron: "23 * * * *" }), env, ctx);
    await waitOnExecutionContext(ctx);
    expect(await env.DB.prepare("SELECT 1 FROM play_invites WHERE id = ?1").bind(t.inv.id).first()).toBeNull();
  });
});

describe("anonymous reads are rate limited", () => {
  it("the read and the audio each answer 429 past their limit", async () => {
    const t = await setup("limit");
    expect((await open(t.inv.token, { envOverride: { OPEN_READ_LIMITER: noLimit } })).status).toBe(429);
    expect((await open(t.inv.token, { envOverride: { OPEN_AUDIO_LIMITER: noLimit } })).status).toBe(200);
    const audio = (envOverride) => call("GET", `/v1/plays/open/invite/takes/${t.patTake}/audio`, { ...asViewer(t.inv.token), envOverride });
    expect((await audio({ OPEN_AUDIO_LIMITER: noLimit })).status).toBe(429);
    expect((await audio({ OPEN_READ_LIMITER: noLimit })).status).toBe(200);
  });

  it("the finished listing is limited too", async () => {
    expect((await call("GET", "/v1/plays/finished", { envOverride: { OPEN_READ_LIMITER: noLimit } })).status).toBe(429);
    expect((await call("GET", `/v1/plays/finished/${"A".repeat(36)}`, { envOverride: { OPEN_READ_LIMITER: noLimit } })).status).toBe(429);
  });
});

/* ---- Finished ear dramas ---- */

/**
 * A published production: the director's (Pat) lines of the first part and Zoë's of the second are
 * on the item (`perPart` each). The files are rows; no archive.org call is made.
 */
async function finished(label, { at, perPart = 2, state = "sent" } = {}) {
  const t = await setup(label);
  const published = at ?? Date.now();
  await env.DB.prepare(
    "INSERT INTO play_archive_jobs (production_id, user_id, status, take_ids, created_at, updated_at, identifier, item_url, published_at) VALUES (?1, ?2, 'published', '[]', ?3, ?3, ?4, ?5, ?6)",
  )
    .bind(t.p.id, t.director.user_id, published, `eardrama-${t.p.id}`, itemUrl(`eardrama-${t.p.id}`), published)
    .run();
  let seq = 0;
  const lines = {};
  for (const [part, who] of [[firstPart, t.director], [secondPart, t.zoe]]) {
    lines[part] = [];
    for (const line of linesFor(part).slice(0, perPart)) {
      const take = await seedTake(t.p.id, who.user_id, line, part, { chosen: 0 });
      await env.DB.prepare(
        "INSERT INTO play_archive_files (production_id, line_id, seq, part, take_id, name, state, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
      )
        .bind(t.p.id, line, seq++, part, take, `${seq}.wav`, state, Date.now())
        .run();
      lines[part].push(line);
    }
  }
  return { ...t, lines, published };
}

const list = async (query = "", over = {}) => {
  const r = await call("GET", `/v1/plays/finished${query}`, over);
  return { r, body: r.status === 200 ? await r.json() : await r.json().catch(() => null) };
};
const ours = (body, ...pids) => body.productions.filter((x) => pids.includes(x.id));

describe("finished ear dramas are listed and credited", () => {
  beforeEach(async () => {
    await env.DB.prepare("DELETE FROM play_archive_jobs").run();
  });

  it("lists a published production without an account: title, source, credits, the item url, the date", async () => {
    const f = await finished("list");
    const { r, body } = await list();
    expect(r.status).toBe(200);
    expect(r.headers.get("cache-control")).toBe("public, max-age=300, s-maxage=300");
    expect(body.productions).toEqual([
      {
        id: f.p.id,
        script_id: script.id,
        title: f.p.title,
        source: MANIFEST.scripts[script.id].source,
        credits: [
          { part: firstPart, name: "Pat" },
          { part: secondPart, name: "Zoë" },
        ],
        archive_url: itemUrl(`eardrama-${f.p.id}`),
        published_at: f.published,
      },
    ]);
    expect(body.next_cursor).toBeNull();
    expect(JSON.stringify(body)).not.toContain(f.director.user_id);
  });

  it("lists only published productions", async () => {
    const f = await finished("states");
    const queued = await finished("queued");
    await env.DB.prepare("UPDATE play_archive_jobs SET status = 'queued' WHERE production_id = ?1").bind(queued.p.id).run();
    const failed = await finished("failed");
    await env.DB.prepare("UPDATE play_archive_jobs SET status = 'failed' WHERE production_id = ?1").bind(failed.p.id).run();
    const { body } = await list();
    expect(body.productions.map((x) => x.id)).toEqual([f.p.id]);
    expect((await call("GET", `/v1/plays/finished/${queued.p.id}`)).status).toBe(404);
  });

  it("is newest published first, ties broken by id, whatever the creation order", async () => {
    const old = await finished("o", { at: 1_000_000 });
    const newest = await finished("n", { at: 3_000_000 });
    const mid = await finished("m", { at: 2_000_000 });
    const tieA = await finished("ta", { at: 2_000_000 });
    const tied = [mid.p.id, tieA.p.id].sort().reverse();
    const { body } = await list();
    expect(body.productions.map((x) => x.id)).toEqual([newest.p.id, ...tied, old.p.id]);
  });

  it("pages with a cursor: no repeats, no gaps, the last page ends it", async () => {
    const made = [];
    for (let i = 0; i < 5; i++) made.push((await finished(`pg${i}`, { at: 5_000_000 + (i % 3) * 1000 })).p.id);
    const seen = [];
    let cursor = null;
    let pages = 0;
    do {
      const { r, body } = await list(`?limit=2${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`);
      expect(r.status).toBe(200);
      expect(body.productions.length).toBeLessThanOrEqual(2);
      seen.push(...body.productions.map((x) => x.id));
      cursor = body.next_cursor;
      pages++;
    } while (cursor && pages < 10);
    expect(pages).toBe(3);
    expect(seen).toHaveLength(5);
    expect(new Set(seen).size).toBe(5);
    expect(seen.sort()).toEqual([...made].sort());
    const exact = await list("?limit=5");
    expect(exact.body.productions).toHaveLength(5);
    expect(exact.body.next_cursor).toBeNull();
  });

  it("refuses a limit outside 1 to the cap and a cursor that is not one", async () => {
    expect(FINISHED_DEFAULT).toBeLessThanOrEqual(FINISHED_MAX);
    for (const q of ["?limit=0", "?limit=51", "?limit=abc", "?limit=1.5", "?cursor=nope", "?cursor=1:2"]) {
      expect((await list(q)).r.status, q).toBe(400);
    }
    expect((await list("?limit=50")).r.status).toBe(200);
  });

  it("a single production by id, public and cached", async () => {
    const f = await finished("one");
    const r = await call("GET", `/v1/plays/finished/${f.p.id}`);
    expect(r.status).toBe(200);
    expect(r.headers.get("cache-control")).toBe("public, max-age=300, s-maxage=300");
    const one = await r.json();
    expect(one).toMatchObject({ id: f.p.id, title: f.p.title, archive_url: itemUrl(`eardrama-${f.p.id}`), published_at: f.published });
    expect(one.credits).toEqual([
      { part: firstPart, name: "Pat" },
      { part: secondPart, name: "Zoë" },
    ]);
    expect((await call("GET", `/v1/plays/finished/${"B".repeat(36)}`)).status).toBe(404);
  });

  it("a removed line drops its credit; the part stays credited while any line of it is on the item", async () => {
    const f = await finished("removed", { perPart: 2 });
    const [first, second] = f.lines[secondPart];
    await env.DB.prepare("UPDATE play_archive_files SET state = 'remove' WHERE production_id = ?1 AND line_id = ?2").bind(f.p.id, first).run();
    expect((await call("GET", `/v1/plays/finished/${f.p.id}`).then((r) => r.json())).credits).toContainEqual({ part: secondPart, name: "Zoë" });
    await env.DB.prepare("UPDATE play_archive_files SET state = 'removed' WHERE production_id = ?1 AND line_id = ?2").bind(f.p.id, second).run();
    const credits = (await call("GET", `/v1/plays/finished/${f.p.id}`).then((r) => r.json())).credits;
    expect(credits).toEqual([{ part: firstPart, name: "Pat" }]);
    expect(JSON.stringify((await list()).body)).not.toContain("Zoë");
  });

  it("a production with every line removed is not listed", async () => {
    const f = await finished("empty");
    await env.DB.prepare("UPDATE play_archive_files SET state = 'removed' WHERE production_id = ?1").bind(f.p.id).run();
    expect(ours((await list()).body, f.p.id)).toEqual([]);
    expect((await call("GET", `/v1/plays/finished/${f.p.id}`)).status).toBe(404);
  });

  it("a pending replacement is still credited", async () => {
    const f = await finished("pending", { state: "pending" });
    expect(ours((await list()).body, f.p.id)[0].credits).toHaveLength(2);
  });

  it("a deleted account leaves its lines on the item, uncredited by name", async () => {
    const f = await finished("deleted");
    const r = await call("DELETE", "/v1/account", { token: f.zoe.access_token, body: {} });
    expect(r.status).toBe(200);
    const { body } = await list();
    const mine = ours(body, f.p.id)[0];
    expect(mine.credits).toEqual([
      { part: firstPart, name: "Pat" },
      { part: secondPart, name: "" },
    ]);
    expect(JSON.stringify(body)).not.toContain("Zoë");
    expect(mine.archive_url).toBe(itemUrl(`eardrama-${f.p.id}`));
  });

  it("is reachable with no account and writes nothing", async () => {
    const f = await finished("anon");
    for (const [method, path] of [
      ["POST", "/v1/plays/finished"],
      ["DELETE", `/v1/plays/finished/${f.p.id}`],
      ["PUT", `/v1/plays/finished/${f.p.id}`],
    ]) {
      expect((await call(method, path, { body: {} })).status, `${method} ${path}`).toBe(401);
    }
    expect((await call("GET", "/v1/plays/finished")).status).toBe(200);
  });
});
