#!/usr/bin/env python3
"""The tvOS deployment floor has not drifted above the one the app chose.

tvOS 27 dropped the Apple TV HD (2015) and Apple TV 4K 1st gen (2017); both
run tvOS 26. A floor of 27 or higher silently stops shipping to those boxes —
no error anywhere, the store just stops offering the app. A floor is chosen by
the hardware it buys; this holds the choice in CI.

Reads every TVOS_DEPLOYMENT_TARGET in the adopting app's .xcodeproj and
xcconfig files.

Config (env):
  TVOS_MAX_FLOOR  highest allowed major version (default 26)

No Xcode project yet (a fresh template) -> a clear note and exit 0.
Run: python3 tools/test_tvos_floor.py
"""
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAX_MAJOR = int(os.environ.get("TVOS_MAX_FLOOR", "26"))
SKIP_DIRS = {".git", "build", "DerivedData", "node_modules", "android", "windows", "Pods"}
KEY = "TVOS_DEPLOYMENT_TARGET"


def sources():
    out = []
    for pattern in ("*.xcodeproj/project.pbxproj", "*/*.xcodeproj/project.pbxproj",
                    "*.xcconfig", "*/*.xcconfig"):
        for p in ROOT.glob(pattern):
            if not SKIP_DIRS.intersection(p.relative_to(ROOT).parts):
                out.append(p)
    return sorted(set(out))


def floors(text: str) -> list:
    return [float(v) for v in re.findall(rf"^\s*{KEY}\s*=\s*([0-9.]+);?", text, re.M)]


def ok(values) -> bool:
    return bool(values) and all(v < MAX_MAJOR + 1 for v in values)


fails = 0


def check(name, cond):
    global fails
    print(("PASS " if cond else "FAIL ") + name)
    fails += not cond


check(f"control: a {MAX_MAJOR + 1}.0 target is refused",
      not ok(floors(f"\t\t\t\t{KEY} = {MAX_MAJOR}.0;\n\t\t\t\t{KEY} = {MAX_MAJOR + 1}.0;")))
check("control: no target at all is refused", not ok(floors("")))
check("control: an xcconfig floor is read", floors(f"{KEY} = 26.0\n") == [26.0])

files = sources()
if not any(p.suffix == ".pbxproj" for p in files):
    print(f"NOTE no .xcodeproj in {ROOT.name} yet — nothing to hold (this test "
          f"starts enforcing once the Apple app exists)")
    sys.exit(1 if fails else 0)

found = {str(p.relative_to(ROOT)): floors(p.read_text()) for p in files}
values = [v for vs in found.values() for v in vs]
if not values and "tvos" not in os.environ.get("APP_STORE_PLATFORMS", "tvos"):
    print("NOTE this app does not ship tvOS (APP_STORE_PLATFORMS) — nothing to hold")
    sys.exit(1 if fails else 0)
check(f"every tvOS deployment target is {MAX_MAJOR}.x or lower "
      f"({ {k: sorted(set(v)) for k, v in found.items() if v} })", ok(values))
sys.exit(1 if fails else 0)
