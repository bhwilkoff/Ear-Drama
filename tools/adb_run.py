"""Drive a REAL Android device (phone, Google TV, Fire TV) and grade the app from
the glass.

The adb-specific hazards below each cost a failed run on a previous app, and are
reproduced here rather than rediscovered:

  * CONNECT BEFORE EVERY COMMAND. A network device's TLS debugging port rotates
    after sleep, and the connection drops between commands. Every call goes
    through `adbs()`, which resolves the serial first.
  * A dump must DELETE the target file first — a failed `uiautomator dump`
    otherwise serves a STALE tree from some earlier session, which reads as our
    app showing another app's UI. The same rule applies to screenshots: every
    capture goes through devharness.capture_fresh (delete first, fresh only).
  * Retry a tree dump once: it is briefly empty during transitions.
  * `input tap` is INERT on the TV profile (motion events are not part of the
    focus grammar); it works on the phone profile. Scenarios here reach their
    surface by intent extra regardless — never by pressing blind. When a TV
    control must be pressed, KEYCODE_ENTER activates a Compose tvFocusable;
    KEYCODE_DPAD_CENTER does not (see tools/gtv_scenario.py).
  * On Fire OS `monkey` reports success but never foregrounds. Use `am start -n`.
  * A secure keyguard (a phone) is unlocked by the OWNER, ONCE. `svc power stayon
    true` plus a long screen_off_timeout keep it from re-engaging, so every later
    run wakes into an unlocked device. Check those settings BEFORE telling anyone
    "the phone is locked" — asking twice for a condition the harness can prevent is
    a harness bug. The harness never draws a pattern or types a passcode.
  * adb trust is silently revoked after 7 days unless
    `settings put global adb_allowed_connection_time 0` — the device then simply
    stops answering, which looks like it is off.

Devices come from the bench manifest (tools/bench.py). A device whose role is
owner-personal-never-touch is refused; owner-watches needs --owner-ok.

Usage:
    python3 tools/adb_run.py --list
    python3 tools/adb_run.py --device pixel --scenario home
    python3 tools/adb_run.py --device pixel --extra appname_start_tab=search \
        --expect "Search" --name adhoc
"""
from app_config import *  # app identity + calibrated thresholds

import argparse
import os
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_config  # noqa: E402
import bench  # noqa: E402
import devlease  # noqa: E402
from devharness import Grader, capture_fresh, ocr, qa_dir, sh  # noqa: E402

ADB_BIN = str(app_config.ADB)

# The DEBUG package, deliberately. The launch hooks open with
# `if (!BuildConfig.DEBUG) return`, so against the release build every intent
# extra is silently ignored and every scenario lands on Home — six of them once
# did, and all six PASSED, because a readable frame of the wrong screen satisfies
# every check that is not looking for the RIGHT screen. Override with
# APP_ADB_PKG only if you know the hooks are not needed.
PKG = os.environ.get("APP_ADB_PKG", ANDROID_PACKAGE_DEBUG)
ACTIVITY = ANDROID_MAIN_ACTIVITY
SHOT_EVERY = 3.0

# Applied to every launch unless a scenario overrides them. Doors are muted and
# time-bounded by default (app_config.ANDROID_DOOR_EXTRAS); --audible drops mute.
BASE_EXTRAS = {android_extra(HOOK_SKIP_ONBOARD): ("ez", "true"), **ANDROID_DOOR_EXTRAS}
MUTE_EXTRA = next((k for k in ANDROID_DOOR_EXTRAS if "mute" in k), None)

APP_ANCHOR_RX = APP_ANCHOR_RX  # see tools/app_config.py

TV_PLATFORMS = ("androidtv", "firetv")

# FILL IN: EXAMPLES matching what the template's starter honours — the extras
# android/app/.../navigation/LaunchDoors.kt reads: appname_start_tab (home|search),
# appname_start_item, appname_mute, appname_door_seconds, each derived from the
# Apple hook name by android_extra(). Add your app's surfaces the same way; an
# unknown tab value should be ignored by AppRoot rather than crash a sweep, so a
# typo here shows up as "wrong screen", not a crash.
# expect_any is calibrated against a real capture, never guessed, and tolerates
# the legitimate EMPTY state where one exists: a fresh debug install has no
# history, and an assertion that only knows the populated shape fails on a
# healthy screen. Tab labels are on every screen, so replace each regex with
# content unique to that surface. "forbid" narrows the error check for a screen
# whose known debug-build failure is not a regression (e.g. Play Billing returns
# no products for a debug package that is not Play-registered).
SCENARIOS = {
    "home":        {"extras": {android_extra(HOOK_START_TAB): ("es", "home")},   "minutes": 0.6,
                    "expect_any": r"Home"},                              # FILL IN
    "search":      {"extras": {android_extra(HOOK_START_TAB): ("es", "search")}, "minutes": 0.6,
                    "expect_any": r"Search"},                            # FILL IN
    # Mute is in every launch already (ANDROID_DOOR_EXTRAS); spelled out on the
    # scenario most likely to start playback.
    "item":        {"extras": {android_extra(HOOK_START_ITEM): ("es", QA_ITEM_ID),
                               android_extra(HOOK_MUTE): ("ez", "true")}, "minutes": 0.6,
                    "expect_any": QA_ITEM_RX},
    # The door bounds itself: the app leaves the item on its own clock.
    "door-return": {"extras": {android_extra(HOOK_START_ITEM): ("es", QA_ITEM_ID),
                               android_extra(HOOK_DOOR_SECONDS): ("ei", "10")},
                    "minutes": 0.6, "expect_any": QA_ITEM_RX,
                    "expect_end": r"Home"},                              # FILL IN
}

_ENTRY = {}


def serial_of(dev):
    e = _ENTRY.get(dev) or bench.get(dev) or {}
    return e.get("serial") or (f"{e['address']}:5555" if e.get("address") else dev)


def connect(dev):
    """Resolve a live serial, re-connecting if the port rotated. Returns the
    serial adb will accept right now."""
    serial = serial_of(dev)
    out = sh([ADB_BIN, "devices"], timeout=30).stdout
    if re.search(rf"^{re.escape(serial)}\s+device", out, re.M):
        return serial
    sh([ADB_BIN, "connect", serial], timeout=30)
    return serial


def adbs(dev, *args, timeout=60, binary=False):
    serial = connect(dev)
    cmd = [ADB_BIN, "-s", serial] + list(args)
    if binary:
        return subprocess.run(cmd, capture_output=True, timeout=timeout)
    return sh(cmd, timeout=timeout)


def device_state(dev):
    """What the device says about wake, keyguard and trust — measured, not guessed.
    Returns a dict of findings plus human-readable `notes`."""
    s = {"notes": []}
    power = adbs(dev, "shell", "dumpsys", "power", timeout=45).stdout
    m = re.search(r"mWakefulness=(\w+)", power)
    s["wakefulness"] = m.group(1) if m else "unknown"
    m = re.search(r"mStayOn=(\w+)", power)
    s["stayon"] = m.group(1) if m else "unknown"
    wm = adbs(dev, "shell", "dumpsys", "window", timeout=45).stdout
    m = re.search(r"(?:mDreamingLockscreen|isKeyguardShowing|mShowingLockscreen)=(\w+)", wm)
    s["keyguard"] = m.group(1) if m else "unknown"
    s["screen_off_timeout"] = adbs(dev, "shell", "settings", "get", "system",
                                   "screen_off_timeout", timeout=30).stdout.strip()
    s["adb_allowed_connection_time"] = adbs(
        dev, "shell", "settings", "get", "global", "adb_allowed_connection_time",
        timeout=30).stdout.strip()
    if s["adb_allowed_connection_time"] not in ("0",):
        s["notes"].append(
            f"adb_allowed_connection_time={s['adb_allowed_connection_time'] or 'default'}: "
            "adb trust is silently revoked after 7 days. Fix once: adb shell settings "
            "put global adb_allowed_connection_time 0")
    if s["keyguard"] == "true":
        protocol = ("The one-unlock protocol: the owner unlocks ONCE; `svc power "
                    "stayon true` + `settings put system screen_off_timeout 1800000` "
                    "stop it re-engaging, so no later run needs asking.")
        if s["stayon"] in ("false", "0", "unknown"):
            s["notes"].append("keyguard is showing and stayon is OFF — the setting was "
                              "lost, so the device re-locked. " + protocol)
        else:
            s["notes"].append("keyguard is showing although stayon is set — the owner "
                              "has not unlocked since boot. " + protocol)
    return s


def wake(dev):
    """Wake and dismiss an insecure keyguard. `stayon` keeps the screen up for the
    rest of the run so a long capture does not go dark halfway and get graded on
    blackness. A SECURE keyguard is not opened by this — it is prevented from
    re-engaging after the owner's one unlock."""
    adbs(dev, "shell", "svc", "power", "stayon", "true")
    adbs(dev, "shell", "input", "keyevent", "KEYCODE_WAKEUP")
    time.sleep(1.2)
    adbs(dev, "shell", "wm", "dismiss-keyguard")
    time.sleep(1.0)


def launch(dev, extras, deep_link=None):
    full = dict(BASE_EXTRAS)
    full.update(extras or {})
    adbs(dev, "shell", "am", "force-stop", PKG)
    time.sleep(0.8)
    if deep_link:
        args = ["shell", "am", "start", "-a", "android.intent.action.VIEW",
                "-d", deep_link, PKG]
    else:
        args = ["shell", "am", "start", "-n", f"{PKG}/{ACTIVITY}"]
    for k, (kind, v) in full.items():
        args += [f"--{kind}", k, v]
    r = adbs(dev, *args, timeout=90)
    if "Error" in (r.stdout + r.stderr) or "Exception" in (r.stdout + r.stderr):
        sys.exit(f"launch failed: {r.stdout[-300:]} {r.stderr[-300:]}")


def app_alive(dev):
    r = adbs(dev, "shell", "pidof", PKG, timeout=45)
    return bool(r.stdout.strip())


def teardown(dev):
    """Leave it as found: stop the app, then ASK THE DEVICE whether it stopped.
    A force-stop sent is not a process gone."""
    adbs(dev, "shell", "am", "force-stop", PKG, timeout=45)
    time.sleep(1.5)
    pid = adbs(dev, "shell", "pidof", PKG, timeout=45).stdout.strip()
    return (not pid), ("stopped — verified by pidof" if not pid
                       else f"STILL RUNNING (pid {pid}) after force-stop")


def capture_loop(dev, outdir, minutes):
    shots, i = [], 0
    deadline = time.time() + minutes * 60

    def grab(p):
        r = adbs(dev, "exec-out", "screencap", "-p", timeout=60, binary=True)
        if r.stdout:
            Path(p).write_bytes(r.stdout)
        return r

    while time.time() < deadline:
        p = outdir / f"shot-{i:04d}.png"
        ok, why = capture_fresh(p, grab)
        if ok:
            shots.append((time.time(), p))
        else:
            print(f"[adb] capture {p.name} refused — {why}")
            time.sleep(2)
        i += 1
        time.sleep(max(0, SHOT_EVERY - 1.0))
    return shots


def logcat_errors(dev):
    """Crash-adjacent lines from OUR pid only. A stack trace explains a dead app
    that the glass can only report as 'gone'."""
    pid = adbs(dev, "shell", "pidof", PKG, timeout=45).stdout.strip().split(" ")[0]
    if not pid:
        return ""
    r = adbs(dev, "shell", "logcat", "-d", f"--pid={pid}", "-t", "200", timeout=60)
    return "\n".join(l for l in r.stdout.splitlines()
                     if re.search(r"\bE/|FATAL|Exception", l))[-2000:]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--device", default="pixel",
                    help="bench name (pixel|androidtv|firetv|…) or a raw serial")
    ap.add_argument("--scenario")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--minutes", type=float)
    ap.add_argument("--extra", action="append", default=[],
                    help="k=v (string extra) — use k:ez=true for a boolean")
    ap.add_argument("--link", help="deep link, e.g. appname://item/example-item")
    ap.add_argument("--expect", help="ad-hoc expect_any regex")
    ap.add_argument("--name")
    ap.add_argument("--owner-ok", action="store_true",
                    help="allow an owner-watches device (ask the owner first)")
    ap.add_argument("--audible", action="store_true",
                    help="drop the mute door extra (ask the owner first)")
    a = ap.parse_args()

    if a.list:
        for k, v in SCENARIOS.items():
            print(f"  {k:12s} {v['extras']}")
        return 0

    name_dev = a.device
    if bench.get(name_dev) is None and name_dev == "pixel" and bench.get("android"):
        name_dev = "android"            # simple app_config.DEVICES form
    entry = bench.require(name_dev, allow_owner=a.owner_ok,
                          platforms=("android",) + TV_PLATFORMS)
    _ENTRY[name_dev] = entry
    profile = "tv" if entry.get("platform") in TV_PLATFORMS else "phone"

    spec = dict(SCENARIOS.get(a.scenario, {"extras": {}, "minutes": 0.6}))
    spec["extras"] = dict(spec.get("extras", {}))
    for kv in a.extra:
        k, _, v = kv.partition("=")
        kind = "es"
        if ":" in k:
            k, _, kind = k.partition(":")
        spec["extras"][k] = (kind, v)
    if a.expect:
        spec["expect_any"] = a.expect
    if a.minutes:
        spec["minutes"] = a.minutes
    if a.audible and MUTE_EXTRA:
        BASE_EXTRAS.pop(MUTE_EXTRA, None)
        print("[adb] AUDIBLE run: the app will make sound on a real device. "
              "Ask the owner before running this.")

    name = a.name or a.scenario or "adhoc"
    outdir = qa_dir(f"adb-{a.device}", name)
    print(f"[adb] {name} on {a.device} ({profile}) -> {outdir}")

    lease = bench.lease_name(entry)
    try:
        with devlease.hold([lease], task=f"adb_run {name}"):
            return _run(name_dev, a, spec, name, outdir)
    except RuntimeError as e:
        print(f"[adb] SKIP — {e}. This run covers NOTHING on {a.device}.")
        return 2


def _run(dev, a, spec, name, outdir):
    st = device_state(dev)
    print(f"[adb] wakefulness={st['wakefulness']} keyguard={st['keyguard']} "
          f"stayon={st['stayon']} screen_off_timeout={st['screen_off_timeout']}")
    for n in st["notes"]:
        print(f"[adb] NOTE: {n}")

    wake(dev)
    launch(dev, spec["extras"], a.link)
    time.sleep(5)   # let the first real frame render before the first capture
    shots = capture_loop(dev, outdir, spec.get("minutes", 0.6))
    alive_end = app_alive(dev)
    err = "" if alive_end else logcat_errors(dev)
    texts = ocr(shots)

    g = Grader(outdir, device=a.device, scenario=name, device_state=st,
               extras={k: v[1] for k, v in spec["extras"].items()}, shots=len(shots))
    g.grade("captured_frames", len(shots) >= 3, f"{len(shots)} frames")
    g.grade("app_alive_to_end", alive_end, "process present at capture end"
            if alive_end else "process GONE at capture end (crash or exit)")
    if err:
        (outdir / "logcat-errors.txt").write_text(err)
        print(f"[adb] wrote logcat-errors.txt ({len(err)} bytes)")
    g.grade_glass(shots, texts, spec, APP_ANCHOR_RX)
    ok, detail = teardown(dev)
    g.grade("left_as_found", ok, detail)
    return g.finish()


if __name__ == "__main__":
    sys.exit(main())
