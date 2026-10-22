"""Drive a REAL iPhone/iPad and grade the app from the glass.

The tvOS sibling is tools/atv_run.py and the Android one is tools/adb_run.py;
the shared grading spine is tools/devharness.py and the Apple plumbing is
tools/apple_device.py. The doctrine is the same everywhere — the app's own claims
are never the evidence for what a user sees; the screen is. What differs is the
plumbing:

  * There is NO remote wake on iOS. devicectl cannot wake a locked device and
    there is no Companion protocol to borrow. The arrangement is physical:
    passcode OFF, Auto-Lock NEVER, device on a charger. A LOCKED device installs
    fine and refuses to launch (FBSOpenApplicationErrorDomain 7, "Locked"), which
    otherwise arrives as an empty console plus a black screenshot — several
    unrelated failures and a couple of vacuous passes. The launch names it once.
  * There is no press verb either, so scenarios reach their surface through the
    DebugHooks env spine (launch doors) or a deep link via --url. Never by
    pressing blind. The tap tier is XCUITest, not this runner.
  * Every door launch is muted and time-bounded (app_config.DOOR_DEFAULTS).

Every run holds one lease for the whole run and leaves the device as found: the
app is terminated and the device is asked to confirm it is gone.

Usage:
    python3 tools/ios_run.py --list
    python3 tools/ios_run.py --device ipad --scenario home
    python3 tools/ios_run.py --device iphone --env APP_START_TAB=search \
        --expect "Search" --name adhoc
"""
from app_config import *  # app identity + calibrated thresholds

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import apple_device as ad  # noqa: E402
import bench  # noqa: E402
import devlease  # noqa: E402
from devharness import Grader, ocr, qa_dir   # noqa: E402

BUNDLE = APPLE_BUNDLE_ID
SHOT_EVERY = 3.0

BASE_ENV = {HOOK_SKIP_ONBOARD: "1", **DOOR_DEFAULTS}

# Chrome that proves OUR app owns the glass rather than Springboard.
APP_ANCHOR_RX = APP_ANCHOR_RX  # see tools/app_config.py

# expect_any regexes are calibrated against real captures on your own device,
# never guessed — an assertion written from imagination fails on correct pixels
# and teaches the loop to be ignored. (Other keys devharness.Grader.grade_glass
# reads: expect_end, forbid.)
#
# FILL IN: EXAMPLES matching what the template's starter honours (APP_START_TAB
# home|search, APP_START_ITEM, APP_MUTE, APP_DOOR_SECONDS — see
# apple/Core/Store/LaunchDoors.swift). Tab titles are on every screen, so replace
# each regex with content unique to that surface, then add your app's surfaces.
SCENARIOS = {
    "home":        {"env": {HOOK_START_TAB: "home"},   "minutes": 0.6,
                    "expect_any": r"Home"},                              # FILL IN
    "search":      {"env": {HOOK_START_TAB: "search"}, "minutes": 0.6,
                    "expect_any": r"Search"},                            # FILL IN
    # Mute is in every launch already (DOOR_DEFAULTS); spelled out on the
    # scenario most likely to start playback.
    "item":        {"env": {HOOK_START_ITEM: QA_ITEM_ID, HOOK_MUTE: "1"}, "minutes": 0.6,
                    "expect_any": QA_ITEM_RX},
    # The door bounds itself: the app leaves the item on its own clock.
    "door-return": {"env": {HOOK_START_ITEM: QA_ITEM_ID, HOOK_DOOR_SECONDS: "10"},
                    "minutes": 0.6, "expect_any": QA_ITEM_RX,
                    "expect_end": r"Home"},                              # FILL IN
}


def capture_loop(udid, outdir, minutes):
    shots, i = [], 0
    deadline = time.time() + minutes * 60
    while time.time() < deadline:
        p = outdir / f"shot-{i:04d}.png"
        i += 1
        ok, why = ad.capture(udid, p, timeout=45)
        if not ok:
            # One flaky capture must not kill the scenario — skip the frame, keep
            # the run, say so. A stale file is refused, never graded.
            print(f"[ios] capture {p.name}: {why} — skipping frame")
            time.sleep(2)
            continue
        shots.append((time.time(), p))
        time.sleep(max(0, SHOT_EVERY - 1.0))
    return shots


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--device", default="ipad", help="bench name or a raw UDID")
    ap.add_argument("--scenario")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--minutes", type=float)
    ap.add_argument("--env", action="append", default=[], help="K=V extra env")
    ap.add_argument("--url", help="deep link, e.g. appname://item/example-item")
    ap.add_argument("--expect", help="ad-hoc expect_any regex")
    ap.add_argument("--name")
    ap.add_argument("--owner-ok", action="store_true",
                    help="allow a device whose role is owner-watches (ask first)")
    ap.add_argument("--audible", action="store_true",
                    help="drop the mute door (ask the owner first)")
    ap.add_argument("--leave-running", action="store_true",
                    help="skip teardown — only when the owner asked to look at it")
    ap.add_argument("--lease-wait", type=int, default=0)
    a = ap.parse_args()

    if a.list:
        for k, v in SCENARIOS.items():
            print(f"  {k:12s} {v['env']}")
        return 0

    spec = dict(SCENARIOS.get(a.scenario, {"env": {}, "minutes": 0.6}))
    spec["env"] = dict(spec.get("env", {}))
    for kv in a.env:
        k, _, v = kv.partition("=")
        spec["env"][k] = v
    if a.expect:
        spec["expect_any"] = a.expect
    if a.minutes:
        spec["minutes"] = a.minutes

    entry = bench.require(a.device, allow_owner=a.owner_ok, platforms=("ios", "ipados"))
    udid = entry.get("udid")
    if not udid:
        raise SystemExit(f"{entry['name']} has no udid in the bench manifest")
    name = a.name or a.scenario or "adhoc"
    outdir = qa_dir("ios", name)
    print(f"[ios] {name} on {entry['name']} -> {outdir}")

    env = dict(BASE_ENV)
    if a.audible:
        env.pop(HOOK_MUTE, None)
        print("[ios] AUDIBLE run — the owner should have been asked first")
    env.update(spec["env"])

    g = Grader(outdir, device=entry["name"], scenario=name, env=env)
    try:
        with devlease.hold([bench.lease_name(entry)], task=f"ios_run {name}",
                           wait=a.lease_wait):
            return _run(entry, udid, env, spec, outdir, g, a)
    except RuntimeError as e:
        g.grade("device_leased", False, f"{e} — this run covers NOTHING")
        return g.finish()


def _run(entry, udid, env, spec, outdir, g, a):
    shots, alive_end, texts, launched = [], None, {}, False
    # No `return g.finish()` inside the try: it would write the report BEFORE the
    # finally graded the teardown, so a device left running could not fail the run.
    try:
        try:
            events = ad.launch_guarded(entry, BUNDLE, env, outdir, settle=6)
            g.report["launch_events"] = events
            launched = True
        except ad.LaunchFailed as e:
            g.grade("launched", False, str(e))
        if launched and a.url:
            ok, out = ad.launch(udid, BUNDLE, env, url=a.url)
            if not ok:
                g.grade("deep_link_launched", False, out[-200:])
                launched = False
            else:
                time.sleep(6)
        if launched:
            shots = capture_loop(udid, outdir, spec.get("minutes", 0.6))
            alive_end = ad.app_alive(udid)
            texts = ocr(shots)
    finally:
        if a.leave_running:
            print("[ios] --leave-running: NOT tearing down (the owner asked to look)")
        else:
            ok, lines = ad.teardown(entry)
            g.grade("left_as_found", ok, "; ".join(lines))
    if not launched:
        return g.finish()
    g.report["shots"] = len(shots)
    g.grade("captured_frames", len(shots) >= 3, f"{len(shots)} frames")
    g.grade("app_alive_to_end", alive_end is True, "process present at capture end"
            if alive_end else ("could not ask the device" if alive_end is None
                               else "process GONE at capture end (crash or exit)"))
    g.grade_glass(shots, texts, spec, APP_ANCHOR_RX)
    return g.finish()


if __name__ == "__main__":
    sys.exit(main())
