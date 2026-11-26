#!/usr/bin/env python3
"""No voice model ships in a store download (Decision 090, PLAYS-DESIGN 2.8 rule 13).

The Kokoro model (532 MB on Apple, 107 MB on Android) is fetched only by the person's tap.
An accidental bundle is the one real size risk, so this fails when:

  * a model file sits anywhere a build packs from: apple/ (XcodeGen bundles whole source
    folders, tracked or not), android/ (the base module and every feature module), assets/;
    a model file is .onnx, .ort, .mlmodel, .mlmodelc, .mlpackage, or a .bin over 5 MB;
  * a build file (project.yml, any build.gradle.kts) names one as a resource or asset;
  * with --artifact, a built .ipa / .app / .apk / .aab holds one (an .aab's base/ module and
    every other module are read; tools/bundle_report.py calls this from CI).

Build outputs (build/, DerivedData/, .gradle/) are skipped. A negative control plants each
kind of model in a scratch tree and must see every one caught, or the run fails.
"""
import os
import re
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCANNED = ["apple", "android", "assets"]
SKIP_DIRS = {"build", "DerivedData", ".gradle", ".cxx", ".kotlin", "node_modules", ".git", ".idea"}
MODEL_EXT = (".onnx", ".ort", ".mlmodel", ".mlmodelc", ".mlpackage")
BIN_LIMIT = 5 * 1024 * 1024
BUILD_FILES = re.compile(r"(^|/)(project\.yml|build\.gradle\.kts|build\.gradle)$")
BUILD_REF = re.compile(r"[\w./-]*(\.onnx|\.ort|\.mlmodelc?|\.mlpackage|voices-en\.bin|kokoro-v\d[\w.-]*\.bin)\b")


def is_model_name(name, size):
    low = name.lower().rstrip("/")
    if any(low.endswith(e) or f"{e}/" in low + "/" for e in MODEL_EXT):
        return True
    return low.endswith(".bin") and size > BIN_LIMIT


def scan_tree(root, tops=SCANNED):
    found = []
    for top in tops:
        base = os.path.join(root, top)
        if not os.path.isdir(base):
            continue
        for d, dirs, files in os.walk(base):
            dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS)
            for x in sorted(dirs):
                if x.lower().endswith((".mlmodelc", ".mlpackage")):
                    found.append(os.path.relpath(os.path.join(d, x), root))
            dirs[:] = [x for x in dirs if not x.lower().endswith((".mlmodelc", ".mlpackage"))]
            for f in sorted(files):
                p = os.path.join(d, f)
                rel = os.path.relpath(p, root)
                try:
                    size = os.path.getsize(p)
                except OSError:
                    continue
                if is_model_name(f, size):
                    found.append(rel)
                elif BUILD_FILES.search(rel):
                    with open(p, encoding="utf-8", errors="replace") as fh:
                        for n, line in enumerate(fh, 1):
                            if line.lstrip().startswith(("#", "//")):
                                continue
                            m = BUILD_REF.search(line)
                            if m:
                                found.append(f"{rel}:{n} names {m.group(0)}")
    return found


def scan_archive(path):
    """Model entries inside a built .ipa/.apk/.aab (zip) or a .app folder."""
    found = []
    if os.path.isdir(path):
        for d, dirs, files in os.walk(path):
            dirs.sort()
            for x in sorted(dirs + files):
                p = os.path.join(d, x)
                size = os.path.getsize(p) if os.path.isfile(p) else 0
                if is_model_name(x, size):
                    found.append(os.path.relpath(p, path))
        return found
    with zipfile.ZipFile(path) as z:
        for info in sorted(z.infolist(), key=lambda i: i.filename):
            if is_model_name(info.filename, info.file_size):
                found.append(info.filename)
    return found


def control():
    """Every planted model must be caught, and a clean tree must pass."""
    with tempfile.TemporaryDirectory() as t:
        clean = os.path.join(t, "apple", "Core")
        os.makedirs(clean)
        open(os.path.join(clean, "small.bin"), "wb").write(b"x" * 1024)
        open(os.path.join(t, "apple", "project.yml"), "w").write("resources:\n  - path: Fonts\n# a.onnx in a comment\n")
        assert scan_tree(t) == [], scan_tree(t)
        plants = [
            ("apple/Resources/kokoro.onnx", 10),
            ("android/app/src/main/assets/model.ort", 10),
            ("android/kokoro/src/main/assets/voices.bin", BIN_LIMIT + 1),
            ("assets/k.mlmodel", 10),
        ]
        for rel, size in plants:
            p = os.path.join(t, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "wb") as fh:
                fh.truncate(size)
        os.makedirs(os.path.join(t, "apple", "Resources", "Kokoro.mlpackage", "Data"))
        with open(os.path.join(t, "android", "app", "build.gradle.kts"), "w") as fh:
            fh.write('android { sourceSets { getByName("main").assets.srcDir("x/kokoro-v3.mlpackage") } }\n')
        got = scan_tree(t)
        want = [r for r, _ in plants] + ["apple/Resources/Kokoro.mlpackage", "android/app/build.gradle.kts"]
        missed = [w for w in want if not any(g.startswith(w) for g in got)]
        if missed:
            return f"the scan missed planted models: {missed}"
        aab = os.path.join(t, "x.aab")
        with zipfile.ZipFile(aab, "w") as z:
            z.writestr("base/dex/classes.dex", b"x")
            z.writestr("base/assets/kokoro.onnx", b"x")
        if scan_archive(aab) != ["base/assets/kokoro.onnx"]:
            return "the archive scan missed a planted model"
    return None


def main(argv):
    bad = control()
    if bad:
        print(f"FAIL control: {bad}")
        return 1
    print("  ok   control: 6 planted models caught in a tree and 1 in an archive; a clean tree passes")
    found = scan_tree(ROOT)
    arts = [a for a in argv if not a.startswith("--")] if "--artifact" in argv else []
    for a in arts:
        found += [f"{os.path.basename(a)}: {e}" for e in scan_archive(a)]
    if found:
        for f in found:
            print(f"FAIL model in a store download: {f}")
        return 1
    print(f"PASS: no voice model in {', '.join(SCANNED)}" + (f" or {len(arts)} artifact(s)" if arts else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
