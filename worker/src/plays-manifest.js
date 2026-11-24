/**
 * The castable manifest: what tools/castable-manifest.mjs writes (the bundle's
 * manifest and the library's rows) and what a new production is checked
 * against (plays-castable.js). Shared by Node and the Worker, so it uses only
 * Web Crypto.
 */

import { MAX_LINES, canonicalCast, partOfLine } from "./plays-relay.js";

export const FORMAT = 2;
export const ROW_FORMAT = 1;
/** Revisions of one play the bundled manifest keeps: the apps in the stores hold older bundles than the repo's. */
export const KEPT_REVISIONS = 6;

/** A catalog play's id (`gut-3012`, `gut-4269-18`, `grw-A1`): never an own script's, and nothing a URL could misread. */
export const SCRIPT_ID = /^(?!own-)[a-z]{3}-[A-Za-z0-9]{1,12}(-\d{1,4})?$/;
export const REVISION = /^[0-9a-f]{12}$/;

/** The castable buckets of catalog/tools/script_rights.py STATE (tools/test_castable_manifest.mjs holds the two equal). */
export const CASTABLE_BUCKETS = [
  "script_gov_work",
  "script_pd_published_age",
  "script_registered_age",
  "script_source_cleared",
  "script_registered_not_renewed",
  "script_author_died",
];
export const publishableBucket = (bucket) => CASTABLE_BUCKETS.includes(bucket);

export async function sha256Text(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export const castHash = (cast) => sha256Text(canonicalCast(cast));

/** One script's row. */
export async function rowFor(s) {
  const cast = s.lines.map((l) => [l.id, partOfLine(l)]);
  // The rights evidence and source travel with the script so the archive.org
  // item carries the script's own record, never words written for it (§8 rule 2).
  const rights = { bucket: s.rights.bucket, evidence: s.rights.evidence.map((e) => ({ claim: e.claim, src: e.src })) };
  return {
    revision: s.revision,
    title: s.title,
    cast: await castHash(cast),
    lines: cast.length,
    source: s.source?.url ?? null,
    rights,
    publishable: publishableBucket(s.rights.bucket),
  };
}

/**
 * The bundled manifest: each play's rows, newest first. `before` is the
 * manifest this one replaces: a revision it held stays accepted (an app in a
 * store still carries it) for as long as the play is in the bundle.
 */
export async function manifestFor(file, before = null) {
  const scripts = {};
  for (const s of file.scripts) {
    const row = await rowFor(s);
    const older = (before?.format === FORMAT && before.scripts[s.id]) || [];
    scripts[s.id] = [row, ...older.filter((r) => r.revision !== row.revision)].slice(0, KEPT_REVISIONS);
  }
  return { format: FORMAT, source_format: file.format, scripts };
}

const isText = (v, max) => typeof v === "string" && v.length > 0 && v.length <= max;

/** A row read back (from the site, the edge cache, or D1) with only its own fields, or null unless it is whole and `id`'s. */
export function validRow(raw, id) {
  if (!raw || typeof raw !== "object" || raw.format !== ROW_FORMAT || raw.id !== id) return null;
  const { revision, title, cast, lines, source, rights, publishable } = raw;
  if (typeof revision !== "string" || !REVISION.test(revision)) return null;
  if (!isText(title, 300)) return null;
  if (typeof cast !== "string" || !/^[0-9a-f]{64}$/.test(cast)) return null;
  if (!Number.isInteger(lines) || lines < 1 || lines > MAX_LINES) return null;
  if (source !== null && !(isText(source, 500) && /^https?:\/\//.test(source))) return null;
  if (!rights || !isText(rights.bucket, 80) || !Array.isArray(rights.evidence) || rights.evidence.length > 50) return null;
  if (!rights.evidence.every((e) => e && isText(e.claim, 2000) && isText(e.src, 500))) return null;
  if (typeof publishable !== "boolean") return null;
  const evidence = rights.evidence.map((e) => ({ claim: e.claim, src: e.src }));
  return { format: ROW_FORMAT, id, revision, title, cast, lines, source, rights: { bucket: rights.bucket, evidence }, publishable };
}
