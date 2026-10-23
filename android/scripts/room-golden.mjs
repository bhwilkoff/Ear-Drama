// Writes the Listen Together golden cases Android's RoomProtocolTest checks:
// every answer below comes from worker/src/room-protocol.js itself, so the
// Kotlin port (together/RoomProtocol.kt) is held to the Worker's rules, not
// to a re-derivation. Run after any change to room-protocol.js:
//
//   node android/scripts/room-golden.mjs
//
// The file records the SHA-256 of room-protocol.js; the test fails when the
// protocol changes and this has not been run again.
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as P from "../../worker/src/room-protocol.js";

const here = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(here, "../../worker/src/room-protocol.js");
const out = join(here, "../app/src/test/resources/together/room-golden.json");

const T = 1_761_200_000_000;
const state = (position, playing, rate = 1, updatedAt = T) => ({
  episode_id: "suspense|1948-03-11",
  archive_id: "OTRR_Suspense_Singles",
  file: "Suspense 48-03-11 The Lodger.mp3",
  position,
  playing,
  rate,
  updated_at: updatedAt,
  generation: 3,
});

// [state, serverNow, player]: each threshold from both sides, both rates, paused and playing.
const driftInputs = [
  [state(100, true), T, { position: 100, playing: true }],
  [state(100, true), T, { position: 100.1, playing: true }],
  [state(100, true), T, { position: 99.86, playing: true }],
  [state(100, true), T, { position: 100.2, playing: true }],
  [state(100, true), T, { position: 99.8, playing: true }],
  [state(100, true), T, { position: 101.9, playing: true }],
  [state(100, true), T, { position: 98.1, playing: true }],
  [state(100, true), T, { position: 102.5, playing: true }],
  [state(100, true), T, { position: 97, playing: true }],
  [state(100, true), T + 4000, { position: 104.05, playing: true }],
  [state(100, true), T + 4000, { position: 103, playing: true }],
  [state(100, true, 1.5), T + 4000, { position: 106, playing: true }],
  [state(100, true, 1.5), T + 4000, { position: 105.5, playing: true }],
  [state(100, true, 0.75), T + 2000, { position: 101.5, playing: true }],
  [state(100, true, 2), T + 10000, { position: 0, playing: false }],
  [state(100, true), T, { position: 100.5, playing: false }],
  [state(100, true), T, { position: 100, playing: false }],
  [state(100, false), T + 9000, { position: 100, playing: true }],
  [state(100, false), T + 9000, { position: 100.1, playing: false }],
  [state(100, false), T, { position: 100.2, playing: false }],
  [state(100, false), T, { position: 40, playing: false }],
  [state(7 * 86400 - 1, true), T + 60000, { position: 7 * 86400, playing: true }],
];

const codeInputs = [
  "7KQ2MX", "7kq2mx", "7KQ-2MX", " 7kq 2mx ", "o1lI0O", "7KQ2M", "7KQ2MXX", "7KQ2MU", "7KQ2M!", "", "abc_def",
];

const clockInputs = [
  [],
  [{ t0: 1000, server_time: 5000, t1: 1200 }],
  [{ t0: 1000, server_time: 5000, t1: 1400 }, { t0: 2000, server_time: 6050, t1: 2100 }, { t0: 3000, server_time: 7000, t1: 3300 }],
  [{ t0: 1000, server_time: 900, t1: 1010 }],
  [{ t0: 1000, server_time: 5000, t1: 900 }, { t0: 2000, server_time: 6000, t1: 2040 }],
];

const pollInputs = [[T, T], [T, T + 59_999], [T, T + 60_000], [T, T + 60_001], [T, T + 600_000]];

const m = (id, joined, seen) => ({ id, joined_at: joined, seen_at: seen });
const handoffInputs = [
  [[m("host", T, T), m("b", T + 10, T), m("a", T + 5, T)], "host", T + 1000],
  [[m("host", T, T), m("b", T + 5, T), m("a", T + 5, T)], "host", T + 1000],
  [[m("host", T, T), m("a", T + 5, T - 200_000), m("b", T + 9, T)], "host", T + 1000],
  [[m("host", T, T)], "host", T + 1000],
  [[m("host", T, T - 130_000), m("a", T + 5, T)], null, T],
];

const golden = {
  protocol_sha256: createHash("sha256").update(readFileSync(protocolPath)).digest("hex"),
  constants: {
    code_alphabet: P.CODE_ALPHABET,
    code_length: P.CODE_LENGTH,
    max_members: P.MAX_MEMBERS,
    member_gone_ms: P.MEMBER_GONE_MS,
    speeds: P.SPEEDS,
    drift: P.DRIFT,
  },
  drift: driftInputs.map(([s, serverNow, player]) => ({
    state: s,
    server_now: serverNow,
    player,
    expected_position: P.expectedPosition(s, serverNow),
    correction: P.correction(s, serverNow, player),
  })),
  codes: codeInputs.map((typed) => ({ typed, code: P.normalizeCode(typed) })),
  clock: clockInputs.map((samples) => ({ samples, offset: P.clockOffset(samples) })),
  poll: pollInputs.map(([lastChangeAt, now]) => ({ last_change_at: lastChangeAt, now, interval: P.pollInterval(lastChangeAt, now) })),
  handoff: handoffInputs.map(([members, leaving, now]) => ({ members, leaving, now, next: P.nextHost(members, leaving, now) })),
  copies: [
    ["OTRR_Suspense_Singles", "Suspense 48-03-11 The Lodger.mp3"],
    ["a.b-c_d", "disc 1/part 2.mp3"],
    ["x", "../evil.mp3"],
    ["x", "/abs.mp3"],
    ["x", "a//b.mp3"],
    ["bad id", "a.mp3"],
    ["x", "a\\b.mp3"],
  ].map(([archiveId, file]) => ({ archive_id: archiveId, file, clean: P.cleanCopy(archiveId, file) !== null })),
};

mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, JSON.stringify(golden, null, 2) + "\n");
console.log(`wrote ${out}: ${golden.drift.length} drift, ${golden.codes.length} code, ${golden.handoff.length} handoff cases`);
