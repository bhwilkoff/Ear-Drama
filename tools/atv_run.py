#!/usr/bin/env python3
"""External-observation scenario runner for a paired Apple TV.

Launches the app with DebugHooks env, screenshots the GLASS on an interval, OCRs
every frame, optionally sends real remote presses (pyatv Companion), and grades
explicit assertions. The app's own claims are never the evidence for what a
viewer sees; the screen is.

Every run, in one process: lease the device -> note its power state -> wake
(polled) -> launch (muted, time-bounded doors) -> prove alive AND frontmost ->
capture (power checked before every capture and press; fresh files only) -> grade
-> LEAVE IT AS FOUND (app terminated and verified gone; a TV that was off is
turned back off and read back) -> release the lease.

Usage:
  python3 tools/atv_run.py --list
  python3 tools/atv_run.py --scenario home
  python3 tools/atv_run.py --device atv-control --scenario home   # another bench TV
  python3 tools/atv_run.py --env APP_START_ITEM=example-item --minutes 1 \
      --expect "Play|Details" --name adhoc-item

Requires: a bench entry for the TV (tools/bench.py; default name "atv") with udid,
and address + pyatv_id for wake/press/power; pyatv in ~/.pyatv-venv (Python 3.12);
the app installed. The OCR binary is built on first use (build/bin/screenocr).
"""
from app_config import *  # app identity + calibrated thresholds

import argparse, json, re, subprocess, sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import apple_device as ad  # noqa: E402
import bench  # noqa: E402
import devlease  # noqa: E402
from devharness import OCR_FAILED, frame_darkness, frame_text, ocr, qa_dir  # noqa: E402

BUNDLE = APPLE_BUNDLE_ID
SHOT_EVERY = 4.0   # 4K captures pressure the device's screenshot daemon;
                   # 2.5s coincided with jetsam events on a previous app's bench

BASE_ENV = {HOOK_SKIP_ONBOARD: "1", **DOOR_DEFAULTS}

# Strings that must NEVER appear on the glass in a healthy run. Extend as
# findings land — every user-visible error string the app can render belongs
# here unless a scenario is specifically ABOUT that error.
# Word-bound: bare "Error" matched inside "terrorists" in a question prompt
# and failed a healthy run. Content can contain any substring.
FORBID_DEFAULT = FORBIDDEN

# ── Scenario table ─────────────────────────────────────────────────────────────
# expect_any:  regex must match some frame's OCR text (anywhere).
# expect_end:  regex must match one of the LAST 4 frames (final state).
# expect_seq:  list of regexes that must first-match in this order over time.
# forbid_extra: regex added to FORBID_DEFAULT; it must match NO frame.
# min_center_stddev: (thresh, frames) — at least `frames` frames must have
#              centerLuma.stddev >= thresh (a loaded photo region; a flat/blank
#              image area fails this). e.g. min_center_stddev=(28.0, 3) on a
#              screen whose center is artwork.
# presses:     [(seconds_after_launch, key), ...] real remote input via pyatv
#              ("up"/"down"/"select"/...), or "sh:<command>" to start a helper.
#              ONE pyatv press can block captures for 45-60 s on some boxes, so a
#              multi-press navigation is better served by a launch door.
# drop_env:    BASE_ENV keys this scenario must NOT send.
#
# FILL IN: these are EXAMPLES matching what the template's starter honours
# (APP_START_TAB home|search, APP_START_ITEM, APP_MUTE, APP_DOOR_SECONDS — see
# apple/Core/Store/LaunchDoors.swift). Replace each regex with words calibrated
# against a real capture of YOUR screen, and add one scenario per surface your app
# has. A regex written from imagination fails on correct pixels, or passes on the
# wrong screen: tab titles are on every screen, so a signature must be content
# unique to the surface.
SCENARIOS = {
    "home": dict(
        env={HOOK_START_TAB: "home"}, minutes=0.4,
        expect_any=r"Home", expect_end=r"Home",                          # FILL IN
        note="Home tab renders."),
    "search": dict(
        env={HOOK_START_TAB: "search"}, minutes=0.4,
        expect_any=r"Search",                                            # FILL IN
        note="Search tab renders."),
    "item": dict(
        # Mute is already in every launch (DOOR_DEFAULTS); it is spelled out here
        # because this is the scenario most likely to start playback.
        env={HOOK_START_ITEM: QA_ITEM_ID, HOOK_MUTE: "1"}, minutes=0.5,
        expect_any=QA_ITEM_RX,
        note="APP_START_ITEM opens the item's detail, muted."),
    "door-return": dict(
        # The door bound itself: the app must leave the item on its own clock.
        env={HOOK_START_ITEM: QA_ITEM_ID, HOOK_DOOR_SECONDS: "15"}, minutes=0.8,
        expect_seq=[QA_ITEM_RX, r"Home"], expect_end=r"Home",            # FILL IN
        note="APP_DOOR_SECONDS ends the door and returns to Home by itself."),
}


def capture_loop(entry, atv, outdir, minutes, presses, log):
    """Capture on an interval. Power is checked BEFORE every capture and press: a
    sleeping Apple TV returns a valid black PNG, so the frame cannot be trusted to
    say the TV was off — the TV has to be asked. A frame taken while the TV was not
    on is not captured at all; the blind window is logged instead."""
    udid = entry["udid"]
    shots, i = [], 0
    t0 = time.time()
    deadline = t0 + minutes * 60
    pending = sorted(presses or [], key=lambda p: p[0])
    while time.time() < deadline:
        state = atv.power_state() if atv.available else None
        if state == "off":
            log.append(f"{time.time() - t0:.0f}s TV off/dozing — frame skipped, waking")
            print(f"[atv] TV reports Off at +{time.time() - t0:.0f}s — waking (blind window logged)")
            atv.wake()
            continue
        while pending and time.time() - t0 >= pending[0][0]:
            _, key = pending.pop(0)
            if key.startswith("sh:"):
                print(f"[atv] action: {key[3:]}")
                subprocess.Popen(key[3:], shell=True)
            else:
                ok, why = atv.press(key)
                print(f"[atv] press: {key}" + ("" if ok else f" — FAILED: {why}"))
                log.append(f"press {key}: {'ok' if ok else why}")
        p = outdir / f"shot-{i:04d}.png"
        ok, why = ad.capture(udid, p, timeout=30)
        if not ok:
            # One flaky capture must not kill the scenario — skip the frame, keep
            # the run, say so. A stale file is refused, never graded.
            print(f"[atv] capture {p.name}: {why} — skipping frame")
            log.append(f"capture {p.name}: {why}")
            time.sleep(2)
            i += 1
            continue
        shots.append((time.time(), p))
        # Doze signature as a SECOND opinion: a near-all-black frame while power
        # said On is either a dark scene or the television (not the Apple TV) off.
        dk = frame_darkness(p)
        if dk and dk[1] > 99.5:
            print(f"[atv] {p.name} is {dk[1]}% black — dark scene, or the TELEVISION "
                  "is off / on another input (the Apple TV cannot fix that)")
            log.append(f"{p.name} {dk[1]}% black")
        i += 1
        time.sleep(max(0, SHOT_EVERY - 1.0))
    return shots


def main():
    try:
        return _main()
    except SystemExit:
        raise
    except Exception:
        import traceback
        traceback.print_exc()
        # A runner crash must leave a report naming itself — a missing report
        # reads as "interrupted" and hides the crash class entirely.
        try:
            outdir = Path(getattr(_main, "outdir", QA_ROOT))
            outdir.mkdir(parents=True, exist_ok=True)
            (outdir / "report.json").write_text(json.dumps(
                {"error": traceback.format_exc().splitlines()[-1]}))
        except Exception:
            pass
        return 3


def _main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--device", default="atv", help="bench name (default atv) or UDID")
    ap.add_argument("--scenario")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--minutes", type=float)
    ap.add_argument("--env", action="append", default=[], help="K=V extra env")
    ap.add_argument("--expect", help="ad-hoc expect_any regex")
    ap.add_argument("--luma", help="ad-hoc image gate THRESH:FRAMES (e.g. 28:2)")
    ap.add_argument("--name", default=None)
    ap.add_argument("--outdir", default=None)
    ap.add_argument("--owner-ok", action="store_true",
                    help="allow a device whose role is owner-watches (ask first)")
    ap.add_argument("--audible", action="store_true",
                    help="drop the mute door (ask the owner first)")
    ap.add_argument("--leave-running", action="store_true",
                    help="skip teardown — only when the owner asked to look at it")
    ap.add_argument("--lease-wait", type=int, default=0,
                    help="seconds to wait for a leased device (default: skip now)")
    args = ap.parse_args()

    if args.list:
        for k, v in SCENARIOS.items():
            print(f"{k:20s} {v['note']}")
        return 0

    spec = dict(SCENARIOS.get(args.scenario, {"env": {}, "minutes": 1.0}))
    spec["env"] = dict(spec.get("env", {}))
    name = args.name or args.scenario or "adhoc"
    for kv in args.env:
        k, _, v = kv.partition("=")
        spec["env"][k] = v
    if args.minutes:
        spec["minutes"] = args.minutes
    if args.expect:
        spec["expect_any"] = args.expect
    if args.luma:
        t, n = args.luma.split(":")
        spec["min_center_stddev"] = (float(t), int(n))

    entry = bench.require(args.device, allow_owner=args.owner_ok, platforms=("tvos",))
    if not entry.get("udid"):
        raise SystemExit(f"{entry['name']} has no udid in the bench manifest")
    outdir = Path(args.outdir) if args.outdir else qa_dir("atv", name)
    outdir.mkdir(parents=True, exist_ok=True)
    _main.outdir = outdir
    print(f"[atv] scenario {name} on {entry['name']} -> {outdir}")

    env = {k: v for k, v in BASE_ENV.items() if k not in spec.get("drop_env", ())}
    if args.audible:
        env.pop(HOOK_MUTE, None)
        print("[atv] AUDIBLE run — the owner should have been asked first")
    env.update(spec.get("env", {}))

    # One lease, one process, the whole run (install/launch/capture/teardown).
    try:
        with devlease.hold([bench.lease_name(entry)], task=f"atv_run {name}",
                           wait=args.lease_wait):
            return _run(entry, spec, env, name, outdir, args)
    except RuntimeError as e:
        print(f"[atv] SKIP — {e}. This run covers NOTHING; never read it as a pass.")
        (outdir / "report.json").write_text(json.dumps(
            {"scenario": name, "result": "SKIP", "why": str(e)}))
        return 2


def _run(entry, spec, env, name, outdir, args):
    atv = ad.ATV(entry)
    found_power = atv.power_state()
    print(f"[atv] found the TV: power {found_power or 'unknown'}"
          + ("" if atv.available else f" ({atv.why_unavailable()})"))
    report = {"scenario": name, "device": entry["name"], "found_power": found_power,
              "env": env, "assertions": {}}
    log = []

    def grade(k, ok, ev):
        report["assertions"][k] = {"pass": bool(ok), "evidence": ev}
        print(f"  [{'PASS' if ok else 'FAIL'}] {k}: {ev}")

    shots, alive_end, texts, launched = [], None, {}, True
    try:
        try:
            report["launch_events"] = ad.launch_guarded(entry, BUNDLE, env, outdir)
        except ad.LaunchFailed as e:
            grade("launched", False, str(e))
            launched = False
        if launched:
            shots = capture_loop(entry, atv, outdir, spec.get("minutes", 1.0),
                                 spec.get("presses"), log)
            print(f"[atv] {len(shots)} screenshots")
            alive_end = ad.app_alive(entry["udid"])
            texts = ocr(shots)
    finally:
        # Graded like every other assertion, BEFORE the report is written: a TV
        # left on, or an app left running, fails the run.
        if args.leave_running:
            print("[atv] --leave-running: NOT tearing down (the owner asked to look)")
        else:
            ok, lines = ad.teardown(entry, found_power=found_power)
            grade("left_as_found", ok, "; ".join(lines))
    if not launched:
        return _finish(report, outdir)
    report["shots"] = len(shots)
    report["capture_log"] = log

    grade("captured_frames", len(shots) >= 3, f"{len(shots)} frames")
    grade("app_alive_to_end", alive_end is True, "process present at capture end"
          if alive_end else ("could not ask the device" if alive_end is None
                             else "process GONE at capture end (crash or exit)"))
    if OCR_FAILED in texts:
        grade("ocr_available", False, texts[OCR_FAILED])
        return _finish(report, outdir)

    ordered = [(w, frame_text(texts.get(p.name, {}))) for w, p in shots]
    all_text = " | ".join(t for _, t in ordered)
    readable = max((len(texts.get(p.name, {}).get("allText", [])) for _, p in shots),
                   default=0)
    if readable < MIN_OCR_LINES:
        dk = frame_darkness(shots[-1][1]) if shots else None
        grade("screen_readable", False, f"best frame had {readable} OCR lines"
              + (f"; last frame {dk[1]}% black (mean luma {dk[0]})" if dk else "")
              + " — nothing below was graded")
        return _finish(report, outdir)

    if "expect_any" in spec:
        m = re.search(spec["expect_any"], all_text, re.I)
        grade("expect_any", bool(m), f"/{spec['expect_any']}/ "
              + (f"matched {m.group(0)!r}" if m else "matched nothing"))
    if "expect_end" in spec:
        tail = " | ".join(t for _, t in ordered[-4:])
        m = re.search(spec["expect_end"], tail, re.I)
        grade("expect_end", bool(m), f"/{spec['expect_end']}/ in last frames"
              + ("" if m else " — NOT found"))
    for i, rx in enumerate(spec.get("expect_seq", [])):
        hit = next((j for j, (_, t) in enumerate(ordered) if re.search(rx, t, re.I)), None)
        grade(f"seq_{i}_{rx[:18]}", hit is not None,
              f"first match at frame {hit}" if hit is not None else "never matched")
        if hit is not None:
            ordered = ordered[hit:]   # next regex must match at/after this frame

    forbid = FORBID_DEFAULT + ("|" + spec["forbid_extra"] if spec.get("forbid_extra") else "")
    bad = []
    for _, p in shots:
        m = re.search(forbid, frame_text(texts.get(p.name, {})), re.I)
        if m:
            bad.append((p.name, m.group(0)))
    grade("no_error_text", not bad,
          "clean" if not bad else f"{len(bad)} frames, e.g. {bad[0]}")

    if "min_center_stddev" in spec:
        thresh, need = spec["min_center_stddev"]
        rich = [p.name for _, p in shots
                if (texts.get(p.name, {}).get("centerLuma") or {}).get("stddev", 0) >= thresh]
        grade("image_region_loaded", len(rich) >= need,
              f"{len(rich)} frames with center stddev >= {thresh} (need {need})")

    (outdir / "ocr.json").write_text(json.dumps(texts, indent=1))
    return _finish(report, outdir)


def _finish(report, outdir):
    failed = [k for k, v in report["assertions"].items() if not v["pass"]]
    report["result"] = "OK" if not failed else "FAIL"
    (outdir / "report.json").write_text(json.dumps(report, indent=1))
    print(f"\nRESULT: {'OK' if not failed else 'FAIL — ' + ', '.join(failed)}")
    print(f"report: {outdir}/report.json")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
