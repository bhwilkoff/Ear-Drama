"""Real-hardware harness for the macOS app — the 5th platform, and the one with
no coverage at all until now.

The Mac is the only platform where the app is not alone on the display, so the
capture is the app's own WINDOW, by window id, owned by exactly the pid under test
(tools/mac_window_shot.swift via macapp.capture). Never a full-screen grab and never
a screen region: those photograph whatever else is open — the desktop, a terminal,
someone's documents — and every one of those strings would count as "text the app
put on the glass", besides leaking what was never ours to capture.

The run holds the "mac" lease for its whole length (another session capturing this
Mac's windows at the same time would fight over the same app) and quits the app at
the end.

    python3 tools/mac_run.py --list
    python3 tools/mac_run.py --only home,search
"""
from app_config import *  # app identity + calibrated thresholds

import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import devlease  # noqa: E402
import macapp  # noqa: E402
from devharness import Grader, ocr, qa_dir, sh  # noqa: E402

# Prefer the locally built app: the harness should grade what is about to ship,
# not the copy in /Applications, which lags. Pointing at /Applications is why a
# keychain-password dialog kept turning up in Mac runs after the fix landed.
_DEV = REPO / f"build/dd-mac/Build/Products/Debug/{APPLE_APP_NAME}.app"
APP = str(_DEV if _DEV.exists() else Path(f"/Applications/{APPLE_APP_NAME}.app"))
BIN = f"{APP}/Contents/MacOS/{APPLE_EXECUTABLE}"
PROC = APPLE_EXECUTABLE

# The Mac shell is a NavigationSplitView, so the sidebar is on screen for every
# section — which makes the sidebar labels useless as a screen signature. Every
# expect_any below is content from the DETAIL column only.
ANCHOR = APP_ANCHOR_RX  # see tools/app_config.py

# FILL IN: EXAMPLES matching what the template's starter honours (APP_START_TAB
# home|browse|search|library — the SidebarSection raw values in
# apple/macOS/ContentView_macOS.swift — plus APP_START_ITEM, APP_MUTE and
# APP_DOOR_SECONDS). Replace each regex with detail-column content calibrated
# against a real capture, then add your app's surfaces. Two frames are taken
# (~6 s and ~13 s after launch), so a door-seconds bound must end before ~13 s.
SCENARIOS = {
    "home":        ({HOOK_START_TAB: "home"},
                    {"expect_any": r"Home"}),                            # FILL IN
    "search":      ({HOOK_START_TAB: "search"},
                    {"expect_any": r"Search"}),                          # FILL IN
    "item":        ({HOOK_START_ITEM: QA_ITEM_ID, HOOK_MUTE: "1"},
                    {"expect_any": QA_ITEM_RX}),
    "door-return": ({HOOK_START_ITEM: QA_ITEM_ID, HOOK_DOOR_SECONDS: "8"},
                    {"expect_any": QA_ITEM_RX, "expect_end": r"Home"}),  # FILL IN
}


_PID = None


def quit_app():
    macapp.quit_all()


def launch(env):
    """`open -a` does NOT forward env to a GUI app, so the binary is exec'd
    directly — which is what makes the APP_* hooks reachable on the Mac, and
    also why every later call must address the PID rather than the name.
    Doors are muted and time-bounded (app_config.DOOR_DEFAULTS)."""
    global _PID
    _PID = macapp.launch(BIN, {**DOOR_DEFAULTS, **env})


def capture(path, tries=20):
    return macapp.capture(_PID, path, tries=tries) if _PID else False


def run(name, outdir):
    env, spec = SCENARIOS[name]
    quit_app()
    launch(env)
    d = outdir / name
    d.mkdir(parents=True, exist_ok=True)
    shots = []
    # Two frames a few seconds apart: the first catches the initial paint, the
    # second catches content that arrives over the network. Grading the union
    # means a slow fetch is not a failure, but a never-arriving one still is.
    for i, wait in enumerate((6, 7)):
        time.sleep(wait)
        p = d / f"{i}.png"
        if capture(p):
            shots.append((wait, p))
    return shots, spec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--list", action="store_true", help="print the scenarios and exit")
    a = ap.parse_args()

    if a.list:
        for k, (env, _) in SCENARIOS.items():
            print(f"  {k:12s} {env}")
        return 0

    names = [n for n in (a.only.split(",") if a.only else SCENARIOS) if n in SCENARIOS]
    out = qa_dir("mac", "sweep")
    g = Grader(out, platform="mac", app=APP, scenarios=names)

    if not Path(BIN).exists():
        g.grade("app_installed", False, f"{BIN} missing — nothing to test")
        return g.finish()

    try:
        with devlease.hold(["mac"], task=f"mac_run {','.join(names)}"):
            return _sweep(names, out, g)
    except RuntimeError as e:
        g.grade("mac_leased", False, f"{e} — this sweep covers NOTHING")
        return g.finish()


def _sweep(names, out, g):
    try:
        for n in names:
            print(f"\n=== {n} ===")
            shots, spec = run(n, out)
            if not shots:
                g.grade(f"{n}.captured", False, "no window ever appeared")
                continue
            texts = ocr(shots)
            sub = Grader(out, platform="mac")
            sub.grade_glass(shots, texts, spec, ANCHOR)
            for k, v in sub.report["assertions"].items():
                g.grade(f"{n}.{k}", v["pass"], v["evidence"])
    finally:
        quit_app()          # leave as found, whatever happened above
    return g.finish()


if __name__ == "__main__":
    sys.exit(main())
