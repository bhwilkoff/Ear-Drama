"""SYSTEM_OVERLAY_RX against OCR text of real iPhone 12 frames.

The Screen Time frame (2026-10-27 9:35 PM) is the one a UI test PASSED under; it
must be caught. The app's own frames (2026-10-28 tap tier) are the controls: the
player, Library with its queue, and Search must never read as an overlay.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_config  # noqa: E402

SCREEN_TIME = "9:35 SOS Time Limit You've reached your limit on Ear Drama. OK Ask for More Time"
PERMISSION = "“Ear Drama” Would Like to Find and Connect to Devices on Your Local Network Don’t Allow Allow"
APP_FRAMES = [
    "5:41 SOS X Minus One The Sense of Wonder 1956-04-24 NBC 12:58 -14:57 15 30 1.5x Sleep 14:59",
    "Library Queue 1956-04-24 The Sense of Wonder X Minus One 27:55 Undated Andy Clyde Bio "
    "In progress Home Browse Stations Library Search Edit",
    "Search gangbusters august 1954 Aired August 1954 1954-08-02 The Case Of The Kewpie Doll Champ "
    "Gangbusters 23:42 Home Browse Stations Library Search",
    "Sleep timer End of this episode 15 minutes 30 minutes 45 minutes 1 hour",
]


def hit(text):
    return bool(re.search(app_config.SYSTEM_OVERLAY_RX, text, re.I))


def main():
    bad = []
    if not hit(SCREEN_TIME):
        bad.append("Screen Time's Time Limit frame not caught")
    if not hit(PERMISSION):
        bad.append("a permission alert not caught")
    bad += [f"app frame read as an overlay: {t[:50]}" for t in APP_FRAMES if hit(t)]
    for b in bad:
        print("FAIL", b)
    print(f"{2 + len(APP_FRAMES) - len(bad)}/{2 + len(APP_FRAMES)} passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
