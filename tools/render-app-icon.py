#!/usr/bin/env python3
"""The ring-microphone icon's variants, from one copy of the mark's geometry
(the same shapes as branding/icon-master.svg; Decision 060, 09 §2.3 candidate 1).

    python3 tools/render-app-icon.py           write every variant
    python3 tools/render-app-icon.py --check   render the master and this file's
                                               default; exit 1 if they differ

Writes:
  branding/icon-dark.svg, icon-tinted.svg, icon-monochrome.svg   the sources
  apple/Assets.xcassets/AppIcon.appiconset/Icon-1024{,-dark,-tinted}.png
  android/.../drawable/ic_launcher_foreground.xml, ic_launcher_monochrome.xml
  <scratch>/android-adaptive-preview.png (with --preview DIR): the adaptive
    icon as a launcher draws it, circle-masked, for looking at

iOS appearances (HIG, App icons): the default is the master, opaque; dark is
the mark in On Air's dark-mode red on a transparent ground, so the system lays
its own dark backdrop under it; tinted is a white mark on black, grayscale,
which the system tints. The grille's three bars are holes in the element, so
one silhouette serves every variant and Android's monochrome layer.

Rendering uses headless Chrome (no rsvg or Inkscape on this Mac) and Pillow.
The Mac and tvOS icons are not written here (branding/mac-icon.svg,
branding/tvos-icon-layers/).
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
TOKENS = json.loads((ROOT / "design-tokens.json").read_text())
RED = TOKENS["color"]["brand"]["record"]["light"]
DARK_RED = TOKENS["color"]["brand"]["record"]["dark"]
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
ICONSET = ROOT / "apple" / "Assets.xcassets" / "AppIcon.appiconset"
DRAWABLE = ROOT / "android" / "app" / "src" / "main" / "res" / "drawable"

# The mark, in the master's 1024 space. Strokes: the ring and its four springs.
RING = "M220,448 A292,292 0 1,1 804,448 A292,292 0 1,1 220,448 Z"
SPRINGS = "M318,254 L436,352 M706,254 L588,352 M318,642 L436,544 M706,642 L588,544"


def bar(y):
    return f"M462,{y - 8} H562 A8,8 0 0,1 562,{y + 8} H462 A8,8 0 0,1 462,{y - 8} Z"


# Fills: the element with its three grille bars cut out (even-odd), the stand, the base.
ELEMENT = "M422,412 A90,90 0 0,1 602,412 L602,484 A90,90 0 0,1 422,484 Z " + " ".join(bar(y) for y in (404, 448, 492))
STAND = "M494,734 H530 A10,10 0 0,1 540,744 V854 A10,10 0 0,1 530,864 H494 A10,10 0 0,1 484,854 V744 A10,10 0 0,1 494,734 Z"
BASE = "M360,852 H664 A28,28 0 0,1 664,908 H360 A28,28 0 0,1 360,852 Z"


def svg(mark, ground=None, note=""):
    g = f'  <rect width="1024" height="1024" fill="{ground}"/>\n' if ground else ""
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">\n'
        f"  <!-- {note} Written by tools/render-app-icon.py; edit the geometry there. -->\n"
        f"{g}"
        f'  <g fill="none" stroke="{mark}" stroke-linecap="round">\n'
        f'    <path d="{RING}" stroke-width="60"/>\n'
        f'    <path d="{SPRINGS}" stroke-width="20"/>\n'
        "  </g>\n"
        f'  <g fill="{mark}">\n'
        f'    <path d="{ELEMENT}" fill-rule="evenodd"/>\n'
        f'    <path d="{STAND}"/>\n'
        f'    <path d="{BASE}"/>\n'
        "  </g>\n"
        "</svg>\n"
    )


# Android: a 108 dp canvas whose launcher mask shows the middle 72 dp and
# guarantees a 66 dp circle. The mark's farthest point (a base corner) sits
# about 425 units from its center (512, 517), so 0.072 keeps it inside 31 dp.
SCALE = 0.072
CX, CY = 512, 517


def vector(note):
    tx, ty = 54 - CX * SCALE, 54 - CY * SCALE
    return f"""<?xml version="1.0" encoding="utf-8"?>
<!-- {note} Written by tools/render-app-icon.py from the mark in
     branding/icon-master.svg; edit the geometry there, not here. The mark fits
     the 66 dp circle every launcher mask keeps. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <group
        android:scaleX="{SCALE}"
        android:scaleY="{SCALE}"
        android:translateX="{tx:.3f}"
        android:translateY="{ty:.3f}">
        <path
            android:strokeColor="#FFFFFFFF"
            android:strokeWidth="60"
            android:pathData="{RING}"/>
        <path
            android:strokeColor="#FFFFFFFF"
            android:strokeWidth="20"
            android:strokeLineCap="round"
            android:pathData="{SPRINGS}"/>
        <path
            android:fillColor="#FFFFFFFF"
            android:fillType="evenOdd"
            android:pathData="{ELEMENT}"/>
        <path
            android:fillColor="#FFFFFFFF"
            android:pathData="{STAND}"/>
        <path
            android:fillColor="#FFFFFFFF"
            android:pathData="{BASE}"/>
    </group>
</vector>
"""


def render(svg_path, out, size=1024):
    """Headless Chrome screenshot of an SVG on a transparent page."""
    with tempfile.TemporaryDirectory() as tmp:
        page = Path(tmp) / "icon.html"
        page.write_text(
            '<!doctype html><html><head><style>html,body{margin:0;background:transparent}'
            f'img{{display:block;width:{size}px;height:{size}px}}</style></head>'
            f'<body><img src="{Path(svg_path).resolve().as_uri()}"></body></html>'
        )
        shot = Path(tmp) / "shot.png"
        subprocess.run(
            [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
             f"--user-data-dir={tmp}/profile", "--force-device-scale-factor=1",
             "--default-background-color=00000000", f"--window-size={size},{size}",
             "--allow-file-access-from-files", f"--screenshot={shot}", page.as_uri()],
            check=True, capture_output=True, timeout=60,
        )
        img = Image.open(shot).convert("RGBA")
        if img.size != (size, size):
            raise SystemExit(f"Chrome rendered {img.size}, not {size}x{size}")
        img.save(out)
    return Image.open(out)


def opaque(path):
    Image.open(path).convert("RGB").save(path)


def android_preview(out_dir):
    """The adaptive icon as a launcher shows it: ground, mark, circle mask."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    fg_svg = out_dir / "android-foreground.svg"
    # The same transform as the vector: 108 units scaled to 432 px (4 px per dp).
    tx, ty = 54 - CX * SCALE, 54 - CY * SCALE
    body = svg("#FFFFFF").split("\n", 2)[2]
    fg_svg.write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108" width="432" height="432">\n'
        f'<rect width="108" height="108" fill="{RED}"/>\n'
        f'<g transform="translate({tx:.3f} {ty:.3f}) scale({SCALE})">\n' + body.replace("</svg>\n", "") + "</g></svg>\n"
    )
    full = render(fg_svg, out_dir / "android-adaptive-full.png", 432)
    mask = Image.new("L", full.size, 0)
    # The launcher shows the middle 72 of 108 dp; a circle is the tightest mask.
    m = 432 * 18 / 108
    ImageDraw.Draw(mask).ellipse([m, m, 432 - m, 432 - m], fill=255)
    shown = Image.new("RGBA", full.size, (0, 0, 0, 0))
    shown.paste(full, (0, 0), mask)
    shown = shown.crop((int(m), int(m), int(432 - m), int(432 - m)))
    shown.save(out_dir / "android-adaptive-preview.png")
    print(f"  preview  {out_dir / 'android-adaptive-preview.png'}")


def check():
    with tempfile.TemporaryDirectory() as tmp:
        default = Path(tmp) / "default.svg"
        default.write_text(svg("#FFFFFF", RED, "check"))
        a = render(ROOT / "branding" / "icon-master.svg", Path(tmp) / "a.png").convert("RGB")
        b = render(default, Path(tmp) / "b.png").convert("RGB")
        off = sum(ImageChops.difference(a, b).convert("L").histogram()[65:])
        white = sum(a.convert("L").histogram()[200:]) / (1024 * 1024)
    drawn = 0.1 < white < 0.5
    print(f"  {'ok  ' if drawn else 'FAIL'}  the master rendered ({white:.0%} of it is the white mark)")
    print(f"  {'ok  ' if off < 200 else 'FAIL'}  the geometry here matches branding/icon-master.svg ({off} pixels differ)")
    return 0 if drawn and off < 200 else 1


def main():
    if "--check" in sys.argv:
        return check()
    b = ROOT / "branding"
    (b / "icon-dark.svg").write_text(svg(DARK_RED, None, "The iOS dark icon: On Air's dark-mode red on a transparent ground."))
    (b / "icon-tinted.svg").write_text(svg("#FFFFFF", "#000000", "The iOS tinted icon: grayscale, white on black, for the system to tint."))
    (b / "icon-monochrome.svg").write_text(svg("#000000", None, "The one-color silhouette (Android themed icon)."))
    render(b / "icon-master.svg", ICONSET / "Icon-1024.png")
    opaque(ICONSET / "Icon-1024.png")
    render(b / "icon-dark.svg", ICONSET / "Icon-1024-dark.png")
    render(b / "icon-tinted.svg", ICONSET / "Icon-1024-tinted.png")
    Image.open(ICONSET / "Icon-1024-tinted.png").convert("L").convert("RGB").save(ICONSET / "Icon-1024-tinted.png")
    for name in ("Icon-1024.png", "Icon-1024-dark.png", "Icon-1024-tinted.png"):
        print(f"  wrote  {(ICONSET / name).relative_to(ROOT)}")
    (DRAWABLE / "ic_launcher_foreground.xml").write_text(vector("The adaptive icon's foreground: the white ring microphone."))
    (DRAWABLE / "ic_launcher_monochrome.xml").write_text(vector("The themed icon's monochrome layer: the same silhouette; the launcher recolors it."))
    print(f"  wrote  {DRAWABLE.relative_to(ROOT)}/ic_launcher_foreground.xml, ic_launcher_monochrome.xml")
    if "--preview" in sys.argv:
        android_preview(sys.argv[sys.argv.index("--preview") + 1])
    return 0


if __name__ == "__main__":
    sys.exit(main())
