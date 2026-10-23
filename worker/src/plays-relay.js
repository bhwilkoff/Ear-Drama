/**
 * Shared plays, phase 2: the cast sheet and the relay, as plain functions of
 * plain data (docs/PLAYS-DESIGN.md §11). No imports, so the manifest builder
 * (tools/castable-manifest.mjs) runs this file in Node as shipped.
 *
 * The part rules are js/plays-core.js's and apple/Core/Plays' (castParts,
 * linePart, the relay), carried to a production that lives on the Worker:
 *
 * C7, PENDING OWNER: strictly one part at a time, in a fixed order, largest
 * part first. Only the next open part can be claimed, and only while no other
 * part records. A finished part can be reopened for a re-take only while no
 * other part records. In phase 2 a claim lapses CLAIM_TTL_MS after it was
 * made, and the part is open again (its takes stay).
 * C6, PENDING OWNER: sound and directions may be left silent; a speaking part
 * may not.
 */

export const DIRECTIONS = "directions";
export const SOUND = "sound";
export const CLAIM_TTL_MS = 7 * 24 * 60 * 60 * 1000;
export const MAX_LINES = 20000;

export const isSpeaking = (part) => typeof part === "string" && part.startsWith("role:");

/** The part a script line belongs to (js/plays-core.js linePart). */
export function partOfLine(line) {
  if (line.kind === "speech") return `role:${line.role || ""}`;
  if (line.kind === "direction") return DIRECTIONS;
  return SOUND;
}

/** The cast sheet as one string, hashed into the manifest: `id\tpart` per line. */
export function canonicalCast(lines) {
  return lines.map(([id, part]) => `${id}\t${part}`).join("\n");
}

/**
 * Validates a client's cast sheet: `[{ id, part }]` or `[[id, part]]` in script
 * order. Returns `[[id, part], ...]` or null.
 */
export function parseCast(raw) {
  if (!Array.isArray(raw) || raw.length < 1 || raw.length > MAX_LINES) return null;
  const out = [];
  const seen = new Set();
  for (const l of raw) {
    const id = Array.isArray(l) ? l[0] : l && l.id;
    const part = Array.isArray(l) ? l[1] : l && l.part;
    if (typeof id !== "string" || id.length < 1 || id.length > 64 || /[\u0000-\u001f\t\n]/.test(id)) return null;
    if (typeof part !== "string" || part.length > 160 || /[\u0000-\u001f]/.test(part)) return null;
    if (!(part === DIRECTIONS || part === SOUND || (isSpeaking(part) && part.length > 5))) return null;
    if (seen.has(id)) return null;
    seen.add(id);
    out.push([id, part]);
  }
  return out;
}

/** Speaking parts largest first (by lines, then first appearance), then sound, then directions. */
export function castParts(cast) {
  const counts = new Map();
  const first = new Map();
  cast.forEach(([, part], i) => {
    counts.set(part, (counts.get(part) || 0) + 1);
    if (!first.has(part)) first.set(part, i);
  });
  const speaking = [...counts.keys()]
    .filter(isSpeaking)
    .sort((a, b) => counts.get(b) - counts.get(a) || first.get(a) - first.get(b));
  const others = [SOUND, DIRECTIONS].filter((p) => counts.has(p));
  return [...speaking, ...others].map((id) => ({ id, lineCount: counts.get(id) }));
}

export const linesOf = (cast, part) => cast.filter(([, p]) => p === part).map(([id]) => id);
export const partOf = (cast, lineID) => {
  const l = cast.find(([id]) => id === lineID);
  return l ? l[1] : null;
};

/**
 * A part's status now: 'open' when it has no row or its claim lapsed.
 * `rows` maps part -> { status, user_id, claimed_at }.
 */
export function statusOf(rows, part, now) {
  const r = rows[part];
  if (!r) return "open";
  if (r.status === "recording" && now - r.claimed_at > CLAIM_TTL_MS) return "open";
  return r.status;
}

export function current(cast, rows, now) {
  return castParts(cast).map((p) => p.id).find((id) => statusOf(rows, id, now) === "recording") || null;
}

export function next(cast, rows, now) {
  if (current(cast, rows, now)) return null;
  return castParts(cast).map((p) => p.id).find((id) => statusOf(rows, id, now) === "open") || null;
}

/** null when `part` may be claimed now, or the refusal. */
export function claimRefusal(cast, rows, part, now) {
  if (!castParts(cast).some((p) => p.id === part)) return { error: "no_such_part" };
  const cur = current(cast, rows, now);
  if (cur) return { error: "another_part_is_recording", detail: cur };
  const nx = next(cast, rows, now);
  if (nx !== part) return { error: "not_next", detail: nx };
  return null;
}

/** True when `userId` holds a live claim on `part`. */
export function isClaimant(rows, part, userId, now) {
  return statusOf(rows, part, now) === "recording" && rows[part].user_id === userId;
}

/** "Done with this part": a speaking part is done only when every one of its lines has a chosen take. */
export function finishRefusal(cast, rows, part, userId, chosenLines, now) {
  if (!isClaimant(rows, part, userId, now)) return { error: "not_your_claim" };
  if (isSpeaking(part)) {
    const missing = linesOf(cast, part).filter((id) => !chosenLines.has(id));
    if (missing.length) return { error: "lines_missing", detail: missing.slice(0, 50) };
  }
  return null;
}

export function silentRefusal(cast, rows, part, userId, now) {
  if (isSpeaking(part)) return { error: "speaking_part_needs_a_voice" };
  if (isClaimant(rows, part, userId, now)) return null;
  const nx = next(cast, rows, now);
  return nx === part ? null : { error: "not_next", detail: nx };
}

export function reopenRefusal(cast, rows, part, userId, directorId, now) {
  const cur = current(cast, rows, now);
  if (cur) return { error: "another_part_is_recording", detail: cur };
  const st = statusOf(rows, part, now);
  if (st !== "done" && st !== "silent") return { error: "not_finished" };
  if (rows[part].user_id !== userId && directorId !== userId) return { error: "not_your_part" };
  return null;
}

/** What still stands between a production and its upload: open parts and unvoiced speech. */
export function incomplete(cast, rows, chosenLines, now) {
  const parts = castParts(cast)
    .map((p) => p.id)
    .filter((id) => !["done", "silent"].includes(statusOf(rows, id, now)));
  const lines = cast.filter(([id, part]) => isSpeaking(part) && !chosenLines.has(id)).map(([id]) => id);
  return parts.length || lines.length ? { parts, lines: lines.slice(0, 50) } : null;
}
