/**
 * Listen Together: the room protocol and its arbiter (LOOP-PLAN M6).
 *
 * PURE. This file imports nothing and touches no network, clock, or store:
 * every function takes `now` and returns a value. The Worker's HTTP + D1
 * adapter (rooms.js) is one transport; SharePlay on Apple is meant to carry
 * the same state shape later, and the clients port these rules (AGENTS.md
 * "Shared data": protocol and arbiter with no networking import, each
 * transport a thin adapter).
 *
 * Ported from Archive Watch's Watch Together (worker/src/together.js and
 * docs/SHAREPLAY.md §11): the host publishes STATE, never the playhead; the
 * server is the clock; guests correct by rate before seeking; the host is
 * authoritative and a stalled guest catches up; the room carries the host's
 * exact copy and every guest plays that file (Archive Watch Decision 143).
 * What is new: the host is a member, not a separate key, so when the host
 * leaves the longest-present member takes over instead of the room dying.
 */

export const PROTOCOL_VERSION = 1;

/** Crockford Base32: no I, L, O, or U, so every spelling a listener hears lands on one code. */
export const CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
/**
 * Six characters, not Archive Watch's four. A join needs only the code, so the
 * code is what keeps a stranger out: 32^6 is 1,073,741,824 codes, so with 1,000
 * live rooms one guess lands on a room 1 time in 1,073,741, and the per-address
 * join limit (20 a minute) puts that past two years of guessing from one address.
 */
export const CODE_LENGTH = 6;

export const MAX_MEMBERS = 20;
/** A member not heard from for this long has left: four missed 30 s reads, and a background browser tab still reads once a minute. */
export const MEMBER_GONE_MS = 2 * 60 * 1000;
/** A member's own read refreshes its presence only when older than this, so a 2 s poll is not a D1 write. */
export const SEEN_REFRESH_MS = 20 * 1000;
/** A room whose state has not changed for this long is over (longer than any broadcast evening's gap). */
export const ROOM_IDLE_MS = 6 * 60 * 60 * 1000;

/** Decision 062: the five player speeds. A room carries the host's chosen speed, never a drift nudge. */
export const SPEEDS = [0.75, 1, 1.25, 1.5, 2];
const MAX_POSITION_S = 7 * 86400;

/** Drift correction (Archive Watch SHAREPLAY §11.3). Seconds. */
export const DRIFT = {
  ignoreBelow: 0.15,
  seekAbove: 2,
  nudge: 0.03,
  pollFastMs: 2000,
  pollSlowMs: 10000,
  slowAfterStillMs: 60000,
};

/** The same normalization on every stack, or a code read aloud reaches different rooms. */
export function normalizeCode(typed) {
  if (typeof typed !== "string") return null;
  let out = "";
  for (const ch of typed.toUpperCase()) {
    if (ch === " " || ch === "-" || ch === "_") continue;
    if (ch === "I" || ch === "L") {
      out += "1";
      continue;
    }
    if (ch === "O") {
      out += "0";
      continue;
    }
    if (!CODE_ALPHABET.includes(ch)) return null;
    out += ch;
  }
  return out.length === CODE_LENGTH ? out : null;
}

/** Bytes from a CSPRNG in, a code out. 256 is a multiple of 32, so `b % 32` is unbiased. */
export function codeFromBytes(bytes) {
  let out = "";
  for (let i = 0; i < CODE_LENGTH; i++) out += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
  return out;
}

/** The catalog's episode ids (`{seriesKey}|{YYYY-MM-DD}` and the like): printable, bounded. */
export function cleanEpisodeId(v) {
  if (typeof v !== "string" || v.length < 1 || v.length > 200) return null;
  if (/[\u0000-\u001f\u007f]/.test(v)) return null;
  return v;
}

const ARCHIVE_ID = /^[A-Za-z0-9._-]{1,100}$/;

/**
 * THE HOST'S COPY: an archive.org identifier and a file name inside it, never
 * a URL. Every client builds https://archive.org/download/<id>/<file> itself,
 * so a room can never point a guest's player at another host or another item.
 */
export function cleanCopy(archiveId, file) {
  if (typeof archiveId !== "string" || !ARCHIVE_ID.test(archiveId)) return null;
  if (typeof file !== "string" || file.length < 1 || file.length > 400) return null;
  if (file.startsWith("/") || file.includes("\\") || /[\u0000-\u001f\u007f]/.test(file)) return null;
  if (file.split("/").some((part) => part === ".." || part === "." || part === "")) return null;
  return { archive_id: archiveId, file };
}

function position(v) {
  const n = Number(v);
  return Number.isFinite(n) && n >= 0 && n <= MAX_POSITION_S ? n : null;
}

/**
 * THE ARBITER. The host proposes; this returns the next state or a refusal.
 * `updated_at` is the SERVER's clock when `position` was true, set here and
 * never taken from a client. The generation is bumped here, so two writers
 * cannot disagree about it. A missing field keeps the current value, except
 * that a new episode must name its copy: keeping the old copy for a new
 * episode would put every guest on another recording.
 *
 * `current` is null when the room is being created.
 */
export function applyHostState(current, input, now) {
  if (!input || typeof input !== "object" || Array.isArray(input)) return { error: "state must be an object" };
  const next = current
    ? { ...current }
    : { episode_id: null, archive_id: null, file: null, position: 0, playing: false, rate: 1, generation: 0 };

  if (input.episode_id !== undefined) {
    const id = cleanEpisodeId(input.episode_id);
    if (!id) return { error: "bad episode_id" };
    if (id !== next.episode_id && (input.archive_id === undefined || input.file === undefined)) {
      return { error: "a new episode needs its archive_id and file" };
    }
    next.episode_id = id;
  }
  if (input.archive_id !== undefined || input.file !== undefined) {
    const copy = cleanCopy(input.archive_id, input.file);
    if (!copy) return { error: "bad copy" };
    next.archive_id = copy.archive_id;
    next.file = copy.file;
  }
  if (!next.episode_id || !next.archive_id) return { error: "episode_id, archive_id and file are required" };

  if (input.position !== undefined) {
    const p = position(input.position);
    if (p === null) return { error: "bad position" };
    next.position = p;
  } else if (current) {
    next.position = expectedPosition(current, now);
  }
  if (input.playing !== undefined) {
    if (typeof input.playing !== "boolean") return { error: "playing must be true or false" };
    next.playing = input.playing;
  }
  if (input.rate !== undefined) {
    if (!SPEEDS.includes(input.rate)) return { error: "rate must be one of 0.75, 1, 1.25, 1.5, 2" };
    next.rate = input.rate;
  }
  next.updated_at = now;
  next.generation = (current ? current.generation : 0) + 1;
  return { state: next };
}

/** Where the host's player is at server time `now`, extrapolated from the last state. */
export function expectedPosition(state, now) {
  if (!state.playing) return state.position;
  return Math.min(MAX_POSITION_S, state.position + ((now - state.updated_at) / 1000) * state.rate);
}

/** Members still present at `now`. A member is `{ id, joined_at, seen_at }`. */
export function liveMembers(members, now) {
  return members.filter((m) => now - m.seen_at <= MEMBER_GONE_MS);
}

/**
 * HOST HANDOFF. When the host leaves or goes quiet, the member who has been in
 * the room longest takes over (ties by id, so every server picks the same one).
 * Null means nobody is left and the room ends.
 */
export function nextHost(members, leavingId, now) {
  const left = liveMembers(members, now).filter((m) => m.id !== leavingId);
  left.sort((a, b) => a.joined_at - b.joined_at || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return left.length ? left[0].id : null;
}

/** Whether a room is past its idle limit. */
export function roomExpired(room, now) {
  return now - room.touched_at > ROOM_IDLE_MS;
}

/** The state every member reads. Guests get the host's copy; nobody gets a key. */
export function publicState(s) {
  return {
    episode_id: s.episode_id,
    archive_id: s.archive_id,
    file: s.file,
    position: s.position,
    playing: s.playing,
    rate: s.rate,
    updated_at: s.updated_at,
  };
}

/** The room message: what a read answers, and what SharePlay would carry. */
export function roomSnapshot({ code, state, role, members, now }) {
  return {
    v: PROTOCOL_VERSION,
    code,
    role,
    members,
    generation: state.generation,
    state: publicState(state),
    server_time: now,
  };
}

/**
 * THE CLOCK (Cristian's algorithm). Each sample is `{ t0, server_time, t1 }`
 * from one read: offset = server - (t0 + t1) / 2, wrong by at most RTT / 2. The
 * sample with the smallest round trip wins; an average would throw the bound away.
 * Returns the offset to ADD to the local clock, or null with no samples.
 */
export function clockOffset(samples) {
  let best = null;
  for (const s of samples) {
    const rtt = s.t1 - s.t0;
    if (!(rtt >= 0)) continue;
    if (!best || rtt < best.rtt) best = { rtt, offset: s.server_time - (s.t0 + s.t1) / 2 };
  }
  return best ? best.offset : null;
}

/**
 * DRIFT CORRECTION, as a value the player applies (Archive Watch SHAREPLAY §11.3).
 * `serverNow` is the local clock plus `clockOffset`; `player` is the guest's
 * `{ position, playing }`. Nobody is asked to do anything: the app applies
 * the answer silently.
 *
 * - play/pause follows the host at once, never nudged;
 * - under 150 ms off: nothing;
 * - 150 ms to 2 s: play at the host's rate x 0.97 or 1.03 until inside 150 ms;
 * - over 2 s: seek, since a nudge would take a minute to close it;
 * - a guest who stalled catches up; the room never waits for them.
 */
export function correction(state, serverNow, player) {
  const target = expectedPosition(state, serverNow);
  if (!state.playing) {
    if (player.playing) return { action: "pause", position: target };
    return Math.abs(player.position - target) > DRIFT.ignoreBelow ? { action: "seek", position: target } : { action: "none" };
  }
  const off = player.position - target;
  const far = Math.abs(off);
  if (far > DRIFT.seekAbove) return { action: "seek", position: target, play: true };
  if (!player.playing) return { action: "play", position: target, rate: state.rate };
  if (far < DRIFT.ignoreBelow) return { action: "rate", rate: state.rate };
  return { action: "rate", rate: state.rate * (off > 0 ? 1 - DRIFT.nudge : 1 + DRIFT.nudge) };
}

/** How long a member waits before its next read: fast while things change, slow when still. */
export function pollInterval(lastChangeAt, now) {
  return now - lastChangeAt > DRIFT.slowAfterStillMs ? DRIFT.pollSlowMs : DRIFT.pollFastMs;
}
