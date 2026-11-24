// A published play library for the tests: fixture plays, never the live catalog,
// and a stand-in for https://eardrama.org that serves their castable rows. The rows
// are built here from the fixture, not by the code under test.
import { castHash } from "../src/plays-manifest.js";
import { castOf } from "./plays-helpers.js";

export const LIBRARY = "https://eardrama.org/data/plays/library";

let n = 0;
/** A small play nobody bundled: two speaking parts, three lines, at a revision of its own. */
export function fixturePlay(over = {}) {
  const num = 900000 + n++;
  return {
    id: `gut-${num}`,
    revision: num.toString(16).padStart(12, "0"),
    title: `Fixture Play ${num}`,
    source: { name: "Fixture", url: `https://www.gutenberg.org/ebooks/${num}` },
    rights: { bucket: "script_source_cleared", evidence: [{ claim: "Public domain in the USA.", src: `https://www.gutenberg.org/ebooks/${num}.rdf` }] },
    lines: [
      { id: "L0001", kind: "direction", source: "A room." },
      { id: "L0002", kind: "speech", role: "ANNA", source: "Good evening." },
      { id: "L0003", kind: "speech", role: "BEN", source: "Is it?" },
    ],
    ...over,
  };
}

export async function rowOf(play, over = {}) {
  return {
    format: 1,
    id: play.id,
    revision: play.revision,
    title: play.title,
    cast: await castHash(castOf(play)),
    lines: play.lines.length,
    source: play.source?.url ?? null,
    rights: { bucket: play.rights.bucket, evidence: play.rights.evidence },
    publishable: true,
    ...over,
  };
}

/**
 * A stand-in for the site's library. `rows` maps an id to the row served; `state.answer`
 * (id, init) answers instead, with a Response or a throw. Every request is kept.
 */
export function fakeLibrary() {
  const rows = new Map();
  const requests = [];
  const state = { answer: null };
  return {
    rows,
    requests,
    state,
    put: async (play, over) => rows.set(play.id, await rowOf(play, over)),
    handle: async (url, init = {}) => {
      if (!String(url).startsWith("https://eardrama.org/")) return undefined;
      requests.push({ url: String(url), init });
      const id = /\/castable\/([^/?]+)\.json(\?|$)/.exec(String(url))?.[1];
      if (state.answer) return await state.answer(id, init);
      const row = rows.get(id);
      return row ? Response.json(row) : new Response("<!doctype html>not found", { status: 404 });
    },
  };
}

export const bodyFor = (play, over = {}) => ({
  script_id: play.id,
  script_revision: play.revision,
  cast: castOf(play).map(([id, part]) => ({ id, part })),
  ...over,
});
