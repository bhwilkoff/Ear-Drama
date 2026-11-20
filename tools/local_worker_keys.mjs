/* The local bench's sign-in keys (tools/local_worker.py, tools/class_bench.py; worker/src/auth.js testKeys).
 *
 *   node tools/local_worker_keys.mjs pair                      -> {"jwks":{"keys":[...]},"private":{...jwk}}
 *   node tools/local_worker_keys.mjs mint <private.json> <sub>  -> an Apple-shaped identity token for that subject
 *
 * The key set is passed only to a local `wrangler dev --var LOCAL_TEST_JWKS:...`; a Worker that carries it refuses
 * every public host. The private key lives in the bench's scratch directory for one run and is never committed.
 */
import { readFileSync } from "node:fs";
import { webcrypto as crypto } from "node:crypto";

const b64u = (buf) => Buffer.from(buf).toString("base64url");
const ALG = { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" };

if (process.argv[2] === "pair") {
  const pair = await crypto.subtle.generateKey({ ...ALG, modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]) }, true, ["sign", "verify"]);
  const pub = await crypto.subtle.exportKey("jwk", pair.publicKey);
  const priv = await crypto.subtle.exportKey("jwk", pair.privateKey);
  const kid = "bench-" + b64u(crypto.getRandomValues(new Uint8Array(6)));
  process.stdout.write(JSON.stringify({ jwks: { keys: [{ kty: "RSA", n: pub.n, e: pub.e, kid, alg: "RS256", use: "sig" }] }, private: { ...priv, kid } }) + "\n");
} else if (process.argv[2] === "mint") {
  const priv = JSON.parse(readFileSync(process.argv[3], "utf8"));
  const key = await crypto.subtle.importKey("jwk", { ...priv, kid: undefined }, ALG, false, ["sign"]);
  const now = Math.floor(Date.now() / 1000);
  const head = b64u(JSON.stringify({ alg: "RS256", kid: priv.kid, typ: "JWT" }));
  const body = b64u(JSON.stringify({ iss: "https://appleid.apple.com", aud: "app.eardrama", sub: process.argv[4], iat: now, exp: now + 600 }));
  const sig = await crypto.subtle.sign(ALG, key, new TextEncoder().encode(`${head}.${body}`));
  process.stdout.write(`${head}.${body}.${b64u(sig)}\n`);
} else {
  process.stderr.write("usage: pair | mint <private.json> <sub>\n");
  process.exit(2);
}
