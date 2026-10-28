"""Run the iOS tap tier (apple/UITests, scheme EarDramaUITests) on the real iPhone.

The glass runner (tools/ios_run.py) has no press verb; this is the press tier. It
holds the device lease for the whole run, builds and runs the XCUITest bundle with
`xcodebuild test`, exports every screenshot the tests attached, prints pass/fail per
test from the result bundle, and compares the device's systemCrashLogs list before
and after: a new EarDrama-*.ips is a FAIL whatever the tests said.

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
import devlease  # noqa: E402

REPO = app_config.REPO
SCHEME = "EarDramaUITests"
TEAM = os.environ.get("ASC_TEAM_ID", "L2G756LY8N")
LEASE_TTL = 900
CRASH_RX = re.compile(rf"^\s*({re.escape(app_config.APPLE_APP_NAME)}-[\w.-]+\.ips)\b", re.M)


def env():
    e = dict(os.environ)
    e.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    # The app's bundled seed; a worktree without catalog/out reads the main checkout's.
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


def run(entry, udid, a, outdir, bundle):
    before = crash_logs(udid)
    if before is None:
        print("[uitest] could not list systemCrashLogs before the run — crash check UNKNOWN")
    cmd = ["xcodebuild", "test", "-project", str(REPO / "EarDrama.xcodeproj"),
           "-scheme", SCHEME, "-destination", f"id={udid}",
           "-resultBundlePath", str(bundle),
           f"DEVELOPMENT_TEAM={TEAM}", "-allowProvisioningUpdates"]
    seed = a.catalog_seed or os.environ.get("CATALOG_SEED_PATH")
    if seed:
        cmd.append(f"CATALOG_SEED_PATH={seed}")
    for o in a.only:
        cmd += ["-only-testing", f"{SCHEME}/{o}"]
    log = outdir / f"xcodebuild-{int(time.time())}.log"
    print(f"[uitest] {' '.join(cmd[:6])} ... (log {log})")
    # Renew-free: hold() renews in the background for as long as this process lives.
    with log.open("w") as fh:
        rc = subprocess.run(cmd, stdout=fh, stderr=subprocess.STDOUT, env=env(),
                            cwd=REPO).returncode
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
        for name, result in tests:
            good = result == "Passed"
            ok_all &= good
            print(f"{'PASS' if good else 'FAIL'} {name} ({result})")
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
