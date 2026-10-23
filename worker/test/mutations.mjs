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
  ["deletion skips history", "src/account.js", '"history", "follows"', '"follows"'],
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
  ["cron skips rooms", "src/index.js", "Promise.all([sweepSessions(env), sweepRooms(env)])", "Promise.all([sweepSessions(env)])"],
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
];

let survivors = 0;
for (const [name, file, from, to] of M) {
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
console.log(survivors ? `${survivors} mutation(s) survived` : `all ${M.length} mutations caught`);
process.exit(survivors ? 1 : 0);
