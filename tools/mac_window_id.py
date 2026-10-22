"""Print the CoreGraphics window id of the app's main window — and nothing else.

Store screenshots and harness frames capture the WINDOW (`screencapture -l <id>`),
never a screen rectangle and never the full screen. A rectangle capture photographs
whatever is at those coordinates: an emulator in the middle of a store frame, and —
worse — the owner's personal documents, when the app
window was not in front. So there is NO fallback here: if the window id cannot be
found, this exits 1 and says why. It never prints bounds for `-R`.

The owning application is matched EXACTLY (APP_NAME, or tools/app_config.py). A
title substring is not an identity — a terminal tab once carried the same words as
the app window it was mistaken for.

    python3 tools/mac_window_id.py            # prints e.g. 12345
    APP_NAME="My App" python3 tools/mac_window_id.py
"""
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_config  # noqa: E402

# The app's DISPLAY name — the window OWNER, which can differ from the process name.
APP_NAME = os.environ.get("APP_NAME", app_config.APPLE_APP_NAME)
MIN_WIDTH = 600  # skip tiny panels/tooltips

try:
    import Quartz
except ImportError:                     # pyobjc is not installed on every machine
    Quartz = None


def via_quartz():
    windows = Quartz.CGWindowListCopyWindowInfo(
        Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
        Quartz.kCGNullWindowID,
    ) or []
    best, best_area = None, 0
    for w in windows:
        if w.get("kCGWindowOwnerName") != APP_NAME:     # EXACT owner
            continue
        b = w.get(Quartz.kCGWindowBounds) or {}
        width, height = b.get("Width", 0), b.get("Height", 0)
        if width < MIN_WIDTH:
            continue
        if width * height > best_area:
            best, best_area = int(w["kCGWindowNumber"]), width * height
    return best


def via_winshot():
    """No pyobjc: ask the Swift helper (tools/mac_window_shot.swift), which does the
    same exact-owner lookup natively."""
    from devharness import ensure_winshot
    ok, why = ensure_winshot()
    if not ok:
        print(f"no window-id instrument: {why}", file=sys.stderr)
        return None
    r = subprocess.run([str(app_config.WINSHOT_BIN), APP_NAME, "", "--id-only",
                        "--min-width", str(MIN_WIDTH)], capture_output=True, text=True)
    out = r.stdout.strip()
    if r.returncode != 0 or not out.isdigit():
        print(out or r.stderr.strip(), file=sys.stderr)
        return None
    return int(out)


def main() -> int:
    wid = via_quartz() if Quartz is not None else via_winshot()
    if wid is None:
        print(f"no on-screen window owned by exactly {APP_NAME!r} — nothing captured "
              "(there is deliberately no region/full-screen fallback)", file=sys.stderr)
        return 1
    print(wid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
