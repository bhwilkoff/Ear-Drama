#!/usr/bin/env python3
"""Guard on the BUILT Info.plist and privacy manifest, not only the source files.

A key can be in project.yml or the source plist and never reach the built app
(UIBackgroundModes as an INFOPLIST_KEY, 2026-11-01). This reads the product.

    python3 tools/test_built_info_plist.py ios=<EarDrama.app> tvos=<EarDrama.app> macos=<EarDrama.app>
    python3 tools/test_built_info_plist.py --self-test <any one built iOS .app>
    python3 tools/test_built_info_plist.py --source      # project.yml and PrivacyInfo.xcprivacy, with negative controls

With no products given it exits 2 ("not verified"), never 0.
Required: iOS: NSMicrophoneUsageDescription + UIBackgroundModes audio;
tvOS: UIBackgroundModes audio; macOS: NSMicrophoneUsageDescription.
The microphone's words must be true in every case (a take is sent when a person shares it and is public when they
publish it), and the manifest must declare what docs/store/NEXT-VERSION.md section 2 proves is collected.
"""
import copy
import plistlib
import re
import sys
from pathlib import Path

REQUIRED = {
    "ios": (["NSMicrophoneUsageDescription"], True),
    "tvos": ([], True),
    "macos": (["NSMicrophoneUsageDescription"], False),
}


ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "apple" / "Resources" / "PrivacyInfo.xcprivacy"
COLLECTED = {"Name", "UserID", "AudioData", "OtherUserContent", "ProductInteraction"}
ACCESSED = {"UserDefaults": ["CA92.1"], "FileTimestamp": ["C617.1"]}


def read(app, name, required=True):
    app = Path(app)
    for rel in (name, f"Contents/{name}", f"Contents/Resources/{name}"):
        if (app / rel).exists():
            return plistlib.loads((app / rel).read_bytes())
    if required:
        raise SystemExit(f"no {name} in {app}")
    return {}


def plist_of(app):
    return read(app, "Info.plist")


def mic_problems(words):
    if not words:
        return []
    return [f"microphone words do not say `{w}`: {words}" for w in ("this device until", "share", "publish") if w not in words]


def manifest_problems(m):
    out = []
    types = m.get("NSPrivacyCollectedDataTypes") or []
    names = [t.get("NSPrivacyCollectedDataType", "").removeprefix("NSPrivacyCollectedDataType") for t in types]
    if sorted(names) != sorted(COLLECTED):
        out.append(f"privacy manifest collects {sorted(names)}, must be {sorted(COLLECTED)}")
    for t, n in zip(types, names):
        if t.get("NSPrivacyCollectedDataTypeLinked") is not True or t.get("NSPrivacyCollectedDataTypeTracking") is not False:
            out.append(f"{n}: must be linked and not tracking")
        if t.get("NSPrivacyCollectedDataTypePurposes") != ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]:
            out.append(f"{n}: purpose must be App Functionality alone")
    if m.get("NSPrivacyTracking") is not False or m.get("NSPrivacyTrackingDomains") != []:
        out.append("privacy manifest must not track")
    got = {a["NSPrivacyAccessedAPIType"].removeprefix("NSPrivacyAccessedAPICategory"): a["NSPrivacyAccessedAPITypeReasons"]
           for a in m.get("NSPrivacyAccessedAPITypes") or []}
    if got != ACCESSED:
        out.append(f"accessed APIs are {got}, must be {ACCESSED}")
    return out


def source_check():
    words = re.search(r'INFOPLIST_KEY_NSMicrophoneUsageDescription: "([^"]*)"', (ROOT / "project.yml").read_text())
    m = plistlib.loads(MANIFEST.read_bytes())
    found = mic_problems(words and words[1] or "-") + manifest_problems(m)
    if found:
        print("\n".join("FAIL " + f for f in found))
        return 1
    controls = [mic_problems("Ear Drama records your part in a play. The recording stays on this device.")]
    for change in (lambda x: x.update(NSPrivacyCollectedDataTypes=[]),
                   lambda x: x["NSPrivacyCollectedDataTypes"].pop(),
                   lambda x: x["NSPrivacyCollectedDataTypes"][0].update(NSPrivacyCollectedDataTypeTracking=True),
                   lambda x: x["NSPrivacyCollectedDataTypes"][0].update(NSPrivacyCollectedDataTypeLinked=False),
                   lambda x: x["NSPrivacyAccessedAPITypes"].pop()):
        broken = copy.deepcopy(m)
        change(broken)
        controls.append(manifest_problems(broken))
    missed = [i for i, c in enumerate(controls) if not c]
    print(f"FAIL negative controls {missed} passed" if missed else "PASS microphone words and privacy manifest, source")
    return 1 if missed else 0


def problems(platform, info):
    keys, needs_audio = REQUIRED[platform]
    out = [f"{platform}: {k} missing or empty" for k in keys if not info.get(k)]
    if needs_audio and "audio" not in (info.get("UIBackgroundModes") or []):
        out.append(f"{platform}: UIBackgroundModes lacks audio")
    return out + [f"{platform}: {p}" for p in mic_problems(info.get("NSMicrophoneUsageDescription"))]


def main(argv):
    if argv == ["--source"]:
        return source_check()
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
        found += [f"{platform}: {p}" for p in manifest_problems(read(path, "PrivacyInfo.xcprivacy", required=False))]
    for f in found:
        print("FAIL", f)
    print("FAIL" if found else "PASS", len(argv), "built plist(s)")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
