#!/usr/bin/env python3
"""The tvOS Top Shelf images carry both scales at Apple's pixel sizes.

App Store Connect flagged build 98 (1.0.97) with ITMS-90471 "Missing Image Asset:
Top Shelf Image Wide 2x": the image sets held one unscaled PNG each. Sources are
branding/tvos-icon-layers/topshelf.svg and topshelf-wide.svg, rendered at 1x and 2x.
"""
import json
import sys
from pathlib import Path

from PIL import Image

BRAND = Path(__file__).resolve().parent.parent / "apple/Assets.xcassets/App Icon & Top Shelf Image.brandassets"
WANT = {
    "Top Shelf Image.imageset": (1920, 720),
    "Top Shelf Image Wide.imageset": (2320, 720),
}


def problems(brand=BRAND):
    out = []
    for name, (w, h) in WANT.items():
        d = brand / name
        images = json.loads((d / "Contents.json").read_text())["images"]
        by_scale = {i.get("scale"): i.get("filename") for i in images if i.get("idiom") == "tv"}
        for scale, k in (("1x", 1), ("2x", 2)):
            f = by_scale.get(scale)
            if not f:
                out.append(f"{name}: no {scale} image")
                continue
            img = Image.open(d / f)
            if img.size != (w * k, h * k):
                out.append(f"{name} {scale}: {img.size}, want {(w * k, h * k)}")
            if img.mode not in ("RGB", "L"):
                out.append(f"{name} {scale}: mode {img.mode}; Top Shelf images must be opaque")
    return out


if __name__ == "__main__":
    p = problems()
    for line in p:
        print("FAIL", line)
    print("PASS: both Top Shelf images carry 1x and 2x at Apple's sizes" if not p else f"{len(p)} problem(s)")
    sys.exit(1 if p else 0)
