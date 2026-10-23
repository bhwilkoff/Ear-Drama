#!/usr/bin/env python3
"""Render the smart-TV and Roku stubs' art: PLACEHOLDERS for the owner to replace.

DECISIONS 056 makes webOS, Tizen and Roku 1.0 stubs, and DECISIONS 060 chose
the ring-microphone icon without a final palette or a TV-sized master. Until
that art exists, every vendor slot still needs a file of the right size or the
package will not build, so this draws a plain wordmark on the dark ground with
the word PLACEHOLDER on it. Nothing here is store art: replace each file (same
name, same size) before any submission.

It also draws the two Roku 9-patches the channel's design uses (the light focus
ring and the button pill). Those are design, not placeholders.

    python3 tools/make_tv_stub_art.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "roku" / "fonts" / "PublicSans-Bold.ttf"

GROUND = (0x14, 0x16, 0x19, 255)     # color.brand.background.dark
ACCENT = (0xA7, 0xBF, 0xD6, 255)     # color.brand.primary.dark
TEXT = (0xEB, 0xEB, 0xEB, 255)       # broadcast-safe text (no channel above 235)
MUTED = (0xA2, 0xA9, 0xB4, 255)      # color.brand.textMuted.dark

# (path, width, height). Sizes are each vendor's required slot.
PLACEHOLDERS = [
    ("tv/webos/icon.png", 80, 80),            # LG: app icon
    ("tv/webos/largeIcon.png", 130, 130),     # LG: large icon
    ("tv/webos/splash.png", 1920, 1080),      # LG: splash background
    ("tv/tizen/icon.png", 512, 423),          # Samsung: TV app icon
    ("roku/images/poster_fhd.png", 540, 405),  # Roku: channel poster, FHD
    ("roku/images/poster_hd.png", 290, 218),   # Roku: channel poster, HD
    ("roku/images/splash_fhd.png", 1920, 1080),
    ("roku/images/splash_hd.png", 1280, 720),
]


def font(size):
    return ImageFont.truetype(str(FONT), size)


def centered(draw, y, text, size, fill, w):
    f = font(size)
    box = draw.textbbox((0, 0), text, font=f)
    draw.text(((w - (box[2] - box[0])) / 2 - box[0], y), text, font=f, fill=fill)
    return box[3] - box[1]


def placeholder(path, w, h):
    img = Image.new("RGBA", (w, h), GROUND)
    d = ImageDraw.Draw(img)
    short = min(w, h)
    mark = "Ear Drama" if w >= 200 else "ED"
    size = max(12, int(short * (0.16 if w >= 200 else 0.34)))
    stamp = max(8, int(short * 0.07))
    th = d.textbbox((0, 0), mark, font=font(size))
    block = (th[3] - th[1]) + stamp * 2
    y = (h - block) / 2
    centered(d, y, mark, size, TEXT, w)
    rule = y + th[3] + stamp * 0.8
    d.rectangle([w * 0.3, rule, w * 0.7, rule + max(2, short // 120)], fill=ACCENT)
    centered(d, h - stamp * 2.2, "PLACEHOLDER", stamp, MUTED, w)
    out = ROOT / path
    out.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out)
    return out


def nine_patch(path, size, radius, draw_shape):
    """A Roku/Android 9-patch: the art plus a 1px frame whose black pixels on
    the top and left edges mark the stretchable middle."""
    art = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw_shape(ImageDraw.Draw(art), size, radius)
    img = Image.new("RGBA", (size + 2, size + 2), (0, 0, 0, 0))
    img.paste(art, (1, 1))
    d = ImageDraw.Draw(img)
    lo, hi = radius + 1, size - radius
    d.line([(lo, 0), (hi, 0)], fill=(0, 0, 0, 255))
    d.line([(0, lo), (0, hi)], fill=(0, 0, 0, 255))
    out = ROOT / path
    img.save(out)
    return out


def ring(d, size, radius):
    # Light ring with a soft outer edge: a faint wide stroke under a crisp one.
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, outline=(0xEB, 0xEB, 0xEB, 90), width=6)
    d.rounded_rectangle([2, 2, size - 3, size - 3], radius=radius - 2, outline=TEXT, width=4)


def pill(d, size, radius):
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=TEXT)


def main():
    for path, w, h in PLACEHOLDERS:
        print("placeholder", placeholder(path, w, h).relative_to(ROOT), f"{w}x{h}")
    print("9-patch", nine_patch("roku/images/ring.9.png", 48, 16, ring).relative_to(ROOT))
    print("9-patch", nine_patch("roku/images/pill.9.png", 64, 30, pill).relative_to(ROOT))


if __name__ == "__main__":
    main()
