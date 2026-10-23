import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import worker from "../src/index.js";
import { call, env, installProviderKeys, signIn } from "./helpers.js";
import relaySource from "../src/plays-relay.js?raw";
import MANIFEST from "../src/castable-manifest.json";
import { manifestFor } from "../src/plays-manifest.js";
import { CLAIM_TTL_MS, DIRECTIONS, SOUND, isSpeaking } from "../src/plays-relay.js";
import { CONSENT_TEXT, CONSENT_VERSION, MAX_TAKES_PER_LINE, normalizeClassCode } from "../src/plays.js";
import { nameRefusal } from "../src/plays-names.js";
import { MAX_TAKE_BYTES, MAX_TAKE_SECONDS, readTakeAudio } from "../src/plays-audio.js";
import {
  cast,
  catalog,
  claim,
  claimByInvite,
  consent,
  createBody,
  createProduction,
  firstPart,
  flac,
  invite,
  linesFor,
  newTakeId,
  order,
  partAction,
  record,
  script,
  secondPart,
  seedChosen,
  upload,
  wav,
} from "./plays-helpers.js";

let fetchSpy;
beforeEach(() => {
  fetchSpy = installProviderKeys();
});
afterEach(() => vi.restoreAllMocks());

let n = 0;
const person = (label) => signIn(`plays-${label}-${n++}`);

/** A production with its director holding the first part and consented. */
async function recording(label = "dir") {
  const director = await person(label);
  const p = await createProduction(director, { display_name: "Director" });
  expect((await claim(director, p.id, firstPart)).status).toBe(200);
  expect((await consent(director, p.id)).status).toBe(204);
  return { director, p };
}

/** A second person brought in by invite, holding `part`, consented. */
async function castMember(director, pid, part, label = "actor", name = "Actor") {
  const actor = await person(label);
  const inv = await invite(director, pid);
  const r = await claimByInvite(actor, inv.token, part, { display_name: name });
  expect(r.status, await r.clone().text()).toBe(200);
  expect((await consent(actor, pid)).status).toBe(204);
  return actor;
}

async function finishFirstPart(director, pid) {
  await seedChosen(pid, director.user_id, linesFor(firstPart), firstPart);
  expect((await partAction(director, pid, firstPart, "done")).status).toBe(200);
}

const runSweep = async () => {
  const ctx = createExecutionContext();
  await worker.scheduled(createScheduledController(), env, ctx);
  await waitOnExecutionContext(ctx);
};

describe("the castable manifest (PLAYS-DESIGN §8 rule 1)", () => {
  it("matches the catalog's castable file; rebuild it with node tools/castable-manifest.mjs", async () => {
    expect(await manifestFor(catalog)).toEqual(MANIFEST);
  });

  it("CONTROL: a production is made from a manifest script, its revision, and its cast sheet", async () => {
    const s = await person("make");
    const r = await call("POST", "/v1/plays/productions", { token: s.access_token, body: createBody() });
    expect(r.status).toBe(201);
    const p = await r.json();
    expect(p).toMatchObject({ scriptID: script.id, scriptRevision: script.revision, title: script.title, takes: [], chosen: {}, roomTone: [], listenedThrough: false });
    expect(p.director).toBe(s.user_id);
  });

  it("refuses a script that is not in the manifest", async () => {
    const s = await person("unknown");
    const r = await call("POST", "/v1/plays/productions", { token: s.access_token, body: createBody({ script_id: "gut-0-not-castable" }) });
    expect(r.status).toBe(422);
    expect((await r.json()).error).toBe("not_castable");
    const proto = await call("POST", "/v1/plays/productions", { token: s.access_token, body: createBody({ script_id: "__proto__" }) });
    expect(proto.status).toBe(422);
  });

  it("refuses another revision, and names the current one", async () => {
    const s = await person("rev");
    const r = await call("POST", "/v1/plays/productions", { token: s.access_token, body: createBody({ script_revision: "000000000000" }) });
    expect(r.status).toBe(409);
    expect(await r.json()).toEqual({ error: "revision_mismatch", detail: script.revision });
  });

  it("refuses a cast sheet that is not the script's: a line moved to another part, or lines reordered", async () => {
    const s = await person("cast");
    const moved = cast.map(([id, part], i) => ({ id, part: i === 0 ? (part === DIRECTIONS ? SOUND : DIRECTIONS) : part }));
    const r = await call("POST", "/v1/plays/productions", { token: s.access_token, body: createBody({ cast: moved }) });
    expect(r.status).toBe(422);
    expect((await r.json()).error).toBe("cast_mismatch");
    const swapped = cast.map(([id, part]) => ({ id, part }));
    [swapped[0], swapped[1]] = [swapped[1], swapped[0]];
    expect((await call("POST", "/v1/plays/productions", { token: s.access_token, body: createBody({ cast: swapped }) })).status).toBe(422);
  });
});

describe("the production record (production.json field names)", () => {
  it("has every production.json field, parts in the cast, and Foundation dates", async () => {
    const s = await person("rec");
    const p = await createProduction(s);
    for (const k of ["id", "scriptID", "scriptRevision", "title", "created", "parts", "takes", "chosen", "roomTone", "listenedThrough"]) {
      expect(p, k).toHaveProperty(k);
    }
    expect(Object.keys(p.parts).sort()).toEqual([...order].sort());
    for (const st of Object.values(p.parts)) expect(st).toEqual({ status: "open" });
    expect(Math.abs(p.created - (Date.now() / 1000 - 978307200))).toBeLessThan(60);
    expect(p.next).toBe(firstPart);
  });

  it("merges every member's takes, line by line, with the take's fields", async () => {
    const { director, p } = await recording("merge");
    const line = linesFor(firstPart)[0];
    const a = await upload(director, p.id, line, { meta: { heard: { L0: "standin" }, capture: "aec" } });
    expect(a.status).toBe(201);
    await finishFirstPart(director, p.id);
    const actor = await castMember(director, p.id, secondPart);
    const b = await upload(actor, p.id, linesFor(secondPart)[0]);
    expect(b.status).toBe(201);
    for (const viewer of [director, actor]) {
      const rec = await record(viewer, p.id);
      const ids = rec.takes.map((t) => t.id);
      expect(ids).toContain(a.takeId);
      expect(ids).toContain(b.takeId);
      expect(rec.chosen[linesFor(secondPart)[0]]).toBe(b.takeId);
      const t = rec.takes.find((x) => x.id === a.takeId);
      expect(t).toMatchObject({ lineID: line, part: firstPart, frames: 48000, sampleRate: 48000, capture: "aec", heard: { L0: "standin" }, bleed: false });
      expect(rec.parts[secondPart]).toMatchObject({ status: "recording", performer: "Actor", user_id: actor.user_id });
    }
  });

  it("is seen only by members: anyone else gets not found", async () => {
    const s = await person("own");
    const stranger = await person("stranger");
    const p = await createProduction(s);
    expect((await call("GET", `/v1/plays/productions/${p.id}`, { token: stranger.access_token })).status).toBe(404);
    expect((await call("GET", `/v1/plays/productions/${p.id}`, { token: s.access_token })).status).toBe(200);
    const list = await (await call("GET", "/v1/plays/productions", { token: stranger.access_token })).json();
    expect(list.productions).toEqual([]);
  });
});

describe("invite links", () => {
  it("are 256 random bits, returned once and stored only as a hash", async () => {
    const s = await person("inv");
    const p = await createProduction(s);
    const a = await invite(s, p.id);
    const b = await invite(s, p.id);
    expect(a.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(a.token).not.toBe(b.token);
    const rows = (await env.DB.prepare("SELECT * FROM play_invites WHERE production_id = ?1").bind(p.id).all()).results;
    expect(JSON.stringify(rows)).not.toContain(a.token);
    const rec = await record(s, p.id);
    expect(rec.invites.map((i) => i.id).sort()).toEqual([a.id, b.id].sort());
    expect(JSON.stringify(rec)).not.toContain(a.token);
  });

  it("show the cast sheet and let a signed-in person claim the next part", async () => {
    const s = await person("inv-view");
    const p = await createProduction(s);
    const inv = await invite(s, p.id);
    const actor = await person("inv-actor");
    const view = await (await call("POST", "/v1/plays/invites/view", { token: actor.access_token, body: { token: inv.token } })).json();
    expect(view.parts.map((x) => x.id)).toEqual(order);
    expect(view).toMatchObject({ next: firstPart, member: false, title: script.title });
    const r = await claimByInvite(actor, inv.token, firstPart);
    expect(r.status).toBe(200);
    expect((await r.json()).parts[firstPart]).toMatchObject({ status: "recording", user_id: actor.user_id });
  });

  it("only the director makes or revokes them", async () => {
    const { director, p } = await recording("inv-dir");
    await finishFirstPart(director, p.id);
    const actor = await castMember(director, p.id, secondPart);
    expect((await call("POST", `/v1/plays/productions/${p.id}/invites`, { token: actor.access_token, body: {} })).status).toBe(403);
    const inv = await invite(director, p.id);
    expect((await call("DELETE", `/v1/plays/productions/${p.id}/invites/${inv.id}`, { token: actor.access_token })).status).toBe(403);
  });

  it("stop working when revoked", async () => {
    const s = await person("inv-rev");
    const p = await createProduction(s);
    const inv = await invite(s, p.id);
    const actor = await person("inv-rev-actor");
    const view = () => call("POST", "/v1/plays/invites/view", { token: actor.access_token, body: { token: inv.token } });
    expect((await view()).status).toBe(200);
    expect((await call("DELETE", `/v1/plays/productions/${p.id}/invites/${inv.id}`, { token: s.access_token })).status).toBe(204);
    expect((await view()).status).toBe(404);
    expect((await claimByInvite(actor, inv.token, firstPart)).status).toBe(404);
  });

  it("stop working when they expire, and last 1 to 30 days", async () => {
    const s = await person("inv-exp");
    const p = await createProduction(s);
    expect((await call("POST", `/v1/plays/productions/${p.id}/invites`, { token: s.access_token, body: { expires_in_days: 31 } })).status).toBe(400);
    const inv = await invite(s, p.id, { expires_in_days: 1 });
    expect(inv.expires_at - Date.now()).toBeGreaterThan(23 * 3600_000);
    expect(inv.expires_at - Date.now()).toBeLessThanOrEqual(24 * 3600_000);
    const actor = await person("inv-exp-actor");
    await env.DB.prepare("UPDATE play_invites SET expires_at = ?2 WHERE id = ?1").bind(inv.id, Date.now() - 1).run();
    expect((await claimByInvite(actor, inv.token, firstPart)).status).toBe(404);
    await runSweep();
    expect(await env.DB.prepare("SELECT id FROM play_invites WHERE id = ?1").bind(inv.id).first()).toBeNull();
  });

  it("a made-up token opens nothing", async () => {
    const actor = await person("inv-guess");
    const r = await call("POST", "/v1/plays/invites/view", { token: actor.access_token, body: { token: "A".repeat(43) } });
    expect(r.status).toBe(404);
  });
});

describe("the relay order (C7, pending owner: one part at a time, largest first)", () => {
  it("only the next part may be claimed", async () => {
    const s = await person("order");
    const p = await createProduction(s);
    const r = await claim(s, p.id, secondPart);
    expect(r.status).toBe(409);
    expect(await r.json()).toEqual({ error: "not_next", detail: firstPart });
    expect((await claim(s, p.id, firstPart)).status).toBe(200);
  });

  it("no part may be claimed while another records, by invite or by a member", async () => {
    const { director, p } = await recording("busy");
    const inv = await invite(director, p.id);
    const actor = await person("busy-actor");
    const r = await claimByInvite(actor, inv.token, secondPart);
    expect(r.status).toBe(409);
    expect(await r.json()).toEqual({ error: "another_part_is_recording", detail: firstPart });
    expect((await record(director, p.id)).members.map((m) => m.user_id)).toEqual([director.user_id]);
  });

  it("a speaking part is done only when every one of its lines has a take", async () => {
    const { director, p } = await recording("done");
    const lines = linesFor(firstPart);
    await seedChosen(p.id, director.user_id, lines.slice(1), firstPart);
    const r = await partAction(director, p.id, firstPart, "done");
    expect(r.status).toBe(409);
    expect(await r.json()).toMatchObject({ error: "lines_missing", detail: [lines[0]] });
    expect((await upload(director, p.id, lines[0])).status).toBe(201);
    const ok = await partAction(director, p.id, firstPart, "done");
    expect(ok.status).toBe(200);
    expect((await ok.json()).next).toBe(secondPart);
  });

  it("a speaking part cannot be left silent; sound and directions can (C6)", async () => {
    const s = await person("silent");
    const p = await createProduction(s);
    expect((await partAction(s, p.id, firstPart, "silent")).status).toBe(409);
    const quiet = order.filter((x) => !isSpeaking(x));
    expect(quiet.length).toBeGreaterThan(0);
    for (const part of order.filter(isSpeaking)) {
      await env.DB.prepare("INSERT INTO play_parts (production_id, part, status, user_id, claimed_at) VALUES (?1, ?2, 'done', ?3, ?4)")
        .bind(p.id, part, s.user_id, Date.now())
        .run();
    }
    expect((await partAction(s, p.id, quiet[0], "silent")).status).toBe(200);
  });

  it("a finished part reopens only while nothing records, and only for its performer or the director", async () => {
    const { director, p } = await recording("reopen");
    await finishFirstPart(director, p.id);
    const actor = await castMember(director, p.id, secondPart);
    expect((await partAction(director, p.id, firstPart, "reopen")).status).toBe(409);
    await seedChosen(p.id, actor.user_id, linesFor(secondPart), secondPart);
    expect((await partAction(actor, p.id, secondPart, "done")).status).toBe(200);
    const r = await partAction(actor, p.id, firstPart, "reopen");
    expect(r.status).toBe(409);
    expect((await r.json()).error).toBe("not_your_part");
    expect((await partAction(director, p.id, secondPart, "reopen")).status).toBe(200);
  });

  it("a claim lapses after seven days, and the sweep reopens the part", async () => {
    const { director, p } = await recording("lapse");
    const other = await person("lapse-other");
    const inv = await invite(director, p.id);
    await env.DB.prepare("UPDATE play_parts SET claimed_at = ?2 WHERE production_id = ?1")
      .bind(p.id, Date.now() - CLAIM_TTL_MS + 60_000)
      .run();
    expect((await claimByInvite(other, inv.token, firstPart)).status).toBe(409);
    await env.DB.prepare("UPDATE play_parts SET claimed_at = ?2 WHERE production_id = ?1").bind(p.id, Date.now() - CLAIM_TTL_MS - 1).run();
    expect((await record(director, p.id)).parts[firstPart]).toEqual({ status: "open" });
    expect((await upload(director, p.id, linesFor(firstPart)[0])).status).toBe(403);
    await runSweep();
    expect(await env.DB.prepare("SELECT 1 FROM play_parts WHERE production_id = ?1").bind(p.id).first()).toBeNull();
    expect((await claimByInvite(other, inv.token, firstPart)).status).toBe(200);
  });

  it("only the claimant releases a claim", async () => {
    const { director, p } = await recording("release");
    const other = await person("release-other");
    await env.DB.prepare("INSERT INTO play_members (production_id, user_id, joined_at) VALUES (?1, ?2, ?3)").bind(p.id, other.user_id, Date.now()).run();
    const r = await partAction(other, p.id, firstPart, "release");
    expect(r.status).toBe(409);
    expect((await r.json()).error).toBe("not_your_claim");
    expect((await partAction(director, p.id, firstPart, "release")).status).toBe(200);
    expect((await record(director, p.id)).next).toBe(firstPart);
  });
});

describe("takes", () => {
  it("are uploaded only by the part's claimant", async () => {
    const { director, p } = await recording("t-claim");
    const inv = await invite(director, p.id);
    const other = await person("t-other");
    await call("POST", "/v1/plays/invites/view", { token: other.access_token, body: { token: inv.token } });
    expect((await claimByInvite(other, inv.token, firstPart)).status).toBe(409);
    expect((await upload(director, p.id, linesFor(firstPart)[0])).status).toBe(201);
  });

  it("a member who is not the claimant cannot upload", async () => {
    const { director, p } = await recording("t-member");
    await finishFirstPart(director, p.id);
    const actor = await castMember(director, p.id, secondPart);
    const r = await upload(director, p.id, linesFor(secondPart)[0]);
    expect(r.status).toBe(403);
    expect((await upload(actor, p.id, linesFor(secondPart)[0])).status).toBe(201);
  });

  it("go only on a line of the claimed part", async () => {
    const { director, p } = await recording("t-line");
    const r = await upload(director, p.id, linesFor(secondPart)[0]);
    expect(r.status).toBe(403);
    const named = await upload(director, p.id, linesFor(secondPart)[0], { meta: { part: firstPart } });
    expect(named.status).toBe(422);
    expect((await upload(director, p.id, "no-such-line")).status).toBe(422);
  });

  it("need the CC0 consent, at the current version, first", async () => {
    const s = await person("t-consent");
    const p = await createProduction(s);
    await claim(s, p.id, firstPart);
    const r = await upload(s, p.id, linesFor(firstPart)[0]);
    expect(r.status).toBe(403);
    expect(await r.json()).toEqual({ error: "consent_required", detail: CONSENT_VERSION });
    await env.DB.prepare("INSERT INTO play_consents (user_id, production_id, version, consented_at) VALUES (?1, ?2, 'cc0-old', 1)")
      .bind(s.user_id, p.id)
      .run();
    expect((await upload(s, p.id, linesFor(firstPart)[0])).status).toBe(403);
    expect((await consent(s, p.id, "cc0-old")).status).toBe(409);
    expect((await consent(s, p.id)).status).toBe(204);
    expect((await upload(s, p.id, linesFor(firstPart)[0])).status).toBe(201);
  });

  it("are refused when the bleed check found the device voice in them", async () => {
    const { director, p } = await recording("t-bleed");
    const r = await upload(director, p.id, linesFor(firstPart)[0], { meta: { bleed: true } });
    expect(r.status).toBe(422);
    expect((await r.json()).error).toBe("bleed_flagged");
  });

  it("are measured from their own header: too long is refused, whatever the client says", async () => {
    const { director, p } = await recording("t-long");
    const rate = 8000;
    const over = (MAX_TAKE_SECONDS + 1) * rate;
    const r = await upload(director, p.id, linesFor(firstPart)[0], { bytes: wav(over, { rate, bits: 16 }), meta: { sampleRate: rate, frames: undefined } });
    expect(r.status).toBe(413);
    expect((await r.json()).error).toBe("take_too_long");
    const under = (MAX_TAKE_SECONDS - 1) * rate;
    expect((await upload(director, p.id, linesFor(firstPart)[0], { bytes: wav(under, { rate, bits: 16 }), meta: { sampleRate: rate, frames: under } })).status).toBe(201);
  });

  it("whose declared length disagrees with the audio are refused", async () => {
    const { director, p } = await recording("t-mismatch");
    const r = await upload(director, p.id, linesFor(firstPart)[0], { bytes: wav(48000), meta: { frames: 96000 } });
    expect(r.status).toBe(422);
    expect((await r.json()).detail).toBe("frames");
    const lying = wav(4800, { claim: 48000 * 3 * 200 });
    expect((await upload(director, p.id, linesFor(firstPart)[0], { bytes: lying, meta: { frames: undefined } })).status).toBe(415);
  });

  it("over the size limit are refused", async () => {
    const { director, p } = await recording("t-big");
    const r = await upload(director, p.id, linesFor(firstPart)[0], { bytes: new Uint8Array(MAX_TAKE_BYTES + 1) });
    expect(r.status).toBe(413);
    expect((await r.json()).error).toBe("too_large");
  });

  it("are mono WAV or FLAC only", async () => {
    const { director, p } = await recording("t-format");
    const line = linesFor(firstPart)[0];
    expect((await upload(director, p.id, line, { bytes: new TextEncoder().encode("not audio at all, really not") })).status).toBe(415);
    expect((await upload(director, p.id, line, { bytes: wav(48000, { channels: 2 }) })).status).toBe(415);
    const f = await upload(director, p.id, line, { bytes: flac(96000), meta: { frames: 96000 } });
    expect(f.status).toBe(201);
    expect(await f.json()).toMatchObject({ frames: 96000, sampleRate: 48000 });
    expect(readTakeAudio(flac(123456, { rate: 44100 }))).toMatchObject({ frames: 123456, sampleRate: 44100, type: "audio/flac" });
  });

  it("are immutable: a second upload with the same id is refused and the first audio stays", async () => {
    const { director, p } = await recording("t-immutable");
    const line = linesFor(firstPart)[0];
    const id = newTakeId();
    const first = wav(4800);
    expect((await upload(director, p.id, line, { id, bytes: first, meta: { frames: 4800 } })).status).toBe(201);
    const again = await upload(director, p.id, line, { id, bytes: wav(9600), meta: { frames: 9600 } });
    expect(again.status).toBe(409);
    const audio = await call("GET", `/v1/plays/productions/${p.id}/takes/${id}/audio`, { token: director.access_token });
    expect(audio.status).toBe(200);
    expect(new Uint8Array(await audio.arrayBuffer()).length).toBe(first.length);
    expect((await env.TAKES.list({ prefix: `plays/${p.id}/` })).objects.length).toBe(1);
  });

  it("the newest becomes the line's chosen take, the older stays, and the claimant can choose it back", async () => {
    const { director, p } = await recording("t-choose");
    const line = linesFor(firstPart)[0];
    const a = await upload(director, p.id, line);
    const b = await upload(director, p.id, line);
    let rec = await record(director, p.id);
    expect(rec.chosen[line]).toBe(b.takeId);
    expect(rec.takes.map((t) => t.id)).toEqual([a.takeId, b.takeId]);
    const r = await call("POST", `/v1/plays/productions/${p.id}/chosen`, { token: director.access_token, body: { take_id: a.takeId } });
    expect(r.status).toBe(200);
    rec = await r.json();
    expect(rec.chosen[line]).toBe(a.takeId);
  });

  it(`stop at ${MAX_TAKES_PER_LINE} a line`, async () => {
    const { director, p } = await recording("t-many");
    const line = linesFor(firstPart)[0];
    for (let i = 0; i < MAX_TAKES_PER_LINE; i++) expect((await upload(director, p.id, line, { bytes: wav(480), meta: { frames: 480 } })).status).toBe(201);
    const r = await upload(director, p.id, line, { bytes: wav(480), meta: { frames: 480 } });
    expect(r.status).toBe(409);
    expect((await r.json()).error).toBe("too_many_takes");
  });

  it("answer 503 when the bucket is not configured, and nothing is written", async () => {
    const { director, p } = await recording("t-nobucket");
    const r = await call("PUT", `/v1/plays/productions/${p.id}/takes/${newTakeId()}`, {
      token: director.access_token,
      body: wav(480),
      headers: { "x-take": JSON.stringify({ lineID: linesFor(firstPart)[0] }) },
      envOverride: { TAKES: undefined },
    });
    expect(r.status).toBe(503);
    expect((await record(director, p.id)).takes).toEqual([]);
  });

  it("audio is served to members only", async () => {
    const { director, p } = await recording("t-audio");
    const up = await upload(director, p.id, linesFor(firstPart)[0]);
    const stranger = await person("t-audio-stranger");
    const path = `/v1/plays/productions/${p.id}/takes/${up.takeId}/audio`;
    expect((await call("GET", path, { token: stranger.access_token })).status).toBe(404);
    const r = await call("GET", path, { token: director.access_token });
    expect(r.status).toBe(200);
    expect(r.headers.get("content-type")).toBe("audio/wav");
  });
});

describe("blocks and reports (App Store guideline 1.2)", () => {
  it("a block hides the blocked person's takes from the blocker only", async () => {
    const { director, p } = await recording("b-hide");
    await finishFirstPart(director, p.id);
    const actor = await castMember(director, p.id, secondPart);
    const up = await upload(actor, p.id, linesFor(secondPart)[0]);
    const path = `/v1/plays/productions/${p.id}/takes/${up.takeId}/audio`;
    expect((await record(director, p.id)).takes.map((t) => t.id)).toContain(up.takeId);
    expect((await call("POST", "/v1/plays/blocks", { token: director.access_token, body: { user_id: actor.user_id } })).status).toBe(204);
    const rec = await record(director, p.id);
    expect(rec.takes.map((t) => t.id)).not.toContain(up.takeId);
    expect(rec.chosen[linesFor(secondPart)[0]]).toBeUndefined();
    expect(rec.hidden_takes).toBe(1);
    expect((await call("GET", path, { token: director.access_token })).status).toBe(404);
    expect((await record(actor, p.id)).takes.map((t) => t.id)).toContain(up.takeId);
    expect((await call("GET", "/v1/plays/blocks", { token: director.access_token })).json()).resolves.toEqual({ blocked: [actor.user_id] });
    await call("DELETE", `/v1/plays/blocks/${actor.user_id}`, { token: director.access_token });
    expect((await record(director, p.id)).takes.map((t) => t.id)).toContain(up.takeId);
  });

  it("a person cannot be invited by someone they blocked, nor invite someone they blocked", async () => {
    const a = await person("b-a");
    const b = await person("b-b");
    const c = await person("b-c");
    expect((await call("POST", "/v1/plays/blocks", { token: a.access_token, body: { user_id: b.user_id } })).status).toBe(204);
    const bp = await createProduction(b);
    const bInv = await invite(b, bp.id);
    expect((await claimByInvite(a, bInv.token, firstPart)).status).toBe(404);
    const ap = await createProduction(a);
    const aInv = await invite(a, ap.id);
    expect((await call("POST", "/v1/plays/invites/view", { token: b.access_token, body: { token: aInv.token } })).status).toBe(404);
    // CONTROL: the same links work for someone with no block.
    expect((await claimByInvite(c, bInv.token, firstPart)).status).toBe(200);
    expect((await call("POST", "/v1/plays/invites/view", { token: c.access_token, body: { token: aInv.token } })).status).toBe(200);
  });

  it("blocking an account that does not exist answers the same and stores nothing", async () => {
    const a = await person("b-ghost");
    expect((await call("POST", "/v1/plays/blocks", { token: a.access_token, body: { user_id: "no-such-user" } })).status).toBe(204);
    expect((await call("POST", "/v1/plays/blocks", { token: a.access_token, body: { user_id: a.user_id } })).status).toBe(400);
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM play_blocks WHERE user_id = ?1").bind(a.user_id).first()).n).toBe(0);
  });

  it("a reported take is hidden from its reporter at once and stays for everyone else", async () => {
    const { director, p } = await recording("r-take");
    await finishFirstPart(director, p.id);
    const actor = await castMember(director, p.id, secondPart);
    const up = await upload(actor, p.id, linesFor(secondPart)[0]);
    const r = await call("POST", "/v1/plays/reports", {
      token: director.access_token,
      body: { production_id: p.id, take_id: up.takeId, reason: "offensive", note: "shouting a slur" },
    });
    expect(r.status).toBe(201);
    expect((await record(director, p.id)).takes.map((t) => t.id)).not.toContain(up.takeId);
    expect((await record(actor, p.id)).takes.map((t) => t.id)).toContain(up.takeId);
    const row = await env.DB.prepare("SELECT * FROM play_reports WHERE id = ?1").bind((await r.json()).id).first();
    expect(row).toMatchObject({ user_id: director.user_id, target_user_id: actor.user_id, take_id: up.takeId, reason: "offensive", status: "open" });
  });

  it("a member can be reported by another member, and only from inside the production", async () => {
    const { director, p } = await recording("r-member");
    await finishFirstPart(director, p.id);
    const actor = await castMember(director, p.id, secondPart);
    const stranger = await person("r-stranger");
    const body = { production_id: p.id, user_id: actor.user_id, reason: "harassment" };
    expect((await call("POST", "/v1/plays/reports", { token: stranger.access_token, body })).status).toBe(404);
    expect((await call("POST", "/v1/plays/reports", { token: director.access_token, body: { ...body, reason: "because" } })).status).toBe(400);
    expect((await call("POST", "/v1/plays/reports", { token: actor.access_token, body })).status).toBe(404);
    expect((await call("POST", "/v1/plays/reports", { token: director.access_token, body })).status).toBe(201);
  });
});

describe("display names (the deny list)", () => {
  it("refuses denied words, their look-alikes, links, and the service's own name", () => {
    for (const bad of ["fuck", "Sh1t Head", "5h!t", "F.U.C.K.", "ass", "Mr Ass", "www.example", "see https://x", "Ear Drama", "EarDrama Staff", "x".repeat(41)]) {
      expect(nameRefusal(bad), bad).not.toBeNull();
    }
  });

  it("CONTROL: passes ordinary names, including ones that contain a short denied word", () => {
    for (const ok of ["Pat", "Cassandra", "Hancock", "Dick Whittington", "Zoë", "Mrs. Malaprop", "", undefined]) {
      expect(nameRefusal(ok), ok).toBeNull();
    }
  });

  it("is enforced on every name the Worker stores", async () => {
    const s = await person("n-routes");
    expect((await call("POST", "/v1/plays/productions", { token: s.access_token, body: createBody({ display_name: "sh1t" }) })).status).toBe(422);
    const p = await createProduction(s);
    const inv = await invite(s, p.id);
    const actor = await person("n-actor");
    expect((await claimByInvite(actor, inv.token, firstPart, { display_name: "fvck you a55" })).status).toBe(422);
    expect((await call("POST", "/v1/plays/classes", { token: s.access_token, body: { name: "fuck class" } })).status).toBe(422);
    const c = await (await call("POST", "/v1/plays/classes", { token: s.access_token, body: { name: "Room 9" } })).json();
    expect((await call("POST", "/v1/plays/classes/join", { token: actor.access_token, body: { code: c.code, display_name: "Ass" } })).status).toBe(422);
    expect((await call("POST", "/v1/plays/classes/join", { token: actor.access_token, body: { code: c.code, display_name: "Pat" } })).status).toBe(200);
  });
});

describe("the CC0 consent (Decision 059)", () => {
  it("is a version id with the owner's words still a marked placeholder", async () => {
    const s = await person("c-get");
    const r = await (await call("GET", "/v1/plays/consent", { token: s.access_token })).json();
    expect(r).toEqual({ version: CONSENT_VERSION, text: CONSENT_TEXT });
    expect(CONSENT_TEXT.startsWith("OWNER:")).toBe(true);
  });

  it("is recorded per person per production, with its version", async () => {
    const { director, p } = await recording("c-row");
    const row = await env.DB.prepare("SELECT * FROM play_consents WHERE user_id = ?1 AND production_id = ?2").bind(director.user_id, p.id).first();
    expect(row).toMatchObject({ version: CONSENT_VERSION });
    expect(row.consented_at).toBeGreaterThan(0);
    const other = await createProduction(director);
    expect(await env.DB.prepare("SELECT 1 FROM play_consents WHERE user_id = ?1 AND production_id = ?2").bind(director.user_id, other.id).first()).toBeNull();
  });
});

describe("publishing: the archive.org upload, queued only", () => {
  async function complete(label) {
    const { director, p } = await recording(label);
    for (const part of order) {
      if (isSpeaking(part)) await seedChosen(p.id, director.user_id, linesFor(part), part);
      await env.DB.prepare(
        "INSERT INTO play_parts (production_id, part, status, user_id, claimed_at) VALUES (?1, ?2, ?3, ?4, ?5) ON CONFLICT (production_id, part) DO UPDATE SET status = excluded.status",
      )
        .bind(p.id, part, isSpeaking(part) ? "done" : "silent", director.user_id, Date.now())
        .run();
    }
    return { director, p };
  }

  it("queues a job whose status waits on the owner's archive.org account, and calls no one", async () => {
    const { director, p } = await complete("pub-ok");
    const before = fetchSpy.mock.calls.length;
    const r = await call("POST", `/v1/plays/productions/${p.id}/publish`, { token: director.access_token });
    expect(r.status).toBe(201);
    const job = await r.json();
    expect(job.status).toBe("pending_owner_account");
    expect(job.take_ids.length).toBe(cast.filter(([, part]) => isSpeaking(part)).length);
    expect(fetchSpy.mock.calls.length).toBe(before);
    const again = await call("POST", `/v1/plays/productions/${p.id}/publish`, { token: director.access_token });
    expect(again.status).toBe(200);
    expect((await record(director, p.id)).archive.status).toBe("pending_owner_account");
  });

  it("refuses an unfinished production", async () => {
    const { director, p } = await recording("pub-open");
    const r = await call("POST", `/v1/plays/productions/${p.id}/publish`, { token: director.access_token });
    expect(r.status).toBe(409);
    expect((await r.json()).error).toBe("incomplete");
  });

  it("is the director's alone", async () => {
    const { director, p } = await complete("pub-dir");
    const other = await person("pub-other");
    await env.DB.prepare("INSERT INTO play_members (production_id, user_id, joined_at) VALUES (?1, ?2, ?3)").bind(p.id, other.user_id, Date.now()).run();
    expect((await call("POST", `/v1/plays/productions/${p.id}/publish`, { token: other.access_token })).status).toBe(403);
  });

  it("holds back while a chosen take is reported", async () => {
    const { director, p } = await complete("pub-rep");
    const take = await env.DB.prepare("SELECT id FROM play_takes WHERE production_id = ?1 AND chosen = 1 LIMIT 1").bind(p.id).first();
    expect((await call("POST", "/v1/plays/reports", { token: director.access_token, body: { production_id: p.id, take_id: take.id, reason: "other" } })).status).toBe(201);
    const r = await call("POST", `/v1/plays/productions/${p.id}/publish`, { token: director.access_token });
    expect(r.status).toBe(409);
    expect(await r.json()).toEqual({ error: "reported_take", detail: [take.id] });
  });

  it("needs every performer's consent at the current version", async () => {
    const { director, p } = await complete("pub-consent");
    await env.DB.prepare("UPDATE play_consents SET version = 'cc0-old' WHERE production_id = ?1").bind(p.id).run();
    const r = await call("POST", `/v1/plays/productions/${p.id}/publish`, { token: director.access_token });
    expect(r.status).toBe(409);
    expect(await r.json()).toEqual({ error: "consent_missing", detail: [director.user_id] });
  });
});

describe("teacher classes (Decision 059)", () => {
  it("a teacher makes a class and a student joins by its code, typed loosely", async () => {
    const t = await person("cl-teacher");
    const s = await person("cl-student");
    const c = await (await call("POST", "/v1/plays/classes", { token: t.access_token, body: { name: "Year 7 Drama" } })).json();
    // Eight characters is 40 bits: guessing one of 10,000 classes at 20 joins a minute takes years.
    expect(c.code).toMatch(/^[0-9A-HJKMNP-TV-Z]{8}$/);
    const typed = `${c.code.slice(0, 4).toLowerCase()}-${c.code.slice(4)}`.replace(/0/g, "o").replace(/1/g, "l");
    expect(normalizeClassCode(typed)).toBe(c.code);
    expect((await call("POST", "/v1/plays/classes/join", { token: s.access_token, body: { code: typed, display_name: "Sam" } })).status).toBe(200);
    const roster = await (await call("GET", `/v1/plays/classes/${c.id}`, { token: t.access_token })).json();
    expect(roster.members.map((m) => [m.user_id, m.display_name])).toEqual([[s.user_id, "Sam"]]);
    const seen = await (await call("GET", `/v1/plays/classes/${c.id}`, { token: s.access_token })).json();
    expect(seen).toEqual({ id: c.id, name: "Year 7 Drama", under13: false });
    const outsider = await person("cl-outsider");
    expect((await call("GET", `/v1/plays/classes/${c.id}`, { token: outsider.access_token })).status).toBe(404);
    const mine = await (await call("GET", "/v1/plays/classes", { token: s.access_token })).json();
    expect(mine.member_of.map((x) => x.id)).toEqual([c.id]);
    expect((await call("DELETE", `/v1/plays/classes/${c.id}/members/${s.user_id}`, { token: t.access_token })).status).toBe(204);
    expect((await call("GET", `/v1/plays/classes/${c.id}`, { token: s.access_token })).status).toBe(404);
  });

  it("an under-13 class takes no student until the school's consent is recorded", async () => {
    const t = await person("u13-teacher");
    const s = await person("u13-student");
    const c = await (await call("POST", "/v1/plays/classes", { token: t.access_token, body: { name: "Grade 5", under13: true } })).json();
    const join = () => call("POST", "/v1/plays/classes/join", { token: s.access_token, body: { code: c.code } });
    const refused = await join();
    expect(refused.status).toBe(403);
    expect((await refused.json()).error).toBe("school_consent_required");
    const policy = { SCHOOL_CONSENT_POLICY: "privacy-test-1" };
    expect((await call("POST", `/v1/plays/classes/${c.id}/school-consent`, { token: s.access_token, body: {}, envOverride: policy })).status).toBe(403);
    const r = await call("POST", `/v1/plays/classes/${c.id}/school-consent`, { token: t.access_token, body: { reference: "Letter 2026-10" }, envOverride: policy });
    expect(r.status).toBe(201);
    expect(await r.json()).toMatchObject({ policy_version: "privacy-test-1" });
    expect((await join()).status).toBe(200);
  });

  it("no school consent can be recorded until the owner's privacy policy names its version", async () => {
    const t = await person("u13-nopolicy");
    const c = await (await call("POST", "/v1/plays/classes", { token: t.access_token, body: { name: "Grade 4", under13: true } })).json();
    const r = await call("POST", `/v1/plays/classes/${c.id}/school-consent`, { token: t.access_token, body: {} });
    expect(r.status).toBe(503);
    expect((await r.json()).error).toBe("pending_owner_policy");
  });

  it("CONTROL: a class not marked under 13 needs no school consent; the flag must be a boolean", async () => {
    const t = await person("o13-teacher");
    const s = await person("o13-student");
    expect((await call("POST", "/v1/plays/classes", { token: t.access_token, body: { name: "Seniors", under13: "no" } })).status).toBe(400);
    const c = await (await call("POST", "/v1/plays/classes", { token: t.access_token, body: { name: "Seniors" } })).json();
    expect((await call("POST", "/v1/plays/classes/join", { token: s.access_token, body: { code: c.code } })).status).toBe(200);
    expect((await call("POST", "/v1/plays/classes/join", { token: t.access_token, body: { code: c.code } })).status).toBe(409);
    expect((await call("POST", "/v1/plays/classes/join", { token: s.access_token, body: { code: "ZZZZZZZZ" } })).status).toBe(404);
  });
});

describe("rate limits", () => {
  const deny = { limit: async () => ({ success: false }) };

  it("take uploads are limited per person", async () => {
    const { director, p } = await recording("rl-up");
    const r = await call("PUT", `/v1/plays/productions/${p.id}/takes/${newTakeId()}`, {
      token: director.access_token,
      body: wav(480),
      headers: { "x-take": JSON.stringify({ lineID: linesFor(firstPart)[0] }) },
      envOverride: { PLAY_UPLOAD_LIMITER: deny },
    });
    expect(r.status).toBe(429);
  });

  it("invite views and claims and class joins are limited per person", async () => {
    const s = await person("rl-join");
    for (const [path, body] of [["/v1/plays/invites/view", { token: "x" }], ["/v1/plays/invites/claim", { token: "x" }], ["/v1/plays/classes/join", { code: "x" }]]) {
      const r = await call("POST", path, { token: s.access_token, body, envOverride: { PLAY_JOIN_LIMITER: deny } });
      expect(r.status, path).toBe(429);
    }
  });
});

describe("the relay is pure", () => {
  it("imports nothing", () => {
    expect(relaySource).not.toMatch(/^\s*import\s/m);
  });
});
