// The archive.org uploader (P14) and replacing or removing a published take
// (P12), against a fake archive.org: nothing here reaches the real one. The
// Worker keeps no take audio (Decision 082): the cron lays the item out and
// removes lines, and each line's file comes from a device (`sendLine`). The
// script is the castable one with the fewest lines, picked from the data.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import worker from "../src/index.js";
import { call, env, installProviderKeys, signIn } from "./helpers.js";
import { castOf, catalog, consent, flac, newTakeId, wav } from "./plays-helpers.js";
import { castParts, isSpeaking, linesOf } from "../src/plays-relay.js";
import MANIFEST from "../src/castable-manifest.json";
import { DELETED_PERSON } from "../src/plays.js";
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

// A publish here sends one file a line from the "device", 147 requests: more than the default 5 s under a full parallel run.
vi.setConfig({ testTimeout: 30_000 });

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
      // The Worker streams each file; reading it here is archive.org receiving it.
      const bytes = init.body instanceof ReadableStream ? (await new Response(init.body).arrayBuffer()).byteLength : init.body.byteLength;
      items.get(id).files.set(name, { bytes, derive: headers["x-archive-queue-derive"] !== "0" });
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

/** The devices' own copies of each take (the Worker keeps none, Decision 082): take id to bytes. */
const onDevice = new Map();

/** A chosen take row for `line`; its audio stays on the device (`onDevice`). */
async function seedTake(pid, userId, line, part, { bytes = wav(4800), type = "audio/wav" } = {}) {
  const id = newTakeId();
  onDevice.set(id, bytes);
  await env.DB.batch([
    env.DB.prepare("UPDATE play_takes SET chosen = 0 WHERE production_id = ?1 AND line_id = ?2").bind(pid, line),
    env.DB.prepare(
      "INSERT INTO play_takes (production_id, id, user_id, line_id, part, file, content_type, bytes, frames, sample_rate, capture, created, uploaded_at, chosen) " +
        "VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 4800, 48000, 'direct', 0, ?9, 1)",
    ).bind(pid, id, userId, line, part, `${id}.wav`, type, bytes.length, Date.now()),
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

/** One line's file from a device: `bytes` defaults to the device's copy of the line's take. */
async function sendLine(s, pid, line, { bytes, envOverride = { ...KEYS, USER_LIMITER: undefined } } = {}) {
  const f = (await files(pid)).find((x) => x.line_id === line);
  const body = bytes || onDevice.get(f.take_id);
  return call("PUT", `/v1/plays/productions/${pid}/archive/files/${encodeURIComponent(line)}`, {
    token: s.access_token,
    body,
    envOverride,
    headers: { "content-length": String(body.length) },
  });
}

/** The director's device sends every line still waiting, in script order; returns the responses. */
async function sendAll(s, pid, opts) {
  const out = [];
  for (const f of await files(pid)) if (f.state === "pending") out.push(await sendLine(s, pid, f.line_id, opts));
  return out;
}

/** Runs the cron until the job settles or `max` runs pass; returns the runs taken. */
async function drain(pid, { now = Date.now(), max = 50 } = {}) {
  for (let i = 1; i <= max; i++) {
    const before = fake.requests.length;
    await runArchive(ia, now, 1000);
    const j = await job(pid);
    const busy = (await files(pid)).some((f) => f.state === "remove");
    if (fake.requests.length === before || (!busy && j.status !== "uploading" && j.credits)) return i;
  }
  return max;
}

/** Publish, the cron lays the item out, the director's device sends every file. */
async function published(label) {
  const t = await complete(label);
  expect((await publish(t.director, t.p.id)).status).toBe(201);
  await runArchive(ia, Date.now(), 1000);
  for (const r of await sendAll(t.director, t.p.id)) expect(r.status, await r.clone().text()).toBe(200);
  expect((await job(t.p.id)).status).toBe("published");
  fake.requests.length = 0;
  return t;
}

const herLines = () => linesOf(cast, herPart);

describe("the gate", () => {
  it("runs nothing without both keys, and a file is refused without them", async () => {
    const { director, p } = await complete("gate");
    expect((await publish(director, p.id)).status).toBe(201);
    await runArchive({ ...env, IA_S3_ACCESS_KEY: ACCESS }, Date.now(), 1000);
    await runArchive({ ...env, IA_S3_SECRET_KEY: SECRET }, Date.now(), 1000);
    expect(fake.requests).toEqual([]);
    expect((await job(p.id)).status).toBe("queued");
    await runArchive(ia, Date.now(), 1000);
    expect((await sendLine(director, p.id, speakingLines[0], { envOverride: { IA_S3_ACCESS_KEY: ACCESS } })).status).toBe(503);
  });

  it("a file waits for the cron to lay the item out", async () => {
    const { director, p } = await complete("early");
    expect((await publish(director, p.id)).status).toBe(201);
    const r = await call("PUT", `/v1/plays/productions/${p.id}/archive/files/${encodeURIComponent(speakingLines[0])}`, {
      token: director.access_token,
      body: wav(4800),
      envOverride: KEYS,
      headers: { "content-length": String(wav(4800).length) },
    });
    expect(r.status).toBe(409);
    expect((await r.json()).error).toBe("not_ready");
  });

  it("the five-minute trigger lays the item out, and so does the hourly one, with no request to archive.org", async () => {
    const a = await complete("cron");
    expect((await publish(a.director, a.p.id)).status).toBe(201);
    const ctx = createExecutionContext();
    await worker.scheduled(createScheduledController({ cron: ARCHIVE_CRON }), ia, ctx);
    await waitOnExecutionContext(ctx);
    expect((await job(a.p.id)).status).toBe("uploading");
    expect((await files(a.p.id)).length).toBe(speakingLines.length);
    const b = await complete("cron2");
    expect((await publish(b.director, b.p.id)).status).toBe(201);
    const ctx2 = createExecutionContext();
    await worker.scheduled(createScheduledController({ cron: "23 * * * *" }), ia, ctx2);
    await waitOnExecutionContext(ctx2);
    expect((await job(b.p.id)).status).toBe("uploading");
    expect(fake.requests).toEqual([]);
  });
});

describe("a first publish", () => {
  it("makes one item, its metadata from data, one file per line in script order, derived once", async () => {
    const { director, her, p } = await complete("ok");
    expect((await publish(director, p.id)).status).toBe(201);
    await runArchive(ia, Date.now(), 1000);
    const sent = await sendAll(director, p.id);
    expect(sent.every((r) => r.status === 200)).toBe(true);
    const id = identifierFor(p.id);
    expect(id).toBe(`eardrama-${p.id.toLowerCase()}`);
    expect(id).toMatch(/^[a-z0-9][a-z0-9._-]{4,99}$/);
    expect([...fake.items.keys()]).toEqual([id]);
    const item = fake.items.get(id);
    const entry = MANIFEST.scripts[small.id];
    expect(item.meta).toMatchObject({ mediatype: "audio", collection: IA_COLLECTION, title: `${entry.title} (Ear Drama recording)`, licenseurl: CC0_URL, source: entry.source, language: "eng" });
    // The owner-approved labels (2026-10-29): subject "Ear Drama" finds every production.
    expect(item.meta.subject).toEqual(["Ear Drama", "audio drama", "eardrama.org"]);
    expect(item.meta.description).toBe(`Recorded part by part with Ear Drama (https://eardrama.org). Script: ${entry.title}, from ${entry.source}. Each file is one line, in script order.`);
    expect(speaking.length).toBeGreaterThan(1);
    expect(item.meta.creator).toEqual(["Pat", "Zoë"]);
    expect(item.meta.credits).toContain(`${herPart}: Zoë`);
    for (const e of entry.rights.evidence) expect(item.meta.rights).toContain(e.claim);
    const names = [...item.files.keys()];
    expect(names.length).toBe(speakingLines.length);
    expect([...names].sort()).toEqual(names.slice().sort());
    // The read-along's contract (PLAYS-DESIGN 2.11): a file's number is its line's 1-based place in the script,
    // so a client names the line a file speaks from the file name and the script alone.
    expect(names.map((n) => small.lines[Number(n.slice(0, 4)) - 1].id)).toEqual(speakingLines);
    expect(fake.puts().map((r) => r.path.split("/").pop())).toEqual([...names].sort());
    // Each file arrives whole, streamed with its length.
    for (const [name, f] of item.files) expect(f.bytes, name).toBe(wav(4800).length);
    expect([...item.files.values()].filter((f) => f.derive).length).toBe(1);
    expect(item.files.get(names.at(-1)).derive).toBe(true);
    const rec = await record(her, p.id);
    expect(rec.archive).toMatchObject({ status: "published", url: itemUrl(id), reason: null });
    expect(metaValue("Zoë")).toBe("uri(Zo%C3%AB)");
  });

  it("asks archive.org's check_limit before the first file only", async () => {
    const { director, p } = await complete("budget");
    expect((await publish(director, p.id)).status).toBe(201);
    await runArchive(ia, Date.now(), 1000);
    await sendAll(director, p.id);
    expect(fake.requests[0].search).toContain("check_limit=1");
    expect(fake.requests.filter((r) => r.search.includes("check_limit")).length).toBe(1);
  });

  it("refuses the file while check_limit says the item's queue is over its limit", async () => {
    const { director, p } = await complete("limit");
    expect((await publish(director, p.id)).status).toBe(201);
    await runArchive(ia, Date.now(), 1000);
    fake.state.overLimit = true;
    const r = await sendLine(director, p.id, speakingLines[0]);
    expect(r.status).toBe(503);
    expect((await r.json()).error).toBe("archive_busy");
    expect(fake.puts()).toEqual([]);
  });

  it("only the chosen take goes: another recording of the line, or another format, is refused", async () => {
    const { director, p } = await complete("nottake");
    expect((await publish(director, p.id)).status).toBe(201);
    await runArchive(ia, Date.now(), 1000);
    const r = await sendLine(director, p.id, speakingLines[0], { bytes: wav(48000) });
    expect(r.status).toBe(422);
    expect((await r.json()).error).toBe("not_the_take");
    expect((await sendLine(director, p.id, speakingLines[0], { bytes: flac(4800) })).status).toBe(422);
    expect(fake.puts()).toEqual([]);
  });

  it("a line is the director's or its performer's to send, no one else's", async () => {
    const { director, her, p } = await complete("sender");
    const other = await person("sender-3");
    await env.DB.prepare("INSERT INTO play_members (production_id, user_id, display_name, joined_at) VALUES (?1, ?2, 'Sam', ?3)").bind(p.id, other.user_id, Date.now()).run();
    expect((await publish(director, p.id)).status).toBe(201);
    await runArchive(ia, Date.now(), 1000);
    expect((await sendLine(other, p.id, herLines()[0])).status).toBe(403);
    expect((await sendLine(her, p.id, linesOf(cast, speaking[0])[0])).status).toBe(403);
    expect((await sendLine(her, p.id, herLines()[0])).status).toBe(200);
  });
});

describe("idempotency and retries", () => {
  it("never sends a line twice: a sent line answers 409, and a 503 SlowDown leaves the line waiting for the device's retry", async () => {
    const { director, p } = await complete("retry");
    expect((await publish(director, p.id)).status).toBe(201);
    await runArchive(ia, Date.now(), 1000);
    let put = 0;
    fake.state.fail = (r) =>
      r.method === "PUT" && ++put === 2 ? new Response("<Error><Code>SlowDown</Code><Message>Please reduce your request rate.</Message></Error>", { status: 503 }) : null;
    const [first, second] = speakingLines;
    expect((await sendLine(director, p.id, first)).status).toBe(200);
    const slow = await sendLine(director, p.id, second);
    expect(slow.status).toBe(503);
    expect((await slow.json()).detail).toContain("SlowDown");
    expect((await files(p.id)).find((f) => f.line_id === second).state).toBe("pending");
    const again = await sendLine(director, p.id, first);
    expect(again.status).toBe(409);
    expect((await again.json()).error).toBe("already_sent");
    await sendAll(director, p.id);
    expect((await job(p.id)).status).toBe("published");
    const ok = fake.puts().filter((_, i) => i !== 1);
    const counts = {};
    for (const r of ok) counts[r.path] = (counts[r.path] || 0) + 1;
    expect(Object.values(counts).every((c) => c === 1)).toBe(true);
    expect(Object.keys(counts).length).toBe(speakingLines.length);
    // Done is done: the cron sends nothing.
    fake.requests.length = 0;
    await runArchive(ia, Date.now() + MAX_ATTEMPTS * backoff(MAX_ATTEMPTS), 1000);
    expect(fake.requests).toEqual([]);
  });

  it("a run that holds the lease keeps another off the job", async () => {
    const { director, p } = await complete("lease");
    expect((await publish(director, p.id)).status).toBe(201);
    const now = Date.now();
    await env.DB.prepare("UPDATE play_archive_jobs SET lease_until = ?2 WHERE production_id = ?1").bind(p.id, now + 60_000).run();
    await runArchive(ia, now, 1000);
    expect((await job(p.id)).status).toBe("queued");
    expect(await files(p.id)).toEqual([]);
  });

  it("two runs at once lay the item out once: the lease is taken before any work", async () => {
    const { director, p } = await complete("race");
    expect((await publish(director, p.id)).status).toBe(201);
    const now = Date.now();
    await Promise.all([runArchive(ia, now, 1000), runArchive(ia, now, 1000), runArchive(ia, now, 1000)]);
    expect((await files(p.id)).length).toBe(speakingLines.length);
    expect((await job(p.id)).status).toBe("uploading");
  });

  it("Publish again after a failure keeps the lines already on the item sent", async () => {
    const { director, p } = await complete("republish");
    expect((await publish(director, p.id)).status).toBe(201);
    await runArchive(ia, Date.now(), 1000);
    const [first, second] = speakingLines;
    expect((await sendLine(director, p.id, first)).status).toBe(200);
    expect((await sendLine(director, p.id, second)).status).toBe(200);
    await env.DB.prepare("UPDATE play_archive_jobs SET status = 'failed', reason = 'test' WHERE production_id = ?1").bind(p.id).run();
    expect((await publish(director, p.id)).status).toBe(200);
    await runArchive(ia, Date.now(), 1000);
    const states = Object.fromEntries((await files(p.id)).map((f) => [f.line_id, f.state]));
    expect([states[first], states[second]]).toEqual(["sent", "sent"]);
    expect((await sendLine(director, p.id, first)).status).toBe(409);
  });

  it("a refusal is answered to the device and fails nothing: the line waits and goes when archive.org takes it", async () => {
    const { director, p } = await complete("size");
    expect((await publish(director, p.id)).status).toBe(201);
    await runArchive(ia, Date.now(), 1000);
    fake.state.fail = (r) =>
      r.method === "PUT" ? new Response("<Error><Code>EntityTooLarge</Code><Message>Your proposed upload exceeds the maximum allowed size</Message></Error>", { status: 400 }) : null;
    const r = await sendLine(director, p.id, speakingLines[0]);
    expect(r.status).toBe(502);
    expect(await r.json()).toMatchObject({ error: "archive_refused" });
    expect((await job(p.id)).status).toBe("uploading");
    fake.state.fail = null;
    expect((await sendLine(director, p.id, speakingLines[0])).status).toBe(200);
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
    await runArchive(ia, Date.now(), 1000);
    let first = true;
    // An answer that echoes the secret, as a careless error page might.
    fake.state.fail = (r) =>
      r.method === "PUT" && first ? ((first = false), new Response(`<Error><Code>SlowDown</Code><Message>key ${SECRET} ${ACCESS}</Message></Error>`, { status: 503 })) : null;
    const refused = await (await sendLine(director, p.id, speakingLines[0])).text();
    await sendAll(director, p.id);
    const texts = [
      ...logs,
      refused,
      JSON.stringify(await job(p.id)),
      JSON.stringify(await files(p.id)),
      await pub.text(),
      JSON.stringify(await record(director, p.id)),
      JSON.stringify(await record(her, p.id)),
      await (await call("GET", "/v1/plays/consent", { token: her.access_token, envOverride: KEYS })).text(),
    ];
    expect(logs.length).toBeGreaterThan(0);
    expect(refused).toContain("[redacted]");
    for (const t of texts) {
      expect(t).not.toContain(SECRET);
      expect(t).not.toContain(ACCESS);
    }
    expect(new Set(fake.requests.map((r) => r.host))).toEqual(new Set(["s3.us.archive.org"]));
    for (const r of fake.puts()) expect(r.headers.authorization).toBe(`LOW ${ACCESS}:${SECRET}`);
  });
});

describe("replacing or removing a published take (P12)", () => {
  /** A performer's replacement: recorded on the Worker (fields only), its audio kept on the device for sendLine. */
  const replace = async (s, pid, line, { bytes = wav(9600), meta = {} } = {}) => {
    const id = newTakeId();
    const r = await call("PUT", `/v1/plays/productions/${pid}/takes/${id}`, {
      token: s.access_token,
      body: bytes,
      headers: { "content-length": String(bytes.length), "x-take": JSON.stringify({ lineID: line, frames: 9600, sampleRate: 48000, ...meta }) },
      envOverride: KEYS,
    });
    if (r.status === 201) onDevice.set(id, bytes);
    return r;
  };
  const remove = (s, pid, line, body = {}) =>
    call("POST", `/v1/plays/productions/${pid}/archive/lines/${encodeURIComponent(line)}/remove`, { token: s.access_token, body, envOverride: KEYS });
  const fileOf = async (pid, line) => (await files(pid)).find((f) => f.line_id === line);

  it("a performer replaces their own take: the same name is overwritten, from their own device", async () => {
    const { her, p } = await published("rep");
    const line = herLines()[0];
    const before = await fileOf(p.id, line);
    const r = await replace(her, p.id, line);
    expect(r.status).toBe(201);
    expect((await r.json()).delivered).toBe(false);
    expect((await fileOf(p.id, line)).state).toBe("pending");
    expect((await sendLine(her, p.id, line)).status).toBe(200);
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
    expect((await sendLine(her, p.id, line)).status).toBe(200);
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
    const held = await sendLine(her, p.id, line);
    expect(held.status).toBe(409);
    expect((await held.json()).error).toBe("reported_take");
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

  it("a removal archive.org answers with 503 backs off, and after MAX_ATTEMPTS that line is marked failed", async () => {
    const { her, p } = await published("rm-retry");
    const line = herLines()[0];
    expect((await remove(her, p.id, line)).status).toBe(202);
    fake.state.fail = (r) => (r.method === "DELETE" ? new Response("<Error><Code>SlowDown</Code></Error>", { status: 503 }) : null);
    let now = Date.now();
    await runArchive(ia, now, 1000);
    const j = await job(p.id);
    expect(j.attempts).toBe(1);
    expect(j.next_attempt_at).toBe(now + backoff(1));
    const seen = fake.requests.length;
    await runArchive(ia, now + backoff(1) - 1, 1000);
    expect(fake.requests.length).toBe(seen);
    for (let i = 1; i < MAX_ATTEMPTS; i++) {
      now += backoff(i);
      await runArchive(ia, now, 1000);
    }
    expect((await fileOf(p.id, line)).state).toBe("failed");
    expect((await fileOf(p.id, line)).reason).toMatch(new RegExp(`^gave up after ${MAX_ATTEMPTS} attempts: archive.org 503 SlowDown`));
    expect((await job(p.id)).status).toBe("published");
  });

  it("three cron runs at once delete a removed line once: the lease is taken before any request", async () => {
    const { director, p } = await published("rm-race");
    expect((await remove(director, p.id, linesOf(cast, speaking[0])[0])).status).toBe(202);
    const now = Date.now();
    await Promise.all([runArchive(ia, now, 1000), runArchive(ia, now, 1000), runArchive(ia, now, 1000)]);
    expect(fake.requests.filter((r) => r.method === "DELETE").length).toBe(1);
  });

  it("the cron keeps to its request budget", async () => {
    const { director, p } = await published("rm-budget");
    const mine = linesOf(cast, speaking[0]).slice(0, 3);
    for (const line of mine) expect((await remove(director, p.id, line)).status).toBe(202);
    await runArchive(ia, Date.now(), 2);
    expect(fake.requests.filter((r) => r.method === "DELETE").length).toBe(2);
  });

  it("a removal archive.org refuses (4xx) fails that line at once, and is not retried", async () => {
    const { her, p } = await published("rm-refused");
    const line = herLines()[0];
    expect((await remove(her, p.id, line)).status).toBe(202);
    fake.state.fail = (r) => (r.method === "DELETE" ? new Response("<Error><Code>AccessDenied</Code></Error>", { status: 403 }) : null);
    await runArchive(ia, Date.now(), 1000);
    expect((await fileOf(p.id, line)).state).toBe("failed");
    fake.requests.length = 0;
    await runArchive(ia, Date.now() + 86_400_000, 1000);
    expect(fake.requests.filter((r) => r.method === "DELETE")).toEqual([]);
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

  it("a 404 on delete means already gone", async () => {
    const { her, p } = await published("rm-404");
    const a = herLines()[0];
    fake.items.get(identifierFor(p.id)).files.delete((await fileOf(p.id, a)).name);
    expect((await remove(her, p.id, a)).status).toBe(202);
    await drain(p.id);
    expect((await fileOf(p.id, a)).state).toBe("removed");
  });

  it("when the director deletes their account, the production stays directed by no one and its performers keep their own controls", async () => {
    const { director, her, p } = await published("rm-del");
    const dirLine = linesOf(cast, speaking[0])[0];
    expect((await call("DELETE", "/v1/account", { token: director.access_token })).status).toBe(200);
    expect((await job(p.id)).user_id).toBe(DELETED_PERSON);
    expect((await remove(her, p.id, herLines()[0])).status).toBe(202);
    expect((await remove(her, p.id, dirLine)).status).toBe(403);
  });
});

describe("a published production outlives its members' accounts (owner, 2026-10-29)", () => {
  const takeUsers = async (pid) =>
    (await env.DB.prepare("SELECT DISTINCT user_id FROM play_takes WHERE production_id = ?1").bind(pid).all()).results.map((r) => r.user_id).sort();
  const listed = (pid) => call("GET", `/v1/plays/finished/${pid}`);

  it("a performer's deletion keeps the listing, the takes and the item; their part goes uncredited", async () => {
    const { director, her, p } = await published("surv-her");
    const lines = (await files(p.id)).length;
    const item = fake.items.get(identifierFor(p.id));
    const partsOf = async () => (await env.DB.prepare("SELECT part, user_id FROM play_parts WHERE production_id = ?1 ORDER BY part").bind(p.id).all()).results;
    const partsBefore = await partsOf();
    expect((await (await listed(p.id)).json()).credits).toContainEqual({ part: herPart, name: "Zoë" });
    expect((await call("DELETE", "/v1/account", { token: her.access_token })).status).toBe(200);
    const body = await (await listed(p.id)).json();
    expect(body.credits).toContainEqual({ part: herPart, name: "" });
    expect(body.credits.some((c) => c.name === "Zoë")).toBe(false);
    expect((await files(p.id)).length).toBe(lines);
    expect(await takeUsers(p.id)).toEqual([DELETED_PERSON, director.user_id].sort());
    expect((await partsOf()).map((r) => r.part)).toEqual(partsBefore.map((r) => r.part));
    expect((await partsOf()).find((r) => r.part === herPart).user_id).toBe(DELETED_PERSON);
    expect((await job(p.id)).status).toBe("published");
    expect((await job(p.id)).credits).toBeNull();
    await drain(p.id);
    expect(item.meta.credits).not.toContain("Zoë");
    expect(item.meta.creator).toEqual(["Pat"]);
    expect(item.files.size).toBe(lines);
  });

  it("the director's deletion keeps it too, and no remaining member becomes the director", async () => {
    const { director, her, p } = await published("surv-dir");
    const lines = (await files(p.id)).length;
    expect((await call("DELETE", "/v1/account", { token: director.access_token })).status).toBe(200);
    expect((await listed(p.id)).status).toBe(200);
    expect((await files(p.id)).length).toBe(lines);
    const rec = await record(her, p.id);
    expect(rec.director).toBe(DELETED_PERSON);
    expect(rec.members.some((m) => m.name === "Pat")).toBe(false);
    expect((await env.DB.prepare("SELECT user_id FROM play_productions WHERE id = ?1").bind(p.id).first()).user_id).toBe(DELETED_PERSON);
  });

  it("when everyone has deleted their account the production, its takes and its item remain", async () => {
    const { director, her, p } = await published("surv-all");
    const lines = (await files(p.id)).length;
    expect((await call("DELETE", "/v1/account", { token: her.access_token })).status).toBe(200);
    expect((await call("DELETE", "/v1/account", { token: director.access_token })).status).toBe(200);
    expect(await takeUsers(p.id)).toEqual([DELETED_PERSON]);
    expect((await listed(p.id)).status).toBe(200);
    expect((await files(p.id)).length).toBe(lines);
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM play_members WHERE production_id = ?1").bind(p.id).first()).n).toBe(0);
  });

  it("CONTROL: an unpublished production still goes with its last member", async () => {
    const { director, her, p } = await complete("surv-ctl");
    expect((await call("DELETE", "/v1/account", { token: her.access_token })).status).toBe(200);
    expect((await call("DELETE", "/v1/account", { token: director.access_token })).status).toBe(200);
    expect(await env.DB.prepare("SELECT 1 FROM play_productions WHERE id = ?1").bind(p.id).first()).toBeNull();
    expect(await takeUsers(p.id)).toEqual([]);
  });
});

// Owner 2026-11-23: "fix the re-scan of the exact same failures. We should never build something that does that."
describe("the cron does not pick the same job again for nothing", () => {
  it("jobs only waiting for their devices do not crowd a new job out of the run", async () => {
    for (let i = 0; i < 5; i++) {
      const w = await complete(`wait-${i}`);
      expect((await publish(w.director, w.p.id)).status).toBe(201);
      await runArchive(ia, Date.now(), 1000);
      expect((await job(w.p.id)).status).toBe("uploading");
    }
    const fresh = await complete("wait-new");
    expect((await publish(fresh.director, fresh.p.id)).status).toBe(201);
    await runArchive(ia, Date.now(), 1000);
    expect((await job(fresh.p.id)).status).toBe("uploading");
  });

  it("a credits rewrite archive.org keeps refusing with 503 is given up on and reported, and only a new change tries again", async () => {
    const { p } = await published("cr-retry");
    const reopen = () => env.DB.prepare("UPDATE play_archive_jobs SET credits = NULL WHERE production_id = ?1").bind(p.id).run();
    await reopen();
    fake.state.fail = (r) => (r.host === "archive.org" ? new Response("busy", { status: 503 }) : null);
    let now = Date.now();
    await runArchive(ia, now, 1000);
    for (let i = 1; i < MAX_ATTEMPTS; i++) {
      now += backoff(i);
      await runArchive(ia, now, 1000);
    }
    expect((await job(p.id)).reason).toMatch(new RegExp(`^gave up after ${MAX_ATTEMPTS} attempts`));
    fake.requests.length = 0;
    await runArchive(ia, now + 13 * 3_600_000, 1000);
    await runArchive(ia, now + 30 * 86_400_000, 1000);
    expect(fake.requests).toEqual([]);
    await reopen();
    await runArchive(ia, now + 31 * 86_400_000, 1000);
    expect(fake.requests.length).toBe(1);
  });
});
