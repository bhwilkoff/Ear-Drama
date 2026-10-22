"""Which surfaces can this testing system actually REACH, per platform?

A harness can only assert about a screen it can open. Every gap here is a surface
that is not failing — it is unasked, which reads identically in a green report and
is strictly worse, because a gap in coverage looks like a pass.

This reads the four codebases for the launch hooks each one honours and prints the
matrix, so "everything can be driven" is a measured claim rather than a hope.

    python3 tools/hook_coverage.py
"""
import re
import pathlib
import collections
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from app_config import (APPLE_APP_NAME, WINDOWS_PROCESS, HOOK_START_TAB,  # noqa: E402
                        HOOK_START_ITEM, HOOK_SKIP_ONBOARD, HOOK_FORCE_OFFLINE,
                        HOOK_TYPE_SIZE, HOOK_MUTE, HOOK_DOOR_SECONDS, android_extra)

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Each platform: where its hooks live, and how a hook name appears there. Each
# pattern is (regex, prefix): the prefix is prepended to what the regex captures.
# "apple" is the template's starter directory; an adopted app lives in <AppName>/.
SOURCES = {
    "apple":   ([APPLE_APP_NAME, "apple"],
                [(r'environment\["(APP_[A-Z_]+)"\]', "")], {".swift"}),
    "android": (["android/app/src/main"], [(r'"(appname_[a-z_]+)"', "")], {".kt"}),
    # The Windows projects are <Name>.App / <Name>.Core (windows/README.md).
    "windows": ([f"windows/{WINDOWS_PROCESS}.App", f"windows/{WINDOWS_PROCESS}.Core"],
                [(r'(?:GetEnvironmentVariable|Env|Flag)\("(APP_[A-Z_]+)"\)', "")], {".cs"}),
    # The web's doors are its URL query params, which read as "?view", "?item"
    # (params.get('view') in js/app.js's init()).
    "web":     (["js"], [(r"params\.get\('([a-z_]+)'\)", "?")], {".js"}),
}
SKIP = {"bin", "obj", "artifacts", "publish", "node_modules", ".git"}

# The canonical hook per capability, in the Apple spelling. Android/Windows names
# are derived; the web is a query param, since its "hook" is the URL. None = no
# equivalent on that platform ("-"), which is a design choice, not a gap.
#
# These are the GENERIC doors every app built from this template has (or should):
# the starters honour the first four; skip-onboarding, force-offline and type-size
# are the app_config hooks a real app wires as those surfaces land.
CAPABILITIES = [
    ("open a tab/section",     HOOK_START_TAB,  android_extra(HOOK_START_TAB), HOOK_START_TAB, "?view"),
    ("open an item",           HOOK_START_ITEM, android_extra(HOOK_START_ITEM), HOOK_START_ITEM, "?item"),
    # Every harness launch sets these (app_config.DOOR_DEFAULTS). A client that does
    # not honour them plays AUDIBLY and indefinitely on somebody's television.
    ("mute the player (door default)", HOOK_MUTE, android_extra(HOOK_MUTE), HOOK_MUTE, "?mute"),
    ("bound a door's duration", HOOK_DOOR_SECONDS, android_extra(HOOK_DOOR_SECONDS),
     HOOK_DOOR_SECONDS, "?door_seconds"),
    ("skip the walkthrough",   HOOK_SKIP_ONBOARD, android_extra(HOOK_SKIP_ONBOARD), HOOK_SKIP_ONBOARD, None),
    ("render the offline state", HOOK_FORCE_OFFLINE, android_extra(HOOK_FORCE_OFFLINE),
     HOOK_FORCE_OFFLINE, None),
    ("one Dynamic Type size",  HOOK_TYPE_SIZE,  android_extra(HOOK_TYPE_SIZE), HOOK_TYPE_SIZE, None),
]

# FILL IN: your app's OWN surfaces, one row per door (same shape as above: label,
# Apple env var, Android extra, Windows env var, web query param or None). Write
# every cell as the name the code ACTUALLY uses, verified by reading it: guessing an
# Android extra from the Apple spelling has reported gaps that did not exist. For
# a Windows row, also add its accessor to WINDOWS_ACCESSOR below. Examples:
#   ("start playback",        HOOK_AUTOPLAY,   android_extra(HOOK_AUTOPLAY), HOOK_AUTOPLAY, "?autoplay"),
#   ("open Settings",         "APP_SETTINGS",  "appname_open",               "APP_SETTINGS", "?view"),
#   ("open the paywall",      "APP_PAYWALL",   "appname_open",               "APP_PAYWALL",  None),
APP_CAPABILITIES = [
]


# A hook can be DECLARED and never acted on. On Windows the hooks live in one
# LaunchHooks.cs, so finding the env-var string there proves only that someone wrote
# the accessor — the first version of this script reported "yes" for two hooks I had
# declared and not wired, which is the same "assertion that cannot fire" problem it
# exists to find, in the instrument itself. So the Windows column additionally
# requires the ACCESSOR to be referenced somewhere other than its own declaration.
WINDOWS_ACCESSOR = {
    HOOK_START_TAB: "LaunchHooks.StartTab",
    HOOK_START_ITEM: "LaunchHooks.StartItem",
    HOOK_MUTE: "LaunchHooks.Mute",
    HOOK_DOOR_SECONDS: "LaunchHooks.DoorSeconds",
    HOOK_SKIP_ONBOARD: "LaunchHooks.SkipOnboard",
    HOOK_FORCE_OFFLINE: "LaunchHooks.ForceOffline",
    HOOK_TYPE_SIZE: "LaunchHooks.TypeSize",
    # FILL IN: one accessor per APP_CAPABILITIES row with a Windows cell.
}


def windows_wired(key):
    """True when the hook is referenced OUTSIDE its own declaration file."""
    accessor = WINDOWS_ACCESSOR.get(key)
    if accessor is None:
        return False
    for d in (f"windows/{WINDOWS_PROCESS}.App", f"windows/{WINDOWS_PROCESS}.Core"):
        base = ROOT / d
        for p in base.rglob("*.cs"):
            if SKIP & set(p.relative_to(base).parts) or p.name == "LaunchHooks.cs":
                continue
            if accessor in p.read_text(errors="ignore"):
                return True
    return False


def harvest(platform):
    dirs, patterns, exts = SOURCES[platform]
    found = collections.Counter()
    rxs = [(re.compile(rx), prefix) for rx, prefix in patterns]
    for d in dirs:
        base = ROOT / d
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if p.suffix not in exts or not p.is_file():
                continue
            if SKIP & set(p.relative_to(base).parts):
                continue
            text = p.read_text(errors="ignore")
            for rx, prefix in rxs:
                for m in rx.findall(text):
                    found[prefix + m] += 1
    return found


def main():
    have = {p: harvest(p) for p in SOURCES}
    cols = ["apple", "android", "windows", "web"]
    print(f"{'capability':30} " + " ".join(f"{c:>8}" for c in cols))
    print("-" * 30 + " " + " ".join("-" * 8 for _ in cols))
    gaps = []
    for label, ap, an, wi, web in CAPABILITIES + APP_CAPABILITIES:
        row, keys = [], {"apple": ap, "android": an, "windows": wi, "web": web}
        for c in cols:
            k = keys[c]
            ok = bool(k) and have[c].get(k, 0) > 0
            if ok and c == "windows":
                ok = windows_wired(k)
            row.append("  yes   " if ok else ("   -    " if k is None else "   NO   "))
            if k is not None and not ok:
                gaps.append((label, c, k))
        print(f"{label:30} " + " ".join(row))
    print(f"\n{len(gaps)} surface(s) this system cannot reach:")
    for label, c, k in gaps:
        print(f"  {c:8} {label:30} (needs {k})")
    print("\n'-' = no equivalent on that platform. 'NO' = the capability exists in the "
          "app but nothing can drive it, so it is untested and reads as a pass.")


if __name__ == "__main__":
    main()
