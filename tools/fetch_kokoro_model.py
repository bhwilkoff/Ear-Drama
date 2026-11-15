#!/usr/bin/env python3
"""Place the web's Kokoro model (Decision 078) under the site, from the `kokoro-model` Release.

    python3 tools/fetch_kokoro_model.py DEST        # tools/assemble_site.sh: DEST = <site>/data/kokoro

Reads the newest `kokoro-vN-web-manifest.json` (tools/publish_kokoro_model.py), downloads every asset it
names (the fp32 model's parts under 50 MB, the voice table, the vocabulary), and writes each at its served
path with the manifest as DEST/manifest.json, the file js/kokoro-model.js reads. Each download must match
the size and sha256 GitHub reports for the asset AND the manifest's own size and SHA-256; the parts must
add up to the model's size and SHA-256. Any mismatch exits 1 and leaves DEST absent: the site build stops
rather than serve a model that would fail its check in the browser. Stdlib only; sends GH_TOKEN or
GITHUB_TOKEN when one is set. A copy already in DEST that matches is kept (a rerun downloads nothing).
"""
import hashlib
import json
import os
import re
import shutil
import sys
import time
import urllib.error
import urllib.request

REPO = os.environ.get("REPO") or os.environ.get("GITHUB_REPOSITORY") or "bhwilkoff/Ear-Drama"
TAG = "kokoro-model"
MANIFEST = re.compile(r"^kokoro-v(\d+)-web-manifest\.json$")
LICENSES = {"Apache-2.0", "MIT", "BSD-2-Clause", "BSD-3-Clause"}
MAX_FILE = 50_000_000
PATH = re.compile(r"^[\w.-]+$")


def request(url, accept):
    headers = {"Accept": accept, "User-Agent": "ear-drama-site-build"}
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"
    return urllib.request.Request(url, headers=headers)


def get(url, accept="application/octet-stream", attempts=4):
    for n in range(1, attempts + 1):
        try:
            with urllib.request.urlopen(request(url, accept), timeout=300) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code < 500 and e.code != 429:
                raise SystemExit(f"{url}: HTTP {e.code}")
            err = e
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            err = e
        if n == attempts:
            raise SystemExit(f"{url}: {err}")
        time.sleep(5 * n)


def newest(assets):
    named = [(int(m.group(1)), a) for a in assets for m in [MANIFEST.match(a["name"])] if m]
    if not named:
        raise SystemExit(f"release {TAG} has no kokoro-vN-web-manifest.json")
    return max(named, key=lambda t: t[0])[1]


def check_manifest(m):
    """The shape js/kokoro-model.js accepts, plus the Release asset each served file comes from."""
    assert m["format"] == 1 and m["files"], "no files"
    for f in m["files"]:
        assert PATH.match(f["path"]) and f["license"] in LICENSES, f["path"]
        assert isinstance(f["bytes"], int) and re.fullmatch(r"[0-9a-f]{64}", f["sha256"]), f["path"]
        pieces = f.get("parts") or [f]
        if "parts" in f:
            assert sum(p["bytes"] for p in f["parts"]) == f["bytes"], (f["path"], "parts do not add up")
        for p in pieces:
            assert PATH.match(p["path"]) and p["asset"] and re.fullmatch(r"[0-9a-f]{64}", p["sha256"]), p
            assert p["bytes"] < MAX_FILE, (p["path"], "over 50 MB: Pages would warn, and refuse at 100 MB")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    dest = sys.argv[1]
    rel = json.loads(get(f"https://api.github.com/repos/{REPO}/releases/tags/{TAG}", "application/vnd.github+json"))
    assets = {a["name"]: a for a in rel.get("assets") or []}
    ma = newest(list(assets.values()))
    raw = get(ma["browser_download_url"])
    if len(raw) != ma["size"] or hashlib.sha256(raw).hexdigest() != (ma.get("digest") or "").removeprefix("sha256:"):
        raise SystemExit(f"{ma['name']}: does not match the release's size and digest")
    m = json.loads(raw)
    try:
        check_manifest(m)
    except (AssertionError, KeyError, TypeError) as e:
        raise SystemExit(f"{ma['name']} is not a web model manifest: {e!r}")
    tmp = dest.rstrip("/") + ".download"
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)
    got = 0
    for f in m["files"]:
        whole = hashlib.sha256()
        for p in f.get("parts") or [f]:
            a = assets.get(p["asset"])
            if not a:
                raise SystemExit(f"{ma['name']} names {p['asset']}, which the release does not hold")
            have = os.path.join(dest, p["path"])
            blob = open(have, "rb").read() if os.path.exists(have) and os.path.getsize(have) == p["bytes"] else None
            if blob is None or hashlib.sha256(blob).hexdigest() != p["sha256"]:
                blob = get(a["browser_download_url"])
                got += len(blob)
            digest = hashlib.sha256(blob).hexdigest()
            if len(blob) != p["bytes"] or len(blob) != a["size"] or digest != p["sha256"] or \
                    "sha256:" + digest != a.get("digest"):
                raise SystemExit(f"{p['asset']}: size or SHA-256 differs from the manifest or the release")
            whole.update(blob)
            with open(os.path.join(tmp, p["path"]), "wb") as out:
                out.write(blob)
        if "parts" in f and whole.hexdigest() != f["sha256"]:
            raise SystemExit(f"{f['path']}: its parts do not assemble to the manifest's SHA-256")
    with open(os.path.join(tmp, "manifest.json"), "wb") as out:
        out.write(raw)
    shutil.rmtree(dest, ignore_errors=True)
    os.makedirs(os.path.dirname(os.path.abspath(dest)), exist_ok=True)
    os.replace(tmp, dest)
    total = sum(f["bytes"] for f in m["files"])
    print(f"kokoro web model: {ma['name']}, {len(os.listdir(dest))} files, {total} bytes "
          f"({got} downloaded), placed in {dest}")


if __name__ == "__main__":
    main()
