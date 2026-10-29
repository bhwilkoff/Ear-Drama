"""ia_lib's cache readers (tools/ia_lib.py), each rule with its broken control.

    python3 tests/test_ia_lib.py
"""
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import ia_lib as ia

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


def raises(fn):
    try:
        fn()
        return None
    except Exception as e:  # noqa: BLE001: the kind is the result
        return type(e).__name__


with tempfile.TemporaryDirectory() as t:
    plain, gz = os.path.join(t, "plain.json"), os.path.join(t, "cache.json")
    ia.write_json(plain, {"kind": "plain"})
    ia.write_json(gz + ".gz", {"kind": "gzipped"}, gz=True)
    check("a plain file reads", ia.read_json(plain), {"kind": "plain"})
    check("a .gz path reads gzipped", ia.read_json(gz + ".gz"), {"kind": "gzipped"})
    check("a plain path whose cache was written gzipped reads the .gz", ia.read_json(gz), {"kind": "gzipped"})
    ia.write_json(gz, {"kind": "both"})
    check("when both exist, the plain file named is the one read", ia.read_json(gz), {"kind": "both"})
    check("control: a path absent in both forms is still missing",
          raises(lambda: ia.read_json(os.path.join(t, "absent.json"))), "FileNotFoundError")
    check("control: a .gz path absent does not fall back further",
          raises(lambda: ia.read_json(os.path.join(t, "plain.json.gz"))), "FileNotFoundError")

import build_db as B  # noqa: E402

with tempfile.TemporaryDirectory() as t:
    only_gz, absent = os.path.join(t, "editorial.json"), os.path.join(t, "none.json")
    ia.write_json(only_gz + ".gz", {"kind": "gzipped"}, gz=True)
    check("build_db.load reads a file that exists only as .gz", B.load(only_gz, {}), {"kind": "gzipped"})
    check("control: build_db.load of a path absent in both forms is the default", B.load(absent, "dflt"), "dflt")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
