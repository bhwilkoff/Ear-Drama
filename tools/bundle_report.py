#!/usr/bin/env python3
"""Prints a built app's size, and refuses one that carries a voice model (Decision 090).

    python3 tools/bundle_report.py android/app/build/outputs/bundle/release/app-release.aab

For each .aab / .apk / .ipa (or .app folder): the file's size, an .aab's compressed size per
module (base, kokoro, ...), and its five largest entries. Written to stdout and, in GitHub
Actions, to the run's summary ($GITHUB_STEP_SUMMARY). Exits 1 when any artifact holds a model
(tools/test_no_model_in_bundle.py's rule) or a path does not exist.

Called by play-release.yml after the signed bundle is built. The App Store workflows are never
edited (2026-11-09: an edited copy was held as malicious), so no IPA size is printed in CI.
"""
import os
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_no_model_in_bundle import scan_archive  # noqa: E402


def mb(n):
    return f"{n / 1e6:.1f} MB"


def report(path):
    lines = []
    if os.path.isdir(path):
        total = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(path) for f in fs)
        lines.append(f"| {os.path.basename(path)} | {mb(total)} | folder |")
        return lines, scan_archive(path)
    size = os.path.getsize(path)
    with zipfile.ZipFile(path) as z:
        infos = [i for i in z.infolist() if not i.is_dir()]
    lines.append(f"| {os.path.basename(path)} | {mb(size)} | {len(infos)} entries |")
    if path.endswith(".aab"):
        mods = {}
        for i in infos:
            top = i.filename.split("/", 1)[0] if "/" in i.filename else "(root)"
            mods[top] = mods.get(top, 0) + i.compress_size
        for m in sorted(mods, key=lambda k: -mods[k]):
            lines.append(f"| &nbsp;&nbsp;module `{m}` | {mb(mods[m])} | compressed |")
    for i in sorted(infos, key=lambda i: -i.compress_size)[:5]:
        lines.append(f"| &nbsp;&nbsp;`{i.filename}` | {mb(i.compress_size)} | largest |")
    return lines, scan_archive(path)


def main(paths):
    if not paths:
        print("usage: bundle_report.py ARTIFACT...")
        return 2
    out = ["### App size (Decision 090)", "", "| Artifact | Size | |", "|---|---|---|"]
    bad = []
    for p in paths:
        if not os.path.exists(p):
            bad.append(f"{p}: does not exist")
            continue
        lines, models = report(p)
        out += lines
        bad += [f"{os.path.basename(p)}: {m} is a voice model" for m in models]
    out += ["", "No voice model inside." if not bad else "**Refused:** " + "; ".join(bad)]
    text = "\n".join(out)
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write(text + "\n")
    for b in bad:
        print(f"::error::{b}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
