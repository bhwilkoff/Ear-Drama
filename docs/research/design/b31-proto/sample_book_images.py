#!/usr/bin/env python3
"""B31 sample: what the Gutenberg HTML edition's own images are, for a handful of book ids.

    python3 docs/research/design/b31-proto/sample_book_images.py OUTDIR 14484 68576 ...

One request per book, two seconds apart, to Gutenberg's cached HTML (pg<ID>-images.html). Prints each
<img>'s file, size attributes, alt text and nearest caption, and downloads the first three images into
OUTDIR/<id>/ so a person can look at them. Research only; nothing in the catalog reads this.
"""
import html
import os
import re
import sys
import time
import urllib.request

UA = {"User-Agent": "ear-drama-research (one-off sample)"}
out = sys.argv[1]
for gid in sys.argv[2:]:
    # The PGLAF mirror's tree: www.gutenberg.org answered 503 with Retry-After 21600 on 2026-11-26.
    tree = "/".join(gid[:-1]) + "/" + gid if len(gid) > 1 else "0/" + gid
    base = f"https://aleph.pglaf.org/{tree}/{gid}-h/"
    try:
        page = urllib.request.urlopen(urllib.request.Request(base + f"{gid}-h.htm", headers=UA), timeout=30).read().decode("utf-8", "replace")
    except Exception as e:  # noqa: BLE001
        print(gid, "FAILED", e)
        continue
    imgs = re.findall(r"<img[^>]*>", page, re.I)
    print(f"{gid}: {len(imgs)} <img>")
    os.makedirs(os.path.join(out, gid), exist_ok=True)
    for i, tag in enumerate(imgs[:8]):
        src = re.search(r'src="([^"]+)"', tag)
        alt = re.search(r'alt="([^"]*)"', tag)
        w = re.search(r'width="?(\d+)', tag)
        pos = page.find(tag)
        cap = re.sub(r"<[^>]+>", " ", page[pos + len(tag): pos + len(tag) + 300])
        cap = html.unescape(" ".join(cap.split()))[:90]
        print(f"   {src.group(1) if src else '?'} w={w.group(1) if w else '?'} alt={alt.group(1)[:50] if alt else ''!r} after={cap!r}")
        if i < 3 and src:
            time.sleep(1)
            try:
                data = urllib.request.urlopen(urllib.request.Request(base + src.group(1), headers=UA), timeout=30).read()
                open(os.path.join(out, gid, f"{i}-" + os.path.basename(src.group(1))), "wb").write(data)
            except Exception as e:  # noqa: BLE001
                print("     download failed", e)
    time.sleep(2)
