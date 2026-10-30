"""tools/cut_catalog_release.sh against a fake `gh` that keeps its Releases in a folder.

Nothing here reaches GitHub: the fake gh is first on PATH, and records every call.

Broken controls, 2026-10-28, each run against a mutated copy (CUT_SCRIPT=...):
    the existing-Release check removed        an existing tag is cut: 1 failure
    the digest read-back removed              a corrupted upload is published: 2 failures
    gh release upload given --clobber         the static and the call checks: 2 failures
"""
import hashlib
import lzma
import os
import subprocess
import sys
import tempfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SCRIPT = os.environ.get("CUT_SCRIPT") or os.path.join(ROOT, "tools", "cut_catalog_release.sh")

FAKE_GH = r"""#!/usr/bin/env bash
st="$FAKE_STATE"
printf '%s\n' "$*" >> "$st/calls"
case "$1 $2" in
  "api repos/"*)
    case "$2" in
      */releases)
        if [ -s "$st/pending" ]; then
          c=$(( $(cat "$st/lag" 2>/dev/null || echo 0) - 1 ))
          if [ "$c" -le 0 ]; then cat "$st/pending" >> "$st/releases"; : > "$st/pending"; else echo "$c" > "$st/lag"; fi
        fi
        cat "$st/releases" ;;
      */git/ref/tags/*)
        t=${2##*/}
        if grep -qxF "$t" "$st/gitrefs"; then echo '{"ref":"refs/tags/'"$t"'"}'; exit 0; fi
        echo 'gh: Not Found (HTTP 404)' >&2; exit 1 ;;
    esac ;;
  "release create")
    if [ -n "${FAKE_LAG:-}" ]; then echo "$3" > "$st/pending"; echo "$FAKE_LAG" > "$st/lag"; else echo "$3" >> "$st/releases"; fi ;;
  "release upload")
    for a in "$@"; do [ -f "$a" ] && p="$a"; done
    sum=$( (sha256sum "$p" 2>/dev/null || shasum -a 256 "$p") | awk '{print $1}')
    [ -n "${FAKE_CORRUPT:-}" ] && sum=0000
    echo "$(basename "$p") $(wc -c < "$p" | tr -d ' ') sha256:$sum" >> "$st/assets" ;;
  "release view") cat "$st/assets" ;;
  "release edit") echo published > "$st/published" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 9 ;;
esac
"""

failures = []


def check(name, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + name + ("" if ok else f": {detail}"))
    if not ok:
        failures.append(name)


def setup(releases=("catalog-2026-10-21", "catalog-latest"), gitrefs=("catalog-2026-10-21",)):
    t = tempfile.mkdtemp(prefix="cutrel-")
    bindir, st, folder = (os.path.join(t, d) for d in ("bin", "state", "staged"))
    for d in (bindir, st, folder):
        os.makedirs(d)
    with open(os.path.join(bindir, "gh"), "w") as f:
        f.write(FAKE_GH)
    os.chmod(os.path.join(bindir, "gh"), 0o755)
    for fn, rows in (("releases", releases), ("gitrefs", gitrefs)):
        with open(os.path.join(st, fn), "w") as f:
            f.write("".join(r + "\n" for r in rows))
    open(os.path.join(st, "assets"), "w").close()
    open(os.path.join(st, "calls"), "w").close()
    files = {"radio-catalog.sqlite.xz": lzma.compress(b"db", format=lzma.FORMAT_XZ),
             "harvest-cache.tar.xz": lzma.compress(b"cache", format=lzma.FORMAT_XZ),
             "build_report.json": b"{}"}
    sums = ""
    for n, b in files.items():
        with open(os.path.join(folder, n), "wb") as f:
            f.write(b)
        sums += f"{hashlib.sha256(b).hexdigest()}  {n}\n"
    with open(os.path.join(folder, "SHA256SUMS"), "w") as f:
        f.write(sums)
    with open(os.path.join(folder, "NOTES.md"), "w") as f:
        f.write("notes\n")
    return t, bindir, st, folder


def run(bindir, st, *args, env_extra=None):
    env = dict(os.environ, PATH=bindir + os.pathsep + os.environ["PATH"], FAKE_STATE=st, REPO="o/r")
    env.update(env_extra or {})
    p = subprocess.run(["bash", SCRIPT, *args], capture_output=True, text=True, env=env, timeout=120)
    with open(os.path.join(st, "calls")) as f:
        calls = f.read().splitlines()
    return p.returncode, p.stdout + p.stderr, calls


def writes(calls):
    return [c for c in calls if c.split()[:2] in (["release", "create"], ["release", "upload"], ["release", "edit"])]


TAG = "catalog-2026-10-28"

# 1. A dry run of a good folder passes and writes nothing.
_, b, st, d = setup()
rc, out, calls = run(b, st, "--dry-run", d, TAG)
check("dry run of a good folder passes", rc == 0, out)
check("dry run writes nothing", not writes(calls), writes(calls))

# 2. An existing Release (or draft) with the tag is refused, in a dry run.
_, b, st, d = setup(releases=("catalog-2026-10-21", TAG))
rc, out, calls = run(b, st, "--dry-run", d, TAG)
check("an existing Release is refused", rc != 0 and "already exists" in out, out)

# 3. An existing git tag with no Release is refused.
_, b, st, d = setup(gitrefs=("catalog-2026-10-21", TAG))
rc, out, calls = run(b, st, "--dry-run", d, TAG)
check("an existing git tag is refused", rc != 0 and "git tag" in out, out)

# 4. A tag older than the newest dated Release is refused (the workflow would never restore it).
_, b, st, d = setup(releases=("catalog-2026-11-01",))
rc, out, calls = run(b, st, "--dry-run", d, TAG)
check("a tag that is not the newest is refused", rc != 0 and "not newer" in out, out)

# 5. A file that does not match SHA256SUMS is refused before any call to GitHub.
_, b, st, d = setup()
with open(os.path.join(d, "build_report.json"), "ab") as f:
    f.write(b" ")
rc, out, calls = run(b, st, d, TAG)
check("a checksum mismatch is refused", rc != 0 and "checksums" in out, out)
check("a checksum mismatch calls no gh", not calls, calls)

# 6. A file SHA256SUMS does not list is refused.
_, b, st, d = setup()
with open(os.path.join(d, "extra.json"), "w") as f:
    f.write("{}")
rc, out, calls = run(b, st, "--dry-run", d, TAG)
check("an unlisted file is refused", rc != 0 and "not listed" in out, out)

# 7. --clobber is refused outright, and a tag of the wrong form too.
_, b, st, d = setup()
rc, out, calls = run(b, st, "--clobber", d, TAG)
check("--clobber is refused", rc != 0 and not calls, out)
rc, out, calls = run(b, st, "--dry-run", d, "catalog-latest")
check("a tag the workflow would not restore is refused", rc != 0 and "catalog-YYYY-MM-DD" in out, out)

# 8. A real run: draft, every asset uploaded without --clobber, digests read back, then published.
_, b, st, d = setup()
rc, out, calls = run(b, st, d, TAG)
w = writes(calls)
check("a good run passes", rc == 0, out)
check("a good run creates a draft first", bool(w) and w[0].startswith(f"release create {TAG}") and "--draft" in w[0], w)
check("a good run uploads every asset", sum(c.startswith("release upload") for c in w) == 4, w)
check("no call passes --clobber", not any("--clobber" in c for c in calls), calls)
check("a good run publishes last", bool(w) and w[-1].startswith(f"release edit {TAG}") and "--draft=false" in w[-1], w)

# 9. An upload whose digest GitHub reports differently is never published.
_, b, st, d = setup()
rc, out, calls = run(b, st, d, TAG, env_extra={"FAKE_CORRUPT": "1"})
check("a corrupted upload is refused", rc != 0 and "sha256" in out, out)
check("a corrupted upload stays a draft", not os.path.exists(os.path.join(st, "published")), calls)

# 9b. GitHub's Release list lags the create (2026-10-29: read 0 at once, stranded a good draft).
_, b, st, d = setup()
rc, out, calls = run(b, st, d, TAG, env_extra={"FAKE_LAG": "3", "CUT_LIST_WAIT": "0"})
check("a lagging Release list is asked again, then the run publishes", rc == 0 and os.path.exists(os.path.join(st, "published")), out)

# 10. Static: no line of the script uploads with --clobber.
with open(SCRIPT) as f:
    bad = [ln for ln in f if not ln.lstrip().startswith("#") and "release upload" in ln and "--clobber" in ln]
check("the script never uploads with --clobber", not bad, bad)

print(f"{'FAILED' if failures else 'passed'}: {len(failures)} failures")
sys.exit(1 if failures else 0)
