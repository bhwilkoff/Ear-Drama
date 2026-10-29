// The archive.org uploader (P14) and replacing or removing a published take
// (P12), against a fake archive.org: nothing here reaches the real one. The
// script is the castable one with the fewest lines, picked from the data.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import worker from "../src/index.js";
import { call, env, installProviderKeys, signIn } from "./helpers.js";
import { castOf, catalog, consent, flac, newTakeId, wav } from "./plays-helpers.js";
import { castParts, isSpeaking, linesOf } from "../src/plays-relay.js";
import MANIFEST from "../src/castable-manifest.json";
import {
  ARCHIVE_CRON,
  CC0_URL,
  IA_COLLECTION,
  MAX_ATTEMPTS,
  REQUESTS_PER_RUN,
  backoff,
  identifierFor,
  itemUrl,
  metaValue,
  runArchive,
} from "../src/plays-archive.js";

const ACCESS = "TESTIAACCESS7f3a";
const SECRET = "TESTIASECRET9c2e";
const KEYS = { IA_S3_ACCESS_KEY: ACCESS, IA_S3_SECRET_KEY: SECRET };
const ia = { ...env, ...KEYS };

const small = [...catalog.scripts].sort((a, b) => a.lines.length - b.lines.length)[0];
const cast = castOf(small);
const parts = castParts(cast).map((p) => p.id);
const speaking = parts.filter(isSpeaking);
/** The second speaking part goes to a second performer. */
const herPart = speaking[speaking.length - 1];
const speakingLines = cast.filter(([, part]) => isSpeaking(part)).map(([id]) => id);

/** A fake archive.org: items with their metadata and files, every request kept, and `fail` to answer one. */
function fakeArchive() {
  const items = new Map();
  const requests = [];
  const state = { fail: null, overLimit: false };
  const handle = async (url, init = {}) => {
    const u = new URL(url);
    if (u.hostname !== "s3.us.archive.org" && u.hostname !== "archive.org") return undefined;
    const headers = Object.fromEntries(Object.entries(init.headers || {}).map(([k, v]) => [k.toLowerCase(), v]));
    const method = init.method || "GET";
    const req = { method, host: u.hostname, path: decodeURIComponent(u.pathname), search: u.search, headers, body: init.body };
    requests.push(req);
    if (state.fail) {
      const r = state.fail(req);
      if (r) return r;
    }
    if (u.hostname === "archive.org") {
      const id = u.pathname.split("/")[2];
      const form = new URLSearchParams(init.body);
      for (const op of JSON.parse(form.get("-patch"))) {
        const key = op.path.slice(1);
        if (op.op === "remove") delete items.get(id).meta[key];
        else items.get(id).meta[key] = op.value;
      }
      return Response.json({ success: true });
    }
    if (u.searchParams.get("check_limit")) return Response.json({ bucket: u.searchParams.get("bucket"), over_limit: state.overLimit ? 1 : 0 });
    if (headers.authorization !== `LOW ${ACCESS}:${SECRET}`) return new Response("<Error><Code>InvalidAccessKeyId</Code></Error>", { status: 403 });
    const [, id, ...rest] = u.pathname.split("/");
    const name = decodeURIComponent(rest.join("/"));
    if (method === "PUT") {
      if (!items.has(id)) {
        if (headers["x-archive-auto-make-bucket"] !== "1") return new Response("<Error><Code>NoSuchBucket</Code></Error>", { status: 404 });
        const meta = {};
        for (const [k, v] of Object.entries(headers)) {
          const m = /^x-archive-meta(\d\d)?-(.+)$/.exec(k);
          if (!m) continue;
          const value = v.startsWith("uri(") ? decodeURIComponent(v.slice(4, -1)) : v;
          if (m[1]) (meta[m[2]] ||= []).push(value);
          else meta[m[2]] = value;
        }
        items.set(id, { meta, files: new Map() });
      }
      items.get(id).files.set(name, { bytes: init.body.byteLength, derive: headers["x-archive-queue-derive"] !== "0" });
      return new Response(null, { status: 200 });
    }
    if (method === "DELETE") {
      const item = items.get(id);
      if (!item || !item.files.has(name)) return new Response("<Error><Code>NoSuchKey</Code></Error>", { status: 404 });
      item.files.delete(name);
      return new Response(null, { status: 204 });
    }
    return new Response(null, { status: 400 });
  };
  return { items, requests, state, handle, puts: () => requests.filter((r) => r.method === "PUT") };
}

let fake;
let logs;
beforeEach(async () => {
  // D1 outlives a test in this file; each test's uploader sees only its own job.
  await env.DB.prepare("DELETE FROM play_archive_jobs").run();
  fake = fakeArchive();
  installProviderKeys({ extra: (url, init) => fake.handle(url, init) });
  logs = [];
  vi.spyOn(console, "log").mockImplementation((...a) => logs.push(a.join(" ")));
});
afterEach(() => vi.restoreAllMocks());

let n = 0;
const person = (label) => signIn(`ia-${label}-${n++}`);
const setPart = (pid, part, status, userId) =>
  env.DB.prepare(
    "INSERT INTO play_parts (production_id, part, status, user_id, claimed_at) VALUES (?1, ?2, ?3, ?4, ?5) ON CONFLICT (production_id, part) DO UPDATE SET status = excluded.status, user_id = excluded.user_id",
  )
    .bind(pid, part, status, userId, Date.now())
    .run();

/** A chosen take row for `line` with its audio in the bucket. */
async function seedTake(pid, userId, line, part, { bytes = wav(4800), type = "audio/wav" } = {}) {
  const id = newTakeId();
  const key = `plays/${pid}/${id}`;
  await env.TAKES.put(key, bytes, { httpMetadata: { contentType: type } });
  await env.DB.batch([
    env.DB.prepare("UPDATE play_takes SET chosen = 0 WHERE production_id = ?1 AND line_id = ?2").bind(pid, line),
    env.DB.prepare(
      "INSERT INTO play_takes (production_id, id, user_id, line_id, part, file, object_key, content_type, bytes, frames, sample_rate, capture, created, uploaded_at, chosen) " +
        "VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 4800, 48000, 'direct', 0, ?10, 1)",
    ).bind(pid, id, userId, line, part, `${id}.wav`, key, type, bytes.length, Date.now()),
  ]);
  return id;
}

/** A complete production of the small script: the director holds every part but one, a second performer ("Zoë") the other. */
async function complete(label) {
  const director = await person(`${label}-dir`);
  const her = await person(`${label}-her`);
  const r = await call("POST", "/v1/plays/productions", {
    token: director.access_token,
    body: { script_id: small.id, script_revision: small.revision, cast: cast.map(([id, part]) => ({ id, part })), display_name: "Pat" },
  });
  expect(r.status).toBe(201);
  const p = await r.json();
  await env.DB.prepare("INSERT INTO play_members (production_id, user_id, display_name, joined_at) VALUES (?1, ?2, 'Zoë', ?3)")
    .bind(p.id, her.user_id, Date.now() + 1)
    .run();
  for (const part of parts) {
    const who = part === herPart ? her : director;
    if (isSpeaking(part)) for (const line of linesOf(cast, part)) await seedTake(p.id, who.user_id, line, part);
    await setPart(p.id, part, isSpeaking(part) ? "done" : "silent", who.user_id);
  }
  expect((await consent(director, p.id)).status).toBe(204);
  expect((await consent(her, p.id)).status).toBe(204);
  return { director, her, p };
}

const publish = (s, pid, envOverride = KEYS) => call("POST", `/v1/plays/productions/${pid}/publish`, { token: s.access_token, envOverride });
const job = (pid) => env.DB.prepare("SELECT * FROM play_archive_jobs WHERE production_id = ?1").bind(pid).first();
const files = async (pid) =>
  (await env.DB.prepare("SELECT * FROM play_archive_files WHERE production_id = ?1 ORDER BY seq").bind(pid).all()).results;
const record = async (s, pid) => (await call("GET", `/v1/plays/productions/${pid}`, { token: s.access_token, envOverride: KEYS })).json();

/** Runs the uploader until the job settles or `max` runs pass; returns the runs taken. */
async function drain(pid, { now = Date.now(), max = 50 } = {}) {
  for (let i = 1; i <= max; i++) {
    const before = fake.requests.length;
    await runArchive(ia, now, 1000);
    const j = await job(pid);
    const busy = (await files(pid)).some((f) => f.state === "pending" || f.state === "remove");
    if (fake.requests.length === before || (!busy && j.status !== "uploading" && j.credits)) return i;
  }
  return max;
}

async function published(label) {
  const t = await complete(label);
  expect((await publish(t.director, t.p.id)).status).toBe(201);
  await drain(t.p.id);
  expect((await job(t.p.id)).status).toBe("published");
  fake.requests.length = 0;
  return t;
}

const herLines = () => linesOf(cast, herPart);

describe("the gate", () => {
  it("runs nothing without both keys, and nothing without the bucket", async () => {
    const { director, p } = await complete("gate");
    expect((await publish(director, p.id)).status).toBe(201);
    await runArchive({ ...env, IA_S3_ACCESS_KEY: ACCESS }, Date.now(), 1000);
    await runArchive({ ...env, IA_S3_SECRET_KEY: SECRET }, Date.now(), 1000);
    await runArchive({ ...ia, TAKES: undefined }, Date.now(), 1000);
    expect(fake.requests).toEqual([]);
    expect((await job(p.id)).status).toBe("queued");
  });

  it("the five-minute trigger runs the uploader, and so does the hourly one", async () => {
    const { director, p } = await complete("cron");
    expect((await publish(director, p.id)).status).toBe(201);
    const ctx = createExecutionContext();
    await worker.scheduled(createScheduledController({ cron: ARCHIVE_CRON }), ia, ctx);
    await waitOnExecutionContext(ctx);
    expect(fake.puts().length).toBe(REQUESTS_PER_RUN - 1);
    const ctx2 = createExecutionContext();
    await worker.scheduled(createScheduledController({ cron: "23 * * * *" }), ia, ctx2);
    await waitOnExecutionContext(ctx2);
    expect(fake.puts().length).toBe(Math.min(speakingLines.length, 2 * (REQUESTS_PER_RUN - 1)));
  });
});

describe("a first publish", () => {
  it("makes one item, its metadata from data, one file per line in script order, derived once", async () => {
    const { director, her, p } = await complete("ok");
    expect((await publish(director, p.id)).status).toBe(201);
    await drain(p.id);
    const id = identifierFor(p.id);
    expect(id).toBe(`eardrama-${p.id.toLowerCase()}`);
    expect(id).toMatch(/^[a-z0-9][a-z0-9._-]{4,99}$/);
    expect([...fake.items.keys()]).toEqual([id]);
    const item = fake.items.get(id);
    const entry = MANIFEST.scripts[small.id];
    expect(item.meta).toMatchObject({ mediatype: "audio", collection: IA_COLLECTION, title: entry.title, licenseurl: CC0_URL, source: entry.source });
    expect(speaking.length).toBeGreaterThan(1);
    expect(item.meta.creator).toEqual(["Pat", "Zoë"]);
    expect(item.meta.credits).toContain(`${herPart}: Zoë`);
    for (const e of entry.rights.evidence) expect(item.meta.rights).toContain(e.claim);
    const names = [...item.files.keys()];
    expect(names.length).toBe(speakingLines.length);
    expect([...names].sort()).toEqual(names.slice().sort());
    expect(fake.puts().map((r) => r.path.split("/").pop())).toEqual([...names].sort());
    expect([...item.files.values()].filter((f) => f.derive).length).toBe(1);
    expect(item.files.get(names.at(-1)).derive).toBe(true);
    const rec = await record(her, p.id);
    expect(rec.archive).toMatchObject({ status: "published", url: itemUrl(id), reason: null });
    expect(metaValue("Zoë")).toBe("uri(Zo%C3%AB)");
  });

  it("keeps to the request budget and archive.org's check_limit", async () => {
    const { director, p } = await complete("budget");
    expect((await publish(director, p.id)).status).toBe(201);
    await runArchive(ia, Date.now());
    expect(fake.requests.length).toBe(REQUESTS_PER_RUN);
    expect(fake.requests[0].search).toContain("check_limit=1");
  });

  it("waits while check_limit says the item's queue is over its limit", async () => {
    const { director, p } = await complete("limit");
    expect((await publish(director, p.id)).status).toBe(201);
    fake.state.overLimit = true;
    await runArchive(ia, Date.now(), 1000);
    expect(fake.puts()).toEqual([]);
    expect((await job(p.id)).next_attempt_at).toBeGreaterThan(Date.now());
  });
});

describe("idempotency and retries", () => {
  it("never sends a line twice: a 503 SlowDown backs off and resumes at the line that failed", async () => {
    const { director, p } = await complete("retry");
    expect((await publish(director, p.id)).status).toBe(201);
    let put = 0;
    fake.state.fail = (r) =>
      r.method === "PUT" && ++put === 3 ? new Response("<Error><Code>SlowDown</Code><Message>Please reduce your request rate.</Message></Error>", { status: 503 }) : null;
    const t0 = Date.now();
    await runArchive(ia, t0, 1000);
    const j = await job(p.id);
    expect(j).toMatchObject({ status: "uploading", attempts: 1 });
    expect(j.reason).toContain("SlowDown");
    expect(j.next_attempt_at).toBe(t0 + backoff(1));
    expect((await files(p.id)).filter((f) => f.state === "sent").length).toBe(2);
    const seen = fake.requests.length;
    await runArchive(ia, t0 + backoff(1) - 1, 1000);
    expect(fake.requests.length).toBe(seen);
    await drain(p.id, { now: t0 + backoff(1) });
    expect((await job(p.id)).status).toBe("published");
    const ok = fake.puts().filter((_, i) => i !== 2);
    const counts = {};
    for (const r of ok) counts[r.path] = (counts[r.path] || 0) + 1;
    expect(Object.values(counts).every((c) => c === 1)).toBe(true);
    expect(Object.keys(counts).length).toBe(speakingLines.length);
    // Done is done: another run sends nothing.
    fake.requests.length = 0;
    await runArchive(ia, t0 + MAX_ATTEMPTS * backoff(MAX_ATTEMPTS), 1000);
    expect(fake.requests).toEqual([]);
  });

  it("a run that holds the lease keeps another off the job", async () => {
    const { director, p } = await complete("lease");
    expect((await publish(director, p.id)).status).toBe(201);
    const now = Date.now();
    await env.DB.prepare("UPDATE play_archive_jobs SET lease_until = ?2 WHERE production_id = ?1").bind(p.id, now + 60_000).run();
    await runArchive(ia, now, 1000);
    expect(fake.requests).toEqual([]);
  });

  it("two runs at once send each line once: the lease is taken before any request", async () => {
    const { director, p } = await complete("race");
    expect((await publish(director, p.id)).status).toBe(201);
    const now = Date.now();
    await Promise.all([runArchive(ia, now, 1000), runArchive(ia, now, 1000), runArchive(ia, now, 1000)]);
    const names = fake.puts().map((r) => r.path);
    expect(names.length).toBe(speakingLines.length);
    expect(new Set(names).size).toBe(names.length);
  });

  it("gives up after MAX_ATTEMPTS of 503, says why, and a second Publish resumes without resending", async () => {
    const { director, p } = await complete("giveup");
    expect((await publish(director, p.id)).status).toBe(201);
    let put = 0;
    fake.state.fail = (r) => (r.method === "PUT" && ++put > 1 ? new Response("<Error><Code>SlowDown</Code></Error>", { status: 503 }) : null);
    let now = Date.now();
    for (let i = 1; i <= MAX_ATTEMPTS; i++) {
      await runArchive(ia, now, 1000);
      now += backoff(i);
    }
    const j = await job(p.id);
    expect(j.status).toBe("failed");
    expect(j.reason).toMatch(new RegExp(`^gave up after ${MAX_ATTEMPTS} attempts: archive.org 503 SlowDown`));
    expect((await record(director, p.id)).archive).toMatchObject({ status: "failed", url: null });
    fake.state.fail = null;
    fake.requests.length = 0;
    const again = await publish(director, p.id);
    expect(again.status).toBe(200);
    expect((await again.json()).status).toBe("queued");
    await drain(p.id, { now });
    expect((await job(p.id)).status).toBe("published");
    expect(fake.puts().length).toBe(speakingLines.length - 1);
  });

  it("a size refusal fails the job at once, and nothing retries it", async () => {
    const { director, p } = await complete("size");
    expect((await publish(director, p.id)).status).toBe(201);
    fake.state.fail = (r) =>
      r.method === "PUT" ? new Response("<Error><Code>EntityTooLarge</Code><Message>Your proposed upload exceeds the maximum allowed size</Message></Error>", { status: 400 }) : null;
    await runArchive(ia, Date.now(), 1000);
    const j = await job(p.id);
    expect(j.status).toBe("failed");
    expect(j.reason).toContain("EntityTooLarge");
    fake.requests.length = 0;
    await runArchive(ia, Date.now() + 86_400_000, 1000);
    expect(fake.requests).toEqual([]);
  });

  it("a take over the size limit fails before anything is sent", async () => {
    const { director, p } = await complete("presize");
    await env.DB.prepare("UPDATE play_takes SET bytes = 46000000 WHERE production_id = ?1 AND rowid = (SELECT MIN(rowid) FROM play_takes WHERE production_id = ?1)")
      .bind(p.id)
      .run();
    expect((await publish(director, p.id)).status).toBe(201);
    await runArchive(ia, Date.now(), 1000);
    expect(await job(p.id)).toMatchObject({ status: "failed", reason: "too_large" });
    expect(fake.requests).toEqual([]);
  });
});

describe("the keys", () => {
  it("go only to archive.org's hosts, and never into a log, a stored reason, or a response", async () => {
    const { director, her, p } = await complete("keys");
    const pub = await publish(director, p.id);
    let first = true;
    // An answer that echoes the secret, as a careless error page might.
    fake.state.fail = (r) =>
      r.method === "PUT" && first ? ((first = false), new Response(`<Error><Code>SlowDown</Code><Message>key ${SECRET} ${ACCESS}</Message></Error>`, { status: 503 })) : null;
    const t0 = Date.now();
    await runArchive(ia, t0, 1000);
    const failedJob = await job(p.id);
    await drain(p.id, { now: t0 + backoff(1) });
    const texts = [
      ...logs,
      JSON.stringify(failedJob),
      JSON.stringify(await job(p.id)),
      JSON.stringify(await files(p.id)),
      await pub.text(),
      JSON.stringify(await record(director, p.id)),
      JSON.stringify(await record(her, p.id)),
      await (await call("GET", "/v1/plays/consent", { token: her.access_token, envOverride: KEYS })).text(),
    ];
    expect(logs.length).toBeGreaterThan(0);
    expect(failedJob.reason).toContain("[redacted]");
    for (const t of texts) {
      expect(t).not.toContain(SECRET);
      expect(t).not.toContain(ACCESS);
    }
    expect(new Set(fake.requests.map((r) => r.host))).toEqual(new Set(["s3.us.archive.org"]));
    for (const r of fake.puts()) expect(r.headers.authorization).toBe(`LOW ${ACCESS}:${SECRET}`);
  });
});

describe("replacing or removing a published take (P12)", () => {
  const replace = (s, pid, line, { bytes = wav(9600), meta = {} } = {}) =>
    call("PUT", `/v1/plays/productions/${pid}/takes/${newTakeId()}`, {
      token: s.access_token,
      body: bytes,
      headers: { "x-take": JSON.stringify({ lineID: line, frames: 9600, sampleRate: 48000, ...meta }) },
      envOverride: KEYS,
    });
  const remove = (s, pid, line, body = {}) =>
    call("POST", `/v1/plays/productions/${pid}/archive/lines/${encodeURIComponent(line)}/remove`, { token: s.access_token, body, envOverride: KEYS });
  const fileOf = async (pid, line) => (await files(pid)).find((f) => f.line_id === line);

  it("a performer replaces their own take: the same name is overwritten", async () => {
    const { her, p } = await published("rep");
    const line = herLines()[0];
    const before = await fileOf(p.id, line);
    const r = await replace(her, p.id, line);
    expect(r.status).toBe(201);
    expect((await fileOf(p.id, line)).state).toBe("pending");
    await drain(p.id);
    const after = await fileOf(p.id, line);
    expect(after).toMatchObject({ state: "sent", name: before.name });
    expect(after.take_id).not.toBe(before.take_id);
    expect(fake.puts().map((x) => x.path)).toEqual([`/${identifierFor(p.id)}/${before.name}`]);
    expect(fake.puts()[0].headers["x-archive-auto-make-bucket"]).toBeUndefined();
    expect(fake.items.get(identifierFor(p.id)).files.get(before.name).bytes).toBe(wav(9600).length);
  });

  it("a replacement in another format deletes the old file first", async () => {
    const { her, p } = await published("rep-flac");
    const line = herLines()[0];
    const before = await fileOf(p.id, line);
    expect((await replace(her, p.id, line, { bytes: flac(9600) })).status).toBe(201);
    await drain(p.id);
    const item = fake.items.get(identifierFor(p.id));
    expect(item.files.has(before.name)).toBe(false);
    expect(item.files.has(before.name.replace(/\.wav$/, ".flac"))).toBe(true);
    expect(fake.requests.filter((x) => x.method === "DELETE")[0].headers["x-archive-cascade-delete"]).toBe("1");
  });

  it("only the line's performer replaces it, and only at the current consent", async () => {
    const { director, her, p } = await published("rep-who");
    const line = herLines()[0];
    const r = await replace(director, p.id, line);
    expect(r.status).toBe(403);
    expect((await r.json()).error).toBe("not_your_take");
    await env.DB.prepare("UPDATE play_consents SET version = 'cc0-old' WHERE production_id = ?1 AND user_id = ?2").bind(p.id, her.user_id).run();
    const c = await replace(her, p.id, line);
    expect(c.status).toBe(409);
    expect((await c.json()).error).toBe("consent_missing");
  });

  it("a reported replacement is held back, not sent", async () => {
    const { director, her, p } = await published("rep-report");
    const line = herLines()[0];
    const r = await replace(her, p.id, line);
    const take = (await r.json()).id;
    expect((await call("POST", "/v1/plays/reports", { token: director.access_token, body: { production_id: p.id, take_id: take, reason: "offensive" } })).status).toBe(201);
    await runArchive(ia, Date.now(), 1000);
    expect(fake.puts()).toEqual([]);
    expect((await job(p.id)).reason).toBe("reported_take");
  });

  it("a performer removes their take: the file is deleted, the reason kept, and their credit goes when nothing of theirs is left", async () => {
    const { her, p } = await published("rm");
    for (const line of herLines()) expect((await remove(her, p.id, line)).status).toBe(202);
    await drain(p.id);
    const item = fake.items.get(identifierFor(p.id));
    for (const line of herLines()) {
      const f = await fileOf(p.id, line);
      expect(f).toMatchObject({ state: "removed", removed_by: "performer", reason: "withdrawn" });
      expect(item.files.has(f.name)).toBe(false);
    }
    expect(item.meta.creator).toEqual(["Pat"]);
    expect(item.meta.credits).not.toContain("Zoë");
    // Removing again changes nothing.
    fake.requests.length = 0;
    expect((await (await remove(her, p.id, herLines()[0])).json()).state).toBe("removed");
    await runArchive(ia, Date.now(), 1000);
    expect(fake.requests).toEqual([]);
  });

  it("the director removes any take, with a report's reason, and the performer cannot put it back", async () => {
    const { director, her, p } = await published("rm-dir");
    const line = herLines()[0];
    expect((await remove(director, p.id, line, { reason: "offensive" })).status).toBe(202);
    await drain(p.id);
    expect(await fileOf(p.id, line)).toMatchObject({ state: "removed", removed_by: "director", reason: "offensive" });
    const r = await replace(her, p.id, line);
    expect(r.status).toBe(409);
    expect((await r.json()).error).toBe("removed_by_director");
    expect((await remove(director, p.id, line, { reason: "because" })).status).toBe(400);
  });

  it("nobody else removes a take, and nothing is removed before the item is published", async () => {
    const { director, her, p } = await published("rm-other");
    const other = await person("rm-other-3");
    await env.DB.prepare("INSERT INTO play_members (production_id, user_id, display_name, joined_at) VALUES (?1, ?2, 'Sam', ?3)").bind(p.id, other.user_id, Date.now()).run();
    expect((await remove(other, p.id, herLines()[0])).status).toBe(403);
    const fresh = await complete("rm-early");
    expect((await publish(fresh.director, fresh.p.id)).status).toBe(201);
    expect((await remove(fresh.director, fresh.p.id, herLines()[0])).status).toBe(404);
    expect(her).toBeTruthy();
    expect(director).toBeTruthy();
  });

  it("a 404 on delete means already gone; a refused change fails that line alone", async () => {
    const { her, p } = await published("rm-404");
    const [a, b] = herLines().length > 1 ? herLines() : [herLines()[0], null];
    fake.items.get(identifierFor(p.id)).files.delete((await fileOf(p.id, a)).name);
    expect((await remove(her, p.id, a)).status).toBe(202);
    await drain(p.id);
    expect((await fileOf(p.id, a)).state).toBe("removed");
    if (!b) return;
    fake.state.fail = (r) => (r.method === "PUT" ? new Response("<Error><Code>AccessDenied</Code></Error>", { status: 403 }) : null);
    expect((await replace(her, p.id, b)).status).toBe(201);
    await drain(p.id);
    expect((await fileOf(p.id, b)).state).toBe("failed");
    expect((await job(p.id)).status).toBe("published");
  });

  it("when the director deletes their account, the job passes with the production and its performers keep these controls", async () => {
    const { director, her, p } = await published("rm-del");
    expect((await call("DELETE", "/v1/account", { token: director.access_token })).status).toBe(200);
    expect((await job(p.id)).user_id).toBe(her.user_id);
    expect((await remove(her, p.id, herLines()[0])).status).toBe(202);
  });
});
