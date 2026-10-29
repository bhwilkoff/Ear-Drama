// Negative controls for the suite: each mutation breaks one guarantee in
// src/, and the suite must go red for every one. A check that never fails
// proves nothing (docs/ENGINEERING-PROCESS.md). Run: npm run test:mutations
// The file is restored after each run, even when the run throws.
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const M = [
  ["no audience check", "src/jwt.js", 'if (!audienceMatches(payload.aud, audiences)) throw new TokenError("bad_audience");', ""],
  ["no signature check", "src/jwt.js", 'if (!ok) throw new TokenError("bad_signature");\n  if (!rules', "if (!rules"],
  ["no expiry check", "src/jwt.js", 'if (payload.exp + LEEWAY < nowSec) throw new TokenError("expired");', ""],
  ["alg not pinned", "src/jwt.js", 'if (header.alg !== "RS256") throw new TokenError("bad_alg");', ""],
  ["no issuer check", "src/jwt.js", 'if (!rules.issuers.includes(payload.iss)) throw new TokenError("bad_issuer");', ""],
  ["deletion skips users", "src/account.js", '    env.DB.prepare("DELETE FROM users WHERE id = ?1").bind(userId),\n', ""],
  ["deletion skips history", "src/account.js", '  "history",\n', ""],
  ["CORS allows all", "src/http.js", "if (!origin) return true; // native", "return true; // native"],
  [
    "LWW ignores stamps",
    "src/sync.js",
    "WHERE excluded.updated_at > history.updated_at\n   OR (excluded.updated_at = history.updated_at AND excluded.device > history.device)",
    "",
  ],
  ["merge replaces queue", "src/index.js", "handleUpload(a, request, env, { merge: true })", "handleUpload(a, request, env)"],
  ["no session row check", "src/auth.js", 'if (!s) return { error: problem(401, "unauthorized", "session_ended") };', ""],
  // Listen Together rooms (M6)
  ["guest can set state", "src/rooms.js", 'if (!isHost) return problem(403, "host_only", "only the host changes what plays");', ""],
  ["guest can end room", "src/rooms.js", 'if (!isHost) return problem(403, "host_only");', ""],
  ["any key is a member", "src/rooms.js", "return members.find((m) => m.key_hash === hash) || null;", "return members[0] || null;"],
  ["no handoff on leave", "src/rooms.js", "      host = nextHost(live, me.id, now);\n", "      host = null;\n"],
  ["no handoff when quiet", "src/rooms.js", "    host = nextHost(live, host, now);\n", "    host = null;\n"],
  ["handoff to newest", "src/room-protocol.js", "a.joined_at - b.joined_at ||", "b.joined_at - a.joined_at ||"],
  ["quiet members count", "src/room-protocol.js", "return members.filter((m) => now - m.seen_at <= MEMBER_GONE_MS);", "return members;"],
  ["guests miss the copy", "src/room-protocol.js", "    archive_id: s.archive_id,\n    file: s.file,\n    position: s.position,", "    position: s.position,"],
  ["new episode keeps old copy", "src/room-protocol.js", 'return { error: "a new episode needs its archive_id and file" };', ""],
  ["copy path escape", "src/room-protocol.js", 'part === ".." || ', ""],
  ["client sets the clock", "src/room-protocol.js", "  next.updated_at = now;\n", "  next.updated_at = input.updated_at ?? now;\n"],
  ["no idle expiry", "src/room-protocol.js", "return now - room.touched_at > ROOM_IDLE_MS;", "return false;"],
  ["no size limit", "src/rooms.js", 'if (settled.live.length >= MAX_MEMBERS) return problem(409, "room_full");', ""],
  ["cron skips rooms", "src/index.js", "Promise.all([sweepSessions(env), sweepRooms(env), ", "Promise.all([sweepSessions(env), "],
  ["sweep keeps empty rooms", "src/rooms.js", "touched_at < ?1 OR code NOT IN (SELECT code FROM room_members)", "touched_at < ?1"],
  ["four-character codes", "src/room-protocol.js", "export const CODE_LENGTH = 6;", "export const CODE_LENGTH = 4;"],
  ["predictable codes", "src/rooms.js", "  crypto.getRandomValues(bytes);\n  return codeFromBytes(bytes);", "  return codeFromBytes(bytes);"],
  ["no join limit", "src/rooms.js", 'if (await limited(env.ROOM_JOIN_LIMITER, ip)) return problem(429, "rate_limited");', ""],
  ["no create limit", "src/rooms.js", 'if (await limited(env.ROOM_CREATE_LIMITER, ip)) return problem(429, "rate_limited");', ""],
  ["member limit by address", "src/rooms.js", "limited(env.ROOM_MEMBER_LIMITER, me.id)", "limited(env.ROOM_MEMBER_LIMITER, ip)"],
  ["no room floor", "src/index.js", 'if (await limited(env.ROOM_LIMITER, ip)) return problem(429, "rate_limited");', ""],
  ["drift seeks small offsets", "src/room-protocol.js", "seekAbove: 2,", "seekAbove: 0.5,"],
  ["drift ignores pause", "src/room-protocol.js", 'if (player.playing) return { action: "pause", position: target };', ""],
  ["clock averages samples", "src/room-protocol.js", "if (!best || rtt < best.rtt)", "if (!best || rtt > best.rtt)"],
  // Shared plays (M8)
  ["plays need no account", "src/index.js", "    const auth = await authenticate(request, env);\n    if (auth.error) return auth.error;\n    if (await limited(env.USER_LIMITER, auth.userId)) return problem(429, \"rate_limited\");\n    return handlePlays", "    const auth = { userId: \"anon\" };\n    return handlePlays"],
  ["deletion skips play_takes", "src/account.js", '  "play_takes",\n', ""],
  ["deletion skips classes", "src/account.js", '  "play_classes",\n', ""],
  ["deletion skips the blocked side", "src/account.js", '  ["play_blocks", "blocked_id", "delete"],\n', ""],
  ["deletion keeps take audio", "src/account.js", "  const orphans = await playsBeforeDeletion(env, userId);", "  const orphans = [];"],
  ["failed object deletion forgotten", "src/plays.js", "    } catch {\n      failed.push(...chunk);\n    }", "    } catch {}"],
  ["sweep skips orphans", "src/plays.js", "  const failed = new Set(await deleteObjects(env, keys));", "  const failed = new Set(keys);"],
  ["director deletion drops the cast", "src/plays.js", "WHERE user_id = ?1 AND EXISTS (SELECT 1 FROM play_members m WHERE m.production_id = play_productions.id AND m.user_id <> ?1)", "WHERE 0"],
  ["any script is castable", "src/plays.js", '  if (!entry) return problem(422, "not_castable");\n', ""],
  ["any revision is castable", "src/plays.js", '  if (body.script_revision !== entry.revision) return problem(409, "revision_mismatch", entry.revision);\n', ""],
  ["cast sheet trusted", "src/plays.js", '  if ((await castHash(cast)) !== entry.cast) return problem(422, "cast_mismatch");\n', ""],
  ["manifest drifts", "src/castable-manifest.json", '"format": 1,', '"format": 2,'],
  ["non-members read productions", "src/plays.js", "if (!p || !(await member(env, p.id, auth.userId))) return problem(404, \"not_found\");", "if (!p) return problem(404, \"not_found\");"],
  ["invite tokens stored raw", "src/plays.js", "    .bind(id, p.id, auth.userId, await sha256Hex(token), now, expires)", "    .bind(id, p.id, auth.userId, token, now, expires)"],
  ["short invite tokens", "src/plays.js", "  const token = randomToken(32);", "  const token = randomToken(16);"],
  ["invites never expire", "src/plays.js", "if (!inv || inv.revoked || inv.expires_at <= now) return null;", "if (!inv || inv.revoked) return null;"],
  ["revoked invites work", "src/plays.js", "if (!inv || inv.revoked || inv.expires_at <= now) return null;", "if (!inv || inv.expires_at <= now) return null;"],
  ["anyone makes invites", "src/plays.js", "async function createInvite(auth, request, env, p, now) {\n  if (p.user_id !== auth.userId) return problem(403, \"director_only\");", "async function createInvite(auth, request, env, p, now) {"],
  ["invites last forever", "src/plays.js", "days < 1 || days > INVITE_MAX_DAYS", "days < 1"],
  ["claims a part that is not open", "src/plays-relay.js", '  if (statusOf(rows, part, now) !== "open") return { error: "not_open" };\n', ""],
  ["two parts record at once", "src/plays-relay.js", '  if (cur) return { error: "another_part_is_recording", detail: cur };\n  if (statusOf(rows, part, now) !== "open")', '  if (statusOf(rows, part, now) !== "open")'],
  ["claims never lapse", "src/plays-relay.js", '  if (r.status === "recording" && now - r.claimed_at > CLAIM_TTL_MS) return "open";\n', ""],
  ["cron skips plays", "src/index.js", "sweepRooms(env), sweepPlays(env)]", "sweepRooms(env)]"],
  ["done with lines missing", "src/plays-relay.js", '    if (missing.length) return { error: "lines_missing", detail: missing.slice(0, 50) };\n', ""],
  ["speaking part left silent", "src/plays-relay.js", '  if (isSpeaking(part)) return { error: "speaking_part_needs_a_voice" };\n', ""],
  ["reopen while recording", "src/plays-relay.js", 'export function reopenRefusal(cast, rows, part, userId, directorId, now) {\n  const cur = current(cast, rows, now);\n  if (cur) return { error: "another_part_is_recording", detail: cur };', "export function reopenRefusal(cast, rows, part, userId, directorId, now) {"],
  ["anyone reopens", "src/plays-relay.js", '  if (rows[part].user_id !== userId && directorId !== userId) return { error: "not_your_part" };\n', ""],
  ["anyone releases", "src/plays.js", 'refusal = isClaimant(rows, part, auth.userId, now) ? null : { error: "not_your_claim" };', "refusal = null;"],
  ["non-claimant uploads", "src/plays.js", '  if (!isClaimant(await partRows(env, p.id), part, auth.userId, now)) return problem(403, "not_your_claim");\n  // No CC0', "  // No CC0"],
  ["take on a line of its own choosing", "src/plays.js", '  if (meta.part !== undefined && meta.part !== part) return problem(422, "line_is_another_part", part);\n', ""],
  [
    "upload demands the CC0 consent",
    "src/plays.js",
    "  // A take the bleed check flagged holds the device voice",
    '  if (!(await env.DB.prepare("SELECT 1 FROM play_consents WHERE user_id = ?1 AND production_id = ?2").bind(auth.userId, p.id).first())) return problem(403, "consent_required");\n  // A take the bleed check flagged holds the device voice',
  ],
  ["stale consent accepted", "src/plays.js", '  if (body.version !== CONSENT_VERSION) return problem(409, "consent_version_mismatch", CONSENT_VERSION);\n', ""],
  ["bleed take stored", "src/plays.js", '  if (meta.bleed === true) return problem(422, "bleed_flagged");\n', ""],
  ["no take size limit", "src/plays.js", '  if (bytes.length > MAX_TAKE_BYTES) return problem(413, "too_large");\n', ""],
  ["no take duration limit", "src/plays.js", '  if (audio.frames / audio.sampleRate > MAX_TAKE_SECONDS) return problem(413, "take_too_long", `${MAX_TAKE_SECONDS} s`);\n', ""],
  ["declared length trusted", "src/plays.js", '    return problem(422, "audio_mismatch", "frames");', '    meta.frames = audio.frames;'],
  ["header length trusted", "src/plays-audio.js", "      if (body + size > b.length) return null; // the header claims more audio than was sent\n", ""],
  ["stereo accepted", "src/plays-audio.js", "fmt.channels !== 1 || ", ""],
  ["takes overwritten", "src/plays.js", "  if (!ins.meta.changes) {\n    await env.TAKES.delete(key);\n    return problem(409, \"take_exists\");\n  }\n", ""],
  ["class list hides school consent", "src/plays.js", "school_consent: !!policy_version", "school_consent: false"],
  ["uploads always open", "src/plays.js", "    uploads: !!env.TAKES,\n", "    uploads: true,\n"],
  ["placeholder consent counts", "src/plays.js", ' && !CONSENT_TEXTS[version].startsWith("OWNER:")', ""],
  ["publish switch always on", "src/plays.js", "publishes: !!env.IA_ACCESS", "publishes: true"],
  ["consent hides the switch", "src/plays.js", "text: CONSENT_TEXT, uploads: !!env.TAKES,", "text: CONSENT_TEXT, uploads: true,"],
  ["unbounded takes a line", "src/plays.js", '  if (count.n >= MAX_TAKES_PER_LINE) return problem(409, "too_many_takes");\n', ""],
  ["new take not chosen", "src/plays.js", "  await env.DB.batch([...chooseStatements(env, p.id, meta.lineID, takeId), touch(env, p.id, now)]);", "  await env.DB.batch([touch(env, p.id, now)]);"],
  ["no upload limit", "src/plays.js", 'if (await limited(env.PLAY_UPLOAD_LIMITER, auth.userId)) return problem(429, "rate_limited");', ""],
  ["no join limit on claims", "src/plays.js", 'async function claimByInvite(auth, request, env, now) {\n  if (await limited(env.PLAY_JOIN_LIMITER, auth.userId)) return problem(429, "rate_limited");', "async function claimByInvite(auth, request, env, now) {"],
  ["blocked takes shown", "src/plays.js", "  return (t) => blocked.has(t.user_id) || reported.has(t.id);", "  return (t) => reported.has(t.id);"],
  ["reported takes shown", "src/plays.js", "  return (t) => blocked.has(t.user_id) || reported.has(t.id);", "  return (t) => blocked.has(t.user_id);"],
  ["blocked person invited", "src/plays.js", "  if (blocked.has(inv.user_id) || blockedBy.has(inv.user_id)) return null;\n", ""],
  ["blocker invites blocked", "src/plays.js", "blocked.has(inv.user_id) || blockedBy.has(inv.user_id)", "blocked.has(inv.user_id)"],
  ["outsiders report", "src/plays.js", 'if (typeof body.production_id !== "string" || !(await member(env, body.production_id, auth.userId))) {', 'if (typeof body.production_id !== "string") {'],
  ["name filter off", "src/plays-names.js", '  if (STRONG.some((t) => squashed.includes(t))) return "name_not_allowed";\n', ""],
  ["look-alikes pass", "src/plays-names.js", "  return [...plain].map((c) => LOOK_ALIKE[c] || c).join(\"\");", "  return plain;"],
  ["filter skips claims", "src/plays.js", "  const p = await redeem(env, body.token, auth.userId, now);\n  if (!p) return problem(404, \"invite_not_found\");\n  const refusal = nameRefusal(body.display_name);\n  if (refusal) return problem(422, refusal);", "  const p = await redeem(env, body.token, auth.userId, now);\n  if (!p) return problem(404, \"invite_not_found\");"],
  ["publish incomplete", "src/plays.js", '  if (left) return problem(409, "incomplete", left);\n', ""],
  ["publish with a reported take", "src/plays.js", '  if (held.length) return problem(409, "reported_take", held);\n', ""],
  ["publish without the archive account", "src/plays.js", '  if (!env.IA_ACCESS) return problem(503, "publishing_unavailable");\n', ""],
  ["members hide who agreed", "src/plays.js", "consented: consented.has(m.user_id),", "consented: false,"],
  ["publish without consent", "src/plays.js", '  if (missing.length) return problem(409, "consent_missing", missing);\n', ""],
  ["anyone publishes", "src/plays.js", "async function publish(auth, env, p, now) {\n  if (p.user_id !== auth.userId) return problem(403, \"director_only\");", "async function publish(auth, env, p, now) {"],
  ["job claims to have run", "src/plays.js", "VALUES (?1, ?2, 'pending_owner_account', ?3, ?4, ?4)", "VALUES (?1, ?2, 'queued', ?3, ?4, ?4)"],
  ["under-13 join without consent", "src/plays.js", '  if (c.under13 && !c.consent) return problem(403, "school_consent_required");\n', ""],
  ["consent without the policy", "src/plays.js", '  if (!env.SCHOOL_CONSENT_POLICY) return problem(503, "pending_owner_policy");\n', ""],
  ["students record school consent", "src/plays.js", '  if (c.user_id !== auth.userId) return problem(403, "teacher_only");\n', ""],
  ["students see the roster", "src/plays.js", "  if (c.user_id === auth.userId) {\n    const { results }", "  if (true) {\n    const { results }"],
  ["short class codes", "src/plays.js", "export const CLASS_CODE_LENGTH = 8;", "export const CLASS_CODE_LENGTH = 4;"],
];

// --check: confirm every mutation still matches its file exactly once, and run nothing.
if (process.argv.includes("--check")) {
  for (const [name, file, from] of M) {
    const n = readFileSync(root + file, "utf8").split(from).length - 1;
    if (n !== 1) throw new Error(`mutation "${name}" matches ${file} ${n} times`);
  }
  console.log(`all ${M.length} mutations match`);
  process.exit(0);
}

// --only "name,name": run just those (after fixing a survivor); the full run is the gate.
const at = process.argv.indexOf("--only");
const only = at > 0 ? process.argv[at + 1].split(",") : null;
const run = only ? M.filter(([name]) => only.includes(name)) : M;

let survivors = 0;
for (const [name, file, from, to] of run) {
  const path = root + file;
  const src = readFileSync(path, "utf8");
  if (src.split(from).length !== 2) throw new Error(`mutation "${name}" no longer matches ${file} exactly once`);
  writeFileSync(path, src.replace(from, to));
  let red = false;
  try {
    execFileSync("npx", ["vitest", "run"], { cwd: root, stdio: "pipe" });
  } catch {
    red = true;
  } finally {
    writeFileSync(path, src);
  }
  console.log(`${red ? "CAUGHT  " : "SURVIVED"} ${name}`);
  if (!red) survivors++;
}
console.log(survivors ? `${survivors} mutation(s) survived` : `all ${run.length} mutations caught`);
process.exit(survivors ? 1 : 0);
