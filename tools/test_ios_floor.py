#!/usr/bin/env python3
"""The iPhone/iPad deployment floor has not drifted above the one the app chose.

A floor is chosen by the HARDWARE it buys — measured by test-building at each
candidate floor, not by adoption share — and raising it cuts devices off with
no error anywhere: the store simply stops offering the app to them. (iOS 26
dropped the iPhone XS, XS Max and XR; iOS 18 still runs on them, and on every
phone iOS 17 does.) This holds the choice in CI.

Reads every IPHONEOS_DEPLOYMENT_TARGET in the adopting app's .xcodeproj and
xcconfig files, skipping build configurations that are tvOS- or macOS-only
(a Top Shelf extension's IPHONEOS setting is not a floor).

Config (env):
  IOS_MAX_FLOOR   highest allowed major version (default 18)

No Xcode project yet (a fresh template) -> a clear note and exit 0.
Run: python3 tools/test_ios_floor.py
"""
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAX_MAJOR = int(os.environ.get("IOS_MAX_FLOOR", "18"))
SKIP_DIRS = {".git", "build", "DerivedData", "node_modules", "android", "windows", "Pods"}
KEY = "IPHONEOS_DEPLOYMENT_TARGET"


def sources():
    """Every project file and xcconfig within two levels of the repo root."""
    out = []
    for pattern in ("*.xcodeproj/project.pbxproj", "*/*.xcodeproj/project.pbxproj",
                    "*.xcconfig", "*/*.xcconfig"):
        for p in ROOT.glob(pattern):
            if not SKIP_DIRS.intersection(p.relative_to(ROOT).parts):
                out.append(p)
    return sorted(set(out))


def ios_config(body: str) -> bool:
    """Is this build configuration one that ships to iPhone/iPad?"""
    plats = re.search(r'SUPPORTED_PLATFORMS = "?([^;"]+)"?;', body)
    if plats:
        return "iphoneos" in plats.group(1)
    sdk = re.search(r"SDKROOT = (\w+);", body)
    # `auto` is a universal (multi-destination) config, which includes iOS.
    return not sdk or sdk.group(1) in ("iphoneos", "auto")


def floors(text: str) -> list:
    configs = re.findall(r"isa = XCBuildConfiguration;(.*?)\n\t\t\};", text, re.S)
    if not configs:                                    # an xcconfig
        return [float(v) for v in re.findall(rf"^\s*{KEY}\s*=\s*([0-9.]+)", text, re.M)]
    out = []
    for body in configs:
        m = re.search(rf"{KEY} = ([0-9.]+);", body)
        if m and ios_config(body):
            out.append(float(m.group(1)))
    return out


def ok(values) -> bool:
    return bool(values) and all(v < MAX_MAJOR + 1 for v in values)


fails = 0


def check(name, cond):
    global fails
    print(("PASS " if cond else "FAIL ") + name)
    fails += not cond


cfg = (lambda t, extra="": f"isa = XCBuildConfiguration;\n {extra}"
       f"{KEY} = {t};\n\t\t}};")
check(f"control: a target at {MAX_MAJOR + 8}.0 is refused",
      not ok(floors(cfg(f"{MAX_MAJOR}.0") + "\n" + cfg(f"{MAX_MAJOR + 8}.0"))))
check("control: no targets at all is refused", not ok(floors("")))
check("control: a tvOS-only extension's IPHONEOS setting is not a floor",
      ok(floors(cfg(f"{MAX_MAJOR}.0") + "\n"
                + cfg("99.0", 'SUPPORTED_PLATFORMS = "appletvos appletvsimulator";\n '))))
check("control: a universal (SDKROOT = auto) config's floor is read",
      floors(cfg("17.0", "SDKROOT = auto;\n ")) == [17.0])
check("control: an xcconfig floor is read", floors(f"{KEY} = 17.0\n") == [17.0])

files = sources()
projects = [p for p in files if p.suffix == ".pbxproj"]
if not projects:
    print(f"NOTE no .xcodeproj in {ROOT.name} yet — nothing to hold (this test "
          f"starts enforcing once the Apple app exists)")
    sys.exit(1 if fails else 0)

found = {str(p.relative_to(ROOT)): floors(p.read_text()) for p in files}
values = [v for vs in found.values() for v in vs]
if not values and "ios" not in os.environ.get("APP_STORE_PLATFORMS", "ios"):
    print("NOTE this app does not ship iOS (APP_STORE_PLATFORMS) — nothing to hold")
    sys.exit(1 if fails else 0)
check(f"every iOS deployment target is {MAX_MAJOR}.x or lower "
      f"({ {k: sorted(set(v)) for k, v in found.items() if v} })", ok(values))
sys.exit(1 if fails else 0)
