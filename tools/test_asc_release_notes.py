#!/usr/bin/env python3
"""
App Store Connect refuses What's New on an app's FIRST version
(409 STATE_ERROR "Attribute 'whatsNew' cannot be edited at this time"), so the
first-ever submit run (2026-11-14, run 43631804893) went red on every platform
though the builds uploaded fine. `ship` must skip the notes there, and must
still fail on any other 409 or on a later version.

Run: python3 tools/test_asc_release_notes.py   (exit 0 = pass)
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_release as r  # noqa: E402

fails = []


def check(ok, what):
    print(f"  {'PASS' if ok else 'FAIL'}  {what}")
    if not ok:
        fails.append(what)


WHATS_NEW = json.dumps({"errors": [{"code": "STATE_ERROR", "title": "x",
    "detail": "Attribute 'whatsNew' cannot be edited at this time"}]})
OTHER = json.dumps({"errors": [{"code": "STATE_ERROR", "title": "x",
    "detail": "The version is not in valid state"}]})


def run(first, body):
    def fake(path, method="GET", body_=None, **kw):
        if method == "GET":
            return {"data": [{"id": "L", "attributes": {"locale": "en-US"}}]}
        raise r.ASCError(409, body)
    r.call = fake
    try:
        return r.set_notes("V", "notes", "en-US", False, first_version=first)
    except r.ASCError:
        return "raised"


check(run(True, WHATS_NEW) is True, "first version: whatsNew 409 is skipped, not failed")
check(run(False, WHATS_NEW) == "raised", "later version: whatsNew 409 still fails")
check(run(True, OTHER) == "raised", "first version: a different 409 still fails")
sys.exit(1 if fails else 0)
