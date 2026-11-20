// Writes the read room golden cases (worker/test/read-golden.json): every
// expected answer below comes from worker/src/read-protocol.js itself, so the
// web, Swift and Kotlin ports (T3, T4) are held to the Worker's rules, not to a
// re-derivation. One file for every stack. Run after any change to the protocol:
//
//   node worker/tools/read-golden.mjs
//
// The file records the SHA-256 of read-protocol.js; the Worker's test fails
// when the protocol changes and this has not been run again.
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as P from "../src/read-protocol.js";

const here = dirname(fileURLToPath(import.meta.url));
const protocolPath = join(here, "../src/read-protocol.js");
const out = join(here, "../test/read-golden.json");

const T = 1_763_500_000_000;
const MIN = 60_000;

const cast = [
  ["l1", "directions"],
  ["l2", "role:LUCY"],
  ["l3", "role:TOM"],
  ["l4", "role:LUCY"],
  ["l5", "sound"],
  ["l6", "role:TOM"],
  ["l7", "role:NURSE"],
  ["l8", "role:LUCY"],
];
const m = (id, joined, seen, role = "reader", seat = null) => ({ id, role, seat, joined_at: T + joined, seen_at: T + seen });

const adult = P.newRoom({ code: "ABC123", kind: "adult", script_id: "gut-1", script_revision: "r1" }, cast, "host", T).room;
const adultClaimed = { ...adult, claims: { "role:LUCY": "ann", "role:TOM": "host" } };
const adultMembers = [m("host", 0, 0), m("ann", 1000, 1000), m("bob", 2000, 2000), m("tv", 500, 500, "screen")];

const seats = [
  { id: "s1", label: "Lucy" },
  { id: "s2", label: "Tom" },
  { id: "s3", label: "Group 3" },
];
const assignments = [
  { part: "role:LUCY", seat: "s1", from: "l2", to: "l4" },
  { part: "role:LUCY", seat: "s3", from: "l8", to: "l8" },
  { part: "role:TOM", seat: "s2" },
];
const klass = P.newRoom({ code: "KLS456", kind: "class", class_id: "C1", script_id: "gut-1", script_revision: "r1", seats, assignments }, cast, "teacher", T).room;
const classMembers = [m("teacher", 0, 0), m("d1", 100, 100, "reader", "s1"), m("d2", 200, 200, "reader", "s2"), m("d3", 300, 300, "reader", "s3"), m("tv", 50, 50, "screen")];

const record = { ...klass, mode: "record", cursor: "l2", cursor_gen: 0 };

const cases = [];
const add = (fn, args, note) => cases.push({ fn, note, args, expect: JSON.parse(JSON.stringify(P[fn](...args))) });

// Codes and the clock (copied from room-protocol.js; a test holds the two equal).
for (const typed of ["abc-123", "o0il1z", "ABCDE", "ABCDEFG", "ab cd ef", "ABCDEU"]) add("normalizeCode", [typed], "spellings land on one code");
add("codeFromBytes", [[0, 31, 32, 63, 200, 255]], "b % 32");
add("clockOffset", [[{ t0: 0, server_time: 1100, t1: 200 }, { t0: 1000, server_time: 2060, t1: 1040 }, { t0: 5, server_time: 9, t1: 1 }]], "smallest round trip wins");
add("clockOffset", [[]], "no samples");

// Rooms.
add("newRoom", [{ code: "ABC123", kind: "adult", script_id: "gut-1", script_revision: "r1" }, cast, "host", T], "an adult room opens on the first line, its creator leading");
add("newRoom", [{ code: "KLS456", kind: "class", class_id: "C1", script_id: "gut-1", script_revision: "r1", seats, assignments }, cast, "teacher", T], "a class room with seats and a split part");
add("newRoom", [{ code: "X", kind: "class", class_id: "C1", seats, assignments: [{ part: "role:LUCY", seat: "s1" }, { part: "role:LUCY", seat: "s3", from: "l8", to: "l8" }] }, cast, "t", T], "two assignments may not cover one line");
add("newRoom", [{ code: "X", kind: "class", class_id: "C1", seats, assignments: [{ part: "role:LUCY", seat: "s1", from: "l3", to: "l4" }] }, cast, "t", T], "a range starts on its own part's line");
add("newRoom", [{ code: "X", kind: "adult", seats }, cast, "t", T], "adult rooms have no seats");
add("newRoom", [{ code: "X", kind: "adult", mode: "sing" }, cast, "t", T], "three modes only");

// Leading.
add("canLead", [adult, "host"], "the leader leads");
add("canLead", [adult, "ann"], "a reader does not");

// Parts and lines.
add("partsOf", [adultClaimed, adultMembers[1]], "an adult's claimed parts");
add("partsOf", [klass, classMembers[1]], "a seat's assignment with its range");
add("partsOf", [klass, classMembers[4]], "a screen holds nothing");
add("whoReads", [adultClaimed, cast, adultMembers, "l4", T + 3000], "the claimant reads");
add("whoReads", [adultClaimed, cast, adultMembers, "l7", T + 3000], "nobody holds the nurse");
add("whoReads", [adultClaimed, cast, adultMembers, "l2", T + 3 * MIN], "a holder gone 2 minutes is not present");
add("whoReads", [klass, cast, classMembers, "l8", T + 1000], "a split part: the later scene's seat reads");
add("whoReads", [klass, cast, classMembers, "l2", T + 1000], "the first scene's seat reads");
add("whoReads", [klass, cast, classMembers, "zz", T], "no such line");
add("nextMine", [klass, cast, classMembers[1], "l1"], "Next: you, in 1 line");
add("nextMine", [klass, cast, classMembers[1], "l4"], "on the line now");
add("nextMine", [klass, cast, classMembers[1], "l5"], "past the seat's range: nothing left");
add("nextMine", [klass, cast, classMembers[3], "l1"], "the later seat's first line");
add("nextMine", [adultClaimed, cast, adultMembers[0], "l4"], "an adult's next line");

// The leader gone.
add("leaderGone", [klass, classMembers.map((x) => (x.id === "teacher" ? x : { ...x, seen_at: T + 5 * MIN })), T + 5 * MIN], "a class holds still for its teacher");
add("leaderGone", [adult, adultMembers.map((x) => (x.id === "host" ? x : { ...x, seen_at: T + 3 * MIN })), T + 3 * MIN], "an adult room hands to the longest present reader, never the screen");
add("leaderGone", [adult, adultMembers.map((x) => ({ ...x, seen_at: T + MIN })), T + 2 * MIN], "a leader gone under 2 minutes keeps the lead");
add("leaderGone", [adult, [m("host", 0, 0), m("tv", 1, 3 * MIN, "screen")], T + 3 * MIN], "only a screen left: the room waits");

// Claims.
add("claimInRoom", [adultClaimed, cast, adultMembers[2], "role:LUCY"], "first claim wins");
add("claimInRoom", [adultClaimed, cast, adultMembers[2], "role:NURSE"], "an open part is taken");
add("claimInRoom", [adultClaimed, cast, adultMembers[1], "role:LUCY"], "claiming your own part again changes nothing");
add("claimInRoom", [klass, cast, classMembers[1], "role:NURSE"], "a class claims only through assignments");
add("claimInRoom", [adult, cast, adultMembers[3], "role:NURSE"], "a screen holds no part");

// Joining.
add("joinRefusal", [adult, Array.from({ length: 40 }, (_, i) => m(`p${i}`, i, 0)), { role: "reader" }, T + 1000], "This reading is full");
add("joinRefusal", [adult, Array.from({ length: 39 }, (_, i) => m(`p${i}`, i, 0)), { role: "reader" }, T + 1000], "the fortieth member joins");
add("joinRefusal", [{ ...adult, locked: true }, adultMembers, { role: "reader" }, T], "joining locked");
add("joinRefusal", [klass, classMembers, { role: "reader" }, T], "a class reader needs a seat");
add("joinRefusal", [klass, classMembers, { role: "reader", seat: "s1" }, T], "a seat joins");
add("joinRefusal", [klass, classMembers, { role: "screen" }, T], "a screen joins a class without a seat");
add("takeSeat", [klass, [...classMembers, m("d9", 400, 400)], "d9", "s1", false, T + 500], "two devices, one seat");
add("takeSeat", [klass, [...classMembers, m("d9", 400, 400)], "d9", "s1", true, T + 500], "Move here");

// The cursor.
add("applyCursor", [adult, cast, "host", { line: "l2", base: 0 }, T + 10], "the leader moves the cursor");
add("applyCursor", [adult, cast, "ann", { line: "l2", base: 0 }, T + 10], "a reader cannot");
add("applyCursor", [{ ...adult, cursor: "l2", cursor_gen: 1 }, cast, "host", { line: "l2", base: 0 }, T + 20], "a retried Next is a repeat, not a second move");
add("applyCursor", [{ ...adult, cursor: "l2", cursor_gen: 1 }, cast, "host", { line: "l3", base: 0 }, T + 20], "a move from an old generation is stale");
add("applyCursor", [adult, cast, "host", { line: "nope", base: 0 }, T], "no such line");

// The arbiter.
const world = (room, members) => ({ room, cast, members });
add("applyMessage", [world(record, classMembers), "d1", { type: "line-done", line: "l2", base: 0 }, T + 1000], "record: a reader ends their line and the cursor moves on");
add("applyMessage", [world({ ...record, cursor: "l6", cursor_gen: 3 }, classMembers), "d2", { type: "line-done", line: "l6", base: 3 }, T + 1000], "lines nobody holds are skipped");
add("applyMessage", [world(record, classMembers), "d2", { type: "line-done", line: "l2", base: 0 }, T + 1000], "only the line's reader ends it");
add("applyMessage", [world({ ...record, cursor: "l3", cursor_gen: 1, done: ["l2"] }, classMembers), "d1", { type: "line-done", line: "l2", base: 0 }, T + 1000], "a repeated line-done changes nothing");
add("applyMessage", [world({ ...record, cursor: "l3", cursor_gen: 1, done: ["l2"] }, classMembers), "teacher", { type: "again", line: "l2", base: 1 }, T + 1000], "Again re-arms a line");
add("applyMessage", [world(klass, classMembers), "teacher", { type: "lead", to: "d1" }, T + 1000], "a teacher hands the lead to a seat");
add("applyMessage", [world(klass, classMembers), "teacher", { type: "lead", to: "tv" }, T + 1000], "a screen never leads");
add("applyMessage", [world({ ...klass, leader: "d1" }, classMembers), "teacher", { type: "lead", to: "teacher" }, T + 1000], "the teacher takes the lead back");
add("applyMessage", [world(adultClaimed, adultMembers), "ann", { type: "mode", mode: "record" }, T + 1000], "only the leader changes the mode");
add("applyMessage", [world(adultClaimed, adultMembers), "host", { type: "mode", mode: "rehearse" }, T + 1000], "the leader changes the mode");
add("applyMessage", [world(adultClaimed, adultMembers), "ann", { type: "release", part: "role:LUCY" }, T + 1000], "a reader releases their part");
add("applyMessage", [world(adultClaimed, adultMembers), "bob", { type: "ping", t0: 42 }, T + 1000], "a ping is a clock sample and changes nothing");
add("applyMessage", [world(adultClaimed, adultMembers), "host", { type: "lock", locked: true }, T + 1000], "Lock joining");
add("applyMessage", [world(adultClaimed, adultMembers), "host", { type: "read-open", open: true }, T + 1000], "the leader turns Read open parts on");
add("applyMessage", [world(adultClaimed, adultMembers), "ann", { type: "read-open", open: true }, T + 1000], "only the leader turns Read open parts on");
add("applyMessage", [world(adultClaimed, adultMembers), "host", { type: "read-open", open: "yes" }, T + 1000], "read-open takes a boolean");

// Settling and the snapshot.
add("settle", [adult, adultMembers.map((x) => (x.id === "host" ? x : { ...x, seen_at: T + 3 * MIN })), T + 3 * MIN], "an adult room's lead moves after 2 minutes");
add("settle", [klass, classMembers.map((x) => (x.id === "d3" ? x : { ...x, seen_at: T + 40 * MIN })), T + 40 * MIN], "a device gone 30 minutes is forgotten; its seat stays assigned");
add("settle", [klass, classMembers.map((x) => (x.id === "d3" ? x : { ...x, seen_at: T + 10 * MIN })), T + 10 * MIN], "a device gone 10 minutes keeps its place, so its key rejoins");
add("joinSnapshot", [klass, cast, classMembers, "d3", T + 1000], "a late joiner's snapshot: cursor, parts, next line");
add("joinSnapshot", [adultClaimed, cast, adultMembers, "ann", T + 1000], "an adult reader's snapshot");
add("joinSnapshot", [{ ...adultClaimed, owner: "host", owner_name: "Ben", read_open: true }, cast, adultMembers, "ann", T + 1000], "the leader's name and Read open parts travel in the snapshot");
add("joinSnapshot", [{ ...klass, leader: "d2" }, cast, classMembers, "d1", T + 1000], "a seat that leads is named by its label");

const constants = {
  PROTOCOL_VERSION: P.PROTOCOL_VERSION,
  CODE_ALPHABET: P.CODE_ALPHABET,
  CODE_LENGTH: P.CODE_LENGTH,
  MAX_MEMBERS: P.MAX_MEMBERS,
  MEMBER_GONE_MS: P.MEMBER_GONE_MS,
  LEADER_GONE_MS: P.LEADER_GONE_MS,
  MEMBER_FORGET_MS: P.MEMBER_FORGET_MS,
  SEEN_REFRESH_MS: P.SEEN_REFRESH_MS,
  ROOM_IDLE_MS: P.ROOM_IDLE_MS,
  POLL_MS: P.POLL_MS,
  MODES: P.MODES,
  KINDS: P.KINDS,
  ROLES: P.ROLES,
  MAX_SEATS: P.MAX_SEATS,
};

const sha = createHash("sha256").update(readFileSync(protocolPath)).digest("hex");
writeFileSync(out, JSON.stringify({ protocol_sha256: sha, constants, cases }, null, 1) + "\n");
console.log(`wrote ${cases.length} cases to ${out}`);
