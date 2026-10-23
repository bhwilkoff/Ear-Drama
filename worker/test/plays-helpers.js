// Shared plays test helpers. Scripts come from the real castable file and are
// picked from its data, never named (a rebuilt catalog must not break a test).
import catalog from "../../catalog/plays/castable-scripts.json";
import { call, env } from "./helpers.js";
import { castParts, partOfLine, linesOf } from "../src/plays-relay.js";
import { CONSENT_VERSION } from "../src/plays.js";

export { catalog };

export const castOf = (script) => script.lines.map((l) => [l.id, partOfLine(l)]);

/** The castable script with the most parts, so every relay rule has room to act. */
export const script = [...catalog.scripts].sort((a, b) => castParts(castOf(b)).length - castParts(castOf(a)).length)[0];
export const cast = castOf(script);
export const order = castParts(cast).map((p) => p.id);
export const firstPart = order[0];
export const secondPart = order[1];
export const linesFor = (part) => linesOf(cast, part);

export const createBody = (over = {}) => ({
  script_id: script.id,
  script_revision: script.revision,
  cast: cast.map(([id, part]) => ({ id, part })),
  ...over,
});

export async function createProduction(s, over = {}) {
  const r = await call("POST", "/v1/plays/productions", { token: s.access_token, body: createBody(over) });
  if (r.status !== 201) throw new Error(`create failed: ${r.status} ${await r.text()}`);
  return r.json();
}

export async function invite(s, pid, body = {}) {
  const r = await call("POST", `/v1/plays/productions/${pid}/invites`, { token: s.access_token, body });
  if (r.status !== 201) throw new Error(`invite failed: ${r.status} ${await r.text()}`);
  return r.json();
}

export const claimByInvite = (s, token, part, extra = {}) =>
  call("POST", "/v1/plays/invites/claim", { token: s.access_token, body: { token, part, ...extra } });

export const claim = (s, pid, part) => call("POST", `/v1/plays/productions/${pid}/claim`, { token: s.access_token, body: { part } });

export const consent = (s, pid, version = CONSENT_VERSION) =>
  call("POST", `/v1/plays/productions/${pid}/consent`, { token: s.access_token, body: { version } });

export const partAction = (s, pid, part, action) =>
  call("POST", `/v1/plays/productions/${pid}/parts/${encodeURIComponent(part)}/${action}`, { token: s.access_token });

export const record = async (s, pid) => (await call("GET", `/v1/plays/productions/${pid}`, { token: s.access_token })).json();

/** A mono WAV of `frames` silent samples. */
export function wav(frames, { rate = 48000, bits = 24, channels = 1, claim: claimed } = {}) {
  const bytesPer = bits / 8;
  const data = frames * bytesPer * channels;
  const b = new Uint8Array(44 + data);
  const v = new DataView(b.buffer);
  const put = (at, s) => [...s].forEach((c, i) => (b[at + i] = c.charCodeAt(0)));
  put(0, "RIFF");
  v.setUint32(4, 36 + data, true);
  put(8, "WAVE");
  put(12, "fmt ");
  v.setUint32(16, 16, true);
  v.setUint16(20, 1, true);
  v.setUint16(22, channels, true);
  v.setUint32(24, rate, true);
  v.setUint32(28, rate * bytesPer * channels, true);
  v.setUint16(32, bytesPer * channels, true);
  v.setUint16(34, bits, true);
  put(36, "data");
  v.setUint32(40, claimed ?? data, true);
  return b;
}

/** A FLAC stream header (STREAMINFO only) claiming `frames` mono samples. */
export function flac(frames, { rate = 48000, channels = 1 } = {}) {
  const b = new Uint8Array(42 + 16);
  b.set([0x66, 0x4c, 0x61, 0x43], 0); // fLaC
  b[4] = 0x80; // last block, STREAMINFO
  b[7] = 34;
  const s = 8;
  b[s + 10] = (rate >> 12) & 0xff;
  b[s + 11] = (rate >> 4) & 0xff;
  b[s + 12] = ((rate & 0x0f) << 4) | ((channels - 1) << 1) | 1; // 24 bits per sample: (24 - 1) = 0b10111 spans this byte and the next
  b[s + 13] = (0x07 << 4) | Math.floor(frames / 2 ** 32);
  b[s + 14] = (frames >>> 24) & 0xff;
  b[s + 15] = (frames >>> 16) & 0xff;
  b[s + 16] = (frames >>> 8) & 0xff;
  b[s + 17] = frames & 0xff;
  return b;
}

let takeCounter = 0;
export const newTakeId = () => `TAKE-${Date.now().toString(36)}-${(takeCounter++).toString(36).padStart(4, "0")}`;

/** Uploads one take; `meta` overrides the x-take fields. */
export function upload(s, pid, lineID, { id = newTakeId(), bytes = wav(48000), meta = {}, headers = {} } = {}) {
  const fields = { lineID, frames: 48000, sampleRate: 48000, capture: "direct", heard: {}, peak: 0.5, loudness: -18, bleed: false, ...meta };
  return call("PUT", `/v1/plays/productions/${pid}/takes/${id}`, {
    token: s.access_token,
    body: bytes,
    headers: { "content-type": "audio/wav", "x-take": JSON.stringify(fields), ...headers },
  }).then((r) => Object.assign(r, { takeId: id }));
}

/** Writes chosen takes straight into D1 for `lineIDs` (a long part, without uploading each line); a line already chosen keeps its take. */
export async function seedChosen(pid, userId, lineIDs, part) {
  const now = Date.now();
  const stmts = lineIDs.map((line, i) =>
    env.DB.prepare(
      "INSERT INTO play_takes (production_id, id, user_id, line_id, part, file, object_key, content_type, bytes, frames, sample_rate, capture, created, uploaded_at, chosen) " +
        "VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 'audio/wav', 100, 48000, 48000, 'direct', 0, ?8, " +
        "NOT EXISTS (SELECT 1 FROM play_takes WHERE production_id = ?1 AND line_id = ?4 AND chosen = 1))",
    ).bind(pid, `SEED-${pid.slice(0, 8)}-${part.length}-${i}-${line}`, userId, line, part, `seed-${i}.wav`, `plays/${pid}/seed-${part}-${i}-${line}`, now),
  );
  for (let i = 0; i < stmts.length; i += 200) await env.DB.batch(stmts.slice(i, i + 200));
}
