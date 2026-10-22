"""Shared spine for the real-hardware harnesses (tvOS / iOS / Android / Mac / web).

The harnesses this rig descends from were three hand-written scripts that shared
nothing but an OCR binary, and they paid for it: the iOS one had no wake, no alive
probe and no retry ladder because the tvOS resilience was never back-ported.
Everything here is the part that is genuinely platform-agnostic — OCR, grading,
artifact paths, the stale-capture guard and the blind-instrument guard — so a lesson
learned on one device reaches all of them.

Device plumbing deliberately does NOT live here. Waking a tvOS box over Companion,
unlocking a Pixel over adb, and giving up on a locked iPad are not the same
operation wearing different hats, and pretending otherwise is how you get a
lowest-common-denominator harness that cannot express what any one platform
actually needs. Apple plumbing shared by the iOS and tvOS runners lives in
tools/apple_device.py.
"""
import json
import re
import subprocess
import time
from pathlib import Path

import app_config

# ONE OCR binary for every runner, at a durable path (app_config.OCR_BIN), built
# from tools/ScreenOCR/main.swift on first use. See ensure_tool().
OCR = str(app_config.OCR_BIN)

# A frame carrying fewer than this many OCR lines is unreadable — a locked or
# sleeping device yields zero, a real app screen yields many. Line count is
# resolution independent, which a byte-size threshold is not.
MIN_LINES_READABLE = app_config.MIN_OCR_LINES

# Text at the very frame edge is text the layout could not fit. Thresholds are
# CALIBRATED per platform against a real capture, never copied: a 0.010 threshold
# ported from another app called three of this app's correctly-rendered headings
# clipped on every frame, because this app's own gutter sat at x=0.0099-0.0116 on
# the iPad.
CLIP_X_DEFAULT = app_config.CLIP_X

FORBID_DEFAULT = app_config.FORBIDDEN

# A capture older than this is not the capture you just asked for.
FRESH_SECONDS = 60


def sh(cmd, timeout=90, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, **kw)


def qa_dir(platform, name):
    """build/qa/<platform>-<date>/<name>-<epoch>/ — durable, never /tmp, because
    background tasks get reaped and a capture you cannot return to is a capture
    you have to take twice. Anchored at the repo, not the cwd."""
    d = (app_config.QA_ROOT / f"{platform}-{time.strftime('%Y-%m-%d')}"
         / f"{name}-{int(time.time())}")
    d.mkdir(parents=True, exist_ok=True)
    return d


def ensure_tool(binary, source, extra=()):
    """Build a Swift helper into its durable path if it is missing or older than its
    source. Returns (ok, why). A missing instrument is reported, never guessed around.
    """
    binary, source = Path(binary), Path(source)
    if binary.exists() and (not source.exists()
                            or binary.stat().st_mtime >= source.stat().st_mtime):
        return True, str(binary)
    if not source.exists():
        return False, f"{binary} missing and no source at {source}"
    binary.parent.mkdir(parents=True, exist_ok=True)
    try:
        r = subprocess.run(["swiftc", "-O", str(source), "-o", str(binary), *extra],
                           capture_output=True, text=True, timeout=600)
    except (OSError, subprocess.SubprocessError) as e:
        return False, f"could not build {binary}: {e}"
    if r.returncode != 0 or not binary.exists():
        return False, f"swiftc failed for {source}: {(r.stderr or r.stdout)[-300:]}"
    return True, str(binary)


def ensure_ocr():
    return ensure_tool(app_config.OCR_BIN, app_config.OCR_SRC)


def ensure_winshot():
    return ensure_tool(app_config.WINSHOT_BIN, app_config.WINSHOT_SRC)


def capture_fresh(path, run, max_age=FRESH_SECONDS):
    """Take a capture that CANNOT hand back stale evidence. Returns (ok, why).

    `run(path)` performs the capture (any tool). The target is deleted FIRST, and
    the result is refused unless a new non-empty file exists whose mtime is inside
    `max_age`. Written after a PNG from an earlier attempt was read and reasoned
    about as though it were current: that capture had failed, the old file was still
    on disk, and the only tell was the clock drawn inside the image. An instrument
    that can silently return old evidence is worse than none — it produces confident
    wrong conclusions."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        path.unlink()
    except FileNotFoundError:
        pass
    t0 = time.time()
    try:
        detail = run(path)
    except subprocess.TimeoutExpired:
        return False, "capture timed out"
    except (OSError, subprocess.SubprocessError) as e:
        return False, f"capture failed to run: {e}"
    if not path.exists() or path.stat().st_size == 0:
        why = ""
        if isinstance(detail, subprocess.CompletedProcess):
            why = " — " + " ".join(l for l in (detail.stdout + detail.stderr).splitlines()
                                   if re.search(r"error|invalidated|cancel", l, re.I))[:200]
        return False, f"no file written{why}"
    age = time.time() - path.stat().st_mtime
    if age > max_age or path.stat().st_mtime < t0 - 2:
        return False, f"STALE: {path.name} is {age:.0f}s old; the capture did not write it"
    return True, f"{path.stat().st_size // 1024} KB"


# Set by ocr() when the OCR process itself failed. Callers MUST check it before
# reading a low line count as "the screen was dark".
OCR_FAILED = "__ocr_failed__"


def ocr(shots):
    """OCR a list of (wall, Path). Batched 20 per process to amortize launch.

    A failed OCR process used to be indistinguishable from a dark screen: the
    result dict simply came back empty and every frame graded as "0 OCR lines —
    SCREEN OFF/LOCKED". Measured on a loaded machine, a five-device multiplayer
    run reported all five devices asleep while their screenshots were on disk and
    perfectly readable a minute later. An instrument that blames its subject for
    its own failure is worse than one that stays quiet, so a chunk that yields
    nothing for files that DO exist is recorded as an instrument failure."""
    out = {}
    paths = [str(p) for _, p in shots]
    for chunk in (paths[k:k + 20] for k in range(0, len(paths), 20)):
        ok, why = ensure_ocr()
        if not ok:
            out[OCR_FAILED] = f"OCR unavailable: {why}"
            return out
        try:
            r = sh([OCR] + chunk, timeout=600)
        except (OSError, subprocess.SubprocessError) as e:
            # A traceback here is better than a false "screen off", but a sentence
            # saying how to get it back is better than either.
            out[OCR_FAILED] = (f"cannot run {OCR}: {e} — rebuild with "
                               f"`swiftc -O tools/ScreenOCR/main.swift -o {OCR}`")
            return out
        got = 0
        for line in r.stdout.splitlines():
            try:
                d = json.loads(line)
                out[d["file"]] = d
                got += 1
            except json.JSONDecodeError:
                pass
        present = [c for c in chunk if Path(c).exists()]
        if present and got == 0:
            out[OCR_FAILED] = (f"{OCR} produced nothing for {len(present)} existing "
                               f"file(s), rc={r.returncode}: "
                               f"{(r.stderr or r.stdout).strip()[:160]!r}")
    return out


def frame_text(d):
    return " ".join(t["text"] for t in d.get("allText", []))


def clipped_lines(d, clip_x=CLIP_X_DEFAULT):
    """Lines starting at the frame gutter. Big display type is excluded by
    height: a hero numeral legitimately spans the frame, chrome type never
    starts at the edge."""
    return [t for t in d.get("allText", [])
            if t.get("x", 1.0) <= clip_x and t.get("h", 1.0) <= 0.030]


def edge_clips(d, clip_x=CLIP_X_DEFAULT, right_margin=0.010, max_h=0.030):
    """(defects, peeks) for one OCR frame, using the box WIDTH ScreenOCR reports.

    A LEFT-edge cut is always a defect: no padded layout starts a line at x=0. A
    RIGHT-edge cut is usually a horizontally scrolling row's intended PEEK, so it is
    reported, not failed. A line ending in an ellipsis is truncation the layout
    chose — reported as a peek too. Big type (poster lettering, a hero numeral) is
    excluded by height, because artwork legitimately runs to the edge."""
    defects, peeks = [], []
    for t in d.get("allText", []):
        text = (t.get("text") or "").strip()
        if not text or t.get("h", 1.0) > max_h:
            continue
        x, w = t.get("x", 1.0), t.get("w")
        if x <= clip_x:
            defects.append(text)
        elif w is not None and x + w >= 1.0 - right_margin:
            peeks.append(text)
        elif text.endswith(("\u2026", "...")):
            peeks.append(text)
    return defects, peeks


def measure(d, width_pt, max_chars=80, prose_min=25, prose_max_h=0.020):
    """The longest line of PROSE on a frame: (chars, points, text) or None.

    Character count, not width, is what a reader's eye has to track — past ~80 a
    line stops being readable — but the width is returned too, since that is the
    number a `frame(maxWidth:)` is written in. `width_pt` is the frame's width in
    points (the device's logical width)."""
    prose = [t for t in d.get("allText", [])
             if len((t.get("text") or "").strip()) > prose_min
             and t.get("h", 1.0) < prose_max_h]
    if not prose:
        return None
    worst = max(prose, key=lambda t: len(t["text"]))
    return (len(worst["text"].strip()), round((worst.get("w") or 0) * width_pt),
            worst["text"].strip())


def frame_darkness(path):
    """Mean luma 0-255 and the fraction of near-black pixels.

    "Screen off/locked" was being asserted from an EMPTY OCR result, which is a
    guess dressed as a finding — the owner rightly challenged it for a phone that
    was working fine. The frame itself settles it: that capture was 99.97% pure
    black with content only in the battery corner of the status bar, and
    devicectl reported no error and saved a valid PNG. Report the measurement,
    and let a reader draw the conclusion."""
    try:
        from PIL import Image
        g = Image.open(path).convert("L")
        px = list(g.getdata())
    except Exception:                            # noqa: BLE001
        return None
    if not px:
        return None
    dark = sum(1 for v in px if v <= 10) / len(px)
    return round(sum(px) / len(px), 1), round(dark * 100, 2)


class Grader:
    """Collects assertions, prints them as they are decided, and writes a
    machine-comparable report.json. Harnesses that print and exit with no JSON
    cannot be compared across runs and have no regression baseline at all — this
    exists so ours can be."""

    def __init__(self, outdir, **meta):
        self.outdir = Path(outdir)
        self.report = dict(meta)
        self.report["assertions"] = {}
        self.failures = []

    def grade(self, key, ok, evidence):
        self.report["assertions"][key] = {"pass": bool(ok), "evidence": evidence}
        print(f"  [{'PASS' if ok else 'FAIL'}] {key}: {evidence}")
        if not ok:
            self.failures.append(key)
        return bool(ok)

    def grade_glass(self, shots, texts, spec, anchor_rx, clip_x=CLIP_X_DEFAULT):
        """The standard glass battery, in the order that keeps it honest.

        The blind check comes FIRST and gates everything downstream: a null
        result from a blind instrument is indistinguishable from a real absence,
        so an unreadable run must be skipped, never passed."""
        # The instrument speaks first. "The screen was dark" is a claim about the
        # DEVICE, and it must not be made when the OCR process is what failed.
        if OCR_FAILED in texts:
            self.grade("ocr_available", False, texts[OCR_FAILED])
            return False
        counts = [len(texts.get(p.name, {}).get("allText", [])) for _, p in shots]
        best = max(counts, default=0)
        readable = best >= MIN_LINES_READABLE
        self.grade("screen_awake", readable, f"best frame had {best} OCR lines"
                   + ("" if readable else " — SCREEN OFF/LOCKED, nothing was graded"))
        if not readable:
            return False

        all_text = " | ".join(frame_text(texts.get(p.name, {})) for _, p in shots)

        # A READABLE frame of the WRONG app survives every other check and then
        # answers questions about a screen we are not testing.
        owns = bool(re.search(anchor_rx, all_text, re.I))
        self.grade("app_owns_glass", owns, "app chrome on the glass" if owns
                   else "readable frames, but no app chrome — wrong app/screen")

        if "expect_any" in spec:
            m = re.search(spec["expect_any"], all_text, re.I)
            self.grade("expect_any", bool(m), f"/{spec['expect_any']}/ "
                       + (f"matched {m.group(0)!r}" if m else "matched nothing"))
        if "expect_end" in spec and shots:
            # The FINAL state, not any frame: a door that must end on its own is
            # proved by where the run finished, not by where it passed through.
            last = frame_text(texts.get(shots[-1][1].name, {}))
            m = re.search(spec["expect_end"], last, re.I)
            self.grade("expect_end", bool(m), f"/{spec['expect_end']}/ in the last frame"
                       + (f" matched {m.group(0)!r}" if m else " — NOT found"))

        bad = re.search(spec.get("forbid", FORBID_DEFAULT), all_text, re.I)
        self.grade("no_error_text", not bad,
                   "clean" if not bad else f"found {bad.group(0)!r}")

        clipped = {p.name: [t["text"] for t in clipped_lines(texts.get(p.name, {}), clip_x)]
                   for _, p in shots}
        clipped = {k: v for k, v in clipped.items() if v}
        self.grade("no_clipped_text", not clipped, "no edge clipping"
                   if not clipped else f"clipped: {clipped}")
        return True

    def finish(self):
        ok = not self.failures
        self.report["result"] = "OK" if ok else "FAIL"
        (self.outdir / "report.json").write_text(json.dumps(self.report, indent=2))
        print(f"\nRESULT: {'OK' if ok else 'FAIL — ' + ', '.join(self.failures)}")
        print(f"report: {self.outdir}/report.json")
        return 0 if ok else 1
