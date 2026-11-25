/**
 * Which scripts a production, a class production or a read room is made from,
 * and which may be published (R4-0). A script is known by a manifest ROW
 * (plays-manifest.js): its revision, title, source, rights, and the SHA-256 of
 * its cast sheet. Rows come from two places, and never from a client:
 *
 * - the bundle's, in castable-manifest.json, deployed with the Worker: every
 *   revision an app was shipped with, accepted with no request at all;
 * - the published library's, one small file a play on our own site
 *   (`castable/<id>.json`), built from the very scripts that site serves
 *   (tools/assemble_site.sh). Growing the library needs no Worker deploy.
 *
 * READ ONCE. The site is asked only when something is made, for one row, and a
 * row found at the revision asked for is kept in the edge cache under that
 * revision: a revision's cast sheet never changes, so a kept row cannot be
 * stale. Nothing here polls, and no route after creation reads the library.
 *
 * THE ROW GOES WITH THE PRODUCTION (`play_productions.script_row`), so a play
 * that leaves the library, or changes there, breaks no production made from it.
 *
 * A library that cannot be read is `503 library_unavailable`, and nothing is
 * made. A row that is not whole, or not this play's, counts as unreadable.
 */

import { problem } from "./http.js";
import { REVISION, ROW_FORMAT, SCRIPT_ID, publishableBucket, validRow } from "./plays-manifest.js";
import MANIFEST from "./castable-manifest.json";

export const ROW_TIMEOUT_MS = 5000;
export const MAX_ROW_BYTES = 64 * 1024;
const ROW_KEPT_S = 60 * 60;

/** The bundle's rows for `id`, newest first. */
const bundled = (id) => (Object.hasOwn(MANIFEST.scripts, id) ? MANIFEST.scripts[id] : []).map((r) => ({ format: ROW_FORMAT, id, ...r }));

export const cacheKey = (id, revision) => new Request(`https://castable.invalid/${id}/${revision}`);

async function kept(id, revision) {
  try {
    const hit = await caches.default.match(cacheKey(id, revision));
    const row = hit ? validRow(await hit.json(), id) : null;
    return row && row.revision === revision ? row : null;
  } catch {
    return null;
  }
}

async function keep(row) {
  try {
    await caches.default.put(cacheKey(row.id, row.revision), Response.json(row, { headers: { "cache-control": `max-age=${ROW_KEPT_S}` } }));
  } catch {
    // The cache is a saving, never a requirement.
  }
}

/** The library's row for `id` now: { row }, { missing: true }, or { down: true }. `revision` only keys the caches between here and the site. */
async function published(env, id, revision) {
  try {
    const r = await fetch(`${env.PLAY_LIBRARY_URL}/castable/${id}.json?r=${revision}`, {
      headers: { accept: "application/json" },
      redirect: "manual",
      signal: AbortSignal.timeout(ROW_TIMEOUT_MS),
    });
    if (r.status === 404) return { missing: true };
    if (r.status !== 200) return { down: true };
    const text = await r.text();
    if (text.length > MAX_ROW_BYTES) return { down: true };
    const row = validRow(JSON.parse(text), id);
    return row ? { row } : { down: true };
  } catch {
    return { down: true };
  }
}

/**
 * The row for exactly this script and revision: { row }, or { refusal }.
 * `made` is the row of a production the caller has already shown is theirs.
 */
export async function castable(env, id, revision, made = null) {
  if (typeof id !== "string" || !SCRIPT_ID.test(id)) return { refusal: problem(422, "not_castable") };
  const ours = bundled(id);
  const known = [made, ...ours].find((r) => r && r.id === id && r.revision === revision);
  if (known) return { row: known };
  if (typeof revision !== "string" || !REVISION.test(revision)) return { refusal: problem(409, "revision_mismatch", ours[0]?.revision) };
  const before = await kept(id, revision);
  if (before) return { row: before };
  const found = await published(env, id, revision);
  if (found.down) return { refusal: problem(503, "library_unavailable") };
  if (found.missing) return { refusal: ours.length ? problem(409, "revision_mismatch", ours[0].revision) : problem(422, "not_castable") };
  if (found.row.revision !== revision) return { refusal: problem(409, "revision_mismatch", found.row.revision) };
  await keep(found.row);
  return found;
}

/**
 * The row a production was made from, or null. A production made before rows
 * were kept (migration 0012) was made from the bundle, so its play's bundled
 * row stands in.
 */
export function madeFrom(p) {
  if (typeof p.script_row === "string") {
    try {
      return validRow(JSON.parse(p.script_row), p.script_id);
    } catch {
      return null;
    }
  }
  const ours = bundled(p.script_id);
  return ours.find((r) => r.revision === p.script_revision) || ours[0] || null;
}

/** Whether a production of this row may go to archive.org: it is a catalog play's, it says so, and its rights bucket is a castable one. */
export const isPublishable = (row) => !!row && SCRIPT_ID.test(row.id) && row.publishable === true && publishableBucket(row.rights.bucket);
