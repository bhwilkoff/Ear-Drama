// Writes src/castable-manifest.json from catalog/plays/castable-scripts.json:
// for each castable script, its revision, its title, and the SHA-256 of its
// cast sheet (src/plays-relay.js canonicalCast). A production is made only
// from a script id, revision, and cast sheet that match a row here, so the
// Worker never takes a client's word for what is castable (PLAYS-DESIGN §8
// rule 1). Run after every rebuild of the castable file:
//   node tools/castable-manifest.mjs
// test/plays.test.js fails when this file and the catalog's disagree.
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { manifestFor } from "../src/plays-manifest.js";

const here = (p) => fileURLToPath(new URL(p, import.meta.url));
const source = JSON.parse(readFileSync(here("../../catalog/plays/castable-scripts.json"), "utf8"));
const out = await manifestFor(source);
writeFileSync(here("../src/castable-manifest.json"), JSON.stringify(out, null, 1) + "\n");
console.log(`wrote ${Object.keys(out.scripts).length} castable scripts`);
