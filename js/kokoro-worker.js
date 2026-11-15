/**
 * Kokoro-82M inference off the main thread (PROTOTYPE, Decision 076 S6; R2-kokoro-feasibility.md).
 * Receives the model and the voice table as bytes, returns each line's samples (24 kHz mono)
 * as a transferred Float32Array. Keeps nothing: no storage, no network but the runtime itself.
 *
 * The runtime is onnxruntime-web (MIT), WASM only, single-threaded: eardrama.org cannot send the
 * cross-origin isolation headers threads need. PROTOTYPE loads it from jsDelivr at a pinned
 * version; the shipped build self-hosts it.
 */
/* global ort */
'use strict';
const ORT = 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.31.1/dist/';
let session = null;
let table = null;
const STYLE = 256;
const ROWS = 510;

self.onmessage = async (e) => {
  const m = e.data;
  try {
    if (m.type === 'load') {
      // WebGPU where the browser has it and the caller asks (the spike measures both); else WASM.
      const gpu = !!(m.ep === 'webgpu' && self.navigator && navigator.gpu);
      importScripts(`${ORT}${gpu ? 'ort.webgpu.min.js' : 'ort.wasm.min.js'}`);
      ort.env.wasm.wasmPaths = ORT;
      ort.env.wasm.numThreads = 1;
      session = await ort.InferenceSession.create(new Uint8Array(m.model), { executionProviders: gpu ? ['webgpu', 'wasm'] : ['wasm'] });
      table = new Float32Array(m.voices);
      self.postMessage({ id: m.id, ok: true, ep: gpu ? 'webgpu' : 'wasm' });
      return;
    }
    if (m.type === 'synth') {
      const t0 = performance.now();
      const ids = m.tokens;
      const n = Math.min(ids.length - 2, ROWS - 1);
      const at = (m.voice * ROWS + n) * STYLE;
      const style = table.slice(at, at + STYLE);
      const feeds = {
        input_ids: new ort.Tensor('int64', BigInt64Array.from(ids, BigInt), [1, ids.length]),
        style: new ort.Tensor('float32', style, [1, STYLE]),
        speed: new ort.Tensor('float32', Float32Array.of(m.speed), [1]),
      };
      const out = await session.run(feeds);
      const samples = out[session.outputNames[0]].data;
      const copy = new Float32Array(samples);
      // fp16 renders NaN on CPU and WebGPU (R2-kokoro-feasibility §3): silence is refused, never played.
      let bad = 0;
      for (let i = 0; i < copy.length; i++) if (!Number.isFinite(copy[i])) bad++;
      if (bad) { self.postMessage({ id: m.id, error: `${bad} non-finite samples` }); return; }
      self.postMessage({ id: m.id, samples: copy, ms: performance.now() - t0 }, [copy.buffer]);
    }
  } catch (err) {
    self.postMessage({ id: m.id, error: String(err && err.message || err) });
  }
};
