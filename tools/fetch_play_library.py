#!/usr/bin/env python3
"""Download the newest play library from its rolling Release and unpack it where the site build reads it.

    python3 tools/fetch_play_library.py [DEST]        # DEST default catalog/out/plays-library

The library is built by tools/refresh_play_library.sh and published as `plays-library-YYYY-MM-DD.tar.xz`
(a same-day rebuild adds `-2`, `-3`) on the `plays-library` Release; tools/assemble_site.sh calls this when
no library was built in the run. Newest is the latest date, then the highest suffix. The download must match
the size and sha256 GitHub reports for the asset, and the unpacked library must pass the shape check
(catalog/tools/check_play_library.py), or this exits 1: a bad asset fails the build loudly instead of
shipping an empty shelf. Stdlib only; reads the public API, sending GH_TOKEN/GITHUB_TOKEN when one is set.
"""
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "catalog", "tools"))
import play_library_archive as A

REPO = os.environ.get("REPO") or os.environ.get("GITHUB_REPOSITORY") or "bhwilkoff/Ear-Drama"
TAG = "plays-library"
ASSET = re.compile(r"^plays-library-(\d{4}-\d{2}-\d{2})(?:-(\d+))?\.tar\.xz$")


def request(url, accept):
    headers = {"Accept": accept, "User-Agent": "ear-drama-site-build"}
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return urllib.request.Request(url, headers=headers)


def get(url, accept, attempts=4):
    for n in range(1, attempts + 1):
        try:
            with urllib.request.urlopen(request(url, accept), timeout=120) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code < 500 and e.code != 429:
                raise SystemExit(f"{url}: HTTP {e.code}")
            err = e
        except (urllib.error.URLError, TimeoutError) as e:
            err = e
        if n == attempts:
            raise SystemExit(f"{url}: {err}")
        time.sleep(5 * n)


def newest(assets):
    named = [(m.group(1), int(m.group(2) or 1), a) for a in assets for m in [ASSET.match(a["name"])] if m]
    if not named:
        raise SystemExit(f"release {TAG} has no plays-library-YYYY-MM-DD.tar.xz asset")
    return max(named, key=lambda t: t[:2])[2]


def main():
    dest = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "catalog", "out", "plays-library")
    rel = json.loads(get(f"https://api.github.com/repos/{REPO}/releases/tags/{TAG}", "application/vnd.github+json"))
    asset = newest(rel.get("assets") or [])
    blob = get(asset["browser_download_url"], "application/octet-stream")
    if len(blob) != asset["size"]:
        raise SystemExit(f"{asset['name']}: downloaded {len(blob)} bytes, the release says {asset['size']}")
    want = (asset.get("digest") or "").removeprefix("sha256:")
    if want and hashlib.sha256(blob).hexdigest() != want:
        raise SystemExit(f"{asset['name']}: sha256 does not match the release's digest")
    path = dest.rstrip("/") + ".download.tar.xz"
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(blob)
    try:
        idx = A.unpack(path, dest)
    except (AssertionError, ValueError, OSError, KeyError) as e:
        raise SystemExit(f"{asset['name']} is not a play library: {e!r}")
    finally:
        os.remove(path)
    print(f"play library: {asset['name']} ({asset['size']} bytes), {idx['count']} plays, unpacked to {dest}")


if __name__ == "__main__":
    main()
