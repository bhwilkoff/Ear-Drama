#!/usr/bin/env python3
"""
Give an app made from the template its own identity, everywhere at once.

Every copy of the template starts as `com.example.appname`, named "AppName".
A phone keeps one app per identifier, so two classmates who both install
apps still named `com.example.appname` find that the second install replaces
the first, and no store will accept the name at all. Stage 03 asks the agent
to run this once, early.

    python3 tools/set_app_identity.py --id org.yourname.birdlog --name "Bird Log"
    python3 tools/set_app_identity.py --check     # exit 1 if still com.example

It changes the identifiers a device or a store reads, and the name a person
sees under the icon: the Android applicationId and app name, the Apple bundle
identifier and display name, the web manifest, the Windows package identity,
the store workflows, and tools/app_config.py. It deliberately leaves the
source code's own package and folder names (com/example/appname/, AppName.App)
alone: those are never seen on a device, and renaming them touches hundreds of
lines for no one's benefit. On Android that is the difference between
`applicationId` (the identity) and `namespace` (where the code lives).

`--check` passes in the template itself, which is meant to keep the
placeholder, and fails in any copy that still has it. The template is
recognized by its repository name, from GITHUB_REPOSITORY in CI or the
`origin` remote locally.
"""
import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLACEHOLDER = "com.example.appname"
TEMPLATE_REPOS = {"bhwilkoff/universalapptemplate"}

# A reverse-domain identifier both stores accept: at least two parts, each
# starting with a letter, letters, digits, and underscores only. (Apple also
# allows hyphens and Android does not, so neither is allowed here.)
ID_RE = re.compile(r"^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$")


def edits(app_id, name):
    """(file, pattern, value, every) for each place the identity lives: the
    value replaces group 2 of the pattern, between groups 1 and 3. A pattern
    must match where its file exists, or the run stops and writes nothing."""
    prefix = app_id.rsplit(".", 1)[0]
    xml = name.replace("&", "&amp;").replace("<", "&lt;").replace('"', "&quot;")
    return [
        ("android/app/build.gradle.kts", r'(applicationId\s*=\s*")([^"]+)(")', app_id, False),
        ("android/app/src/main/res/values/strings.xml",
         r'(<string name="app_name">)([^<]*)(</string>)', xml, False),
        ("project.yml", r"(bundleIdPrefix:\s*)(\S+)()", prefix, False),
        ("project.yml", r"(PRODUCT_BUNDLE_IDENTIFIER:\s*)([A-Za-z0-9_.-]+?)(\.CoreTests)", app_id, False),
        ("project.yml", r"(PRODUCT_BUNDLE_IDENTIFIER:\s*)((?![A-Za-z0-9_.-]*\.CoreTests)[A-Za-z0-9_.-]+)()", app_id, False),
        ("project.yml", r"(INFOPLIST_KEY_CFBundleDisplayName:\s*)(.+)()", '"' + name.replace('"', "'") + '"', False),
        ("manifest.json", r'("name":\s*")([^"]*)(")', name.replace('"', "'"), False),
        ("manifest.json", r'("short_name":\s*")([^"]*)(")', name.replace('"', "'")[:12], False),
        ("windows/AppName.App/AppxManifest.xml", r'(<Identity\s+Name=")([^"]+)(")', app_id, False),
        ("windows/AppName.App/AppxManifest.xml", r"(<(?:uap:)?DisplayName>)([^<]*)(</(?:uap:)?DisplayName>)", xml, True),
        ("windows/AppName.App/AppxManifest.xml", r'(\sDisplayName=")([^"]*)(")', xml, True),
        (".github/workflows/android-build.yml", r"(packageName:\s*)(\S+)()", app_id, False),
        ("tools/app_config.py", r'(APPLE_BUNDLE_ID\s*=\s*")([^"]+)(")', app_id, False),
        ("tools/app_config.py", r'(ANDROID_PACKAGE\s*=\s*")([^"]+)(")', app_id, False),
        ("tools/app_config.py", r'(ANDROID_PACKAGE_DEBUG\s*=\s*")([^"]+)(")', app_id + ".debug", False),
        ("tools/app_config.py", r'(PRODUCT_NAME\s*=\s*")([^"]+)(")', name.replace('"', "'"), False),
    ]


# Where the placeholder would mean the app has no identity of its own.
IDENTITY_LINES = [
    ("android/app/build.gradle.kts", r'applicationId\s*=\s*"([^"]+)"'),
    ("project.yml", r"PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)"),
    (".github/workflows/android-build.yml", r"packageName:\s*(\S+)"),
    ("tools/app_config.py", r'ANDROID_PACKAGE\s*=\s*"([^"]+)"'),
]


def apply(root, app_id, name):
    texts = {}
    for rel, pattern, value, every in edits(app_id, name):
        path = root / rel
        if not path.exists():
            continue
        text = texts.get(rel, path.read_text(encoding="utf-8"))
        new, n = re.subn(pattern, lambda m: m.group(1) + value + m.group(3), text, count=0 if every else 1)
        if n == 0:
            raise SystemExit(f"Could not find where {rel} keeps its identity ({pattern}). Nothing was written.")
        texts[rel] = new
    changed = []
    for rel, text in texts.items():
        path = root / rel
        if path.read_text(encoding="utf-8") != text:
            path.write_text(text, encoding="utf-8")
            changed.append(rel)
    return changed


def leftovers(root):
    out = []
    for rel, pattern in IDENTITY_LINES:
        path = root / rel
        if not path.exists():
            continue
        for m in re.finditer(pattern, path.read_text(encoding="utf-8")):
            if m.group(1).startswith(PLACEHOLDER):
                out.append(f"{rel}: {m.group(1)}")
    return out


def repo_name(root):
    env = os.environ.get("GITHUB_REPOSITORY")
    if env:
        return env.lower()
    try:
        url = subprocess.run(["git", "-C", str(root), "remote", "get-url", "origin"],
                             capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return ""
    m = re.search(r"[:/]([^/:]+/[^/]+?)(?:\.git)?$", url)
    return m.group(1).lower() if m else ""


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--id", help="reverse-domain identifier, e.g. org.yourname.birdlog")
    ap.add_argument("--name", help="the name people see under the icon, e.g. \"Bird Log\"")
    ap.add_argument("--check", action="store_true", help="fail if the placeholder identity remains")
    ap.add_argument("--root", default=str(ROOT), help=argparse.SUPPRESS)
    args = ap.parse_args(argv)
    root = Path(args.root)

    if args.check:
        left = leftovers(root)
        if not left:
            print("PASS  the app has its own identity")
            return 0
        if repo_name(root) in TEMPLATE_REPOS:
            print("PASS  this is the template, which keeps com.example.appname on purpose")
            return 0
        print("FAIL  the app still has the template's identity:")
        for line in left:
            print("      " + line)
        print("      Ask your agent to run tools/set_app_identity.py (stage 03).")
        return 1

    if not args.id or not args.name:
        ap.error("--id and --name are both needed (or use --check)")
    app_id = args.id.strip().lower()
    if not ID_RE.match(app_id) or app_id.startswith("com.example"):
        ap.error(f"{args.id!r} is not a usable identifier: use reverse-domain form like "
                 "org.yourname.birdlog, lowercase letters, digits, and underscores, and not com.example")
    name = args.name.strip()
    if not name or len(name) > 30:
        ap.error("the name must be 1 to 30 characters")
    changed = apply(root, app_id, name)
    print(f"{app_id}, \"{name}\": changed {len(changed)} file(s)")
    for rel in changed:
        print("  " + rel)
    return 0


if __name__ == "__main__":
    sys.exit(main())
