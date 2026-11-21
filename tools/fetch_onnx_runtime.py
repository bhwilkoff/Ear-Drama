#!/usr/bin/env python3
"""Place the ONNX Runtime the web's Kokoro voices run on under the site, so no third party serves code at runtime.

    python3 tools/fetch_onnx_runtime.py DEST     # tools/assemble_site.sh: DEST = <site>/vendor/onnxruntime-web
    python3 tools/fetch_onnx_runtime.py vendor/onnxruntime-web   # local development (vendor/ is gitignored)

R3d T1 (Decision 084): js/kokoro-worker.js loaded onnxruntime-web from jsDelivr; a school's reviewer would have
had to ask about that request. The pinned npm tarball is downloaded once, checked against the registry's
SHA-512 integrity below, and only the files the worker loads are written: the WASM and WebGPU entry scripts
and the two module/binary pairs they import. A mismatch exits 1 and writes nothing: the site build stops rather
than serve a runtime it did not check. The package is MIT (credited on the site's credits page). Stdlib only.
A copy already in DEST whose files match is kept.
"""
import base64
import hashlib
import io
import os
import shutil
import sys
import tarfile
import time
import urllib.request

VERSION = "1.31.1"
TARBALL = f"https://registry.npmjs.org/onnxruntime-web/-/onnxruntime-web-{VERSION}.tgz"
INTEGRITY = "sha512-5GeH+bWQ+HxM10z7erGlsWqryrwMbSvm/1tkIsKTT48g0fI19VXVVC435t4t7VsPdSQeS7NmuZPXrQ73k82URw=="
FILES = [
    "ort.wasm.min.js",
    "ort.webgpu.min.js",
    "ort-wasm-simd-threaded.mjs",
    "ort-wasm-simd-threaded.wasm",
    "ort-wasm-simd-threaded.asyncify.mjs",
    "ort-wasm-simd-threaded.asyncify.wasm",
]
STAMP = ".version"


def download(url, attempts=4):
    for i in range(attempts):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "ear-drama-site-build"})
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.read()
        except Exception as e:  # a network blip retries in-step; anything else after the last try stops the build
            if i == attempts - 1:
                raise
            print(f"retrying {url}: {e}", file=sys.stderr)
            time.sleep(5 * (i + 1))
    return b""


def integrity_ok(data):
    algo, want = INTEGRITY.split("-", 1)
    return base64.b64encode(hashlib.new(algo, data).digest()).decode() == want


def main(dest):
    stamp = os.path.join(dest, STAMP)
    if os.path.exists(stamp) and open(stamp).read().strip() == INTEGRITY and all(os.path.getsize(os.path.join(dest, f)) > 0 for f in FILES if os.path.exists(os.path.join(dest, f))) and all(os.path.exists(os.path.join(dest, f)) for f in FILES):
        print(f"onnxruntime-web {VERSION}: already in {dest}")
        return 0
    data = download(TARBALL)
    if not integrity_ok(data):
        print(f"::error::onnxruntime-web {VERSION} does not match its pinned integrity; not writing it", file=sys.stderr)
        return 1
    out = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
        for name in FILES:
            member = tar.getmember(f"package/dist/{name}")
            out[name] = tar.extractfile(member).read()
    tmp = dest + ".tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)
    for name, body in out.items():
        if not body:
            print(f"::error::{name} is empty in the tarball", file=sys.stderr)
            shutil.rmtree(tmp)
            return 1
        with open(os.path.join(tmp, name), "wb") as f:
            f.write(body)
    with open(os.path.join(tmp, STAMP), "w") as f:
        f.write(INTEGRITY + "\n")
    shutil.rmtree(dest, ignore_errors=True)
    os.makedirs(os.path.dirname(os.path.abspath(dest)), exist_ok=True)
    os.rename(tmp, dest)
    print(f"onnxruntime-web {VERSION}: {len(FILES)} files, {sum(len(b) for b in out.values()) // 1_000_000} MB in {dest}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
