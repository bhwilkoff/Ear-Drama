"""Pack and unpack the play library as a dated Release asset (plays-library-YYYY-MM-DD.tar.xz).

    python3 tools/play_library_archive.py pack   [DIR] OUT.tar.xz     # DIR default catalog/out/plays-library
    python3 tools/play_library_archive.py unpack ARCHIVE DIR          # refuses an unsafe or malformed archive

The archive holds `plays-library/index.json`, `scripts/<id>.json`, `phonemes/<id>.json`,
`phonemes-report.json` (Decision 078), and since B31 C3 `collections.json`, `characters.json` and
`search/said/<p>.json` (catalog DECISIONS 050), nothing else, in sorted order with no owner or time, so the same
library packs to the same bytes. `unpack` refuses a member that is not one of those shapes (a path that climbs out, a link, a stray file), then runs the shape check
over what it wrote; a bad archive raises, so a caller never ships it.
"""
import os
import re
import shutil
import sys
import tarfile
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_play_library as C

TOP = "plays-library"
MEMBER = re.compile(r"^plays-library/(index\.json|phonemes-report\.json|collections\.json|characters\.json|(scripts|phonemes)/gut-\d+(-\d+)?\.json|"
                    r"search/said/(?:[a-z0-9]{2}|x[0-9a-f]+)\.json)$")
# Beside the index since B31 C3 (contract 4.1): packed when the build wrote them.
FINDING = ("collections.json", "characters.json")


def pack(src, out):
    C.check_library(src, C.MIN_PLAYS, C.MIN_PHONEME_SHARE)
    names = ["index.json", "phonemes-report.json"] + [f for f in FINDING if os.path.exists(os.path.join(src, f))] + \
        [f"{d}/{n}" for d in ("phonemes", "scripts", "search/said") if os.path.isdir(os.path.join(src, d))
         for n in sorted(os.listdir(os.path.join(src, d)))]
    with tarfile.open(out, "w:xz", preset=9) as tar:
        for name in names:
            info = tar.gettarinfo(os.path.join(src, name), arcname=f"{TOP}/{name}")
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            info.mtime = 0
            info.mode = 0o644
            with open(os.path.join(src, name), "rb") as f:
                tar.addfile(info, f)
    return len(names)


def unpack(archive, dest):
    """Extract into `dest` (replaced), checked. Returns the index."""
    with tempfile.TemporaryDirectory() as tmp:
        with tarfile.open(archive, "r:xz") as tar:
            members = tar.getmembers()
            bad = [m.name for m in members if not (m.isreg() and MEMBER.match(m.name))]
            if bad:
                raise ValueError(f"archive holds a member that is not part of a play library: {bad[:3]}")
            if not any(m.name == f"{TOP}/index.json" for m in members):
                raise ValueError("archive has no index.json")
            tar.extractall(tmp, members=members, filter="data")
        idx = C.check_library(os.path.join(tmp, TOP), C.MIN_PLAYS, C.MIN_PHONEME_SHARE)
        shutil.rmtree(dest, ignore_errors=True)
        os.makedirs(os.path.dirname(os.path.abspath(dest)), exist_ok=True)
        shutil.move(os.path.join(tmp, TOP), dest)
    return idx


def main():
    a = sys.argv[1:]
    if a[:1] == ["pack"] and len(a) in (2, 3):
        src = a[1] if len(a) == 3 else C.DEFAULT
        print(f"packed {pack(src, a[-1])} files into {a[-1]} ({os.path.getsize(a[-1])} bytes)")
    elif a[:1] == ["unpack"] and len(a) == 3:
        print(f"unpacked {unpack(a[1], a[2])['count']} plays into {a[2]}")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
