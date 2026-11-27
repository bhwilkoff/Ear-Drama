#!/usr/bin/env python3
"""Publish the Kokoro voice model (Decision 078) as versioned assets of the `kokoro-model` Release.

    python3 tools/publish_kokoro_model.py WORK_DIR [--version 1] [--native q8f16|q8] [--native-only] [--no-upload]
    python3 tools/publish_kokoro_model.py WORK_DIR --coreml CONVERTED_DIR --version 3 [--no-upload]
    python3 tools/publish_kokoro_model.py WORK_DIR --web-w16 --version 5 [--no-upload]   # needs `onnx` (pip)

Fetches the pinned ONNX export from Hugging Face into WORK_DIR (or reuses files already there), checks
every file against the SHA-256 Hugging Face records for it at that revision, builds the 28-voice table,
and uploads, never overwriting an existing asset:

  kokoro-vN-model_q8f16.onnx     the native model (Apple, Android: CPU paths; R2-kokoro-feasibility §3), or with
                                 --native q8, kokoro-vN-model_q8.onnx (model_quantized.onnx: fp32 activations; the
                                 q8f16 file renders NaN on ONNX Runtime Android, S6a)
  kokoro-vN-voices-en.bin        28 English voices, one float32 table (28 x 510 x 256), VOICES order
  kokoro-vN-tokenizer.json       the phoneme vocabulary
  kokoro-vN-manifest.json        the native manifest: each file's asset name, role, bytes, SHA-256, license
  kokoro-vN-web-model.onnx.partNN  the web's fp32 model (WebGPU only; fp16 is NaN) in parts under 50 MB
  kokoro-vN-web-manifest.json    the web manifest, with paths as served under <site>/data/kokoro/ and each
                                 file's Release `asset`; tools/fetch_kokoro_model.py places it at site build

--native-only publishes the native files and manifest alone (the web keeps the version it has).

--coreml publishes the Apple model instead (S6e): CONVERTED_DIR is tools/convert_kokoro_coreml.py's output (the two
multifunction .mlpackages and kokoro-coreml-report.json). Each file inside a package becomes one asset (a Release
asset is a file, and iOS has no unzip API), named kokoro-vN-<its place with / as ->, and
kokoro-vN-apple-manifest.json lists each with its role (duration, decoder, voices, vocab), the place it takes under
the app's model folder (`dest`), bytes, SHA-256 and license, plus the buckets the functions take.
--web-w16 publishes the web's model alone (2026-11-27, Decision 078 update): the fp32 export with its large weights
STORED as fp16, each followed by a Cast to fp32, so every activation and the I/O stay fp32 (never fp16 compute, which
renders NaN). The text encoder (bert), the LSTMs and the prosody predictor keep fp32 weights: in fp16 they move the
pitch track (worst spectral SNR 24.4 dB against fp32 on 12 lines); kept, the audio is fp32's (64 dB). The browser
must not fold the Casts back into fp32 at session creation: js/kokoro-worker.js asks for optimization level
'extended' and a 4 KB constant-folding cap. Parts under 50 MB, the voice table and vocabulary, and
kokoro-vN-web-manifest.json (precision `w16`); no native files.

Every asset's size and SHA-256 are read back from the Release after the upload. Stdlib only, plus `gh` (and `onnx`
for --web-w16).
"""
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.request

REPO = os.environ.get("REPO", "bhwilkoff/Ear-Drama")
TAG = "kokoro-model"
HF = "onnx-community/Kokoro-82M-v1.0-ONNX"
REV = "1939ad2a8e416c0acfeecc08a694d14ef25f2231"
SOURCE = f"https://huggingface.co/{HF}/tree/{REV}"
LICENSE = "Apache-2.0"
ATTRIBUTION = ("Kokoro-82M v1.0 by hexgrad (https://huggingface.co/hexgrad/Kokoro-82M), Apache-2.0; ONNX export by "
               "onnx-community. Trained on permissive and non-copyrighted audio plus Koniwa tnc (CC BY 3.0) and SIWIS (CC BY 4.0).")
VOICES = ["af_heart", "af_alloy", "af_aoede", "af_bella", "af_jessica", "af_kore", "af_nicole", "af_nova", "af_river",
          "af_sarah", "af_sky", "am_adam", "am_echo", "am_eric", "am_fenrir", "am_liam", "am_michael", "am_onyx", "am_puck",
          "am_santa", "bf_alice", "bf_emma", "bf_isabella", "bf_lily", "bm_daniel", "bm_fable", "bm_george", "bm_lewis"]
VOICE_BYTES = 510 * 256 * 4
NATIVE = {"q8f16": "onnx/model_q8f16.onnx", "q8": "onnx/model_quantized.onnx"}
PART = 45_000_000  # under 50 MB in either unit (Pages warns at 50 MB and refuses 100 MB)
# --web-w16: float initializers of at least W16_MIN elements are stored fp16 unless their name matches W16_KEEP_FP32.
W16_MIN = 1024
W16_KEEP_FP32 = r"bert|^onnx::MatMul|LSTM|predictor|F0|/N\."


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def hf_tree(folder):
    url = f"https://huggingface.co/api/models/{HF}/tree/{REV}/{folder}"
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "ear-drama"}), timeout=60) as r:
        return {f["path"]: f for f in json.load(r)}


def fetch(work, rel, want):
    """WORK/rel, downloaded from the pinned revision unless present; checked against Hugging Face's own SHA-256."""
    path = os.path.join(work, rel)
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        url = f"https://huggingface.co/{HF}/resolve/{REV}/{rel}"
        urllib.request.urlretrieve(url, path + ".part")
        os.replace(path + ".part", path)
    oid = (want.get("lfs") or {}).get("oid")
    if want["size"] != os.path.getsize(path) or (oid and sha(path) != oid):
        raise SystemExit(f"{rel}: does not match {HF}@{REV[:12]} (size or SHA-256)")
    return path


def entry(path, name, role, **extra):
    return {"path": name, "role": role, "bytes": os.path.getsize(path), "sha256": sha(path), "license": LICENSE, **extra}


def gh(*args):
    for n in range(4):
        r = subprocess.run(["gh", *args], capture_output=True, text=True)
        if r.returncode == 0:
            return r.stdout
        if n == 3:
            raise SystemExit(f"gh {' '.join(args[:3])} failed: {r.stderr.strip()}")
        time.sleep(5 * (n + 1))


def w16(src, dst):
    """The fp32 ONNX model with large weights stored fp16 and cast back to fp32 at the top of the graph."""
    import re
    import numpy as np
    import onnx
    from onnx import TensorProto, helper, numpy_helper
    keep = re.compile(W16_KEEP_FP32)
    m = onnx.load(src)
    g = m.graph
    inits, casts = [], []
    for init in g.initializer:
        a = numpy_helper.to_array(init) if init.data_type == TensorProto.FLOAT else None
        if a is None or a.size < W16_MIN or keep.search(init.name) or np.abs(a).max() > 65000:
            inits.append(init)
            continue
        h = numpy_helper.from_array(a.astype(np.float16), init.name + "__w16")
        inits.append(h)
        casts.append(helper.make_node("Cast", [h.name], [init.name], to=TensorProto.FLOAT, name=init.name + "__w16_cast"))
    nodes = list(g.node)
    del g.initializer[:]
    g.initializer.extend(inits)
    del g.node[:]
    g.node.extend(casts + nodes)
    onnx.checker.check_model(m)
    onnx.save(m, dst)
    return len(casts)


def web_w16(work, version):
    """The web's w16 model in parts, the voice table, the vocabulary and the web manifest in WORK/publish."""
    pre = f"kokoro-v{version}-"
    onnx_tree, voices, root = hf_tree("onnx"), hf_tree("voices"), hf_tree("")
    fp32 = fetch(work, "onnx/model.onnx", onnx_tree["onnx/model.onnx"])
    tok = fetch(work, "tokenizer.json", root["tokenizer.json"])
    out = os.path.join(work, "publish")
    os.makedirs(out, exist_ok=True)
    model = os.path.join(work, f"{pre}model-w16.onnx")
    n = w16(fp32, model)
    table = os.path.join(out, pre + "voices-en.bin")
    with open(table, "wb") as t:
        for v in VOICES:
            b = open(fetch(work, f"voices/{v}.bin", voices[f"voices/{v}.bin"]), "rb").read()
            assert len(b) == VOICE_BYTES, (v, len(b))
            t.write(b)
    dst_tok = os.path.join(out, pre + "tokenizer.json")
    open(dst_tok, "wb").write(open(tok, "rb").read())
    parts = []
    with open(model, "rb") as f:
        for i, b in enumerate(iter(lambda: f.read(PART), b"")):
            name = f"{pre}web-model-w16.onnx.part{i:02d}"
            open(os.path.join(out, name), "wb").write(b)
            parts.append({"path": f"model-w16.onnx.part{i:02d}", "asset": name, "bytes": len(b),
                          "sha256": hashlib.sha256(b).hexdigest()})
    web = {"format": 1, "version": version, "name": "Kokoro-82M v1.0", "source": SOURCE,
           "attribution": ATTRIBUTION + " fp16-stored weights by Ear Drama (tools/publish_kokoro_model.py --web-w16).",
           "voices": VOICES, "voiceShape": [510, 256], "sampleRate": 24000, "precision": "w16", "backend": "webgpu",
           "files": [
               {"path": "model-w16.onnx", "role": "model", "bytes": os.path.getsize(model), "sha256": sha(model),
                "license": LICENSE, "parts": parts},
               {**entry(table, "voices-en.bin", "voices"), "asset": pre + "voices-en.bin"},
               {**entry(dst_tok, "tokenizer.json", "vocab"), "asset": pre + "tokenizer.json"}]}
    name = pre + "web-manifest.json"
    with open(os.path.join(out, name), "w") as f:
        json.dump(web, f, indent=1)
        f.write("\n")
    names = [p["asset"] for p in parts] + [pre + "voices-en.bin", pre + "tokenizer.json", name]
    print(f"{n} weights stored fp16; web model {os.path.getsize(model)} bytes in {len(parts)} parts; "
          f"{sum(x['bytes'] for x in web['files'])} bytes in all")
    return out, names


def coreml(work, src, version):
    """The Apple model's assets in WORK/publish, and their names."""
    pre = f"kokoro-v{version}-"
    report = json.load(open(os.path.join(src, "kokoro-coreml-report.json")))
    voices, root = hf_tree("voices"), hf_tree("")
    tok = fetch(work, "tokenizer.json", root["tokenizer.json"])
    out = os.path.join(work, "publish")
    os.makedirs(out, exist_ok=True)
    table = os.path.join(out, pre + "voices-en.bin")
    with open(table, "wb") as t:
        for v in VOICES:
            b = open(fetch(work, f"voices/{v}.bin", voices[f"voices/{v}.bin"]), "rb").read()
            assert len(b) == VOICE_BYTES, (v, len(b))
            t.write(b)
    files = []

    def add(path, name, role, dest):
        dst = os.path.join(out, name)
        if os.path.abspath(path) != os.path.abspath(dst):
            if os.path.exists(dst):
                os.remove(dst)
            open(dst, "wb").write(open(path, "rb").read())
        files.append({**entry(dst, name, role), "dest": dest})

    for package, role in (("KokoroDuration.mlpackage", "duration"), ("KokoroDecoder.mlpackage", "decoder")):
        base = os.path.join(src, package)
        for top, dirs, fs in os.walk(base):
            dirs.sort()
            for f in sorted(fs):
                full = os.path.join(top, f)
                place = os.path.relpath(full, src)
                add(full, pre + place.replace("/", "-"), role, place)
    add(table, pre + "voices-en.bin", "voices", "voices-en.bin")
    add(tok, pre + "tokenizer.json", "vocab", "tokenizer.json")
    manifest = {"format": 1, "version": version, "name": "Kokoro-82M v1.0", "source": report["source"],
                "attribution": ATTRIBUTION + " Core ML conversion by Ear Drama (tools/convert_kokoro_coreml.py).",
                "voices": VOICES, "voiceShape": [510, 256], "sampleRate": 24000, "runtime": "coreml",
                "precision": f"{report['precision']}-{report['weights']}w", "frameBuckets": report["frame_buckets"],
                "tokenBuckets": report["token_buckets"], "files": files}
    name = pre + "apple-manifest.json"
    with open(os.path.join(out, name), "w") as f:
        json.dump(manifest, f, indent=1)
        f.write("\n")
    names = [x["path"] for x in files] + [name]
    print(f"{len(names)} assets, Apple model {sum(x['bytes'] for x in files)} bytes")
    return out, names


def main():
    args = [a for i, a in enumerate(sys.argv[1:], 1)
            if not a.startswith("--") and sys.argv[i - 1] not in ("--version", "--native", "--coreml")]
    if not args:
        sys.exit(__doc__)
    work = args[0]
    version = int(sys.argv[sys.argv.index("--version") + 1]) if "--version" in sys.argv else 1
    precision = sys.argv[sys.argv.index("--native") + 1] if "--native" in sys.argv else "q8f16"
    if precision not in NATIVE:
        sys.exit(f"--native must be one of {sorted(NATIVE)}")
    native_only = "--native-only" in sys.argv
    if "--web-w16" in sys.argv:
        out, names = web_w16(work, version)
        if "--no-upload" not in sys.argv:
            upload(out, names)
        return
    if "--coreml" in sys.argv:
        out, names = coreml(work, sys.argv[sys.argv.index("--coreml") + 1], version)
        if "--no-upload" not in sys.argv:
            upload(out, names)
        return
    pre = f"kokoro-v{version}-"
    model_name = f"{pre}model_{precision}.onnx"
    onnx, voices, root = hf_tree("onnx"), hf_tree("voices"), hf_tree("")
    q8 = fetch(work, NATIVE[precision], onnx[NATIVE[precision]])
    fp32 = None if native_only else fetch(work, "onnx/model.onnx", onnx["onnx/model.onnx"])
    tok = fetch(work, "tokenizer.json", root["tokenizer.json"])
    out = os.path.join(work, "publish")
    os.makedirs(out, exist_ok=True)
    table = os.path.join(out, pre + "voices-en.bin")
    with open(table, "wb") as t:
        for v in VOICES:
            p = fetch(work, f"voices/{v}.bin", voices[f"voices/{v}.bin"])
            b = open(p, "rb").read()
            assert len(b) == VOICE_BYTES, (v, len(b))
            t.write(b)
    files = {model_name: q8, pre + "tokenizer.json": tok, pre + "voices-en.bin": table}
    for name, src in list(files.items()):
        dst = os.path.join(out, name)
        if src != dst:
            if os.path.exists(dst):
                os.remove(dst)
            os.link(src, dst) if os.stat(src).st_dev == os.stat(out).st_dev else open(dst, "wb").write(open(src, "rb").read())
    common = {"format": 1, "version": version, "name": "Kokoro-82M v1.0", "source": SOURCE, "attribution": ATTRIBUTION,
              "voices": VOICES, "voiceShape": [510, 256], "sampleRate": 24000}
    native = {**common, "precision": precision, "files": [
        entry(os.path.join(out, model_name), model_name, "model"),
        entry(table, pre + "voices-en.bin", "voices"),
        entry(os.path.join(out, pre + "tokenizer.json"), pre + "tokenizer.json", "vocab")]}
    parts = []
    with open(fp32 or os.devnull, "rb") as f:
        for i, b in enumerate(iter(lambda: f.read(PART), b"")):
            name = f"{pre}web-model.onnx.part{i:02d}"
            open(os.path.join(out, name), "wb").write(b)
            parts.append({"path": f"model.onnx.part{i:02d}", "asset": name, "bytes": len(b),
                          "sha256": hashlib.sha256(b).hexdigest()})
    web = None if native_only else {**common, "precision": "fp32", "backend": "webgpu", "files": [
        {"path": "model.onnx", "role": "model", "bytes": os.path.getsize(fp32), "sha256": sha(fp32), "license": LICENSE,
         "parts": parts},
        {**entry(table, "voices-en.bin", "voices"), "asset": pre + "voices-en.bin"},
        {**entry(tok, "tokenizer.json", "vocab"), "asset": pre + "tokenizer.json"}]}
    for name, doc in ((pre + "manifest.json", native), (pre + "web-manifest.json", web)):
        if doc is None:
            continue
        with open(os.path.join(out, name), "w") as f:
            json.dump(doc, f, indent=1)
            f.write("\n")
    names = sorted(n for n in os.listdir(out) if n.startswith(pre) and (not native_only or "web-" not in n))
    total = sum(os.path.getsize(os.path.join(out, n)) for n in names)
    print(f"{len(names)} assets, {total} bytes: native {sum(f['bytes'] for f in native['files'])}, "
          f"web {sum(f['bytes'] for f in web['files']) if web else 0} ({len(parts)} model parts)")
    if "--no-upload" in sys.argv:
        return
    upload(out, names)


def upload(out, names):
    if subprocess.run(["gh", "release", "view", TAG, "-R", REPO], capture_output=True).returncode != 0:
        gh("release", "create", TAG, "-R", REPO, "--latest=false", "--title", "Kokoro voice model",
           "--notes", "Versioned assets built by tools/publish_kokoro_model.py (Decision 078): kokoro-vN-manifest.json "
           "lists the native files (q8f16), kokoro-vN-web-manifest.json the site's (fp32 in parts, placed under "
           "data/kokoro/ by tools/fetch_kokoro_model.py). Never overwritten; a new version adds new assets. " + ATTRIBUTION)
    have = {a["name"] for a in json.loads(gh("release", "view", TAG, "-R", REPO, "--json", "assets"))["assets"]}
    clash = [n for n in names if n in have]
    if clash:
        raise SystemExit(f"refused: {TAG} already holds {clash[:3]}; publish a new --version")
    # The manifests go last, so a manifest never names an asset that is not there yet.
    order = [n for n in names if not n.endswith("manifest.json")] + [n for n in names if n.endswith("manifest.json")]
    for n in order:
        gh("release", "upload", TAG, "-R", REPO, os.path.join(out, n))
        print("uploaded", n, flush=True)
    got = {a["name"]: (a["size"], a.get("digest")) for a in
           json.loads(gh("release", "view", TAG, "-R", REPO, "--json", "assets"))["assets"]}
    for n in names:
        want = (os.path.getsize(os.path.join(out, n)), "sha256:" + sha(os.path.join(out, n)))
        if got.get(n) != want:
            raise SystemExit(f"{n}: the release says {got.get(n)}, the file is {want}")
    print(f"published {len(names)} assets to https://github.com/{REPO}/releases/tag/{TAG}")


if __name__ == "__main__":
    main()
