"""Run the iOS tap tier (apple/UITests, scheme EarDramaUITests) on the real iPhone.

The glass runner (tools/ios_run.py) has no press verb; this is the press tier. It
holds the device lease for the whole run, builds and runs the XCUITest bundle with
`xcodebuild test`, exports every screenshot the tests attached, prints pass/fail per
test from the result bundle, and compares the device's systemCrashLogs list before
and after: a new EarDrama-*.ips is a FAIL whatever the tests said.

It builds once (`build-for-testing`), installs the app with devicectl, which returns
only when the install is done, confirms the installed build is this one, and only then
runs the tests (`test-without-building`), so "installed" is a fact the run states,
not an assumption. The 2026-10-28 "first launch quits" (LOOP-PLAN P8) was not the app
exiting: XCUIApplication.open(URL) ends the running app and asks the device for a new
one, and on the first open(URL) of some runs the device started none (CoreDevice
10004). That test is reported BLIND launch_dropped, never as an app failure, and the
result bundle carries the device's diagnostics (they were lost before: see env()). Every exported frame is
read by OCR; a frame showing a system overlay (SYSTEM_OVERLAY_RX: Screen Time's Time
Limit, a permission alert) fails its test, because XCUITest's element queries match
through the overlay, and a frame OCR cannot read fails the run as blind.

Every test launch is muted (APP_MUTE) inside the tests themselves. The app is
terminated and the device asked to confirm at the end (apple_device.terminate_verified).

Usage:
    python3 tools/ios_uitest.py                         # the whole suite on `iphone`
    python3 tools/ios_uitest.py --only TabSmokeUITests  # xcodebuild -only-testing
    python3 tools/ios_uitest.py --only QueueUITests/testAddReorderRemove
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

os.environ.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_config  # noqa: E402
import apple_device as ad  # noqa: E402
import bench  # noqa: E402
import devharness as dh  # noqa: E402
import devlease  # noqa: E402

REPO = app_config.REPO
SCHEME = "EarDramaUITests"
TEAM = os.environ.get("ASC_TEAM_ID", "L2G756LY8N")
LEASE_TTL = 900
DERIVED = REPO / "build" / "uitest-dd"
CRASH_RX = re.compile(rf"^\s*({re.escape(app_config.APPLE_APP_NAME)}-[\w.-]+\.ips)\b", re.M)


def env():
    e = dict(os.environ)
    e.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    # xcodebuild collects the device's diagnostics on a failure by running `xcrun devicectl`
    # in an environment that drops DEVELOPER_DIR, so with xcode-select on the Command Line
    # Tools it found no devicectl and every failure came back without device logs. xcrun
    # falls back to PATH; a one-link directory first on PATH gives it the Xcode one.
    shim = REPO / "build" / "devicectl-path"
    tool = Path(e["DEVELOPER_DIR"]) / "usr" / "bin" / "devicectl"
    if tool.exists():
        shim.mkdir(parents=True, exist_ok=True)
        link = shim / "devicectl"
        if not link.is_symlink():
            link.symlink_to(tool)
        e["PATH"] = f"{shim}:{e.get('PATH', '')}"
    return e


def crash_logs(udid):
    r = ad.devicectl("device", "info", "files", "--device", udid,
                     "--domain-type", "systemCrashLogs", timeout=120)
    if r.returncode != 0:
        return None
    return set(CRASH_RX.findall(r.stdout))


def collect_tests(node, out):
    """Flatten `xcresulttool get test-results tests` into (name, result) leaves."""
    if node.get("nodeType") == "Test Case":
        out.append((node.get("name", "?"), node.get("result", "?")))
    for c in node.get("children", []) or []:
        collect_tests(c, out)


def export_shots(bundle, dest):
    dest.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(["xcrun", "xcresulttool", "export", "attachments",
                        "--path", str(bundle), "--output-path", str(dest)],
                       capture_output=True, text=True, env=env())
    if r.returncode != 0:
        print(f"[uitest] attachment export failed: {r.stderr[-300:]}")
        return {}
    names = {}
    mf = dest / "manifest.json"
    if mf.is_file():
        for t in json.loads(mf.read_text()):
            for a in t.get("attachments", []):
                names.setdefault(t.get("testIdentifier", "?"), []).append(
                    (a.get("suggestedHumanReadableName", ""), a.get("exportedFileName", "")))
    return names


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--device", default="iphone")
    ap.add_argument("--only", action="append", default=[],
                    help="Class or Class/testName, repeatable")
    ap.add_argument("--catalog-seed", help="CATALOG_SEED_PATH for the build")
    ap.add_argument("--lease-wait", type=int, default=0)
    a = ap.parse_args()

    entry = bench.require(a.device, platforms=("ios", "ipados"))
    udid = entry.get("udid")
    if not udid:
        raise SystemExit(f"{entry['name']} has no udid in the bench manifest")
    stamp = time.strftime("%Y-%m-%d")
    outdir = app_config.QA_ROOT / f"ios-uitest-{stamp}"
    outdir.mkdir(parents=True, exist_ok=True)
    bundle = outdir / f"result-{int(time.time())}.xcresult"
    print(f"[uitest] {entry['name']} -> {outdir}")

    try:
        with devlease.hold([bench.lease_name(entry)], task="ios_uitest",
                           ttl=LEASE_TTL, wait=a.lease_wait):
            return run(entry, udid, a, outdir, bundle)
    except RuntimeError as e:
        print(f"FAIL device_leased: {e} — this run covers NOTHING")
        return 1


def xcodebuild(action, udid, a, log, extra):
    cmd = ["xcodebuild", action, "-project", str(REPO / "EarDrama.xcodeproj"),
           "-scheme", SCHEME, "-destination", f"id={udid}", "-derivedDataPath", str(DERIVED),
           f"DEVELOPMENT_TEAM={TEAM}", "-allowProvisioningUpdates"] + extra
    seed = a.catalog_seed or os.environ.get("CATALOG_SEED_PATH")
    if seed:
        cmd.append(f"CATALOG_SEED_PATH={seed}")
    print(f"[uitest] xcodebuild {action} ... (log {log})")
    with log.open("w") as fh:
        return subprocess.run(cmd, stdout=fh, stderr=subprocess.STDOUT, env=env(), cwd=REPO).returncode


def install_and_confirm(udid, app):
    """devicectl install blocks until iOS has the app; then ask the device which build
    it holds. Returns (ok, detail)."""
    want = subprocess.run(["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleVersion",
                           str(app / "Info.plist")], capture_output=True, text=True).stdout.strip()
    r = ad.devicectl("device", "install", "app", "--device", udid, str(app), timeout=600)
    if r.returncode != 0:
        return False, f"install failed: {(r.stdout + r.stderr).strip()[-300:]}"
    q = ad.devicectl("device", "info", "apps", "--device", udid,
                     "--bundle-id", app_config.APPLE_BUNDLE_ID, timeout=120)
    got = re.search(rf"{re.escape(app_config.APPLE_BUNDLE_ID)}\s+(\S+)\s+(\S+)", q.stdout)
    if not got:
        return False, f"the device does not list {app_config.APPLE_BUNDLE_ID} after the install"
    if want and want not in got.groups():
        return False, f"the device holds build {got.groups()}, not this build ({want})"
    return True, f"installed build {want}"


LAUNCH_DROP_RX = re.compile(
    r"error: -\[\w+\.(\w+) (\w+)\] : Failed to get launch progress for .*?"
    r"process identifier of the launched application could not be determined")
OPEN_URL_RX = re.compile(r"^\s+t =\s+[\d.]+s\s+(Open \S+ with URL \S+)")


def dropped_launches(log_text):
    """Tests whose launch the DEVICE dropped (CoreDevice 10004): XCTest ended the running
    app for an XCUIApplication launch or open(URL) and no new process started, so
    Springboard came back with no crash log. Returns [(Class/test, step)]. Seen
    2026-10-28 on the first open(URL) of a run (LOOP-PLAN P8): the app's own output
    stops when XCTest ends it and no process follows; it is not an app exit."""
    out, step = [], None
    for line in log_text.splitlines():
        if line.startswith("Test Case "):
            step = None
        elif s := OPEN_URL_RX.match(line):
            step = s.group(1)
        elif m := LAUNCH_DROP_RX.search(line):
            out.append((f"{m.group(1)}/{m.group(2)}", step or "launch()"))
    return out


def overlay_check(outdir_shots, shots):
    """OCR every exported frame. Returns {test id: [failure lines]}, with key None for
    frames the instrument could not read (blind, never a pass)."""
    frames = [(tid, outdir_shots / f) for tid, items in shots.items() for _, f in items
              if f.lower().endswith(".png")]
    bad = {}
    if not frames:
        return bad
    got = dh.ocr([(0, p) for _, p in frames])
    for tid, p in frames:
        d = got.get(p.name)   # ScreenOCR keys its output by file name
        if d is None:   # one retry alone: a batch once hit a passing Vision engine error
            d = dh.ocr([(0, p)]).get(p.name)
        if d is None:
            bad.setdefault(None, []).append(f"{tid}: {p.name} unreadable by OCR")
            continue
        text = " ".join(e.get("text", "") for e in d.get("allText") or [])
        m = re.search(app_config.SYSTEM_OVERLAY_RX, text, re.I)
        if m:
            bad.setdefault(tid, []).append(f"{p.name} shows a system overlay ({m.group(0)!r})")
    return bad


def run(entry, udid, a, outdir, bundle):
    before = crash_logs(udid)
    if before is None:
        print("[uitest] could not list systemCrashLogs before the run — crash check UNKNOWN")
    stamp = int(time.time())
    log = outdir / f"xcodebuild-{stamp}.log"
    if xcodebuild("build-for-testing", udid, a, outdir / f"build-{stamp}.log", []) != 0:
        print(f"FAIL build_for_testing: see {outdir / f'build-{stamp}.log'} — this run covers NOTHING")
        return 1
    app = DERIVED / "Build" / "Products" / "Debug-iphoneos" / f"{app_config.APPLE_APP_NAME}.app"
    ok, detail = install_and_confirm(udid, app)
    print(f"{'PASS' if ok else 'FAIL'} installed: {detail}")
    if not ok:
        print("FAIL suite: the app on the device is not this build — this run covers NOTHING")
        return 1
    extra = ["-resultBundlePath", str(bundle), "-collect-test-diagnostics", "on-failure"]
    for o in a.only:
        extra += ["-only-testing", f"{SCHEME}/{o}"]
    # Renew-free: hold() renews in the background for as long as this process lives.
    rc = xcodebuild("test-without-building", udid, a, log, extra)
    ok_all = True
    try:
        tests = []
        if bundle.exists():
            r = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "tests",
                                "--path", str(bundle)], capture_output=True, text=True,
                               env=env())
            if r.returncode == 0:
                for n in json.loads(r.stdout).get("testNodes", []):
                    collect_tests(n, tests)
        shots = export_shots(bundle, outdir / "attachments" / bundle.stem) if bundle.exists() else {}
        if not tests:
            print(f"FAIL no_tests_ran: xcodebuild rc={rc}; see {log}")
            ok_all = False
        overlays = overlay_check(outdir / "attachments" / bundle.stem, shots)
        dropped = dict(dropped_launches(log.read_text(errors="replace")) if log.exists() else [])
        for name, result in tests:
            hits = [v for tid, v in overlays.items() if tid and tid.split("/")[-1] == name]
            drop = next((s for tid, s in dropped.items() if tid.split("/")[-1] == name.rstrip("()")), None)
            good = result == "Passed" and not hits
            ok_all &= good
            if drop and not good:
                print(f"BLIND {name} ({result}): launch_dropped at '{drop}': XCTest ended the "
                      "running app and the device started no new one (CoreDevice 10004). No app "
                      "process ran, so this tests nothing and is not an app exit (LOOP-PLAN P8); "
                      "device diagnostics are in the result bundle")
                continue
            print(f"{'PASS' if good else 'FAIL'} {name} ({result})")
            for h in (x for v in hits for x in v):
                print(f"  FAIL overlay: {h} — XCUITest matched through it; this pass proves nothing")
        for line in overlays.get(None, []):
            print(f"FAIL overlay_check_blind: {line}")
            ok_all = False
        for tid, items in shots.items():
            print(f"  frames {tid}: " + ", ".join(f"{h or f}" for h, f in items))
    finally:
        t_ok, detail = ad.terminate_verified(udid)
        print(f"{'PASS' if t_ok else 'FAIL'} left_as_found: {detail}")
        ok_all &= t_ok

    after = crash_logs(udid)
    if before is None or after is None:
        print("FAIL crash_logs: could not read the device's systemCrashLogs")
        ok_all = False
    else:
        new = sorted(after - before)
        if new:
            print(f"FAIL new_crash_logs: {', '.join(new)}")
            ok_all = False
        else:
            print(f"PASS no_new_crash_logs ({len(after)} EarDrama logs before and after)")
    print(f"{'PASS' if ok_all else 'FAIL'} suite; frames in {outdir / 'attachments' / bundle.stem}; log {log}")
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
