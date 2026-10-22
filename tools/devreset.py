"""Return every device to a known, empty state — and SAY what it is about to test.

Two problems, one cause. Nothing in this harness ever put a device BACK: a run
left the app wherever it finished — mid-round, still in a room, hosting a night —
and the next run launched on top of that. So a test could inherit the previous
test's screen, and looking at a device on the desk told you nothing about what was
being tested on it.

    reset("pixel")                     # stop the app, leave the device idle
    reset_all(["ipad", "pixel"])       # in parallel where the tool allows
    label("pixel", "daily · empty state")   # what this device is for, on its screen

`label` sets APP_QA_LABEL, which every client renders as a small banner. It is
inert when unset, so it costs a shipped build nothing — and it means a photograph
of the bench is self-describing, instead of six screens that all look like the app.
"""
from app_config import *  # app identity + calibrated thresholds

import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bench  # noqa: E402

APKG = ANDROID_PACKAGE_DEBUG
APPLE_PLATFORMS = ("ios", "ipados", "tvos")
ANDROID_PLATFORMS = ("android", "androidtv", "firetv")


def _run(cmd, timeout=60, env=None):
    e = dict(os.environ, **(env or {}))
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=e)
        return r.returncode == 0, (r.stdout + r.stderr).strip()
    except (subprocess.SubprocessError, OSError) as ex:
        return False, str(ex)[:200]


def _pkill(cmd):
    """pkill exits 1 when NOTHING matched, which is the state a reset wants. Treating
    that as a failure made "the app was not running" indistinguishable from "the app
    could not be stopped" — and a reset that cries wolf is one people stop reading."""
    ok, out = _run(cmd)
    return (True, "not running") if not ok and not out else (ok, out)


def reset(dev):
    """Stop the app on `dev` (a bench name). Returns (ok, detail).

    Deliberately a STOP, not a data wipe. `adb pm clear` would also erase records,
    streaks and the sign-in — state a test may legitimately need, and state that
    belongs to the owner on their own devices. What causes a stale screen is a
    running process, not saved data.

    Apple: devicectl terminates by PID, and `info processes` prints EXECUTABLE
    PATHS, not bundle ids — this reset used to look for the bundle id in that
    output, never found it, and reported "not running" about a live app. It now
    matches the exact executable (apple_device.terminate_verified) and asks the
    device afterwards whether it is gone.

    A never-touch device is refused: stopping an app on somebody's personal phone
    is touching it."""
    try:
        e = bench.require(dev, allow_owner=True)
    except bench.RefusedDevice as ex:
        return False, str(ex)
    platform = e.get("platform") or dev
    if platform in APPLE_PLATFORMS:
        import apple_device
        if not e.get("udid"):
            return False, "no udid on the bench"
        return apple_device.terminate_verified(e["udid"])
    if platform in ANDROID_PLATFORMS:
        serial = e.get("serial") or e.get("address")
        ok, out = _run([str(ADB), "-s", serial, "shell", "am", "force-stop", APKG])
        if not ok:
            return False, out[:200]
        # A stop command sent is not a process gone — ask.
        _, pid = _run([str(ADB), "-s", serial, "shell", "pidof", APKG])
        return (not pid.strip(), "stopped — verified" if not pid.strip()
                else f"STILL RUNNING (pid {pid.strip()})")
    if platform == "macos" or dev == "mac":
        return _pkill(["pkill", "-x", APPLE_EXECUTABLE])
    if platform == "windows" or dev == "windows":
        import winbox
        winbox.quit_app()
        return True, "stopped"
    if platform == "web" or dev == "web":
        return _pkill(["pkill", "-f", "appname-cdp-profile"])
    return False, f"unknown device {dev!r}"


def reset_all(devs, verbose=True):
    out = {}
    for d in devs:
        ok, detail = reset(d)
        out[d] = ok
        if verbose:
            # A failed reset is reported, never swallowed: the next test would then
            # be grading the previous test's screen and would look like it passed.
            print(f"  reset {d:10} {'ok' if ok else 'FAILED — ' + detail[:70]}")
    return out


def label_env(text):
    """The env/extras a client needs to draw the banner."""
    return {"APP_QA_LABEL": text}
