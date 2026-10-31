"""Measure each served picture's luminance range, for `art.grade` (contract section 3.3a).

    python3 tools/measure_art_grade.py                 # every art row of out/publish/ear-drama.sqlite not yet measured
    python3 tools/measure_art_grade.py --limit 50      # a few, to try it
    python3 tools/measure_art_grade.py --report

Needs Pillow and numpy (the catalog's one place that does; the build itself reads only the cache
this writes, `.cache/art_grade.json`, and stays stdlib). For each picture it fetches Commons' 500 px
thumbnail (the step uniform-imagery-design measures on), cuts the crop square a small slot shows
(`art_policy.crop_rect`, the same one every client draws), and records the 1st and 99th percentile of
Rec. 709 luminance in that crop, with the crop it was taken in. `art_policy.grade_text` turns that
into the two numbers a client applies. The pictures are not stored. A result is reused until the
picture's crop changes. A permanent failure (404) is recorded and not retried; a transient one is not.
"""
import argparse
import concurrent.futures
import io
import json
import os
import sqlite3
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import ia_lib as ia
import art_policy as AP

CACHE = os.path.join(ia.CACHE, "art_grade.json")
UA = "EarDrama-Catalog/0.1 (https://eardrama.org; picture grade measurement; ben@learningischange.com)"
STEP = 500


def load():
    return ia.read_json(CACHE) if os.path.exists(CACHE) else {}


def crop_key(r):
    return None if r is None else ",".join(f"{v:.4f}" for v in r)


def fetch(url):
    """('ok', bytes) for the 500 px thumbnail; ('gone', None) on a 404; (None, None) when it may work later."""
    delay = 3.0
    for _ in range(5):
        try:
            req = urllib.request.Request(f"{url}?width={STEP}", headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                return "ok", r.read()
        except urllib.error.HTTPError as e:
            if e.code in (404, 400):
                return "gone", None
            time.sleep(delay)
            delay *= 2
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            time.sleep(delay)
            delay *= 2
    return None, None


def measure(data, crop):
    import numpy as np
    from PIL import Image
    rgb = np.asarray(Image.open(io.BytesIO(data)).convert("RGB")).astype(float) / 255
    h, w = rgb.shape[:2]
    reg = rgb
    if crop:
        y0, x0 = int(crop[1] * h), int(crop[0] * w)
        reg = rgb[y0:max(int((crop[1] + crop[3]) * h), y0 + 1), x0:max(int((crop[0] + crop[2]) * w), x0 + 1)]
    lum = 0.2126 * reg[..., 0] + 0.7152 * reg[..., 1] + 0.0722 * reg[..., 2]
    return float(np.percentile(lum, 1)), float(np.percentile(lum, 99))


def work(item):
    url, crop = item
    state, data = fetch(url)
    if state != "ok":
        return url, crop, state, None
    try:
        return url, crop, "ok", measure(data, crop)
    except Exception as e:  # a file Pillow cannot read is a permanent failure for this picture
        return url, crop, "gone", str(e)[:80]


def served_art(path):
    d = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    return [(url, AP.crop_rect(w, h, AP.face_list(face)))
            for url, w, h, face in d.execute("SELECT url, width, height, face FROM art ORDER BY id")]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=os.path.join(ia.OUT, "publish", "ear-drama.sqlite"))
    ap.add_argument("--limit", type=int)
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--report", action="store_true")
    a = ap.parse_args()
    cache = load()
    if a.report:
        ok = [v for v in cache.values() if "lo" in v]
        print(json.dumps({"measured": len(ok), "gone": sum(1 for v in cache.values() if v.get("gone")),
                          "identity": sum(1 for v in ok if AP.grade_text(v["lo"], v["hi"]) is None)}))
        return
    todo = [(u, c) for u, c in served_art(a.db) if u not in cache or cache[u].get("crop") != crop_key(c)]
    if a.limit:
        todo = todo[:a.limit]
    print(f"{len(todo)} pictures to measure", file=sys.stderr)
    done = failed = 0
    with concurrent.futures.ThreadPoolExecutor(a.workers) as ex:
        for url, crop, state, res in ex.map(work, todo):
            if state == "ok":
                cache[url] = {"lo": round(res[0], 4), "hi": round(res[1], 4), "crop": crop_key(crop)}
                done += 1
            elif state == "gone":
                cache[url] = {"gone": True, "crop": crop_key(crop)}
                failed += 1
            if (done + failed) % 100 == 0 and (done + failed):
                ia.write_json(CACHE, cache)
                print(f"  {done + failed}/{len(todo)}", file=sys.stderr)
    ia.write_json(CACHE, cache)
    print(json.dumps({"measured": done, "gone": failed, "left": len(todo) - done - failed}))
    if todo and not done:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
