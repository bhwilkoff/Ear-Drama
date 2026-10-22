"""Run the real-hardware suite across every reachable device and report one matrix.

This is the entry point an autonomous loop calls. It shells out to the
per-platform runners (tools/atv_run.py, tools/ios_run.py, tools/adb_run.py, …)
rather than importing them, so one platform's crash or hung device cannot take
the whole sweep down with it.

The device list is the BENCH (tools/bench.py): every device, with its role. A
never-touch device is listed as SKIP with its role, not silently dropped; an
owner-watches device is skipped unless --owner-ok.

LEASES ARE HELD HERE, for each device's whole block of scenarios, and handed down
to the runners (DEVICE_LEASE_HOLDER_PID). A lease per runner invocation would leave
a gap between scenarios, and a peer session grabbed a device in exactly such a gap.

Three habits are deliberate:

  * REACHABILITY IS PROBED, NOT ASSUMED. A device that is off or unplugged is
    reported as SKIP, never as a pass and never as a failure. Silence about an
    untested platform is how a green board comes to mean nothing.
  * Every run writes its own report.json under build/qa/, and this writes a
    summary.json beside them. Harnesses that print and exit cannot be compared
    across runs — no baseline and no trend. Ours can be diffed.
  * PASS, FAIL and SKIP are three numbers. A skipped device is never a pass.

Usage:
    python3 tools/qa_suite.py                     # smoke set, every reachable device
    python3 tools/qa_suite.py --devices ipad,pixel     # bench names
    python3 tools/qa_suite.py --full              # every scenario each runner knows
"""
import argparse
import json
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
from devharness import sh   # noqa: E402

ADB = str(app_config.ADB)
TOOLS = Path(__file__).resolve().parent

# The smoke set is the surfaces every platform shares, so a red cell means the
# SAME feature broke somewhere — that is what makes the matrix readable.
# FILL IN: these are the template starters' doors (a tab, the search tab, an item
# via APP_START_ITEM with the mute door). Grow the set as your app's shared
# surfaces land; every name must be a scenario its runner lists (--list).
SMOKE = ["home", "search", "item"]

# platform -> how to run it. "only" runners batch their own scenarios (--only);
# device runners take one --scenario at a time and a --device bench name.
# door-return (APP_DOOR_SECONDS) runs under --full; it is slower by design.
PLATFORMS = {
    "tvos":      {"runner": "atv_run.py", "device": True, "smoke": SMOKE},
    "ipados":    {"runner": "ios_run.py", "device": True, "smoke": SMOKE},
    "ios":       {"runner": "ios_run.py", "device": True, "smoke": SMOKE},
    "android":   {"runner": "adb_run.py", "device": True, "smoke": SMOKE},
    "androidtv": {"runner": "adb_run.py", "device": True, "smoke": SMOKE},
    "firetv":    {"runner": "adb_run.py", "device": True, "smoke": SMOKE},
    # The Mac and the web take their own runners: the Mac captures by window id and
    # the web needs two viewports; neither is "another device" in the adb sense.
    "macos":     {"runner": "mac_run.py", "only": True, "smoke": SMOKE},
    "web":       {"runner": "web_run.py", "only": True, "smoke": SMOKE},
    # The Windows starter has no search section yet (home|library|settings).
    "windows":   {"runner": "win_run.py", "only": True, "smoke": ["home", "library", "item"]},
}


def reachable(e):
    """Probe, never assume. Returns (ok, why). One verdict, one evidence string —
    they must never disagree."""
    p = e.get("platform")
    try:
        if p == "tvos":
            import apple_device
            atv = apple_device.ATV(e)
            if atv.available:
                st = atv.power_state()
                if st is None:
                    return False, "pyatv: no answer"
                # An Off TV is reachable (the runner wakes it); None is not.
                return True, f"pyatv: power {st}"
        if p in ("tvos", "ios", "ipados"):
            r = sh(["xcrun", "devicectl", "list", "devices"], timeout=90)
            line = next((l for l in r.stdout.splitlines() if e.get("udid", "?") in l), "")
            ok = "available" in line or "connected" in line
            return ok, (line.strip()[:60] or "not listed by devicectl")
        if p in ("android", "androidtv", "firetv"):
            # The FULL serial, matched on its own line. Keying on a FRAGMENT of an
            # mDNS serial made the regex require whitespace right after it, so the
            # probe returned False while its evidence string said "adb ok".
            serial = e.get("serial") or e.get("address")
            r = sh([ADB, "devices"], timeout=45)
            if serial not in r.stdout and ":" in serial:
                sh([ADB, "connect", serial], timeout=30)
                r = sh([ADB, "devices"], timeout=45)
            online = re.search(rf"^{re.escape(serial)}\s+device\b", r.stdout, re.M)
            return (online is not None,
                    "adb: device" if online else "not online in adb devices")
        if p == "macos":
            app = Path(f"/Applications/{app_config.APPLE_APP_NAME}.app")
            dev = app_config.REPO / f"build/dd-mac/Build/Products/Debug/{app_config.APPLE_APP_NAME}.app"
            ok = app.exists() or dev.exists()
            return ok, "installed" if ok else f"no {app.name} built or installed"
        if p == "web":
            r = sh(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                    app_config.WEB_URL + "/"], timeout=45)
            return r.stdout.strip() == "200", f"{app_config.WEB_URL} HTTP {r.stdout.strip()}"
        if p == "windows":
            import winbox
            return winbox.check() if winbox.HOST else (False, "no Windows host configured")
    except Exception as ex:                    # noqa: BLE001
        return False, f"probe failed: {ex}"
    return False, f"no scenario runner for platform {p!r}"


def run_one(e, scenario, tag, owner_ok=False):
    cfg = PLATFORMS[e["platform"]]
    runner = str(TOOLS / cfg["runner"])
    if cfg.get("only"):
        cmd = [sys.executable, runner, "--only", scenario]
    else:
        cmd = [sys.executable, runner, "--scenario", scenario,
               "--name", f"{tag}-{scenario}", "--device", e["name"]]
        if owner_ok:
            cmd.append("--owner-ok")
    t0 = time.time()
    try:
        # child_env hands this process's lease down to the runner.
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=900,
                           env=devlease.child_env())
        out = r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        return {"result": "TIMEOUT", "secs": round(time.time() - t0), "failed": ["timeout"]}
    m = re.search(r"^RESULT: (OK|FAIL)(?: — (.*))?$", out, re.M)
    if not m:
        return {"result": "ERROR", "secs": round(time.time() - t0),
                "failed": [out.strip().splitlines()[-1][:80] if out.strip() else "no output"]}
    return {"result": m.group(1), "secs": round(time.time() - t0),
            "failed": [s.strip() for s in (m.group(2) or "").split(",") if s.strip()]}


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--devices", help="comma list of bench names; default the whole bench")
    ap.add_argument("--full", action="store_true", help="every scenario the runner knows")
    ap.add_argument("--scenarios", help="comma list, overrides the smoke set")
    ap.add_argument("--owner-ok", action="store_true",
                    help="include owner-watches devices (ask the owner first)")
    ap.add_argument("--lease-wait", type=int, default=0)
    a = ap.parse_args()

    bench_all = bench.load()
    want = a.devices.split(",") if a.devices else list(bench_all)
    tag = f"suite{int(time.time())}"
    outdir = app_config.QA_ROOT / f"suite-{time.strftime('%Y-%m-%d')}" / tag
    outdir.mkdir(parents=True, exist_ok=True)

    summary = {"started": time.strftime("%Y-%m-%d %H:%M:%S"), "devices": {}}

    def skip(name, why):
        print(f"\n=== {name}: SKIP ({why}) ===")
        summary["devices"][name] = {"status": "SKIP", "why": why, "scenarios": {}}

    for name in want:
        e = bench.get(name, bench_all)
        if e is None:
            skip(name, "not on the bench")
            continue
        try:
            bench.require(name, allow_owner=a.owner_ok, bench=bench_all)
        except bench.RefusedDevice as ex:
            skip(name, str(ex).replace("REFUSED: ", "role: "))
            continue
        if e.get("platform") not in PLATFORMS:
            hint = (" — use tools/roku_playback_audit.py / roku_sweep.py"
                    if e.get("platform") == "roku" else "")
            skip(name, f"no scenario runner for platform {e.get('platform')!r}{hint}")
            continue
        ok, why = reachable(e)
        if not ok:
            skip(name, why)
            continue

        cfg = PLATFORMS[e["platform"]]
        if a.scenarios:
            scenarios = a.scenarios.split(",")
        elif a.full:
            r = sh([sys.executable, str(TOOLS / cfg["runner"]), "--list"], timeout=90)
            scenarios = [l.split()[0] for l in r.stdout.splitlines() if l.strip()]
        else:
            scenarios = cfg["smoke"]

        # Hold the device for its WHOLE block — no gap between scenarios for a peer.
        try:
            with devlease.hold([bench.lease_name(e)], task=f"qa_suite {tag}",
                               wait=a.lease_wait):
                print(f"\n=== {name}: {len(scenarios)} scenarios ===")
                per = {}
                for sc in scenarios:
                    res = run_one(e, sc, tag, a.owner_ok)
                    per[sc] = res
                    mark = {"OK": "  ok", "FAIL": "FAIL", "TIMEOUT": "TIME",
                            "ERROR": " ERR", "SKIP": "SKIP"}[res["result"]]
                    detail = (" — " + ", ".join(res["failed"])) if res["failed"] else ""
                    print(f"  [{mark}] {sc:26s} {res['secs']:4d}s{detail}")
        except RuntimeError as ex:
            skip(name, f"leased elsewhere — {ex}")
            continue
        summary["devices"][name] = {
            "status": "RAN", "scenarios": per,
            "pass": sum(1 for v in per.values() if v["result"] == "OK"),
            "skip": sum(1 for v in per.values() if v["result"] == "SKIP"),
            "fail": sum(1 for v in per.values() if v["result"] not in ("OK", "SKIP"))}

    (outdir / "summary.json").write_text(json.dumps(summary, indent=2))

    print("\n" + "=" * 58)
    total_f = 0
    for dev, d in summary["devices"].items():
        if d["status"] == "SKIP":
            print(f"  {dev:14s} SKIP  ({d['why'][:70]})")
            continue
        total_f += d["fail"]
        bad = [sc for sc, v in d["scenarios"].items() if v["result"] != "OK"]
        print(f"  {dev:14s} {d['pass']:2d} pass  {d['fail']:2d} fail  {d['skip']:2d} skip"
              + (f"   -> {', '.join(bad)}" if bad else ""))
    print("=" * 58)
    print(f"summary: {outdir}/summary.json")
    return 1 if total_f else 0


if __name__ == "__main__":
    sys.exit(main())
