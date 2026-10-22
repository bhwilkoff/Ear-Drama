#!/usr/bin/env python3
"""
tools/set_app_identity.py gives an app its own identity everywhere at once.

Run against a throwaway copy of the template's real files, so a change to any
of those files that hides the identity from the script fails here, before a
student's agent runs it and half the platforms are renamed.

Run: python3 tools/test_app_identity.py   (exit 0 = pass)
"""
import json
import os
import re
import xml.dom.minidom
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import set_app_identity as ident  # noqa: E402

fails = []


def check(ok, what, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'}  {what}" + (f"  ({detail})" if detail and not ok else ""))
    if not ok:
        fails.append(what)


FILES = sorted({rel for rel, *_ in ident.edits("org.x.y", "X")} | {rel for rel, _ in ident.IDENTITY_LINES})

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    for rel in FILES:
        if (ROOT / rel).exists():
            (root / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / rel, root / rel)
    os.environ["GITHUB_REPOSITORY"] = "someone/bird-log"

    check(ident.leftovers(root), "a fresh copy still has the placeholder")
    check(ident.main(["--check", "--root", tmp]) == 1, "--check fails in a copy that kept it")
    os.environ["GITHUB_REPOSITORY"] = "bhwilkoff/UniversalAppTemplate"
    check(ident.main(["--check", "--root", tmp]) == 0, "--check passes in the template itself")
    os.environ["GITHUB_REPOSITORY"] = "someone/bird-log"

    check(ident.main(["--id", "org.someone.birdlog", "--name", "Bird & Log", "--root", tmp]) == 0, "set runs")
    read = lambda rel: (root / rel).read_text(encoding="utf-8")

    check('applicationId = "org.someone.birdlog"' in read("android/app/build.gradle.kts"), "Android applicationId")
    check('namespace = "com.example.appname"' in read("android/app/build.gradle.kts"),
          "Android namespace (where the code lives) is left alone")
    check('<string name="app_name">Bird &amp; Log</string>' in read("android/app/src/main/res/values/strings.xml"),
          "Android app name, escaped for XML")
    yml = read("project.yml")
    check("PRODUCT_BUNDLE_IDENTIFIER: org.someone.birdlog\n" in yml, "Apple bundle identifier")
    check("PRODUCT_BUNDLE_IDENTIFIER: org.someone.birdlog.CoreTests" in yml, "Apple test bundle follows it")
    check("bundleIdPrefix: org.someone" in yml, "Apple bundleIdPrefix")
    check('INFOPLIST_KEY_CFBundleDisplayName: "Bird & Log"' in yml, "Apple display name")
    check('"name": "Bird & Log"' in read("manifest.json"), "web manifest name")
    win = read("windows/AppName.App/AppxManifest.xml")
    check('Name="org.someone.birdlog"' in win, "Windows package identity")
    check("App Name" not in win, "every Windows display name")
    check("packageName: org.someone.birdlog" in read(".github/workflows/android-build.yml"), "Play upload package")
    cfg = read("tools/app_config.py")
    check('ANDROID_PACKAGE_DEBUG = "org.someone.birdlog.debug"' in cfg, "harness debug package")
    check('ANDROID_MAIN_ACTIVITY = "com.example.appname.MainActivity"' in cfg,
          "the activity's class name stays with the code's namespace")
    check(not ident.leftovers(root), "no identity line keeps the placeholder", "; ".join(ident.leftovers(root)))
    check(ident.main(["--check", "--root", tmp]) == 0, "--check passes once it is set")

    before = {rel: read(rel) for rel in FILES if (root / rel).exists()}
    ident.main(["--id", "org.someone.birdlog", "--name", "Bird & Log", "--root", tmp])
    check(before == {rel: read(rel) for rel in before}, "running it again changes nothing")

    ident.main(["--id", "org.someone.birds", "--name", "Birds", "--root", tmp])
    check("PRODUCT_BUNDLE_IDENTIFIER: org.someone.birds.CoreTests" in read("project.yml"),
          "it can be changed again later")

    ident.main(["--id", "org.someone.birds", "--name", 'Bird "Log" <1>', "--root", tmp])
    try:
        json.loads(read("manifest.json"))
        xml.dom.minidom.parseString(read("windows/AppName.App/AppxManifest.xml"))
        xml.dom.minidom.parseString(read("android/app/src/main/res/values/strings.xml"))
        parsed = True
    except Exception as e:  # noqa: BLE001
        parsed = str(e)
    check(parsed is True, "quotes and angle brackets in a name keep JSON and XML valid", str(parsed))
    try:
        import yaml
        name = yaml.safe_load(read("project.yml"))["targets"]["AppName"]["settings"]["base"]["INFOPLIST_KEY_CFBundleDisplayName"]
        check(name == "Bird 'Log' <1>", "and project.yml still reads as YAML", repr(name))
    except ImportError:
        print("  SKIP  project.yml as YAML (PyYAML is not installed)")

    for bad in ["com.example.mine", "birdlog", "Org.Some-One.app", "org.1x.app"]:
        try:
            ident.main(["--id", bad, "--name", "X", "--root", tmp])
            check(False, f"refuses {bad!r}")
        except SystemExit as e:
            check(e.code != 0, f"refuses {bad!r}")

print(f"\n{len(fails)} failed" if fails else "\nall passed")
sys.exit(1 if fails else 0)
