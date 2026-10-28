"""IOS_ANCHOR_RX against OCR text of real iPhone 12 frames (captured 2026-10-27).

A player-sheet frame (no tab bar) must count as the app; a Springboard frame must
not. The Springboard text is the negative control: it contains "Home" and "Search",
which the old anchor accepted.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_config  # noqa: E402

PLAYER = ("5:41 SOS • X Minus One The Sense of Wonder 1956-04-24 • NBC 12:58 -14:57 "
          "15 30 1x C Sleep")
TABS = "5:49 SOS Edit Library Queue Home Browse Stations Library Search"
SPRINGBOARD = ("5:52 Weather Stocks Find My Podcasts Books Fitness Contacts Files Preview "
               "Translate Freeform Journal Tidbits Archive Watch Ear Drama Search SOS "
               "Home Watch Utilities Tips")


def hit(text):
    return bool(re.search(app_config.IOS_ANCHOR_RX, text, re.I))


def main():
    bad = []
    if not hit(PLAYER):
        bad.append("player sheet frame not anchored")
    if not hit(TABS):
        bad.append("tab bar frame not anchored")
    if hit(SPRINGBOARD):
        bad.append("Springboard frame anchored (negative control)")
    if re.search(r"Home|Browse|Stations|Library", SPRINGBOARD):
        pass  # the old anchor matched this frame, which is why it was replaced
    print("FAIL: " + "; ".join(bad) if bad else "ok: ios anchor (3 real frames)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
