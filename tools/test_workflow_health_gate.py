#!/usr/bin/env python3
"""The health issue must carry the failures NOTHING ELSE alerts, and stay quiet otherwise.

The auditor itself never fails (reporters never fail) — `urgent_findings` decides
what goes to the one self-closing workflow-health issue instead of a red X.

GitHub sends its own email on every failed run, so a FAILED finding has already
interrupted the owner — raising it again would be a duplicate alert repeated
daily. The issue is reserved for the classes with no other voice: BROKEN (green
but produced nothing) and KILLED (cancelled with publish skipped — GitHub never
emails about cancelled runs). A finding whose fix is already in flight (a later
manual run succeeded) is reported, not raised — a MONTHLY workflow would
otherwise hold the issue open for weeks over a bug already fixed.

The negative controls are the point: a deferred or merely-reported finding must
never suppress a real one. The rest of the auditor's regressions (failures of
no-yield workflows, displacement, self-cancelling, exit 0) live in
tools/test_workflow_health.py.
"""
import sys
import pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from audit_workflow_health import urgent_findings

CASES = [
    # FAILED already sent its own GitHub email — reported here, never re-failed.
    ("FAILED already emailed by GitHub",     [("FAILED", "x", "boom", False)], 0),
    ("FAILED with a fix in flight",       [("FAILED", "x", "boom", True)],  0),
    ("KILLED with a fix in flight",       [("KILLED", "x", "boom", True)],  0),
    ("KILLED, no newer dispatch",         [("KILLED", "x", "boom", False)], 1),
    ("BROKEN, no newer dispatch",         [("BROKEN", "x", "boom", False)], 1),
    ("DROPPED is never urgent",           [("DROPPED", "x", "q", False)],   0),
    ("STALE is never urgent",             [("STALE", "x", "q", False)],     0),
    ("SILENT is never urgent",            [("SILENT", "x", "q", False)],    0),
    # The ones that must never regress: neither a deferred finding nor a
    # merely-reported FAILED may silence a real urgent one beside it.
    ("deferred + real together",          [("KILLED", "a", "x", True),
                                           ("KILLED", "b", "y", False)],    1),
    ("reported FAILED beside real KILLED", [("FAILED", "a", "x", False),
                                            ("KILLED", "b", "y", False)],   1),
]

ok = True
for name, findings, want in CASES:
    got = len(urgent_findings(findings))
    good = got == want
    ok &= good
    print(f"  {'PASS' if good else 'FAIL'} {name} (urgent={got}, want={want})")

# The reporter reads the auditor's PRINTED lines back, so it must apply the same
# in-flight rule from the text alone, or the issue reopens over a fixed bug.
from audit_workflow_health import FIX_IN_FLIGHT  # noqa: E402
from report_workflow_health import split  # noqa: E402

REPORTER_CASES = [
    ("reporter: in-flight KILLED is not raised",
     [("KILLED", f"x boom — but a manual run SUCCEEDED, so this {FIX_IN_FLIGHT}")], 0),
    ("reporter: KILLED with no marker is raised", [("KILLED", "x boom")], 1),
    ("reporter: in-flight beside a real BROKEN",
     [("KILLED", f"a — {FIX_IN_FLIGHT}"), ("BROKEN", "b green, 0 items")], 1),
    ("reporter: FAILED is never raised", [("FAILED", "x boom")], 0),
]
for name, found, want in REPORTER_CASES:
    got = len(split(found)[0])
    good = got == want
    ok &= good
    print(f"  {'PASS' if good else 'FAIL'} {name} (urgent={got}, want={want})")

print("\nALL PASS" if ok else "\nFAILURES")
sys.exit(0 if ok else 1)
