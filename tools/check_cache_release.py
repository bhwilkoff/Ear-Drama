#!/usr/bin/env python3
"""Refuse a staged catalog Release that holds what tools/cache_denylist.txt names.

    python3 tools/check_cache_release.py <folder>

Every file in the folder is read for what it is, not what it is called: an xz stream is
opened, a tar's member names are compared, a SQLite file's tables are. radio-catalog.sqlite.xz
must be a database and harvest-cache.tar.xz a tar, since a file nothing could read was not
checked. A database with free pages is refused (a dropped table's words stay in them until
VACUUM), and so is an archive or database inside the tar. It does not read the members'
words: a text moved to another name is not caught.
"""
import fnmatch
import lzma
import os
import re
import shutil
import sqlite3
import sys
import tarfile
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MUST = {"radio-catalog.sqlite.xz": "sqlite", "harvest-cache.tar.xz": "tar"}
INNER = re.compile(r"\.(sqlite3?|db|tar|tgz|txz|zip|7z|rar)(\.(gz|xz|bz2|zst))?$", re.I)


def denylist(path):
    """(paths, table patterns); an unreadable, empty or unknown line is an error, never "nothing denied"."""
    paths, tables = [], []
    with open(path, encoding="utf-8") as f:
        for ln in f:
            row = ln.split("#")[0].split()
            if not row:
                continue
            if len(row) != 2 or row[0] not in ("path", "table"):
                raise SystemExit(f"denylist: cannot read the line {ln.strip()!r} of {path}")
            (paths if row[0] == "path" else tables).append(row[1].strip("/").lower())
    if not paths or not tables:
        raise SystemExit(f"denylist: {path} names no path or no table, so it would refuse nothing")
    return paths, tables


def denied_path(name, paths):
    parts = [p for p in name.lower().split("/") if p not in ("", ".")]
    for p in paths:
        want = p.split("/")
        if any(parts[i:i + len(want)] == want for i in range(len(parts) - len(want) + 1)):
            return p
    return None


def check_tar(label, path, paths):
    bad, n = {}, 0
    with tarfile.open(path, "r:*") as t:
        for m in t:
            n += 1
            p = denied_path(m.name, paths)
            if p:
                bad.setdefault(f"{label} holds {p}, which is never public", []).append(m.name)
            elif INNER.search(m.name):
                bad.setdefault(f"{label} holds an archive or database nothing here reads", []).append(m.name)
    if not n:
        bad[f"{label} is an empty tar"] = []
    return [f"{k} ({len(v)} members: {', '.join(v[:3])})" for k, v in bad.items()]


def check_db(label, path, tables):
    c = sqlite3.connect(f"file:{path}?mode=ro&immutable=1", uri=True)
    try:
        names = [r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY name")]
        free = c.execute("PRAGMA freelist_count").fetchone()[0]
    finally:
        c.close()
    out = [f"{label} holds {n}, which is never public" for n in names
           if any(fnmatch.fnmatchcase(n.lower(), t) for t in tables)]
    if free:
        out.append(f"{label} has {free} free pages, where a dropped table's words stay; run VACUUM and stage it again")
    return out


def kind(path):
    with open(path, "rb") as f:
        if f.read(16) == b"SQLite format 3\0":
            return "sqlite"
    try:
        with tarfile.open(path, "r:*"):
            return "tar"
    except (tarfile.TarError, OSError, EOFError):
        return "other"


def check_folder(folder, paths, tables):
    out = []
    for name in sorted(os.listdir(folder)):
        p = os.path.join(folder, name)
        if denied_path(name, paths):
            out.append(f"{name} is a name that is never public")
        with tempfile.TemporaryDirectory() as tmp:
            q = p
            with open(p, "rb") as f:
                packed = f.read(6) == b"\xfd7zXZ\0"
            if packed:
                q = os.path.join(tmp, "unpacked")
                with lzma.open(p) as src, open(q, "wb") as dst:
                    shutil.copyfileobj(src, dst, 1 << 20)
            k = kind(q)
            if name in MUST and k != MUST[name]:
                out.append(f"{name} is not a {MUST[name]} file, so its contents could not be checked")
            try:
                if k == "tar":
                    out += check_tar(name, q, paths)
                elif k == "sqlite":
                    out += check_db(name, q, tables)
            except (tarfile.TarError, sqlite3.Error) as e:
                out.append(f"{name} could not be read ({e}), so its contents were not checked")
    return out


def main():
    if len(sys.argv) != 2 or not os.path.isdir(sys.argv[1]):
        sys.exit("usage: check_cache_release.py <folder>")
    paths, tables = denylist(os.environ.get("CACHE_DENYLIST") or os.path.join(HERE, "cache_denylist.txt"))
    bad = check_folder(sys.argv[1], paths, tables)
    for b in bad:
        print(b, file=sys.stderr)
    if bad:
        sys.exit(1)
    print(f"contents: none of {len(paths)} paths and {len(tables)} table patterns on the denylist is in {sys.argv[1]}")


if __name__ == "__main__":
    main()
