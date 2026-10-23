import { env, createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { vi } from "vitest";
import worker from "../src/index.js";
import { b64urlEncode, clearJwksCache } from "../src/jwt.js";

export const APPLE_AUD = "app.eardrama.test";
export const GOOGLE_AUD = "google-client.test";

async function rsaPair(kid) {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const jwk = await crypto.subtle.exportKey("jwk", pair.publicKey);
  return { kid, privateKey: pair.privateKey, publicJwk: { kty: "RSA", n: jwk.n, e: jwk.e, kid, alg: "RS256", use: "sig" } };
}

export const keys = {
  apple: await rsaPair("apple-test-1"),
  google: await rsaPair("google-test-1"),
  // Not published by any provider: a forger's key.
  forger: await rsaPair("apple-test-1"),
};

/** Serves the two providers' key sets in place of the real JWKS endpoints. */
export function installProviderKeys({ extra } = {}) {
  clearJwksCache();
  const spy = vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input && input.url;
    if (url === "https://appleid.apple.com/auth/keys") return Response.json({ keys: [keys.apple.publicJwk] });
    if (url === "https://www.googleapis.com/oauth2/v3/certs") return Response.json({ keys: [keys.google.publicJwk] });
    if (extra) {
      const r = await extra(url, init);
      if (r) return r;
    }
    throw new Error(`unexpected fetch in test: ${url}`);
  });
  return spy;
}

export async function mint(payload, { key = keys.apple, header = {} } = {}) {
  const head = b64urlEncode(JSON.stringify({ alg: "RS256", kid: key.kid, typ: "JWT", ...header }));
  const body = b64urlEncode(JSON.stringify(payload));
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key.privateKey, new TextEncoder().encode(`${head}.${body}`));
  return `${head}.${body}.${b64urlEncode(new Uint8Array(sig))}`;
}

const nowS = () => Math.floor(Date.now() / 1000);

export function appleClaims(sub, over = {}) {
  return { iss: "https://appleid.apple.com", aud: APPLE_AUD, sub, iat: nowS(), exp: nowS() + 600, ...over };
}

export function googleClaims(sub, over = {}) {
  return { iss: "https://accounts.google.com", aud: GOOGLE_AUD, sub, iat: nowS(), exp: nowS() + 600, ...over };
}

let ipCounter = 1;

/** One request through the real Worker entry point. */
export async function call(method, path, { body, token, origin, ip, envOverride } = {}) {
  const headers = { "cf-connecting-ip": ip || `10.0.${Math.floor(ipCounter / 250)}.${ipCounter++ % 250}` };
  if (body !== undefined) headers["content-type"] = "application/json";
  if (token) headers.authorization = `Bearer ${token}`;
  if (origin) headers.origin = origin;
  const request = new Request(`https://api.eardrama.test${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body),
  });
  const ctx = createExecutionContext();
  const response = await worker.fetch(request, envOverride ? { ...env, ...envOverride } : env, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

export async function signIn(sub, provider = "apple", extra = {}) {
  const token = await mint(provider === "apple" ? appleClaims(sub) : googleClaims(sub), {
    key: provider === "apple" ? keys.apple : keys.google,
  });
  const r = await call("POST", `/v1/auth/${provider}`, { body: { id_token: token, device: "test-device", ...extra } });
  if (r.status !== 200) throw new Error(`sign-in failed: ${r.status} ${await r.text()}`);
  return r.json();
}

export { env };
