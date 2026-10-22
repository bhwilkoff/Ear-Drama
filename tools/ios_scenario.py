#!/usr/bin/env python3
"""iPhone/iPad surface sweeps driven by LAUNCH DOORS — the design-loop companion to
tools/ios_run.py (which grades scenarios). This one photographs surfaces and judges
LAYOUT: clipped text and prose measure, across Dynamic Type sizes.

An iPhone gives two oracles tvOS does not (devicectl launches with env vars AND
deep links), but the JUDGEMENT stays external: a surface is right when the
SCREENSHOT says so, never when the app reports it drew.

    python3 tools/ios_scenario.py doors                  # the door catalog
    python3 tools/ios_scenario.py shot home              # one door, one frame
    python3 tools/ios_scenario.py link item/<id>         # a deep link
    python3 tools/ios_scenario.py sweep                  # every surface
    python3 tools/ios_scenario.py sweep --type-size accessibility3
    python3 tools/ios_scenario.py pip <item-id>          # PiP without a tap
    python3 tools/ios_scenario.py judge build/qa/ios-…   # who clips, and where
    python3 tools/ios_scenario.py measure build/qa/ios-… --width-pt 1366

Device: --device <bench name> (default "iphone"). Every run holds one lease, every
launch is muted and time-bounded, and the app is terminated (verified) at the end.
"""
import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_config as C  # noqa: E402
import apple_device as ad  # noqa: E402
import bench  # noqa: E402
import devlease  # noqa: E402
from devharness import edge_clips, measure, ocr, qa_dir  # noqa: E402

BUNDLE = C.APPLE_BUNDLE_ID
SCHEME = "appname"          # FILL IN: your custom URL scheme (DEEP_LINKS.md)

# ── The launch-door catalog ──────────────────────────────────────────────────
# DEBUG-only env hooks that open a surface without a tap on the device. Keep this
# table in step with the app's DebugHooks and with tools/hook_coverage.py: a door
# the app does not honour lands every sweep on Home, and Home passes every check
# that is not looking for the right screen. FILL IN the app-specific rows.
DOORS = {
    C.HOOK_START_TAB:     "<tab>          lands on a tab",
    C.HOOK_START_ITEM:    "<id>           opens that item's detail",
    C.HOOK_AUTOPLAY:      "1              with START_ITEM, starts playback",
    C.HOOK_MUTE:          "1              the player is silent (DEFAULT on every launch)",
    C.HOOK_DOOR_SECONDS:  f"<n>            the door's activity ends after n s (default {C.DOOR_SECONDS})",
    C.HOOK_TYPE_SIZE:     "xxxLarge|accessibility2|accessibility3  the whole app at that Dynamic Type size",
    C.HOOK_FORCE_OFFLINE: "1              render the offline STATE (fakes the state, never the network)",
    C.HOOK_SKIP_ONBOARD:  "1              skip the walkthrough",
    C.HOOK_QA_LABEL:      "<text>         a small banner saying what this device is testing",
}

# name -> (env, deep-link path or None). FILL IN with your app's surfaces.
SURFACES = [
    ("home",     {C.HOOK_START_TAB: "home"}, None),
    ("search",   {C.HOOK_START_TAB: "search"}, None),
    ("settings", {C.HOOK_START_TAB: "settings"}, None),
]

TYPE_SIZES = ("xxxLarge", "accessibility2", "accessibility3")


class Session:
    """One device, one lease, doors applied, teardown guaranteed."""

    def __init__(self, entry, outdir, audible=False, type_size=None):
        self.entry, self.udid, self.outdir = entry, entry["udid"], outdir
        self.base = {C.HOOK_SKIP_ONBOARD: "1", **C.DOOR_DEFAULTS}
        if audible:
            self.base.pop(C.HOOK_MUTE, None)
            print("[ios] AUDIBLE run — the owner should have been asked first")
        if type_size:
            self.base[C.HOOK_TYPE_SIZE] = type_size

    def launch(self, env=None, url=None, wait=9.0, terminate_existing=True):
        full = dict(self.base)
        full.update(env or {})
        ok, out = ad.launch(self.udid, BUNDLE, full, url=url,
                            terminate_existing=terminate_existing)
        if not ok:
            print(f"  !! launch failed: {out[-200:]}")
        time.sleep(wait)
        return ok

    def shot(self, name):
        p = self.outdir / f"{name}.png"
        ok, why = ad.capture(self.udid, p, timeout=120)
        if not ok:
            print(f"  !! screenshot {name}: {why}")
            return None
        return p


def texts_of(paths):
    got = ocr([(0, p) for p in paths if p])
    return got


def report_frame(p, d):
    lines = [t["text"] for t in d.get("allText", [])]
    defects, peeks = edge_clips(d)
    print(f"   {len(lines)} lines: {' | '.join(lines[:6])}")
    if defects:
        print(f"   CLIP (left edge): {' | '.join(x[:30] for x in defects[:4])}")
    if peeks:
        print(f"   peek/ellipsis:    {' | '.join(x[:24] for x in peeks[:3])}")
    return defects


def cmd_sweep(sess, items):
    shots = []
    for name, env, path in SURFACES:
        print(f"== {name}")
        sess.launch(env=env, url=f"{SCHEME}://{path}" if path else None)
        shots.append(sess.shot(name))
    for i, iid in enumerate(items or []):
        name = f"detail-{i}-{iid[:24]}"
        print(f"== {name}")
        sess.launch(env={C.HOOK_START_ITEM: iid})
        shots.append(sess.shot(name))
    texts = texts_of(shots)
    bad = 0
    for p in shots:
        if p is None:
            bad += 1
            continue
        print(f"-- {p.name}")
        bad += bool(report_frame(p, texts.get(p.name, {})))
    print(f"\n{len(shots) - bad}/{len(shots)} surfaces captured without left-edge clipping")
    return 1 if bad else 0


def cmd_pip(sess, item):
    """Picture-in-picture WITHOUT a tap: play muted, open another app so PiP starts
    automatically, then re-launch ours WITHOUT --terminate-existing. Motion is
    judged by DIFFERENCING two frames of the PiP window. Restore needs a tap and
    is not automated — say so rather than pretend."""
    sess.launch(env={C.HOOK_START_ITEM: item, C.HOOK_AUTOPLAY: "1"}, wait=12)
    ok, out = ad.launch(sess.udid, "com.apple.Preferences", terminate_existing=False)
    time.sleep(4)
    a, b = sess.shot("pip-a"), None
    time.sleep(3)
    b = sess.shot("pip-b")
    if not (a and b):
        print("PiP: capture failed — NOT MEASURED")
        return 1
    try:
        from PIL import Image, ImageChops
        diff = ImageChops.difference(Image.open(a).convert("L"), Image.open(b).convert("L"))
        moved = sum(1 for v in diff.getdata() if v > 24) / (diff.width * diff.height)
    except Exception as e:                      # noqa: BLE001
        print(f"PiP: could not difference the frames ({e}) — NOT MEASURED")
        return 1
    print(f"PiP: {moved * 100:.2f}% of pixels changed between frames "
          f"({'motion' if moved > 0.002 else 'NO motion — frozen or not playing'})")
    print("restore-from-PiP needs a tap and is not automated")
    return 0 if moved > 0.002 else 1


def files_in(args):
    out = []
    for a in args:
        q = Path(a)
        out += sorted(q.glob("*.png")) if q.is_dir() else [q]
    return out


def cmd_judge(paths):
    """Who clips, and where. A LEFT-edge cut is always a defect (no padded layout
    starts a line at x=0); a RIGHT-edge cut is a scrolling row's intended peek."""
    texts = texts_of(paths)
    bad = 0
    for p in paths:
        defects, peeks = edge_clips(texts.get(p.name, {}))
        bad += bool(defects)
        note = " | ".join(h[:30] for h in defects[:3]) or \
            ("peek: " + " | ".join(x[:22] for x in peeks[:2]) if peeks else "")
        print(f"  {'CLIP' if defects else 'ok  '} {p.name:44s} {note}")
    print(f"\n{len(paths) - bad}/{len(paths)} clean; {bad} clipping")
    return 1 if bad else 0


def cmd_measure(paths, width_pt, max_chars):
    """How long is the longest line of prose? Past ~80 characters a line stops being
    readable; the width is printed too, since that is what a maxWidth is written in."""
    texts = texts_of(paths)
    over = 0
    for p in paths:
        m = measure(texts.get(p.name, {}), width_pt, max_chars)
        if not m:
            print(f"  --   {p.name:40s} (no prose)")
            continue
        chars, pts, text = m
        over += chars > max_chars
        print(f"  {'OVER' if chars > max_chars else 'ok  '} {p.name:40s} "
              f"{chars:3d} chars / {pts:5d}pt   {text[:44]}")
    print(f"\n{len(paths) - over} within measure; {over} over {max_chars} chars")
    return 1 if over else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["doors", "shot", "link", "item", "sweep", "pip",
                                    "judge", "measure"])
    ap.add_argument("args", nargs="*")
    ap.add_argument("--device", default="iphone", help="bench name or raw UDID")
    ap.add_argument("--type-size", choices=TYPE_SIZES)
    ap.add_argument("--width-pt", type=float, default=390.0,
                    help="measure: the device's logical width in points")
    ap.add_argument("--max-chars", type=int, default=80)
    ap.add_argument("--owner-ok", action="store_true")
    ap.add_argument("--audible", action="store_true")
    ap.add_argument("--lease-wait", type=int, default=0)
    a = ap.parse_args()

    if a.cmd == "doors":
        for k, v in DOORS.items():
            print(f"  {k:22s} {v}")
        return 0
    if a.cmd == "judge":
        return cmd_judge(files_in(a.args))
    if a.cmd == "measure":
        return cmd_measure(files_in(a.args), a.width_pt, a.max_chars)

    entry = bench.require(a.device, allow_owner=a.owner_ok, platforms=("ios", "ipados"))
    if not entry.get("udid"):
        raise SystemExit(f"{entry['name']} has no udid in the bench manifest")
    outdir = qa_dir("ios", f"{a.cmd}-{a.type_size or 'default'}")
    sess = Session(entry, outdir, audible=a.audible, type_size=a.type_size)
    try:
        with devlease.hold([bench.lease_name(entry)], task=f"ios_scenario {a.cmd}",
                           wait=a.lease_wait):
            try:
                if a.cmd == "sweep":
                    return cmd_sweep(sess, a.args)
                if a.cmd == "pip":
                    if not a.args:
                        ap.error("pip needs an item id")
                    return cmd_pip(sess, a.args[0])
                if a.cmd == "shot":
                    tab = a.args[0] if a.args else "home"
                    sess.launch(env={C.HOOK_START_TAB: tab})
                    p = sess.shot(tab)
                elif a.cmd == "link":
                    sess.launch(url=f"{SCHEME}://{a.args[0]}")
                    p = sess.shot(a.args[0].replace("/", "-"))
                else:
                    sess.launch(env={C.HOOK_START_ITEM: a.args[0]})
                    p = sess.shot("item-" + a.args[0][:20])
                print(p or "NO CAPTURE")
                if p:
                    report_frame(p, texts_of([p]).get(p.name, {}))
                return 0 if p else 1
            finally:
                ok, lines = ad.teardown(entry)
                print("[ios] teardown: " + "; ".join(lines))
    except RuntimeError as e:
        print(f"[ios] SKIP — {e}. Nothing was measured.")
        return 2


if __name__ == "__main__":
    sys.exit(main())
