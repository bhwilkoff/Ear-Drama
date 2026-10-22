#!/usr/bin/env python3
"""Guard for the guard: does frame_is_home_screen() actually detect anything?

A ported copy of this probe returned False for EVERY frame for weeks, so the
foreground check it exists to perform never ran once — and nothing noticed,
because "not the home screen" is the answer a working probe gives most of the
time. A silent always-False is the worst failure a detector can have: the
harness keeps grading, and grades the wrong screen.

The rule it enforces now is three-valued: True (home screen), False (something
else, READ successfully), None (could not see). An OCR failure must be None —
never a confident False.

    python3 tools/test_home_screen_probe.py
"""
import json
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent))
import apple_device as A  # noqa: E402


def _fake_ocr(entries=None, stdout=None, rc=0):
    """Stand in for the OCR binary, emitting ScreenOCR's REAL shape."""
    if stdout is None:
        stdout = json.dumps({"file": "x.png", "captionRegion": [], "allText": entries}) + "\n"
    return lambda *a, **k: SimpleNamespace(stdout=stdout, stderr="", returncode=rc)


def _raises(*a, **k):
    raise subprocess.TimeoutExpired("screenocr", 120)


def main():
    fails = []

    def check(name, fake, expect):
        A.sh = fake
        got = A.frame_is_home_screen(Path("x.png"), ocr_bin="/nonexistent/ocr")
        ok = got is expect
        print(f"  {'PASS' if ok else 'FAIL'} {name} — expected {expect}, got {got}")
        if not ok:
            fails.append(name)

    # ScreenOCR emits DICTS. This is the shape that broke the old port: it assumed
    # a list of strings, joined the dicts, raised TypeError, and swallowed it.
    home = [{"text": "Prime Video", "x": 0.1, "y": 0.5, "w": 0.1, "h": 0.02},
            {"text": "9:41 PM", "x": 0.8, "y": 0.9, "w": 0.05, "h": 0.02}]
    app = [{"text": "Settings", "x": 0.1, "y": 0.5, "w": 0.2, "h": 0.03},
           {"text": "Continue where you left off", "x": 0.1, "y": 0.4, "w": 0.2, "h": 0.02}]

    check("tvOS home screen (dict entries)", _fake_ocr(home), True)
    check("the app's own screen", _fake_ocr(app), False)
    # A plain list of strings is what the broken branch was reaching for; accept
    # it rather than crash, so a future OCR change degrades instead of lying.
    check("plain-string entries", _fake_ocr(["Pluto TV", "9:41 PM"]), True)
    # The regression this file exists for: every way the probe can fail to SEE
    # must come back None, never False.
    check("empty frame is UNKNOWN, not 'not home'", _fake_ocr([]), None)
    check("OCR printed nothing is UNKNOWN", _fake_ocr(stdout="", rc=1), None)
    check("OCR printed garbage is UNKNOWN", _fake_ocr(stdout="not json\n"), None)
    check("OCR timed out is UNKNOWN", _raises, None)

    print("\nALL PASS" if not fails else f"\nFAILED: {', '.join(fails)}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
