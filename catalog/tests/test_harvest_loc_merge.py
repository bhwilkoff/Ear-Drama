"""The LoC harvest merges its records into the file; it never replaces the file.

    python3 tests/test_harvest_loc_merge.py

A job reaches only the records its queries return. Writing just those erased every
record an earlier job (and its item pass) had found, so the cache Release lost
photographs. Synthetic records, a temp file, no network.
Negative control: make save_records write `fresh` instead of the merge -> FAIL on
"a record this job did not reach is kept".
"""
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import harvest_loc_photos as H  # noqa: E402
import ia_lib as L  # noqa: E402

fails = []


def check(ok, what):
    if not ok:
        fails.append(what)


with tempfile.TemporaryDirectory() as d:
    path = os.path.join(d, "records.json.gz")
    old_a = {"id": "a", "title": "A", "files": [{"url": "u"}], "image_master": "m", "queries": ["topic:radio"]}
    old_b = {"id": "b", "title": "B", "files": None, "queries": ["person:x"]}
    L.write_json(path, {"a": old_a, "b": old_b}, gz=True)

    fresh = {"a": {"id": "a", "title": "A2", "files": None, "image_master": None, "queries": ["series:y"]},
             "c": {"id": "c", "title": "C", "files": None, "queries": ["topic:mic"]}}
    merged = H.save_records(path, fresh)
    disk = L.read_json(path)

    check(disk == merged, "the file holds what save_records returned")
    check(set(disk) == {"a", "b", "c"}, f"a record this job did not reach is kept: {sorted(disk)}")
    check(disk["b"] == old_b, "an unreached record is unchanged")
    check(disk["a"]["title"] == "A2", "a reached record takes the fresh fields")
    check(disk["a"]["files"] == [{"url": "u"}] and disk["a"]["image_master"] == "m",
          "fields the job could not fill keep the old value")
    check(disk["a"]["queries"] == ["topic:radio", "series:y"], f"queries are unioned: {disk['a']['queries']}")

    H.save_records(path, {})
    check(set(L.read_json(path)) == {"a", "b", "c"}, "an empty job does not empty the file")

    path2 = os.path.join(d, "new.json.gz")
    H.save_records(path2, {"z": {"id": "z", "queries": []}})
    check(set(L.read_json(path2)) == {"z"}, "a first run writes the file")

for f in fails:
    print("FAIL:", f)
print("harvest_loc merge:", "FAILED" if fails else "ok (7 checks)")
sys.exit(1 if fails else 0)
