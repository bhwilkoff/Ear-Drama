/**
 * A take's audio, read from its own header rather than from what the client
 * says about it: mono WAV (Android and the web, 24-bit) or FLAC (Apple), per
 * PLAYS-DESIGN §4.4 to §4.6. Returns { type, frames, sampleRate } or null.
 */

export const MAX_TAKE_SECONDS = 300;
/** 300 s of 24-bit mono at 48 kHz is 43.2 MB; the header and a margin make 45. */
export const MAX_TAKE_BYTES = 45_000_000;

const ascii = (b, at, n) => String.fromCharCode(...b.subarray(at, at + n));

function readWav(b, total) {
  if (b.length < 44 || ascii(b, 0, 4) !== "RIFF" || ascii(b, 8, 4) !== "WAVE") return null;
  const v = new DataView(b.buffer, b.byteOffset, b.byteLength);
  let at = 12;
  let fmt = null;
  while (at + 8 <= b.length) {
    const id = ascii(b, at, 4);
    const size = v.getUint32(at + 4, true);
    const body = at + 8;
    if (id === "fmt " && size >= 16 && body + 16 <= b.length) {
      fmt = {
        format: v.getUint16(body, true),
        channels: v.getUint16(body + 2, true),
        sampleRate: v.getUint32(body + 4, true),
        bits: v.getUint16(body + 14, true),
      };
    } else if (id === "data") {
      if (!fmt || ![1, 3, 0xfffe].includes(fmt.format) || fmt.channels !== 1 || !fmt.bits || fmt.bits % 8) return null;
      if (body + size > total) return null; // the header claims more audio than was sent
      return { type: "audio/wav", ext: "wav", frames: Math.floor(size / (fmt.bits / 8)), sampleRate: fmt.sampleRate };
    }
    at = body + size + (size % 2);
  }
  return null;
}

function readFlac(b, total) {
  // "fLaC", then the STREAMINFO block (type 0, 34 bytes) must come first.
  if (b.length < 42 || ascii(b, 0, 4) !== "fLaC" || (b[4] & 0x7f) !== 0) return null;
  const s = 8;
  const sampleRate = (b[s + 10] << 12) | (b[s + 11] << 4) | (b[s + 12] >> 4);
  const channels = ((b[s + 12] >> 1) & 0x07) + 1;
  const frames = (b[s + 13] & 0x0f) * 2 ** 32 + ((b[s + 14] << 24) >>> 0) + (b[s + 15] << 16) + (b[s + 16] << 8) + b[s + 17];
  if (channels !== 1 || !sampleRate || !frames) return null;
  return { type: "audio/flac", ext: "flac", frames, sampleRate };
}

/**
 * `bytes` is the whole take, or its first bytes when `total` (the request's
 * Content-Length) says how long the whole is: a take that passes through is
 * checked from its head and never held whole (Decision 082).
 */
export function readTakeAudio(bytes, total) {
  const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  const n = total === undefined ? b.length : total;
  return readWav(b, n) || readFlac(b, n);
}

/** Bytes read before the header is judged: a WAV's fmt and data chunk headers, a FLAC's STREAMINFO. */
export const HEAD_BYTES = 64 * 1024;

/**
 * A take's body, checked as it streams and never held whole (Decision 082):
 * reads up to HEAD_BYTES to judge the header against the declared length,
 * then returns a stream that replays those bytes and passes the rest through
 * one chunk at a time, erroring if the body runs longer or shorter than its
 * Content-Length. Whoever reads the stream sees an error, not a short take.
 * Returns { audio, stream, length } or { error: [status, code, detail] }.
 */
export async function takeStream(request) {
  const declared = request.headers.get("content-length");
  if (declared === null || !/^\d{1,12}$/.test(declared)) return { error: [411, "length_required"] };
  const length = Number(declared);
  if (length > MAX_TAKE_BYTES) return { error: [413, "too_large"] };
  if (!request.body || length === 0) return { error: [415, "unsupported_audio", "mono WAV or FLAC"] };
  const reader = request.body.getReader();
  const head = [];
  let got = 0;
  while (got < Math.min(HEAD_BYTES, length)) {
    const { value, done } = await reader.read();
    if (done) break;
    head.push(value);
    got += value.byteLength;
    if (got > length) break;
  }
  const first = new Uint8Array(got);
  let at = 0;
  for (const c of head) {
    first.set(c, at);
    at += c.byteLength;
  }
  if (got > length) return { error: [413, "too_large"] };
  const audio = readTakeAudio(first, length);
  if (!audio) return { error: [415, "unsupported_audio", "mono WAV or FLAC"] };
  if (audio.frames / audio.sampleRate > MAX_TAKE_SECONDS) return { error: [413, "take_too_long", `${MAX_TAKE_SECONDS} s`] };
  let sent = 0;
  let replayed = false;
  const stream = new ReadableStream(
    {
      async pull(controller) {
        if (!replayed) {
          replayed = true;
          sent = first.byteLength;
          if (sent) return controller.enqueue(first);
        }
        const { value, done } = await reader.read();
        if (done) {
          if (sent !== length) return controller.error(new Error("take_length_mismatch"));
          return controller.close();
        }
        sent += value.byteLength;
        if (sent > length) return controller.error(new Error("take_length_mismatch"));
        controller.enqueue(value);
      },
      cancel(reason) {
        return reader.cancel(reason);
      },
    },
    { highWaterMark: 0 },
  );
  return { audio, stream, length };
}

/** Reads a take stream to its end without keeping it: the director's own take, checked and recorded only. */
export async function drain(stream) {
  const reader = stream.getReader();
  for (;;) {
    const { done } = await reader.read();
    if (done) return;
  }
}
