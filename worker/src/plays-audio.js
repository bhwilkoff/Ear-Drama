/**
 * A take's audio, read from its own header rather than from what the client
 * says about it: mono WAV (Android and the web, 24-bit) or FLAC (Apple), per
 * PLAYS-DESIGN §4.4 to §4.6. Returns { type, frames, sampleRate } or null.
 */

export const MAX_TAKE_SECONDS = 300;
/** 300 s of 24-bit mono at 48 kHz is 43.2 MB; the header and a margin make 45. */
export const MAX_TAKE_BYTES = 45_000_000;

const ascii = (b, at, n) => String.fromCharCode(...b.subarray(at, at + n));

function readWav(b) {
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
      if (body + size > b.length) return null; // the header claims more audio than was sent
      return { type: "audio/wav", ext: "wav", frames: Math.floor(size / (fmt.bits / 8)), sampleRate: fmt.sampleRate };
    }
    at = body + size + (size % 2);
  }
  return null;
}

function readFlac(b) {
  // "fLaC", then the STREAMINFO block (type 0, 34 bytes) must come first.
  if (b.length < 42 || ascii(b, 0, 4) !== "fLaC" || (b[4] & 0x7f) !== 0) return null;
  const s = 8;
  const sampleRate = (b[s + 10] << 12) | (b[s + 11] << 4) | (b[s + 12] >> 4);
  const channels = ((b[s + 12] >> 1) & 0x07) + 1;
  const frames = (b[s + 13] & 0x0f) * 2 ** 32 + ((b[s + 14] << 24) >>> 0) + (b[s + 15] << 16) + (b[s + 16] << 8) + b[s + 17];
  if (channels !== 1 || !sampleRate || !frames) return null;
  return { type: "audio/flac", ext: "flac", frames, sampleRate };
}

export function readTakeAudio(bytes) {
  const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  return readWav(b) || readFlac(b);
}
