/**
 * The castable manifest: what tools/castable-manifest.mjs writes and what a
 * new production is checked against. Shared by Node (the builder) and the
 * Worker (the drift test), so it uses only Web Crypto.
 */

import { canonicalCast, partOfLine } from "./plays-relay.js";

export async function sha256Text(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export const castHash = (cast) => sha256Text(canonicalCast(cast));

export async function manifestFor(file) {
  const scripts = {};
  for (const s of file.scripts) {
    const cast = s.lines.map((l) => [l.id, partOfLine(l)]);
    scripts[s.id] = { revision: s.revision, title: s.title, cast: await castHash(cast), lines: cast.length };
  }
  return { format: 1, source_format: file.format, scripts };
}
