#!/usr/bin/env python3
"""What is ACTUALLY in the Play reports bucket, and when was each file WRITTEN?

Run this before ever calling a Play export "broken". The newest ROW in a CSV
cannot tell a file that stopped being written from one that moved, was renamed,
or is simply behind — only the object's UPDATE TIME can. (Measured once: an
export called broken for days was two ordinary lags stacked — ~6 days of data
lag, plus the current month's file not appearing until part-way through the
month.) The bucket id is a secret, so this usually runs in CI.

    PLAY_REPORTS_BUCKET=pubsite_prod_rev_... python3 tools/pulse_play_bucket_probe.py
"""
from __future__ import annotations

import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pulse_collect as P  # noqa: E402


def main() -> int:
    bucket = P.ID.get("playBucket")
    pkg = P.ID.get("playPackage")
    if not bucket:
        print("no PLAY_REPORTS_BUCKET in this environment")
        return 1
    tok = P._google(["https://www.googleapis.com/auth/devstorage.read_only"])
    # A REDACTED bucket name: its id is a secret, its CONTENTS are the question.
    print(f"bucket: {bucket[:14]}… ({len(bucket)} chars); package filter: {pkg or '(none — every app)'}")
    for prefix in ("stats/installs/", "stats/ratings/", "stats/crashes/", "stats/store_performance/"):
        objs, page = [], None
        while True:
            q = {"prefix": prefix, "maxResults": "1000", **({"pageToken": page} if page else {})}
            url = f"https://storage.googleapis.com/storage/v1/b/{urllib.parse.quote(bucket)}/o?{urllib.parse.urlencode(q)}"
            try:
                d = json.load(urllib.request.urlopen(
                    urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}"}), timeout=60))
            except Exception as e:                     # noqa: BLE001
                print(f"\n{prefix}  COULD NOT LIST: {str(e)[:160]}")
                break
            objs += [o for o in d.get("items", []) if not pkg or pkg in o["name"]]
            page = d.get("nextPageToken")
            if not page:
                break
        if not objs:
            print(f"\n{prefix}  (no objects)")
            continue
        print(f"\n=== {prefix}  {len(objs)} object(s), newest WRITE first")
        for o in sorted(objs, key=lambda x: x.get("updated", ""), reverse=True)[:12]:
            print(f"  {o.get('updated', '?')[:16]}  {int(o.get('size', 0)):>9,}  {o['name'].rsplit('/', 1)[-1]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
