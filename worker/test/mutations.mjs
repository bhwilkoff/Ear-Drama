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
  ["director deletion drops the cast", "src/plays.js", "WHERE user_id = ?1 AND EXISTS (SELECT 1 FROM play_members m WHERE m.production_id = play_productions.id AND m.user_id <> ?1)", "WHERE 0"],
  // A submitted production outlives its members' deletions (owner, 2026-10-29)
  ["submitted takes deleted with their performer", "src/plays.js", "UPDATE play_takes SET user_id = ?2 WHERE user_id = ?1 AND production_id IN (${submitted})", "UPDATE play_takes SET user_id = ?2 WHERE 0"],
  ["submitted parts deleted with their performer", "src/plays.js", "UPDATE play_parts SET user_id = ?2 WHERE user_id = ?1 AND production_id IN (${submitted})", "UPDATE play_parts SET user_id = ?2 WHERE 0"],
  ["submitted production passes to a member", "src/plays.js", "UPDATE play_productions SET user_id = ?2 WHERE user_id = ?1 AND id IN (${submitted})", "UPDATE play_productions SET user_id = ?2 WHERE 0"],
  ["submitted job deleted with its director", "src/plays.js", 'env.DB.prepare("UPDATE play_archive_jobs SET user_id = ?2 WHERE user_id = ?1").bind(userId, DELETED_PERSON),', ""],
  ["deleted person row never made", "src/plays.js", 'env.DB.prepare("INSERT OR IGNORE INTO users (id, created_at) VALUES (?2, 0)").bind(userId, DELETED_PERSON),', ""],
  ["item credits keep the deleted name", "src/plays.js", "\"UPDATE play_archive_jobs SET credits = NULL WHERE status = 'published' AND production_id IN (SELECT production_id FROM play_takes WHERE user_id = ?1)\",", "\"UPDATE play_archive_jobs SET credits = credits WHERE 0\","],
  ["every production counts as submitted", "src/plays.js", 'const submitted = "SELECT production_id FROM play_archive_jobs";', 'const submitted = "SELECT id FROM play_productions";'],
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
  ["cron skips plays", "src/index.js", "sweepReadRooms(env), sweepPlays(env), ", "sweepReadRooms(env), "],
  ["done with lines missing", "src/plays-relay.js", '    if (missing.length) return { error: "lines_missing", detail: missing.slice(0, 50) };\n', ""],
  ["speaking part left silent", "src/plays-relay.js", '  if (isSpeaking(part)) return { error: "speaking_part_needs_a_voice" };\n', ""],
  ["reopen while recording", "src/plays-relay.js", 'export function reopenRefusal(cast, rows, part, userId, directorId, now) {\n  const cur = current(cast, rows, now);\n  if (cur) return { error: "another_part_is_recording", detail: cur };', "export function reopenRefusal(cast, rows, part, userId, directorId, now) {"],
  ["anyone reopens", "src/plays-relay.js", '  if (rows[part].user_id !== userId && directorId !== userId) return { error: "not_your_part" };\n', ""],
  ["anyone releases", "src/plays.js", 'refusal = isClaimant(rows, part, auth.userId, now) ? null : { error: "not_your_claim" };', "refusal = null;"],
  ["non-claimant uploads", "src/plays.js", '  } else if (!isClaimant(await partRows(env, p.id), part, auth.userId, now)) return problem(403, "not_your_claim");', "  }"],
  ["take on a line of its own choosing", "src/plays.js", '  if (meta.part !== undefined && meta.part !== part) return problem(422, "line_is_another_part", part);\n', ""],
  [
    "upload demands the CC0 consent",
    "src/plays.js",
    "  // No CC0 consent here (Decision 072)",
    '  if (!(await env.DB.prepare("SELECT 1 FROM play_consents WHERE user_id = ?1 AND production_id = ?2").bind(auth.userId, p.id).first())) return problem(403, "consent_required");\n  // No CC0 consent here (Decision 072)',
  ],
  ["stale consent accepted", "src/plays.js", '  if (body.version !== CONSENT_VERSION) return problem(409, "consent_version_mismatch", CONSENT_VERSION);\n', ""],
  ["bleed take stored", "src/plays.js", '  if (meta.bleed === true) return problem(422, "bleed_flagged");\n', ""],
  ["no take size limit", "src/plays-audio.js", '  if (length > MAX_TAKE_BYTES) return { error: [413, "too_large"] };\n', ""],
  ["no take duration limit", "src/plays-audio.js", '  if (audio.frames / audio.sampleRate > MAX_TAKE_SECONDS) return { error: [413, "take_too_long", `${MAX_TAKE_SECONDS} s`] };\n', ""],
  ["declared length trusted", "src/plays.js", '    return { error: problem(422, "audio_mismatch", "frames") };', '    meta.frames = audio.frames;'],
  ["t5: a room's bleed take relayed", "src/plays.js", '  if (meta.bleed) return problem(422, "bleed_flagged");\n', ""],
  ["header length trusted", "src/plays-audio.js", "      if (body + size > total) return null; // the header claims more audio than was sent\n", ""],
  ["stereo accepted", "src/plays-audio.js", "fmt.channels !== 1 || ", ""],
  ["class list hides school consent", "src/plays.js", "school_consent: !!policy_version", "school_consent: false"],
  ["uploads always open", "src/plays.js", "    uploads: !!env.TAKE_RELAY,\n", "    uploads: true,\n"],
  ["placeholder consent counts", "src/plays.js", ' && !CONSENT_TEXTS[version].startsWith("OWNER:")', ""],
  ["publish switch always on", "src/plays.js", "publishes: iaConfigured(env)", "publishes: true"],
  ["one archive key is enough", "src/plays-archive.js", "!!(env.IA_S3_ACCESS_KEY && env.IA_S3_SECRET_KEY)", "!!(env.IA_S3_ACCESS_KEY || env.IA_S3_SECRET_KEY)"],
  ["consent hides the switch", "src/plays.js", "text: CONSENT_TEXT, uploads: !!env.TAKE_RELAY,", "text: CONSENT_TEXT, uploads: true,"],
  ["unbounded takes a line", "src/plays.js", '  if (count.n >= MAX_TAKES_PER_LINE) return problem(409, "too_many_takes");\n', ""],
  ["new take not chosen", "src/plays.js", "  const stmts = [...chooseStatements(env, p.id, meta.lineID, takeId), touch(env, p.id, now)];", "  const stmts = [touch(env, p.id, now)];"],
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
  ["publish without the archive account", "src/plays.js", '  if (!iaConfigured(env)) return problem(503, "publishing_unavailable");\n', ""],
  ["members hide who agreed", "src/plays.js", "consented: consented.has(m.user_id),", "consented: false,"],
  ["publish without consent", "src/plays.js", 'if (missing.length || credits.length) return json({ error: "consent_missing", detail: missing, ...(credits.length ? { credits } : {}) }, 409);\n', ""],
  ["anyone publishes", "src/plays.js", "async function publish(auth, request, env, p, now) {\n  if (p.user_id !== auth.userId) return problem(403, \"director_only\");", "async function publish(auth, request, env, p, now) {"],
  ["job claims to have run", "src/plays.js", "VALUES (?1, ?2, 'queued', ?3, ?4, ?4, ?5, ?5)", "VALUES (?1, ?2, 'published', ?3, ?4, ?4, ?5, ?5)"],
  ["under-13 join without consent", "src/plays.js", '  if (c.under13 && !c.consent) return problem(403, "school_consent_required");\n', ""],
  ["consent without the policy", "src/plays.js", '  if (!env.SCHOOL_CONSENT_POLICY) return problem(503, "pending_owner_policy");\n', ""],
  ["students record school consent", "src/plays.js", '  if (c.user_id !== auth.userId) return problem(403, "teacher_only");\n', ""],
  ["students see the roster", "src/plays.js", "  if (c.user_id === auth.userId) {\n    await touchClass", "  if (true) {\n    await touchClass"],
  // The archive.org uploader (P14) and published takes (P12)
  ["uploader never runs", "src/index.js", "Promise.all([sweepSessions(env), sweepRooms(env), sweepReadRooms(env), sweepPlays(env), sweepTakedowns(env), sweepRetention(env), runArchive(env)])", "Promise.all([sweepSessions(env), sweepRooms(env), sweepReadRooms(env), sweepPlays(env), sweepTakedowns(env), sweepRetention(env)])"],
  ["five-minute trigger idle", "src/index.js", "if (event.cron === ARCHIVE_CRON) return ctx.waitUntil(runArchive(env));", "if (event.cron === ARCHIVE_CRON) return;"],
  ["sent lines sent again", "src/plays-archive.js", '  if (f.state !== "pending") return problem(409, "already_sent", f.state);\n', ""],
  ["republish resends", "src/plays-archive.js", "THEN 'sent' ELSE 'pending' END", "THEN 'pending' ELSE 'pending' END"],
  ["no lease", "src/plays-archive.js", "    if (!lease.meta.changes) continue;\n", ""],
  ["no backoff", "src/plays-archive.js", "next_attempt_at: now + backoff(attempts)", "next_attempt_at: now"],
  ["retries forever", "src/plays-archive.js", "if (attempts < MAX_ATTEMPTS) {", "if (true) {"],
  ["503 is final", "src/plays-archive.js", "transient: r.status === 429 || r.status >= 500", "transient: r.status === 429"],
  ["refusals retried", "src/plays-archive.js", "transient: r.status === 429 || r.status >= 500", "transient: true"],
  ["no check_limit", "src/plays-archive.js", "    const limit = await overLimit(env, identifier);\n", "    const limit = null;\n"],
  ["anyone sends a line's file", "src/plays-archive.js", '  if (p.user_id !== userId && f.user_id !== userId) return problem(403, "not_your_take");\n', ""],
  ["any recording sent as the take", "src/plays-archive.js", "  if (a.type !== f.content_type || a.sampleRate !== f.sample_rate || Math.abs(a.frames - f.frames) > a.sampleRate * 0.05) {", "  if (false) {"],
  ["reported file sent", "src/plays-archive.js", '  if (reported) return problem(409, "reported_take", [f.take_id]);\n', ""],
  ["no request budget", "src/plays-archive.js", "    if (budget.left <= 0) break;\n    if (f.state === \"remove\") {", "    if (f.state === \"remove\") {"],
  ["preflight size skipped", "src/plays-archive.js", '  if (total > MAX_ITEM_BYTES || results.some((t) => t.bytes > MAX_TAKE_BYTES)) return "too_large";\n', ""],
  ["keys in reasons", "src/plays-archive.js", "  for (const k of [env.IA_S3_ACCESS_KEY, env.IA_S3_SECRET_KEY]) if (k) s = s.split(k).join(\"[redacted]\");\n", ""],
  ["derives every file", "src/plays-archive.js", '    if (others.pending) extra["x-archive-queue-derive"] = "0";\n', ""],
  ["no item metadata", "src/plays-archive.js", '{ "x-archive-auto-make-bucket": "1", ...metaHeaders(itemMeta(script, await creditsFor(env, p, p.cast), job.created_at)) }', '{ "x-archive-auto-make-bucket": "1" }'],
  ["names sent raw", "src/plays-archive.js", "  return /^[\\x21-\\x7e](?:[\\x20-\\x7e]*[\\x21-\\x7e])?$/.test(s) ? s : `uri(${encodeURIComponent(s)})`;", "  return s;"],
  ["held reports sent", "src/plays-archive.js", '  const sendable = files.filter((f) => f.state === "remove" || !reported.has(f.take_id));', "  const sendable = files;"],
  ["removed credit stays", "src/plays-archive.js", "  if (job.credits !== creditText) {", "  if (false) {"],
  ["delete 404 is an error", "src/plays-archive.js", "      if (r.ok || r.status === 404) {", "      if (r.ok) {"],
  ["stale format kept", "src/plays-archive.js", "  if (f.stale_name) {", "  if (false) {"],
  ["anyone replaces", "src/plays.js", '  if (f.user_id !== userId) return problem(403, "not_your_take");\n', ""],
  ["replace without consent", "src/plays.js", '  if (!agreed || !consentApproved(agreed.version)) return problem(409, "consent_missing", [userId]);\n', ""],
  ["performer undoes the director", "src/plays.js", '  if (f.removed_by === "director") return problem(409, "removed_by_director");\n', ""],
  ["anyone removes", "src/plays.js", '  if (!performer && p.user_id !== auth.userId) return problem(403, "not_your_take");\n', ""],
  ["removal reason unchecked", "src/plays.js", '  if (!REMOVE_REASONS.includes(reason)) return problem(400, "bad_request", `reason is one of ${REMOVE_REASONS.join(", ")}`);\n', ""],
  ["replacement never sent", "src/plays.js", "  if (replacing) stmts.push(replaceStatement(env, p.id, replacing, takeId, audio.type, now));\n", ""],
  // Plays that need no account (plays-open.js, owner 2026-10-29)
  ["open reads need an account", "src/index.js", "  if (isOpenRoute(pathname, method)) {", "  if (false && isOpenRoute(pathname, method)) {"],
  ["open routes take writes", "src/plays-open.js", '  method === "GET" &&\n  (pathname === "/v1/plays/finished"', '  (pathname === "/v1/plays/finished"'],
  ["open reads unlimited", "src/index.js", 'if (await limited(env.OPEN_READ_LIMITER, ip)) return problem(429, "rate_limited");\n    return handleOpen', "return handleOpen"],
  ["open invite read from the query", "src/plays-open.js", 'openInvite(env, request.headers.get(INVITE_HEADER), now);\n  if (!found) return problem(404, "invite_not_found");\n  if (found.gone) return gone();\n  const { p, inviter } = found;', 'openInvite(env, new URL(request.url).searchParams.get("token") || request.headers.get(INVITE_HEADER), now);\n  if (!found) return problem(404, "invite_not_found");\n  if (found.gone) return gone();\n  const { p, inviter } = found;'],
  ["revoked open invite is a 404", "src/plays-open.js", "  if (inv.revoked || inv.expires_at <= now) return { gone: true };", "  if (inv.revoked) return { gone: true };\n  if (inv.expires_at <= now) return null;"],
  ["expired open invite still opens", "src/plays-open.js", "  if (inv.revoked || inv.expires_at <= now) return { gone: true };", "  if (inv.revoked) return { gone: true };"],
  ["revoked open invite still opens", "src/plays-open.js", "  if (inv.revoked || inv.expires_at <= now) return { gone: true };", "  if (inv.expires_at <= now) return { gone: true };"],
  ["expired invites forgotten at once", "src/plays.js", "export const EXPIRED_INVITE_KEPT_MS = 30 * DAY_MS;", "export const EXPIRED_INVITE_KEPT_MS = 0;"],
  ["expired invites never forgotten", "src/plays.js", "bind(now - EXPIRED_INVITE_KEPT_MS)", "bind(0)"],
  ["reported takes heard anonymously", "src/plays-open.js", "return (t) => takes.has(t.id) || people.has(t.user_id);", "return (t) => people.has(t.user_id);"],
  ["reported people heard anonymously", "src/plays-open.js", "return (t) => takes.has(t.id) || people.has(t.user_id);", "return (t) => takes.has(t.id);"],
  ["closed reports forgotten", "src/plays-open.js", 'const takes = new Set(reports.filter((r) => r.take_id).map', 'const takes = new Set(reports.filter((r) => r.take_id && r.status === "open").map'],
  ["inviter's blocks ignored", "src/plays-open.js", "  for (const b of blocks) people.add(b.user_id === inviter ? b.blocked_id : b.user_id);\n", ""],
  ["open blocks one way only", "src/plays-open.js", "people.add(b.user_id === inviter ? b.blocked_id : b.user_id);", "if (b.user_id === inviter) people.add(b.blocked_id);"],
  ["open view shows every take", "src/plays-open.js", 'SELECT * FROM play_takes WHERE production_id = ?1 AND chosen = 1 ORDER BY uploaded_at', 'SELECT * FROM play_takes WHERE production_id = ?1 ORDER BY uploaded_at'],
  ["open view names accounts", "src/plays-open.js", "      members: members.map((m) => ({ name: m.display_name, director: m.user_id === p.user_id })),", "      members: members.map((m) => ({ name: m.display_name, director: m.user_id === p.user_id, user_id: m.user_id })),"],
  ["open view uncached", "src/plays-open.js", 'const INVITE_CACHE = "private, max-age=30";', 'const INVITE_CACHE = "no-store";'],
  ["finished listing uncached", "src/plays-open.js", 'const FINISHED_CACHE = "public, max-age=300, s-maxage=300";', 'const FINISHED_CACHE = "no-store";'],
  ["finished lists unpublished", "src/plays-open.js", "WHERE j.status = 'published' AND j.item_url IS NOT NULL", "WHERE j.item_url IS NOT NULL"],
  ["finished oldest first", "src/plays-open.js", "ORDER BY j.published_at DESC, j.production_id DESC LIMIT ?1", "ORDER BY j.published_at ASC, j.production_id DESC LIMIT ?1"],
  ["finished order by creation", "src/plays-open.js", "ORDER BY j.published_at DESC, j.production_id DESC LIMIT ?1", "ORDER BY p.created_at DESC, j.production_id DESC LIMIT ?1"],
  ["finished ties unordered", "src/plays-open.js", "ORDER BY j.published_at DESC, j.production_id DESC LIMIT ?1", "ORDER BY j.published_at DESC LIMIT ?1"],
  ["finished cursor repeats a row", "src/plays-open.js", "< (?1, ?2) ORDER BY", "<= (?1, ?2) ORDER BY"],
  ["finished cursor always given", "src/plays-open.js", "next_cursor: results.length > limit ?", "next_cursor: results.length >= limit ?"],
  ["finished page unbounded", "src/plays-open.js", "export const FINISHED_MAX = 50;", "export const FINISHED_MAX = 5000;"],
  ["finished cursor unchecked", "src/plays-open.js", '  if (rawCursor !== null && !cursor) return problem(400, "bad_request", "cursor");\n', ""],
  ["removed lines stay credited", "src/plays-open.js", "WHERE f.production_id IN (SELECT value FROM json_each(?1)) AND f.state IN ('pending', 'sent') ORDER BY", "WHERE f.production_id IN (SELECT value FROM json_each(?1)) ORDER BY"],
  ["emptied productions stay listed", "src/plays-open.js", "  \"AND EXISTS (SELECT 1 FROM play_archive_files f WHERE f.production_id = j.production_id AND f.state IN ('pending', 'sent'))\";", "  \"\";"],
  ["deleted performers drop the part", "src/plays-open.js", ': [{ part, name: "" }])', ": [])"],
  ["deleted performers keep their name", "src/plays-open.js", "LEFT JOIN play_members m ON m.production_id = f.production_id AND m.user_id = t.user_id", "LEFT JOIN play_members m ON m.production_id = f.production_id"],
  ["finished one lists unpublished", "src/plays-open.js", "  const row = await env.DB.prepare(`${FINISHED} AND j.production_id = ?1`)", "  const row = await env.DB.prepare(\"SELECT j.production_id AS id, j.item_url, j.published_at, p.script_id, p.script_revision, p.title FROM play_archive_jobs j JOIN play_productions p ON p.id = j.production_id WHERE j.production_id = ?1\")"],
  ["finished drops its script revision", "src/plays-open.js", "    script_revision: r.script_revision,\n", ""],
  ["short class codes", "src/plays.js", "export const CLASS_CODE_LENGTH = 8;", "export const CLASS_CODE_LENGTH = 4;"],
  // Take-down cases (Decision 074)
  ["case routes need no token", "src/takedown.js", 'if (!authorized(request, env)) return problem(403, "forbidden");', ""],
  ["any token length passes", "src/takedown.js", "given.length !== env.TAKEDOWN_TOKEN.length", "false"],
  ["check list carries people", "src/takedown.js", "`SELECT ref, created_ms, status, kind, complete, source, links, work, verdict\n       FROM takedown_cases WHERE status", "`SELECT * FROM takedown_cases WHERE status"],
  ["trap field stored", "src/takedown.js", "if (b.website) return json({ ref: newRef() });", ""],
  ["notice without signature", "src/takedown.js", 'if (!c.signature) return "signature";', ""],
  ["notice without sworn statement", "src/takedown.js", 'if (!c.accurate) return "accurate";', ""],
  ["no form limit", "src/takedown.js", 'if (await limited(env.TAKEDOWN_LIMITER, clientAddress(request))) return problem(429, "rate_limited");', ""],
  ["details kept one year", "src/takedown.js", "RETAIN_MS = 3 * 365", "RETAIN_MS = 1 * 365"],
  ["details kept forever", "src/takedown.js", "WHERE closed_ms IS NOT NULL AND closed_ms < ?1 AND email IS NOT NULL", "WHERE 0 AND ?1"],
  ["open cases swept", "src/takedown.js", "WHERE closed_ms IS NOT NULL AND closed_ms < ?1", "WHERE ?1"],
  ["cron skips take-downs", "src/index.js", "sweepPlays(env), sweepTakedowns(env), sweepRetention(env)", "sweepPlays(env), sweepRetention(env)"],
  // Read rooms (Decision 082): the protocol's rules, then each transport's guarantees
  ["read: anyone leads", "src/read-protocol.js", "return !!memberId && room.leader === memberId;", "return !!memberId;"],
  ["read: stale cursor applied", "src/read-protocol.js", '  if (msg.base !== room.cursor_gen) return { error: "stale", detail: room.cursor_gen };\n  return {', "  return {"],
  ["read: a repeated Next moves again", "src/read-protocol.js", "  if (msg.line === room.cursor) return { room, changed: false };\n  if (msg.base", "  if (msg.base"],
  ["read: last claim wins", "src/read-protocol.js", '  if (holder && holder !== member.id) return { error: "part_taken", detail: holder };\n', ""],
  ["read: class claims parts", "src/read-protocol.js", '  if (room.kind === "class") return { error: "class_assignments_only" };\n', ""],
  ["read: screens claim parts", "src/read-protocol.js", '  if (!member || member.role !== "reader") return { error: "readers_only" };\n  if (typeof part', "  if (typeof part"],
  ["read: class lead passes to a student", "src/read-protocol.js", '  if (room.kind === "class") return { leader: room.leader, waiting: true };\n', ""],
  ["read: handoff to the newest", "src/read-protocol.js", "a.joined_at - b.joined_at ||", "b.joined_at - a.joined_at ||"],
  ["read: screens lead after handoff", "src/read-protocol.js", '.filter((m) => m.id !== room.leader && m.role === "reader")', ".filter((m) => m.id !== room.leader)"],
  ["read: handoff at once", "src/read-protocol.js", "if (leader && now - leader.seen_at <= LEADER_GONE_MS)", "if (leader && now - leader.seen_at <= 0)"],
  ["read: split ranges ignored", "src/read-protocol.js", "    if (i >= lo && i <= hi) return a;", "    return a;"],
  ["read: next line skips the current", "src/read-protocol.js", "  const start = Math.max(0, indexOf(cast, cursor));\n  for (let i = start;", "  const start = Math.max(0, indexOf(cast, cursor));\n  for (let i = start + 1;"],
  ["read: anyone ends a line", "src/read-protocol.js", '  if (!holds(room, cast, member, i)) return { error: "not_your_line" };\n', ""],
  ["read: unheld lines not skipped", "src/read-protocol.js", "    if (held(room, cast, j)) {", "    if (true) {"],
  ["read: screens are handed the lead", "src/read-protocol.js", '  if (to.role === "screen") return { error: "screens_do_not_lead" };\n', ""],
  ["read: room grows past 40", "src/read-protocol.js", "export const MAX_MEMBERS = 40;", "export const MAX_MEMBERS = 400;"],
  ["read: lock ignored", "src/read-protocol.js", '  if (room.locked && !(role === "screen" && want.paired === true)) return "joining_locked";\n', ""],
  ["t5: a pairing lets a reader past the lock", "src/read-protocol.js", '!(role === "screen" && want.paired === true)', '!(want.paired === true)'],
  ["read: two devices on one seat", "src/read-protocol.js", '  if (other && !move) return { error: "seat_in_use" };\n', ""],
  ["read: dropped devices forgotten at once", "src/read-protocol.js", "    (m) => now - m.seen_at <= MEMBER_FORGET_MS ||", "    (m) => now - m.seen_at <= MEMBER_GONE_MS ||"],
  ["read: snapshot leaks key hashes", "src/read-protocol.js", "members: members.map((m) => ({ id: m.id, role: m.role, seat: m.seat, name: m.name || null, live: live.includes(m) })),", "members,"],
  ["read: clock averages samples", "src/read-protocol.js", "if (!best || rtt < best.rtt)", "if (!best || rtt > best.rtt)"],
  ["read: codes drift from Listen Together", "src/read-protocol.js", '    if (ch === "I" || ch === "L") {\n      out += "1";', '    if (ch === "I") {\n      out += "1";'],
  ["read: socket skips hello", "src/read-rooms.js", 'if (!msg || msg.type !== "hello") return ws.send(JSON.stringify({ type: "error", error: "hello_first" }));', 'if (!msg || msg.type !== "hello") return;'],
  ["read: any key is a member", "src/read-rooms.js", "return members.find((m) => m.key_hash === hash) || null;", "return members[0] || null;"],
  ["read: class room without the teacher", "src/read-rooms.js", '    if (c.user_id !== auth.userId) return { response: problem(403, "teacher_only") };\n', ""],
  ["read: any cast accepted", "src/read-rooms.js", '  if ((await castHash(cast)) !== entry.cast) return { response: problem(422, "cast_mismatch") };\n', ""],
  ["read: D1 last write wins", "src/read-rooms.js", "WHERE code = ?1 AND version = ?5", "WHERE code = ?1 AND ?5 = ?5"],
  ["read: no join floor", "src/read-rooms.js", 'if ((action === "POST join" || action === "POST pair") && (await limited(env.READ_JOIN_LIMITER, ip))) return problem(429, "rate_limited");', ""],
  ["read: member limit by address", "src/read-rooms.js", "if (await limited(env.READ_MEMBER_LIMITER, me.id))", "if (await limited(env.READ_MEMBER_LIMITER, 'one'))"],
  ["read: no member limit", "src/read-rooms.js", 'if (await limited(env.READ_MEMBER_LIMITER, me.id)) return { error: "rate_limited" };', ""],
  ["read: rooms under the address floor", "src/index.js", "const floor = isReadRoute(url.pathname) ? env.READ_IP_LIMITER : env.EVERY_IP_LIMITER;", "const floor = env.EVERY_IP_LIMITER;"],
  ["read: object broadcasts nothing", "src/read-rooms.js", "        ws.send(JSON.stringify(snapshot(world, a.member, now)));", "        void 0;"],
  ["read: D1 rooms never swept", "src/index.js", "sweepRooms(env), sweepReadRooms(env), ", "sweepRooms(env), "],
  // Classes, seats and takes that pass through (Decision 082, T2)
  ["t2: seat key stored raw", "src/plays-seats.js", ".bind(c.id, s.id, await sha256Hex(key), now, s.key_hash)", ".bind(c.id, s.id, key, now, s.key_hash)"],
  ["t2: a held seat taken without Move here", "src/plays-seats.js", '  if (s.key_hash && body.move !== true) return problem(409, "seat_in_use");\n', ""],
  ["t2: a released seat's key still works", "src/plays-seats.js", "UPDATE play_class_seats SET key_hash = NULL, claimed_at = NULL WHERE", "UPDATE play_class_seats SET claimed_at = NULL WHERE"],
  ["t2: anyone runs a class", "src/plays-seats.js", '  if (c.user_id !== userId) return { error: problem(403, "teacher_only") };\n', ""],
  ["t2: no seat limit", "src/plays-seats.js", '  if (have.length + fresh.length > MAX_SEATS) return problem(409, "too_many_seats", MAX_SEATS);\n', ""],
  ["t2: seat names unfiltered", "src/plays-seats.js", ': nameRefusal(label);', ": null;"],
  ["t2: a seat acts in another class's production", "src/plays-seats.js", '  if (!p || p.class_id !== seat.class_id) return { error: problem(404, "not_found") };', '  if (!p) return { error: problem(404, "not_found") };'],
  ["t2: unassigned line recorded", "src/plays-seats.js", '  if (!assignedTo(p.cast, await assignmentRows(env, p.id), seat.id, meta.lineID)) return problem(403, "not_assigned");\n', ""],
  ["t2: scene ranges ignored", "src/plays-seats.js", "  for (let i = lo; i <= hi; i++) if (cast[i][1] === a.part) out.push(i);", "  for (let i = 0; i < cast.length; i++) if (cast[i][1] === a.part) out.push(i);"],
  ["t2: under-13 voice passes through", "src/plays-seats.js", '  if (seat.under13 && !seat.consent) return problem(403, "school_consent_required");\n', ""],
  ["t2: seat limit by address", "src/plays-seats.js", "if (await limited(env.SEAT_LIMITER, `${seat.class_id}:${seat.id}`))", "if (await limited(env.SEAT_LIMITER, ip))"],
  ["t2: no seat claim floor", "src/plays-seats.js", '    if (await limited(env.SEAT_JOIN_LIMITER, ip)) return problem(429, "rate_limited");\n', ""],
  ["t2: seats share one upload limit", "src/plays-seats.js", "limited(env.PLAY_UPLOAD_LIMITER, `seat:${seat.class_id}:${seat.id}`)", 'limited(env.PLAY_UPLOAD_LIMITER, "seats")'],
  ["t2: assignments on any production", "src/plays-seats.js", '  if (!p.class_id) return problem(422, "not_a_class_production");\n  const { body, error } = await readJson(request, 256 * 1024);', "  const { body, error } = await readJson(request, 256 * 1024);"],
  ["t2: review state unchecked", "src/plays-seats.js", '  if (!REVIEW_STATES.includes(body.state)) return problem(400, "bad_request", `state is one of ${REVIEW_STATES.join(", ")}`);\n', ""],
  ["t2: long notes kept", "src/plays-seats.js", "note.length > MAX_NOTE || ", ""],
  ["t2: a note shown to every seat", "src/plays-seats.js", 'SELECT * FROM play_takes WHERE production_id = ?1 AND seat_id = ?2 ORDER BY uploaded_at', 'SELECT * FROM play_takes WHERE production_id = ?1 AND ?2 = ?2 ORDER BY uploaded_at'],
  ["t2: a seat chooses another's take", "src/plays-seats.js", "  if (!t || t.seat_id !== seat.id) return problem(404, \"no_such_take\");", "  if (!t) return problem(404, \"no_such_take\");"],
  ["t2: progress counts any take", "src/plays-seats.js", "const mine = takes.filter((k) => k.seat_id === a.seat && lines.includes(k.line_id));", "const mine = takes.filter((k) => lines.includes(k.line_id));"],
  ["t2: under-13 class publishes", "src/plays.js", '  if (!c || c.under13) return problem(403, "under_13_never_published");\n', ""],
  ["t2: published crediting no one", "src/plays.js", '  if (!m || !m.display_name) return problem(422, "credit_name_required");\n', ""],
  ["t2: credit name unfiltered", "src/plays.js", "    const refusal = nameRefusal(body.credit_name);\n    if (refusal) return problem(422, refusal);\n", ""],
  ["t2: class publish with lines missing", "src/plays.js", "  return missing.length ? { lines_missing: missing.slice(0, 50) } : null;", "  return null;"],
  ["t2: the director's own take relayed", "src/plays.js", "direct: director || !!replacing", "direct: !!replacing"],
  ["t2: any member receives the takes", "src/plays.js", 'p.user_id === auth.userId ? pickup(env, p.id) : problem(403, "director_only")', "pickup(env, p.id)"],
  ["t2: a reused take id reads the audio first", "src/plays.js", '  if (await env.DB.prepare("SELECT 1 FROM play_takes WHERE production_id = ?1 AND id = ?2").bind(p.id, takeId).first()) {\n    return problem(409, "take_exists");\n  }\n', ""],
  ["t2: sender waits with nobody there", "src/take-relay.js", "      if (!this.present(now) || this.senders.length >= MAX_WAITING_SENDERS) return problem(409, \"nobody_receiving\");", "      if (this.senders.length >= MAX_WAITING_SENDERS) return problem(409, \"nobody_receiving\");"],
  ["t2: a cut take delivered", "src/take-relay.js", "            if (seen !== expected) return fail(controller);\n", ""],
  ["t2: two takes at once from one sender", "src/take-relay.js", '    if (this.inFlight.has(sender)) return problem(409, "one_take_at_a_time");\n', ""],
  ["t2: relay keeps what it saw", "src/take-relay.js", "  pickup(now) {\n    this.seenAt = now;", "  pickup(now) {\n    this.ctx.storage.put(\"seen\", now);\n    this.seenAt = now;"],
  ["t2: an R2 bucket bound", "wrangler.toml", "# are using archive.org for storage, not cloudflare.\"). There is no R2 bucket.\n", "# are using archive.org for storage, not cloudflare.\").\n[[r2_buckets]]\nbinding = \"TAKES\"\nbucket_name = \"eardrama-takes\"\n"],
  ["t2: class room trusts the request's seats", "src/read-rooms.js", "    body.seats = (await seatsOf(env, body.class_id)).map((s) => ({ id: s.id, label: s.label }));\n", ""],
  ["t2: class room seat without its key", "src/read-rooms.js", '    if (seat !== null && w.room.kind === "class" && !(await seatKeyOpens(env, w.room.class_id, seat, want.seat_key))) return { error: "seat_key_required" };\n', ""],
  ["t2: class room seat change without its key", "src/read-rooms.js", '    return (await seatKeyOpens(env, world.room.class_id, msg.seat, msg.seat_key)) ? null : "seat_key_required";', "    return null;"],
  ["t2: class room on another class's production", "src/read-rooms.js", "      if (!p || p.class_id !== body.class_id || p.script_id !== body.script_id) return", "      if (!p) return"],
  // T3: published works stay (owner 2026-10-29) when their class goes
  // T5: Record in the room, names on join, ended rooms, pairing a TV
  ["t5: anyone records a line", "src/read-protocol.js", '  if (!holds(room, cast, member, i)) return "not_your_line";\n  return null;', "  return null;"],
  ["t5: records outside Record mode", "src/read-protocol.js", '  if (room.mode !== "record") return "not_recording";\n  if (!member', "  if (!member"],
  ["t5: a seat that leads receives a class's takes", "src/read-protocol.js", 'return room.kind === "class" ? room.owner : room.leader;', "return room.leader;"],
  ["t5: anyone holds the room's pickup", "src/read-rooms.js", '    if (P.receiverOf(world.room) !== me.id) return { error: "receivers_only" };\n', ""],
  ["t5: under-13 voices pass", "src/read-rooms.js", "  return !!c && (!c.under13 || !!c.consent);", "  return true;"],
  ["t5: a join claims a pairing", "src/read-rooms.js", '  if (action === "POST join" && body && typeof body === "object") delete body.paired;\n', ""],
  ["t5: pairing codes never expire", "src/read-rooms.js", '  if (row.expires_at <= now) return refuse("pair_expired");\n  const r = await', "  const r = await"],
  ["t5: anyone attaches a screen", "src/read-rooms.js", "  if (lead.error) return refuse(lead.error);\n", ""],
  ["t5: a pairing used twice", "src/read-rooms.js", '  await env.DB.prepare("DELETE FROM read_pairs WHERE code = ?1").bind(code).run();\n  const want', "  const want"],
  ["t5: an ended room forgotten at once", "src/read-rooms.js", 'if (!this.world) return refuse(this.endedAt ? "room_ended" : "no_such_room");', 'if (!this.world) return refuse("no_such_room");'],
  ["t5: an ended D1 room still answers", "src/read-rooms.js", 'async poll(env, code, key, now) {\n    const loaded = await d1.load(env, code);\n    if (!loaded) return refuse("no_such_room");\n    if (loaded.world.room.ended) return refuse("room_ended");\n', 'async poll(env, code, key, now) {\n    const loaded = await d1.load(env, code);\n    if (!loaded) return refuse("no_such_room");\n'],
  ["t5: names unfiltered", "src/read-rooms.js", "if (name === false || (name && nameRefusal(name))) return", "if (name === false) return"],
  ["t5: the sweep keeps expired pairs", "src/read-rooms.js", '  await env.DB.prepare("DELETE FROM read_pairs WHERE expires_at < ?1").bind(now).run();\n', ""],
  // T6: Relay across time and the consent rule (§12.11)
  ["t6: an anonymous reader's take credits the leader", "src/read-rooms.js", 'const credit = world.room.kind === "class" ? null : me.name || "A reader";', "const credit = null;"],
  ["t6: a credited maker counts as consented", "src/plays.js", "if (missing.length || credits.length) return json(", "if (missing.length) return json("],
  ["t6: a credited maker makes the leader the performer", "src/plays.js", "takes.filter((t) => t.chosen && !t.credit).map((t) => t.user_id)", "takes.filter((t) => t.chosen).map((t) => t.user_id)"],
  ["t6: the receiver answer is always yes", "src/plays.js", "return { receiving: await receiving(env, p.id), name:", "return { receiving: true, name:"],
  ["t6: anyone attaches a room to a production", "src/read-rooms.js", "p.class_id || p.user_id !== auth.userId || p.script_id !== body.script_id", "p.class_id || p.script_id !== body.script_id"],
  ["t6: a seat asks about another class's production", "src/plays-seats.js", '  if (!p || p.class_id !== seat.class_id) return { error: problem(404, "not_found") };', "  if (!p) return { error: problem(404, \"not_found\") };"],
  // T7c: a take that ends after the leader moved the cursor still marks its line done (no second microphone)
  ["t7c: a take after the cursor moved is refused", "src/read-protocol.js", "    return { room: { ...room, done: [...room.done, msg.line], generation: room.generation + 1, touched_at: now }, changed: true };", '    return { error: "stale", detail: room.cursor_gen };'],
  ["t7c: the bench's test keys answer a public host", "src/auth.js", "return !!env.LOCAL_TEST_JWKS && !LOCAL_HOST.test(url.hostname);", "return false;"],
  ["t7c: the test keys used without being set", "src/auth.js", "  if (!env.LOCAL_TEST_JWKS) return undefined;\n", "  if (!env.LOCAL_TEST_JWKS) return [];\n"],
  ["t3: a class's deletion takes its published production", "src/plays.js", "UPDATE play_productions SET class_id = NULL WHERE id IN (${submitted})", "UPDATE play_productions SET class_id = NULL WHERE 0 AND id IN (${submitted})"],
  // Retention and deletion (Decision 084)
  ["084: a deleted class stays", "src/plays-retention.js", "    env.DB.prepare(\"DELETE FROM play_classes WHERE id = ?1\").bind(classId),\n", ""],
  ["084: anyone deletes a class", "src/plays-retention.js", "  const t = await teacherClass(env, classId, auth.userId);\n  if (t.error) return t.error;\n  await deleteClass(env, classId);", "  await deleteClass(env, classId);"],
  ["084: deleting a class takes its published production", "src/plays-retention.js", "    env.DB.prepare(`UPDATE play_productions SET class_id = NULL WHERE class_id = ?1 AND id IN (${SUBMITTED})`).bind(classId),\n", ""],
  ["084: a kept production keeps who recorded what", "src/plays-retention.js", "    env.DB.prepare(`UPDATE play_takes SET seat_id = NULL WHERE production_id IN (${submitted})`).bind(classId),\n", ""],
  ["084: a kept production keeps the notes", "src/plays-retention.js", "    env.DB.prepare(`DELETE FROM play_reviews WHERE production_id IN (${submitted})`).bind(classId),\n", ""],
  ["084: a kept production keeps the casting", "src/plays-retention.js", "    env.DB.prepare(`DELETE FROM play_assignments WHERE production_id IN (${submitted})`).bind(classId),\n", ""],
  ["084: anyone deletes a production", "src/plays-retention.js", "  if (p.user_id !== auth.userId) return problem(403, \"director_only\");\n  if (await env.DB", "  if (await env.DB"],
  ["084: a submitted production can be deleted", "src/plays-retention.js", ".bind(p.id).first()) return problem(409, \"submitted\");", ".bind(p.id).first() && false) return problem(409, \"submitted\");"],
  ["084: a class has no end date", "src/plays.js", "  const endsOn = schoolYearEnd(now);", "  const endsOn = null;"],
  ["084: the school year ends in June", "src/plays-retention.js", "d.getUTCMonth() >= 7 ? 1 : 0", "d.getUTCMonth() >= 6 ? 1 : 0"],
  ["084: an end date any distance ahead", "src/plays-retention.js", "  if (ms > now + MAX_END_DAYS * DAY_MS) return \"end_date_too_far\";\n", ""],
  ["084: an end date in the past", "src/plays-retention.js", "  if (endsOn < dateOf(now - DAY_MS)) return \"end_date_past\";\n", ""],
  ["084: anyone moves the end date", "src/plays-retention.js", "  const t = await teacherClass(env, classId, auth.userId);\n  if (t.error) return t.error;\n  const { body, error } = await readJson(request, 4 * 1024);\n  if (error) return error;\n  const refusal = endDateRefusal", "  const { body, error } = await readJson(request, 4 * 1024);\n  if (error) return error;\n  const refusal = endDateRefusal"],
  ["084: the sweep ignores end dates", "src/plays-retention.js", "for (const { id } of [...ended.results, ...idle.results])", "for (const { id } of [...idle.results])"],
  ["084: a class goes on its last day", "src/plays-retention.js", "const cutoff = dateOf(now - DAY_MS - 12 * 60 * 60 * 1000);", "const cutoff = dateOf(now + DAY_MS);"],
  ["084: an idle class goes without notice", "src/plays-retention.js", "WHERE c.notice_at <= ?1 AND ${ACTIVITY} < ?2 LIMIT ?3", "WHERE ?1 = ?1 AND ${ACTIVITY} < ?2 LIMIT ?3"],
  ["084: idle classes never go", "src/plays-retention.js", "  for (const { id } of [...ended.results, ...idle.results]) await deleteClass(env, id);", "  for (const { id } of [...ended.results]) await deleteClass(env, id);"],
  ["084: a production's activity does not count", "src/plays-retention.js", "\"COALESCE((SELECT MAX(p.updated_at) FROM play_productions p WHERE p.class_id = c.id), 0), \" +\n", "\"0, \" +\n"],
  ["084: a notice never ends", "src/plays-retention.js", "    env.DB.prepare(`UPDATE play_classes AS c SET notice_at = NULL WHERE notice_at IS NOT NULL AND ${ACTIVITY} > notice_at`),\n", ""],
  ["084: opening the class keeps the notice", "src/plays-retention.js", "SET touched_at = ?2, notice_at = NULL WHERE id = ?1 AND (touched_at IS NULL", "SET touched_at = ?2 WHERE id = ?1 AND (touched_at IS NULL"],
  ["084: the list hides the notice", "src/plays.js", "deletes_on: deletesOn(notice_at) });", "deletes_on: null });"],
  ["084: idle accounts never go", "src/plays-retention.js", "  for (const { id } of gone.results) await deleteAccount(env, id);\n", ""],
  ["084: an idle account goes without notice", "src/plays-retention.js", "SELECT id FROM users WHERE idle_notice_at <= ?1 AND seen_at < ?2", "SELECT id FROM users WHERE ?1 = ?1 AND seen_at < ?2"],
  ["084: the deleted-account row gets a notice", "src/plays-retention.js", "WHERE idle_notice_at IS NULL AND seen_at < ?2 AND id <> ?3", "WHERE idle_notice_at IS NULL AND seen_at < ?2 AND ?3 = ?3"],
  ["084: the deleted-account row is swept", "src/plays-retention.js", "AND seen_at < ?2 AND id <> ?3 LIMIT ?4", "AND seen_at < ?2 AND ?3 = ?3 LIMIT ?4"],
  ["084: a sign-in does not count", "src/auth.js", "    env.DB.prepare(\"UPDATE users SET seen_at = ?2, idle_notice_at = NULL WHERE id = ?1\").bind(userId, now),\n", ""],
  ["084: cron skips retention", "src/index.js", "sweepTakedowns(env), sweepRetention(env), ", "sweepTakedowns(env), "],
  ["084: anyone exports a class", "src/plays-retention.js", "  const t = await teacherClass(env, classId, auth.userId);\n  if (t.error) return t.error;\n  const c = t.c;", "  const t = { c: await env.DB.prepare(\"SELECT * FROM play_classes WHERE id = ?1\").bind(classId).first() };\n  const c = t.c;"],
  ["084: the export drops the notes", "src/plays-retention.js", "      review: review[k.id] || null,", "      review: null,"],
  ["084: the operator route needs no token", "src/plays-retention.js", "  if (!operatorAllowed(request, env)) return problem(403, \"forbidden\");\n", ""],
  ["084: the operator route takes any token", "src/plays-retention.js", "  return diff === 0;\n}\n\nexport const isOperatorRoute", "  return true;\n}\n\nexport const isOperatorRoute"],
  ["084: a class publishes without the confirmations", "src/plays.js", "  if (body.performers_agreed !== true || body.media_release !== true) return problem(422, \"confirmations_required\");\n", ""],
  ["084: one confirmation is enough", "src/plays.js", "body.performers_agreed !== true || body.media_release !== true", "body.performers_agreed !== true && body.media_release !== true"],
  ["084: the confirmations are not recorded", "src/plays.js", ".bind(p.id, auth.userId, JSON.stringify(takeIds), now, confirmed)", ".bind(p.id, auth.userId, JSON.stringify(takeIds), now, null)"],
  ["084: an unnamed school authorization", "src/plays.js", "  if (!reference) return problem(422, \"reference_required\");\n", ""],
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

// A mutation is "caught" when vitest exits non-zero, so a suite that cannot run at all
// (vitest missing, a broken import) would read as every mutation caught. The unmutated
// suite must pass first (2026-10-29: without node_modules this printed "all 103 caught").
try {
  execFileSync("npx", ["--no-install", "vitest", "run"], { cwd: root, stdio: "pipe" });
} catch (e) {
  console.error("the unmutated suite does not pass, so no mutation can be judged:\n" + String(e.stderr || e.stdout || e.message).slice(-800));
  process.exit(2);
}

// An interrupted run must not leave a mutated source behind.
let pending = null;
for (const sig of ["SIGINT", "SIGTERM"]) {
  process.on(sig, () => {
    if (pending) writeFileSync(pending.path, pending.src);
    process.exit(130);
  });
}

let survivors = 0;
for (const [name, file, from, to] of run) {
  const path = root + file;
  const src = readFileSync(path, "utf8");
  if (src.split(from).length !== 2) throw new Error(`mutation "${name}" no longer matches ${file} exactly once`);
  pending = { path, src };
  writeFileSync(path, src.replace(from, to));
  let red = false;
  try {
    execFileSync("npx", ["vitest", "run"], { cwd: root, stdio: "pipe" });
  } catch {
    red = true;
  } finally {
    writeFileSync(path, src);
    pending = null;
  }
  console.log(`${red ? "CAUGHT  " : "SURVIVED"} ${name}`);
  if (!red) survivors++;
}
console.log(survivors ? `${survivors} mutation(s) survived` : `all ${run.length} mutations caught`);
process.exit(survivors ? 1 : 0);
