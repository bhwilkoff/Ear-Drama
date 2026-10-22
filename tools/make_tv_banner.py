#!/usr/bin/env python3
"""
make_tv_banner.py — render the app's TV banner at BOTH sizes it is
needed in, from the one icon master.

There are two different "TV banners" and conflating them costs a submission:

  1280x720  the Google Play STORE LISTING asset (`tvBanner` in the Play
            Developer API). Play REJECTS anything else outright:
            "Invalid dimensions - expected width: [1280], expected height: [720]".
  320x180   the in-APK leanback banner (`android:banner`, TV-BN) that the
            Android TV launcher draws. Ships in res/drawable-xhdpi/.

The store asset is rendered NATIVELY at 1280x720 rather than upscaled from the
320 version, which would be a visibly soft 4x blowup on a 10-foot screen.

Source of truth for the artwork is the ONE canonical 1024px icon master
(APP_ICON_1024). Derive every banner from it; a second master drifts.

The wordmark is the product name (BANNER_TITLE, else app_config.PRODUCT_NAME):
the first word in white, the rest in the brand color. BANNER_TAGLINE adds an
optional small line underneath.

Usage:  python3 tools/make_tv_banner.py [--check]
        --check verifies the committed files match a fresh render.
"""

import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import app_config as _cfg  # noqa: E402
except Exception:              # pragma: no cover - a template with no config yet
    _cfg = None

REPO = Path(__file__).resolve().parent.parent
_WORDS = (os.environ.get("BANNER_TITLE") or getattr(_cfg, "PRODUCT_NAME", "AppName")).upper().split()
TITLE_1 = _WORDS[0] if _WORDS else "APP"
TITLE_2 = " ".join(_WORDS[1:])
TAGLINE = os.environ.get("BANNER_TAGLINE", "").upper()
MASTER = REPO / os.environ.get("APP_ICON_1024", "branding/icon-1024.png")  # FILL IN: your 1024px icon master
STORE_OUT = REPO / "assets/tv/tv-banner-1280x720.png"
APK_OUT = REPO / "android/app/src/main/res/drawable-xhdpi/tv_banner.png"

# Colors come from design-tokens.json (the dark palette: TV is dark-first), so
# the banner follows the app's look instead of keeping its own copy.
import json as _json


def _rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


_BRAND = _json.loads((REPO / "design-tokens.json").read_text())["color"]["brand"]
INK = _rgb(_BRAND["background"]["dark"])
ACCENT = _rgb(_BRAND["primary"]["dark"])
WHITE = _rgb(_BRAND["text"]["dark"])
MUTED = _rgb(_BRAND["textMuted"]["dark"])

# macOS system faces; the first that resolves wins.
BOLD_FACES = ["/System/Library/Fonts/Supplemental/Futura.ttc",
              "/System/Library/Fonts/Supplemental/Avenir Next.ttc",
              "/System/Library/Fonts/Helvetica.ttc"]
PLAIN_FACES = ["/System/Library/Fonts/Supplemental/Futura.ttc",
               "/System/Library/Fonts/Helvetica.ttc"]


def _font(paths, size, index=0):
    for p in paths:
        try:
            return ImageFont.truetype(p, size, index=index)
        except Exception:  # noqa: BLE001
            continue
    return ImageFont.load_default()


def _tracked(draw, xy, text, font, fill, tracking):
    """Draw letter-spaced text (PIL has no tracking); returns the width used."""
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        x += draw.textlength(ch, font=font) + tracking
    return x - tracking - xy[0]


def _tracked_width(draw, text, font, tracking):
    return sum(draw.textlength(c, font=font) for c in text) + tracking * (len(text) - 1)


def _fit(draw, text, faces, max_w, tracking_ratio, ceiling):
    """Largest font size at which `text` fits `max_w` including tracking.

    Auto-fitting rather than hardcoding a size: 1280x720 is 16:9, so the art
    column leaves far less room than the square icon suggests, and a fixed size
    that looked right at one dimension clipped the wordmark at the other."""
    size = ceiling
    while size > 8:
        f = _font(faces, size)
        if _tracked_width(draw, text, f, size * tracking_ratio) <= max_w:
            return f, size * tracking_ratio
        size -= 1
    return _font(faces, 8), 0


def render(w: int, h: int) -> Image.Image:
    img = Image.new("RGB", (w, h), INK)
    draw = ImageDraw.Draw(img)

    # Left: the icon art, centre-cropped to a column narrower than a
    # square so the wordmark gets real room on a 16:9 canvas.
    art_w = int(w * 0.40)
    art = Image.open(MASTER).convert("RGB")
    scale = h / art.height
    art = art.resize((max(1, int(art.width * scale)), h), Image.LANCZOS)
    left = max(0, (art.width - art_w) // 2)
    img.paste(art.crop((left, 0, left + art_w, h)), (0, 0))

    pad = int(w * 0.05)
    tx = art_w + pad
    avail = w - tx - pad

    # One size for both title lines, fitted to the longer, so they match.
    longest = max((TITLE_1, TITLE_2), key=len)
    f_title, trk = _fit(draw, longest, BOLD_FACES, avail, 0.06, int(h * 0.24))
    title_h = f_title.size
    lines = 2 if TITLE_2 else 1
    line_gap = int(title_h * 0.18)
    rule_gap = int(h * 0.055)
    block_h = title_h * lines + line_gap * (lines - 1)
    if TAGLINE:
        f_sub, sub_trk = _fit(draw, TAGLINE, PLAIN_FACES, avail, 0.16, int(h * 0.075))
        block_h += rule_gap + f_sub.size
    y = (h - block_h) // 2

    _tracked(draw, (tx, y), TITLE_1, f_title, WHITE, trk)
    y += title_h
    if TITLE_2:
        y += line_gap
        _tracked(draw, (tx, y), TITLE_2, f_title, ACCENT, trk)
        y += title_h
    if TAGLINE:
        y += rule_gap
        _tracked(draw, (tx, y), TAGLINE, f_sub, MUTED, sub_trk)
    return img


def main() -> int:
    check = "--check" in sys.argv
    if not MASTER.exists():
        print(f"missing master: {MASTER}", file=sys.stderr)
        return 2
    STORE_OUT.parent.mkdir(parents=True, exist_ok=True)

    failed = False
    for out, (w, h) in ((STORE_OUT, (1280, 720)), (APK_OUT, (320, 180))):
        img = render(w, h)
        if check:
            if not out.exists():
                print(f"MISSING {out}")
                failed = True
                continue
            cur = Image.open(out).convert("RGB")
            same = cur.size == img.size and cur.tobytes() == img.tobytes()
            print(f"{'OK   ' if same else 'STALE'} {out.relative_to(REPO)} {cur.size}")
            failed |= not same
        else:
            img.save(out, "PNG", optimize=True)
            print(f"wrote {out.relative_to(REPO)}  {w}x{h}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
