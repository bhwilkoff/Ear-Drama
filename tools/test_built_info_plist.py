#!/usr/bin/env python3
"""Guard on the BUILT Info.plist, not the source file.

A key can be in project.yml or the source plist and never reach the built app
(UIBackgroundModes as an INFOPLIST_KEY, 2026-11-01). This reads the product.

    python3 tools/test_built_info_plist.py ios=<EarDrama.app> tvos=<EarDrama.app> macos=<EarDrama.app>
    python3 tools/test_built_info_plist.py --self-test <any one built .app>

With no products given it exits 2 ("not verified"), never 0.
Required: iOS: NSMicrophoneUsageDescription + UIBackgroundModes audio;
tvOS: UIBackgroundModes audio; macOS: NSMicrophoneUsageDescription.
"""
import plistlib
import sys
from pathlib import Path

REQUIRED = {
    "ios": (["NSMicrophoneUsageDescription"], True),
    "tvos": ([], True),
    "macos": (["NSMicrophoneUsageDescription"], False),
}


def plist_of(app):
    app = Path(app)
    for rel in ("Info.plist", "Contents/Info.plist"):
        if (app / rel).exists():
            return plistlib.loads((app / rel).read_bytes())
    raise SystemExit(f"no Info.plist in {app}")


def problems(platform, info):
    keys, needs_audio = REQUIRED[platform]
    out = [f"{platform}: {k} missing or empty" for k in keys if not info.get(k)]
    if needs_audio and "audio" not in (info.get("UIBackgroundModes") or []):
        out.append(f"{platform}: UIBackgroundModes lacks audio")
    return out


def main(argv):
    if argv and argv[0] == "--self-test":
        if len(argv) < 2:
            print("NOT VERIFIED: --self-test needs one built .app")
            return 2
        info = plist_of(argv[1])
        good = problems("ios", info)
        broken = dict(info)
        broken.pop("NSMicrophoneUsageDescription", None)
        broken.pop("UIBackgroundModes", None)
        bad = problems("ios", broken)
        print("real plist:", good or "clean")
        print("negative control (keys stripped):", bad)
        return 0 if not good and len(bad) == 2 else 1
    if not argv:
        print("NOT VERIFIED: no built products given")
        return 2
    found = []
    for a in argv:
        platform, _, path = a.partition("=")
        found += problems(platform, plist_of(path))
    for f in found:
        print("FAIL", f)
    print("FAIL" if found else "PASS", len(argv), "built plist(s)")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
