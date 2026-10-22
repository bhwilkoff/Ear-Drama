"""Real-browser harness for the web app — the other platform with no coverage.

Every route is captured at BOTH 375px and 1440px. The project's density rule is
"test at 375px before 1440px", and a desktop-only sweep cannot see the failure
that rule exists to prevent: a layout that is fine wide and clipped narrow. The
clip detector reads the narrow frame, which is where clipping actually happens.

    python3 tools/web_run.py --list
    python3 tools/web_run.py --only home,item
    python3 tools/web_run.py --base https://example.com       # a deployed site

No device lease: the browser is a private headless instance with its own profile,
so nothing here is shared with another session.
"""
from app_config import *  # app identity + calibrated thresholds

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from devharness import Grader, ocr, qa_dir, sh  # noqa: E402

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
# The local dev server by default: a sweep of production while you believe you are
# testing your edit is a silent wrong answer. Pass --base for a deployed site.
BASE = WEB_URL
# Calibrated against a real capture, not assumed: a full-screen view (a player, a
# quiz question) can carry NO site chrome at all, and anchoring on the wordmark
# alone once called a correctly-rendered full-screen view "the wrong app".
ANCHOR = APP_ANCHOR_RX  # see tools/app_config.py

VIEWPORTS = [("narrow", 375, 812), ("wide", 1440, 900)]

# route -> (path, expect_any). Signatures are content unique to that route: the
# site header is on every page and would match everywhere, which is how a sweep
# reports 15/15 while showing one screen fifteen times.
#
# FILL IN: EXAMPLES that drive the web starter's real doors — the query params
# js/app.js reads in init(): ?view=<tab>, ?item=<id>, ?mute=1, ?door_seconds=<n>
# (the twins of APP_START_TAB / _START_ITEM / _MUTE / _DOOR_SECONDS). These are
# real, shareable URLs, not hash routes. Replace each regex with content
# calibrated against a real capture, and add a route per view your app has.
ROUTES = {
    "home":        ("/", r"Home"),                                        # FILL IN
    "search":      ("/?view=search", r"Search"),                          # FILL IN
    "item":        (f"/?item={QA_ITEM_ID}&mute=1", QA_ITEM_RX),
    # The door ends itself inside the capture's virtual-time budget (9 s), so the
    # frame must show Home, not the item.
    "door-return": (f"/?item={QA_ITEM_ID}&mute=1&door_seconds=2", r"Home"),  # FILL IN
}
# Routes that are EXPECTED to land on another route's screen, so the distinct-
# screen check below must not call them duplicates.
SAME_SCREEN_AS = {"door-return": "home"}


def shoot(url, w, h, path, budget=9000):
    # Delete first: the retry below reuses the path, and a failed second shot must
    # not leave the first one standing in for it.
    Path(path).unlink(missing_ok=True)
    sh([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
        f"--window-size={w},{h}", f"--virtual-time-budget={budget}",
        f"--screenshot={path}", url], timeout=90)
    return Path(path).exists() and Path(path).stat().st_size > 3000


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--base", default=BASE)
    ap.add_argument("--list", action="store_true", help="print the routes and exit")
    a = ap.parse_args()

    if a.list:
        for k, (path, _) in ROUTES.items():
            print(f"  {k:12s} {path}")
        return 0

    names = [n for n in (a.only.split(",") if a.only else ROUTES) if n in ROUTES]
    out = qa_dir("web", "sweep")
    g = Grader(out, platform="web", base=a.base, routes=names)

    seen = {}
    for n in names:
        path, sig = ROUTES[n]
        print(f"\n=== {n} ({path}) ===")
        d = out / n
        d.mkdir(parents=True, exist_ok=True)
        shots = []
        for label, w, h in VIEWPORTS:
            p = d / f"{label}.png"
            if shoot(a.base + path, w, h, p):
                shots.append((label, p))
            time.sleep(0.5)
        # A cold headless Chrome under load can return a blank first paint before
        # the virtual-time budget expires, which grades as "SCREEN OFF" for a site
        # that is up — measured once on the home route during a run with three other jobs on
        # the machine. Retry the whole route with a longer budget rather than
        # reporting a live page as dark.
        if shots and max(len(v.get("allText", []))
                         for v in ocr(shots).values()) < 4:
            print("  blank first paint — retrying with a longer budget")
            shots = []
            for label, w, h in VIEWPORTS:
                p = d / f"{label}.png"
                if shoot(a.base + path, w, h, p, budget=20000):
                    shots.append((label, p))
        if not shots:
            g.grade(f"{n}.captured", False, "chrome produced no screenshot")
            continue
        texts = ocr(shots)
        sub = Grader(out, platform="web")
        sub.grade_glass(shots, texts, {"expect_any": sig}, ANCHOR)
        for k, v in sub.report["assertions"].items():
            g.grade(f"{n}.{k}", v["pass"], v["evidence"])
        seen[n] = " ".join(t["text"] for t in
                           texts.get((d / "wide.png").name, {}).get("allText", []))[:150]

    # Distinct routes must show distinct content. Fifteen passing captures of the
    # same screen pass every per-route check ever written.
    dupes = {}
    for n, txt in seen.items():
        if n in SAME_SCREEN_AS:
            continue
        if txt and txt in dupes:
            g.grade(f"{n}.distinct_screen", False, f"identical to {dupes[txt]}")
        dupes[txt] = n
    return g.finish()


if __name__ == "__main__":
    sys.exit(main())
