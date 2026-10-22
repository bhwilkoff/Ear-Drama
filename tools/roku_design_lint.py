#!/usr/bin/env python3
"""The Roku design ship gate, as a lint over the channel's BrightScript + XML.

Each rule is a shape the roku-brightscript-app skill (§4) bans because it reached
the glass at least once in a shipped channel:

  system-font      a Roku system font by name — every level is a bundled face at a size
  narration        an on-screen sentence narrating navigation ("Press OK to play")
  raw-slug         a raw content-type slug printed as a label (map it to a word)
  accent-focus     a focused LABEL painted the accent colour — the accent means
                   "this plays", never "this has focus"; the ring is light
  ring-bitmap      the retired focus-ring 9-patch coming back
  flat-plate       a flat Rectangle button plate (buttons are pills from slices)
  pure-white       #FFFFFF — broadcast-safe is <= 235 per channel; use #EBEBEB
  emoji            an emoji / non-BMP glyph in a string: the font has none, it
                   renders as a tofu box

It reads SOURCE, so it cannot see geometry; the adversarial screenshot pass still
owns "does it look designed". This owns "did a banned shape come back". A lint has
blind spots (it caught instruction strings but not a slug inside a longer sentence)
— it is a floor, not the whole check. Keep it at zero findings as a merge gate.

  python3 tools/roku_design_lint.py [--root roku/components] [--allow-missing]
"""
import argparse
import re
import sys
from pathlib import Path

# FILL IN to match your channel.
SLUG_FIELD = "contentType"        # the item field holding a raw type slug
ACCENT = "m.t.accent"             # how your code names the accent colour
RETIRED_RING_BITMAPS = ("focus_ring.9.png", "focus_footprint.9.png")
BUTTON_PLATE_HEIGHT = 66          # the height your old flat button plates used

RULES = [
    ("system-font", re.compile(r'"font:[A-Za-z]+SystemFont"')),
    ("narration", re.compile(r'"[^"\n]*\bPress (OK|Select|Right|Left|Up|Down|\*)\b')),
    ("narration", re.compile(r'"[^"\n]*\b(OK|Select) to (open|play|tune|watch)\b', re.I)),
    ("narration", re.compile(r'"[^"\n]*\b(Left|Right|Up|Down)/(Left|Right|Up|Down) (for|to)\b', re.I)),
    ("raw-slug", re.compile(r'\.text\s*=\s*(UCase|LCase)?\(?\s*\w+\.' + re.escape(SLUG_FIELD) + r'\b')),
    ("accent-focus", re.compile(r'(title|label|caption)\w*\.color\s*=\s*' + re.escape(ACCENT))),
    ("ring-bitmap", re.compile("|".join(re.escape(b) for b in RETIRED_RING_BITMAPS))),
    ("flat-plate", re.compile(r'CreateChild\("Rectangle"\)\s*\n\s*\w+\.height\s*=\s*'
                              + str(BUTTON_PLATE_HEIGHT) + r'\b')),
    ("pure-white", re.compile(r'(0x|#)FFFFFF(FF)?\b', re.I)),
    ("emoji", re.compile(r'"[^"\n]*[\U00010000-\U0010FFFF☀-➿⏩-⏺][^"\n]*"')),
]

# A rule-scoped exception must say WHY, here, or it is a defect. Format:
#   "File.brs:<start of the matched snippet>": "the reason this one is allowed",
ALLOW = {}

SOURCES = ("*.brs", "*.xml")


def blank_comments(text, suffix):
    """Comments are not UI. Blank them, keeping line numbers."""
    if suffix == ".xml":
        return re.sub(r"<!--.*?-->", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    out = []
    for ln in text.splitlines():
        s = ln.lstrip()
        out.append("" if s.startswith("'") or s.upper().startswith("REM ") else ln)
    return "\n".join(out)


def lint(root):
    files = sorted(f for pat in SOURCES for f in Path(root).rglob(pat))
    findings = []
    for f in files:
        text = blank_comments(f.read_text(errors="replace"), f.suffix)
        for name, rx in RULES:
            for m in rx.finditer(text):
                line = text.count("\n", 0, m.start()) + 1
                snippet = text[m.start():m.end()].strip().splitlines()[0][:90]
                if any(f"{f.name}:{snippet}".startswith(k) for k in ALLOW):
                    continue
                findings.append((f.name, line, name, snippet))
    return files, findings


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default="roku/components")
    ap.add_argument("--allow-missing", action="store_true",
                    help="exit 0 when the root does not exist (a repo with no Roku channel)")
    a = ap.parse_args(argv)
    root = Path(a.root)
    if not root.is_dir():
        print(f"SKIP  {root} does not exist — nothing was linted. An empty scan is not a "
              "pass" + ("; --allow-missing given." if a.allow_missing else "."))
        return 0 if a.allow_missing else 1
    files, findings = lint(root)
    if not files:
        print(f"FAIL  no .brs/.xml under {root} — an empty scan is not a pass")
        return 1
    for fn, line, name, snip in findings:
        print(f"{fn}:{line}: {name}: {snip}")
    print(f"\n{len(findings)} finding(s) across {len(files)} file(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
