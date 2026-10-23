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
