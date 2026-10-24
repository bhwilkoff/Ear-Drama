#!/usr/bin/env python3
"""Derive every shipped font file from the OFL masters in branding/fonts/
(downloaded unmodified from github.com/google/fonts, ofl/bigshoulders and
ofl/publicsans; Decisions 060 and 067).

    python3 -m pip install fonttools brotli   # once, in a venv
    python3 tools/build_fonts.py              # rewrite every output
    python3 tools/build_fonts.py --check      # exit 1 if an output is missing

Outputs:
  fonts/big-shoulders.woff2        web display face, Bold, variable in opsz
  fonts/public-sans.woff2          web body face, variable (wght)
  fonts/public-sans-italic.woff2   web body italic, variable (wght)
  fonts/OFL-*.txt                  the licenses, beside the files they cover
  apple/Resources/Fonts/BigShoulders-Bold.ttf      Apple display face
  android/app/src/main/res/font/big_shoulders_bold.ttf  Android display face

The web files are subset to Latin and Latin Extended (names in the catalog
carry diacritics). The native files are one static instance, Bold at optical
size 28, because the display levels (L1, L2) are both 700 and the system face
carries body text on Apple and Android. Neither license names a Reserved Font
Name, so a subset or instance may keep the family name. The license text stays
in each file's name table (IDs 13 and 14).
"""
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "branding" / "fonts"
BIG = SRC / "BigShoulders[opsz,wght].ttf"
PUB = SRC / "PublicSans[wght].ttf"
PUB_I = SRC / "PublicSans-Italic[wght].ttf"

UNICODES = (
    "U+0000-024F,U+0259,U+02B0-02FF,U+0300-036F,U+1E00-1EFF,U+2000-206F,"
    "U+20A0-20CF,U+2100-214F,U+2190-21FF,U+2212,U+2215,U+25CF,U+FEFF,U+FFFD"
)
NATIVE_OPSZ = 28
NATIVE_WGHT = 700

WEB = {
    ROOT / "fonts" / "big-shoulders.woff2": BIG,
    ROOT / "fonts" / "public-sans.woff2": PUB,
    ROOT / "fonts" / "public-sans-italic.woff2": PUB_I,
}
LICENSES = {
    ROOT / "fonts" / "OFL-BigShoulders.txt": SRC / "OFL-BigShoulders.txt",
    ROOT / "fonts" / "OFL-PublicSans.txt": SRC / "OFL-PublicSans.txt",
    ROOT / "apple" / "Resources" / "Fonts" / "OFL-BigShoulders.txt": SRC / "OFL-BigShoulders.txt",
}
NATIVE = [
    ROOT / "apple" / "Resources" / "Fonts" / "BigShoulders-Bold.ttf",
    ROOT / "android" / "app" / "src" / "main" / "res" / "font" / "big_shoulders_bold.ttf",
]


def subset(font, flavor=None):
    from fontTools import subset as fs
    opts = fs.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.name_languages = ["*"]
    opts.notdef_outline = True
    opts.flavor = flavor
    s = fs.Subsetter(options=opts)
    s.populate(unicodes=fs.parse_unicodes(UNICODES))
    s.subset(font)
    return font


def rename_static(font, family, style, ps):
    name = font["name"]
    for rec in list(name.names):
        if rec.nameID in (1, 2, 3, 4, 6, 16, 17, 25):
            name.removeNames(nameID=rec.nameID)
    for nid, val in ((1, family), (2, style), (3, f"{ps};static"), (4, f"{family} {style}"), (6, ps)):
        name.setName(val, nid, 3, 1, 0x409)
        name.setName(val, nid, 1, 0, 0)
    font["OS/2"].usWeightClass = NATIVE_WGHT
    font["OS/2"].fsSelection = (font["OS/2"].fsSelection | 0x20) & ~0x40  # BOLD, not REGULAR
    font["head"].macStyle |= 0x1


def reload(font):
    """A round trip through bytes, so the subsetter never meets the
    instancer's half-loaded glyph-variation table."""
    import io
    from fontTools.ttLib import TTFont
    buf = io.BytesIO()
    font.save(buf)
    buf.seek(0)
    return TTFont(buf)


def build():
    from fontTools.ttLib import TTFont
    from fontTools.varLib import instancer

    for out, src in WEB.items():
        out.parent.mkdir(parents=True, exist_ok=True)
        f = TTFont(src)
        if src == BIG:
            # The display levels are all 700, so the web keeps only the optical-size axis.
            f = reload(instancer.instantiateVariableFont(f, {"wght": NATIVE_WGHT}))
        f = subset(f, flavor="woff2")
        f.flavor = "woff2"
        f.save(out)
        print(f"  wrote  {out.relative_to(ROOT)}  {out.stat().st_size // 1024} KB")
    for out, src in LICENSES.items():
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, out)
        print(f"  wrote  {out.relative_to(ROOT)}")
    static = reload(instancer.instantiateVariableFont(TTFont(BIG), {"wght": NATIVE_WGHT, "opsz": NATIVE_OPSZ}))
    subset(static)
    rename_static(static, "Big Shoulders", "Bold", "BigShoulders-Bold")
    for out in NATIVE:
        out.parent.mkdir(parents=True, exist_ok=True)
        static.save(out)
        print(f"  wrote  {out.relative_to(ROOT)}  {out.stat().st_size // 1024} KB")


def check():
    missing = [p for p in [*WEB, *LICENSES, *NATIVE] if not p.is_file() or p.stat().st_size == 0]
    for p in missing:
        print(f"  FAIL  {p.relative_to(ROOT)} is missing")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(check() if "--check" in sys.argv else build())
