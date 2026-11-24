// The castable manifest, from the two places plays come from. A production is made only from a
// script id, revision, and cast sheet that match a row (src/plays-castable.js), so the Worker
// never takes a client's word for what is castable (PLAYS-DESIGN §8 rule 1).
//
//   node worker/tools/castable-manifest.mjs
//       rebuilds src/castable-manifest.json from catalog/plays/castable-scripts.json, keeping the
//       revisions it already held. Run after every rebuild of the bundle; test/plays.test.js fails
//       when the two disagree.
//
//   node worker/tools/castable-manifest.mjs --library DIR
//       writes DIR/castable/<id>.json, one row a play, from the index.json and scripts/ in DIR, then
//       checks them. tools/assemble_site.sh runs it on the library it is about to deploy, so a
//       library refresh carries its own manifest and nobody has to remember it;
//       tools/refresh_play_library.sh runs it on a copy before it uploads.
//
//   node worker/tools/castable-manifest.mjs --check DIR
//       fails, naming the plays, when DIR/castable lags the library beside it.
import { mkdirSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { isDeepStrictEqual } from "node:util";
import { ROW_FORMAT, SCRIPT_ID, manifestFor, rowFor, validRow } from "../src/plays-manifest.js";

const read = (path) => JSON.parse(readFileSync(path, "utf8"));

/** Each play of the library in `dir` with its row, or a throw naming the play that has none. */
export async function libraryRows(dir) {
  const rows = new Map();
  for (const p of read(join(dir, "index.json")).plays) {
    if (typeof p.id !== "string" || !SCRIPT_ID.test(p.id)) throw new Error(`the Worker would refuse the id ${JSON.stringify(p.id)} (SCRIPT_ID, worker/src/plays-manifest.js)`);
    const s = read(join(dir, "scripts", `${p.id}.json`)).scripts.find((x) => x.id === p.id);
    if (!s) throw new Error(`scripts/${p.id}.json does not hold ${p.id}`);
    if (s.revision !== p.revision) throw new Error(`${p.id}: the index says ${p.revision}, its script ${s.revision}`);
    const row = validRow({ format: ROW_FORMAT, id: p.id, ...(await rowFor(s)) }, p.id);
    if (!row) throw new Error(`${p.id}: the Worker would refuse its row (validRow, worker/src/plays-manifest.js)`);
    rows.set(p.id, row);
  }
  return rows;
}

export async function writeLibrary(dir) {
  const rows = await libraryRows(dir);
  const out = join(dir, "castable");
  rmSync(out, { recursive: true, force: true });
  mkdirSync(out, { recursive: true });
  for (const [id, row] of rows) writeFileSync(join(out, `${id}.json`), JSON.stringify(row));
  return rows.size;
}

/** What is wrong with DIR/castable for the library in DIR, one clear line, or null. */
export async function lag(dir) {
  const rows = await libraryRows(dir);
  let files = [];
  try {
    files = readdirSync(join(dir, "castable")).sort();
  } catch {
    // No castable/ at all: every play lacks a row.
  }
  const here = new Map(
    files.map((f) => {
      const id = f.replace(/\.json$/, "");
      try {
        return [id, read(join(dir, "castable", f))];
      } catch {
        return [id, null];
      }
    }),
  );
  const missing = [...rows.keys()].filter((id) => !here.has(id));
  const other = [...rows].filter(([id, row]) => here.has(id) && !isDeepStrictEqual(here.get(id), row)).map(([id]) => id);
  const gone = [...here.keys()].filter((id) => !rows.has(id));
  const say = (n, ids, what) => (n ? [`${n} ${what} (${ids.slice(0, 5).join(", ")}${n > 5 ? ", ..." : ""})`] : []);
  const faults = [
    ...say(missing.length, missing, "without a row"),
    ...say(other.length, other, "whose row is not the script's"),
    ...say(gone.length, gone, "rows for plays the library does not hold"),
  ];
  if (!faults.length) return null;
  return `the castable manifest lags the play library: of ${rows.size} plays, ${faults.join("; ")}. Rebuild: node worker/tools/castable-manifest.mjs --library ${dir}`;
}

async function main([mode, dir]) {
  if (mode === undefined) {
    const here = (p) => fileURLToPath(new URL(p, import.meta.url));
    const path = here("../src/castable-manifest.json");
    const out = await manifestFor(read(here("../../catalog/plays/castable-scripts.json")), read(path));
    writeFileSync(path, JSON.stringify(out, null, 1) + "\n");
    console.log(`wrote ${Object.keys(out.scripts).length} castable scripts`);
    return 0;
  }
  if (!["--library", "--check"].includes(mode) || !dir) {
    console.error("usage: castable-manifest.mjs [--library DIR | --check DIR]");
    return 2;
  }
  const wrote = mode === "--library" ? await writeLibrary(dir) : null;
  const fault = await lag(dir);
  if (fault) {
    console.error(fault);
    return 1;
  }
  console.log(wrote === null ? `castable manifest ok: ${dir}` : `castable manifest: ${wrote} plays, at ${join(dir, "castable")}`);
  return 0;
}

// realpath: run through a symlinked path, a plain comparison would be false and the build would pass having done nothing.
if (process.argv[1] && fileURLToPath(import.meta.url) === realpathSync(process.argv[1])) {
  process.exitCode = await main(process.argv.slice(2)).catch((e) => {
    console.error(`castable manifest: ${e.message}`);
    return 1;
  });
}
