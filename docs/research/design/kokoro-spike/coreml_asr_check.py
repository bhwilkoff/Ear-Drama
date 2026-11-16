"""Intelligibility of the Apple model (S6e): the same published lines rendered by kokoro's own PyTorch forward (fp32,
the reference) and by our Core ML conversion through the app's own engine (CoreMLKokoroRenderer: 100-symbol pieces,
buckets, the alignment as a gather, Gaussian noise; apple/Tests/KokoroBenchTests.swift), each transcribed by a local Whisper (faster-whisper base.en, CPU) and scored by word
error rate against the line's words. The comparison between the two is the measurement (asr_check.py's method).
Nothing is played; the renders stay in the scratch dir and are deleted by hand after scoring.

  CONVERT_VENV/bin/python coreml_asr_check.py torch WORK OUT.npz [n_lines]   # PyTorch reference; writes OUT.lines.json
  TEST_RUNNER_KOKORO_BENCH_ROOT=MODEL TEST_RUNNER_KOKORO_QUALITY_LINES=OUT.lines.json TEST_RUNNER_KOKORO_QUALITY_OUT=DIR \
      xcodebuild test ... -only-testing:EarDramaTests/KokoroModelBenchTests/theRealModelRendersTheQualityLines
  ASR_VENV/bin/python     coreml_asr_check.py score OUT.npz DIR REPORT.json  # faster-whisper base.en

(coremltools 9.0 segfaults loading any Core ML model on macOS 27, so the Core ML side runs in Swift.)

WORK is tools/convert_kokoro_coreml.py's folder (the two .mlpackages, voices.bin, hf/).
"""
import json
import os
import random
import re
import sys
import urllib.request

import numpy as np

PLAYS = ["gut-1782", "gut-44302-3", "gut-70684-2", "gut-3012"]
VOICES = {"af_heart": 0, "am_michael": 16}
PIECE = 100
HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.join(HERE, "..", "..", "..", "..", "tools")


def converter():
    sys.path.insert(0, os.path.abspath(TOOLS))
    import convert_kokoro_coreml as c
    return c


def pick(n):
    rows = []
    for p in PLAYS:
        with urllib.request.urlopen(f"https://eardrama.org/data/plays/library/phonemes/{p}.json", timeout=30) as r:
            rows += [(p, l["id"], l["t"], l["us"]) for l in json.load(r)["lines"]]
    random.seed(1116)
    ok = [r for r in rows if 2 <= len(r[2].split()) <= 60 and len(r[3]) <= 400]
    return random.sample(ok, n)


def render_torch(work, out, n):
    import torch
    c = converter()
    km, config, _ = c.load_kmodel(work)
    vocab = config["vocab"]
    table = np.fromfile(os.path.join(work, "voices.bin"), dtype="<f4").reshape(28, 510, 256)
    lines = pick(n)
    torch.manual_seed(0)
    saved = {"meta": np.array(json.dumps([l[:3] for l in lines]))}
    for v, vi in VOICES.items():
        for i, (_, _, _, ps) in enumerate(lines):
            ids = c.tokens(vocab, ps)
            ref = torch.from_numpy(table[vi, ids.shape[1] - 2][None].copy())
            with torch.no_grad():
                a, _ = km.forward_with_tokens(torch.from_numpy(ids).long(), ref, 1.0)
            saved[f"torch_{v}_{i}"] = a.numpy().astype(np.float32)
            print("torch", v, i, flush=True)
    saved["phonemes"] = np.array(json.dumps([l[3] for l in lines]))
    np.savez(out, **saved)
    json.dump({"voices": VOICES, "lines": [{"play": l[0], "id": l[1], "t": l[2], "us": l[3]} for l in lines]},
              open(out[:-4] + ".lines.json", "w"), ensure_ascii=False)


def words(t):
    t = t.lower().replace("’", "'")
    t = re.sub(r"[^a-z' ]", " ", t)
    return [w.strip("'") for w in t.split() if w.strip("'")]


def wer(ref, hyp):
    r, h = words(ref), words(hyp)
    d = list(range(len(h) + 1))
    for i, a in enumerate(r, 1):
        prev, d[0] = d[0], i
        for j, b in enumerate(h, 1):
            prev, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, prev + (a != b))
    return d[-1], len(r)


def to16k(a):
    k = np.sinc(np.arange(-32, 33) / 1.5) * np.hanning(65) / 1.5  # low-pass at 8 kHz before 24 -> 16 kHz
    a = np.convolve(np.nan_to_num(a), k, mode="same")
    return np.interp(np.arange(0, len(a), 1.5), np.arange(len(a)), a).astype(np.float32)


def score(out, coreml_dir, report_path):
    from faster_whisper import WhisperModel
    z = np.load(out)
    lines = json.loads(str(z["meta"]))
    asr = WhisperModel("base.en", device="cpu", compute_type="int8")
    report = {"lines": len(lines), "plays": PLAYS, "voices": list(VOICES), "piece_symbols": PIECE, "models": {}}
    for m in ("torch", "coreml"):
        report["models"][m] = {}
        for v in VOICES:
            E = N = 0
            per = []
            for i, (play, lid, text) in enumerate(lines):
                a = z[f"torch_{v}_{i}"] if m == "torch" else \
                    np.fromfile(os.path.join(coreml_dir, f"coreml_{v}_{i}.f32"), dtype="<f4")
                segs, _ = asr.transcribe(to16k(a), beam_size=1, language="en")
                hyp = " ".join(s.text for s in segs)
                e, n = wer(text, hyp)
                E += e
                N += n
                per.append({"line": f"{play}/{lid}", "wer": round(e / max(1, n), 2), "ref": text[:90], "hyp": hyp[:90],
                            "finite": bool(np.isfinite(a).all()), "peak": round(float(np.abs(np.nan_to_num(a)).max()), 3)})
            report["models"][m][v] = {"wer_pct": round(100 * E / N, 1), "non_finite_lines": sum(not p["finite"] for p in per),
                                      "worst": sorted(per, key=lambda x: -x["wer"])[:5]}
            print(m, v, report["models"][m][v]["wer_pct"], flush=True)
    json.dump(report, open(report_path, "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "torch":
        render_torch(sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 40)
    else:
        score(sys.argv[2], sys.argv[3], sys.argv[4])
