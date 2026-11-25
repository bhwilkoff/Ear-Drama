"""tools/cut_catalog_release.sh against a fake `gh` that keeps its Releases in a folder.

Nothing here reaches GitHub: the fake gh is first on PATH, and records every call.

Broken controls, 2026-10-28, each run against a mutated copy (CUT_SCRIPT=...):
    the existing-Release check removed        an existing tag is cut: 1 failure
    the digest read-back removed              a corrupted upload is published: 2 failures
    gh release upload given --clobber         the static and the call checks: 2 failures
2026-11-24 (R4-9a): every planted case failed against the script before the contents check (13);
check_cache_release.py mutated (CUT_CHECK=... names the copy):
    the tar members never compared            4 failures
    the tables never compared                 3 failures
    the free-page test removed                1 failure
    an empty denylist accepted                1 failure
    an archive inside the tar accepted        1 failure
    the two assets' kinds not checked         2 failures
"""
import hashlib
import io
import lzma
import os
import sqlite3
import subprocess
import sys
import tarfile
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


def tar_bytes(*names, dirs=()):
    """A tar of small members, in the order given."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w") as t:
        for d in dirs:
            ti = tarfile.TarInfo(d)
            ti.type = tarfile.DIRTYPE
            t.addfile(ti)
        for n in names:
            ti = tarfile.TarInfo(n)
            ti.size = 2
            t.addfile(ti, io.BytesIO(b"{}"))
    return buf.getvalue()


def db_bytes(*sql):
    with tempfile.TemporaryDirectory() as tmp:
        p = os.path.join(tmp, "x.sqlite")
        c = sqlite3.connect(p)
        c.execute("PRAGMA auto_vacuum = NONE")
        c.execute("CREATE TABLE episodes (id)")
        for q in sql:
            c.execute(q)
        c.commit()
        c.close()
        return open(p, "rb").read()


GOOD_TAR = tar_bytes("grw/scripts.json", "grw/text_ids.json", "meta/a.json.gz", dirs=("grw", "meta"))
GOOD_DB = db_bytes("CREATE TABLE scripts (id, title)")


def setup(releases=("catalog-2026-10-21", "catalog-latest"), gitrefs=("catalog-2026-10-21",), tar=GOOD_TAR, db=GOOD_DB,
          more=None):
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
    files = {"radio-catalog.sqlite.xz": lzma.compress(db, format=lzma.FORMAT_XZ),
             "harvest-cache.tar.xz": lzma.compress(tar, format=lzma.FORMAT_XZ),
             "build_report.json": b"{}", **(more or {})}
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

# 10. What may not be public (tools/cache_denylist.txt): planted, each refused before any call to GitHub.
CUES = "CREATE TABLE script_cues (script_id, text)"
PLANTED = [
    ("a tar holding grw/text is refused", {"tar": tar_bytes("grw/scripts.json", "grw/text/A1.txt")}, "grw/text/A1.txt"),
    ("a tar whose names start with ./ is refused too", {"tar": tar_bytes("./grw/text/A1.txt")}, "grw/text"),
    ("a tar holding it one folder down is refused", {"tar": tar_bytes("cache/GRW/text/A1.txt")}, "grw/text"),
    ("an empty grw/text folder is refused", {"tar": tar_bytes("grw/scripts.json", dirs=("grw/text",))}, "grw/text"),
    ("a database inside the tar cannot be read, so it is refused", {"tar": tar_bytes("grw/x.sqlite")}, "x.sqlite"),
    ("a database with script_cues is refused", {"db": db_bytes(CUES)}, "script_cues"),
    ("a view under the same name pattern is refused", {"db": db_bytes("CREATE VIEW script_cues_v AS SELECT 1")},
     "script_cues_v"),
    ("a dropped table's free pages are refused",
     {"db": db_bytes(CUES, "INSERT INTO script_cues VALUES (1, hex(zeroblob(40000)))", "DROP TABLE script_cues")}, "VACUUM"),
    ("a second database under another name is refused", {"more": {"notes.bin": db_bytes(CUES)}}, "script_cues"),
    ("a cache that is not a tar is refused: nothing could check it", {"tar": b"not a tar"}, "harvest-cache.tar.xz"),
    ("a database that is not SQLite is refused", {"db": b"not a database"}, "radio-catalog.sqlite.xz"),
]
for name, kw, word in PLANTED:
    _, b, st, d = setup(**kw)
    rc, out, calls = run(b, st, d, TAG)
    check(name, rc != 0 and word in out and not calls, f"rc={rc} calls={calls} {out[-300:]}")
_, b, st, d = setup()
for label, body in (("empty", "# nothing\n"), ("with a word it does not know", "file grw/text\n")):
    deny = os.path.join(d, "..", "deny.txt")
    with open(deny, "w") as f:
        f.write(body)
    rc, out, calls = run(b, st, "--dry-run", d, TAG, env_extra={"CACHE_DENYLIST": deny})
    check(f"a denylist {label} is refused, never read as 'nothing is denied'", rc != 0 and "denylist" in out, out)
with open(os.path.join(ROOT, "tools", "cache_denylist.txt")) as f:
    rows = [ln.split("#")[0].split() for ln in f if ln.split("#")[0].strip()]
check("the list names the Workshop's text and the cues made of it",
      ["path", "grw/text"] in rows and ["table", "script_cues*"] in rows, rows)

# 11. Static: no line of the script uploads with --clobber.
with open(SCRIPT) as f:
    bad = [ln for ln in f if not ln.lstrip().startswith("#") and "release upload" in ln and "--clobber" in ln]
check("the script never uploads with --clobber", not bad, bad)

print(f"{'FAILED' if failures else 'passed'}: {len(failures)} failures")
sys.exit(1 if failures else 0)
