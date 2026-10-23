// Writes listen-together-golden.json from worker/src/room-protocol.js itself, so
// the Swift port (RoomProtocolTests) is held to the Worker's own answers.
//
//   node apple/Tests/Fixtures/make-listen-together-golden.mjs          # rewrite
//   node apple/Tests/Fixtures/make-listen-together-golden.mjs --check  # fail when stale
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as P from "../../../worker/src/room-protocol.js";

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, "listen-together-golden.json");

const playing = { position: 100, playing: true, rate: 1, updated_at: 0 };
const correction = [
  [playing, 0, { position: 100.1, playing: true }],
  [playing, 0, { position: 100.149, playing: true }],
  [playing, 0, { position: 100.151, playing: true }],
  [playing, 0, { position: 101, playing: true }],
  [playing, 0, { position: 99, playing: true }],
  [playing, 0, { position: 101.99, playing: true }],
  [playing, 0, { position: 102.01, playing: true }],
  [playing, 0, { position: 103, playing: true }],
  [playing, 0, { position: 90, playing: true }],
  [playing, 0, { position: 100.5, playing: false }],
  [playing, 0, { position: 50, playing: false }],
  [{ ...playing, playing: false }, 0, { position: 100, playing: true }],
  [{ ...playing, playing: false }, 0, { position: 100.1, playing: false }],
  [{ ...playing, playing: false }, 0, { position: 101, playing: false }],
  [{ ...playing, rate: 2 }, 0, { position: 101, playing: true }],
  [{ ...playing, rate: 0.75 }, 0, { position: 99.5, playing: true }],
  [{ ...playing, rate: 1.5 }, 4000, { position: 106.5, playing: true }],
  [{ ...playing, rate: 1.25 }, 10000, { position: 100, playing: true }],
].map(([state, server_now, player]) => ({ state, server_now, player, expect: P.correction(state, server_now, player) }));

const now = 1_000_000;
const gone = now - P.MEMBER_GONE_MS - 1;
const handoff = [
  [[{ id: "host", joined_at: 1, seen_at: now }, { id: "b", joined_at: 3, seen_at: now },
    { id: "a", joined_at: 2, seen_at: gone }, { id: "c", joined_at: 3, seen_at: now }], "host"],
  [[{ id: "host", joined_at: 1, seen_at: now }], "host"],
  [[{ id: "host", joined_at: 5, seen_at: now }, { id: "z", joined_at: 2, seen_at: now },
    { id: "y", joined_at: 2, seen_at: now }, { id: "x", joined_at: 1, seen_at: gone }], "host"],
  [[{ id: "B", joined_at: 1, seen_at: now }, { id: "a", joined_at: 1, seen_at: now }], null],
  [[{ id: "host", joined_at: 1, seen_at: now }, { id: "edge", joined_at: 9, seen_at: now - P.MEMBER_GONE_MS }], "host"],
  [[], "host"],
].map(([members, leaving]) => ({ members, leaving, now, expect: P.nextHost(members, leaving, now) }));

const cur = { episode_id: "e", archive_id: "i", file: "f", position: 10, playing: true, rate: 1, updated_at: 0, generation: 3 };
const arbiter = [
  [null, { episode_id: "suspense|1948-03-11", archive_id: "OTRR_Suspense", file: "Suspense 48-03-11.mp3" }, 7],
  [null, { episode_id: "suspense|1948-03-11" }, 7],
  [null, { archive_id: "x", file: "y" }, 7],
  [cur, { playing: false }, 5000],
  [cur, { position: 42 }, 5000],
  [cur, { rate: 1.5 }, 2000],
  [cur, { rate: 1.1 }, 2000],
  [cur, { episode_id: "e2" }, 2000],
  [cur, { episode_id: "e2", archive_id: "i2", file: "dir/f2.mp3" }, 2000],
  [cur, { episode_id: "e" }, 2000],
  [cur, { archive_id: "i3" }, 2000],
  [cur, { archive_id: "i", file: "../x.mp3" }, 2000],
  [cur, { position: -1 }, 2000],
  [cur, { position: 7 * 86400 + 1 }, 2000],
  [cur, { episode_id: "" }, 2000],
  [cur, { episode_id: "a\nb", archive_id: "i", file: "f" }, 2000],
  [{ ...cur, playing: false }, { playing: true }, 9000],
].map(([current, input, n]) => ({ current, input, now: n, expect: P.applyHostState(current, input, n) }));

const copies = [
  ["item", "dir/file.mp3"], ["item", "../x.mp3"], ["item", "a/../../x"], ["item", "./x"], ["item", "a//b"],
  ["item", "/x"], ["item", "a\\b"], ["item", "a\nb"], ["item", ""], ["a/b", "x.mp3"], ["", "x.mp3"],
  ["OTRR_Certified-1.0", "Command Performance 1943-02-24 (54) Bob Hope, Bing Crosby.mp3"], ["item", "dir/"],
].map(([archive_id, file]) => ({ archive_id, file, expect: P.cleanCopy(archive_id, file) }));

const clocks = [
  [{ t0: 0, server_time: 5000, t1: 800 }, { t0: 1000, server_time: 5550, t1: 1100 }, { t0: 2000, server_time: 7000, t1: 2900 }],
  [],
  [{ t0: 10, server_time: 0, t1: 5 }],
  [{ t0: 0, server_time: 100, t1: 40 }, { t0: 50, server_time: 200, t1: 90 }],
].map((samples) => ({ samples, expect: P.clockOffset(samples) }));

const golden = {
  note: "Generated from worker/src/room-protocol.js by make-listen-together-golden.mjs. Do not edit by hand.",
  drift: { ignore_below: P.DRIFT.ignoreBelow, seek_above: P.DRIFT.seekAbove, nudge: P.DRIFT.nudge },
  member_gone_ms: P.MEMBER_GONE_MS,
  max_members: P.MAX_MEMBERS,
  speeds: P.SPEEDS,
  correction,
  handoff,
  arbiter,
  copies,
  clocks,
};
const text = JSON.stringify(golden, null, 1) + "\n";
if (process.argv.includes("--check")) {
  if (readFileSync(out, "utf8") !== text) {
    console.error("listen-together-golden.json is stale: rerun make-listen-together-golden.mjs");
    process.exit(1);
  }
  console.log("listen-together-golden.json matches room-protocol.js");
} else {
  writeFileSync(out, text);
  console.log(`wrote ${out}`);
}
