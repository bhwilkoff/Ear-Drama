#!/usr/bin/env python3
"""Android TV / Google TV / Fire TV on-device harness — navigate by the FOCUS TREE.

Evidence channels, all external to the app: screenshots + OCR, the uiautomator
focus tree, and logcat. The app's own report is never the evidence.

Lessons this file encodes (each cost a failed run):

- CONNECT FIRST, every command: the TLS wireless-debugging port ROTATES after
  sleep; classic port 5555 is stable but the connection itself drops between
  commands. connect() tries the cached serial, 5555, then re-resolves the TLS
  port via `adb mdns services` (by the bench entry's `mdns_prefix`).
- NAVIGATE BY THE TREE, never by step counts: focus enters a nav rail at the
  VERTICALLY NEAREST item (a tall hero lands you on the third row, not Home), so
  a blind LEFT/DOWN/SELECT script labels its screenshots wrong. Every press is
  followed by a focus-bounds read; goto_tab walks until the focused rail row's
  LABEL is the target.
- ACTIVATE WITH KEYCODE_ENTER, NOT KEYCODE_DPAD_CENTER. Focus was demonstrably on
  a card (uiautomator focused="true", with its bounds) and DPAD_CENTER did nothing
  — a Compose `tvFocusable`/clickable responds to ENTER. That reads exactly like a
  dead control, and it is the harness's fault, not the app's.
- `input tap` is INERT on the TV profile — motion events are not part of the
  focus grammar. The D-pad is the only input channel.
- BACK from a TAB ROOT exits the app. Press Back only after a PUSHED route
  (PUSHED_ROUTES below); one stray Back once sent a whole walk into the launcher.
- A MERGED Compose node hides its children: a focusable container carries ONE
  node whose `content-desc` is the joined label and whose bounds are the
  container's. Read content-desc as well as text, or whole surfaces go
  unmeasured — and treat a low node count as a warning, not a clean result.
  Compose overlays (dialogs drawn in their own window) can be absent from the
  dump entirely; OCR the screenshot for those.
- A FOCUSED element is SCALED about its centre, so its reported bounds move
  OUTWARD. Judge overscan against the TEXT bounds inside it, never the container:
  the overscan-safe band at 1080p is ~96..1824 x 54..1026 (5% a side), and a
  scaled edge card legitimately pokes past it while its label does not.
- The video plane is NOT composited into `screencap` on these SoCs: a screenshot
  of a playing film is black. Prove playback by player state (logcat, dumpsys
  media_session / audio), never by pixels.
- Fire OS accepts a `monkey` launch but never foregrounds the app: use
  `am start -n`.
- Dumps DELETE the target first: a failed dump otherwise serves a STALE file from
  an earlier session, which reads as our app showing another app's UI.

Usage:
  python3 tools/gtv_scenario.py rail_walk          # capture + OCR-assert all tabs
  python3 tools/gtv_scenario.py shot NAME          # one screenshot into the QA dir
  python3 tools/gtv_scenario.py focus              # print the focused node
  python3 tools/gtv_scenario.py keys DPAD_DOWN ENTER
  python3 tools/gtv_scenario.py go "Settings"      # closed-loop focus walk
  python3 tools/gtv_scenario.py --device firetv tab search
"""
import argparse
import datetime
import json
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_config  # noqa: E402
import bench  # noqa: E402
import devlease  # noqa: E402
from devharness import capture_fresh, ensure_ocr  # noqa: E402

ADB = str(app_config.ADB)
PKG = app_config.ANDROID_PACKAGE_DEBUG
ACTIVITY = app_config.ANDROID_MAIN_ACTIVITY
QA_DIR = app_config.QA_ROOT / f"gtv-{datetime.date.today().isoformat()}"
OCR = str(app_config.OCR_BIN)

# ── FILL IN: your TV shell ─────────────────────────────────────────────────────
# Rail rows in top-to-bottom order, by the LABEL each row draws. The rail scrolls
# once it outgrows the panel, so fixed y-positions are meaningless — rows are
# identified by the label text that sits inside the focused bounds.
RAIL_ORDER = ["home", "search", "library", "settings"]
RAIL_LABELS = {k: k.capitalize() for k in RAIL_ORDER}   # key -> on-screen label
RAIL_X_MAX = 440     # a focused node left of this x (1080p px) is in the rail
# Tabs that PUSH a route (Back returns to the rail) rather than being tab roots
# (Back EXITS the app). Only these get a Back after a walk step.
PUSHED_ROUTES = {"settings"}
# Text that must be on the glass for each tab — OCR-asserted, not assumed.
TAB_EXPECT = {"search": ["Search"], "library": ["Library"], "settings": ["Settings"]}
HOME_EXPECT = ["Home"]
LOADING_TEXT = "Loading"
FOCUS_LOG_EXTRA = ["--ez", "appname_focus_log", "true"]
# Overscan-safe band at 1920x1080 (5% a side).
SAFE_BAND = (96, 54, 1824, 1026)
ACTIVATE = "KEYCODE_ENTER"   # NOT DPAD_CENTER — see the header

_serial = None
_entry = {}


def sh(*args, timeout=30, binary=False):
    r = subprocess.run(list(args), capture_output=True, timeout=timeout)
    return r.stdout if binary else r.stdout.decode(errors="replace")


def connect():
    """Return an adb serial, reconnecting however the device is reachable."""
    global _serial
    host = _entry.get("address") or (_entry.get("serial") or "").split(":")[0]
    prefix = _entry.get("mdns_prefix", "")
    tries = []
    if _serial:
        tries.append(("cached", _serial))
    if _entry.get("serial"):
        tries.append(("serial", _entry["serial"]))
    if host:
        tries.append(("5555", f"{host}:5555"))
    tries.append(("mdns", None))
    for kind, serial in tries:
        if kind == "mdns":
            if not (host and prefix):
                continue
            out = sh(ADB, "mdns", "services")
            m = re.search(rf"{re.escape(prefix)}\S*\s+_adb-tls-connect\._tcp\.?\s+"
                          rf"{re.escape(host)}:(\d+)", out)
            if not m:
                continue
            serial = f"{host}:{m.group(1)}"
        if ":" in serial and kind != "cached":
            sh(ADB, "connect", serial)
        if "ok" in sh(ADB, "-s", serial, "shell", "echo", "ok"):
            _serial = serial
            return serial
    raise SystemExit(f"cannot reach {_entry.get('name', host)} over adb "
                     "(is it awake? has adb trust been revoked — "
                     "adb_allowed_connection_time?)")


def adbs(*args, timeout=30, binary=False):
    return sh(ADB, "-s", connect(), *args, timeout=timeout, binary=binary)


def press(key, settle=1.2):
    key = key if key.startswith("KEYCODE_") else "KEYCODE_" + key
    adbs("shell", "input", "keyevent", key)
    time.sleep(settle)


# ── the tree ──────────────────────────────────────────────────────────────────

_NODE = re.compile(r"<node[^>]*>")
_BOUNDS = re.compile(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')


def _attr(n, name):
    m = re.search(rf' {name}="([^"]*)"', n)
    return m.group(1) if m else ""


def _tree():
    # Delete-first: a failed dump otherwise serves a STALE file from some
    # earlier app's session.
    adbs("shell", "rm", "-f", "/sdcard/ui.xml")
    out = adbs("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    if "dumped" not in out.lower():
        return ""
    return adbs("shell", "cat", "/sdcard/ui.xml")


def tree(retry=True):
    """The live tree; retried once because it is briefly empty during transitions."""
    xml = _tree()
    if not xml and retry:
        time.sleep(1.0)
        xml = _tree()
    return xml


def nodes(xml):
    """Every node as dict(label, text, desc, cls, bounds, focusable, focused).
    `label` is text OR content-desc: a merged Compose node carries its label ONLY
    in content-desc."""
    out = []
    for m in _NODE.finditer(xml or ""):
        n = m.group(0)
        b = _BOUNDS.search(n)
        t, d = _attr(n, "text"), _attr(n, "content-desc")
        out.append({"label": t or d, "text": t, "desc": d, "cls": _attr(n, "class"),
                    "bounds": tuple(int(x) for x in b.groups()) if b else None,
                    "focusable": 'focusable="true"' in n,
                    "focused": 'focused="true"' in n})
    return out


def focused_node(xml=None):
    """The focused node dict, or None."""
    for _ in range(1 if xml is not None else 2):
        for n in nodes(xml if xml is not None else tree()):
            if n["focused"] and n["bounds"]:
                return n
        if xml is None:
            time.sleep(1.0)
    return None


def focused_bounds(xml=None):
    n = focused_node(xml)
    return n["bounds"] if n else None


def _centre(b):
    return (b[0] + b[2]) // 2, (b[1] + b[3]) // 2


def texts_inside(bounds, xml=None):
    """Labels drawn INSIDE `bounds` — a Compose chip/tile is often an unlabeled
    View whose label is a sibling text node, so the focused element is identified
    by whatever text (or content-desc) sits within its box."""
    xml = xml if xml is not None else tree()
    l, t, r, b = bounds
    found = []
    for n in nodes(xml):
        if not n["label"] or not n["bounds"]:
            continue
        cx, cy = _centre(n["bounds"])
        if l <= cx <= r and t <= cy <= b:
            found.append(n["label"])
    return found


def rail_tab_at(bounds, xml=None):
    """The rail row under `bounds`, identified by the label inside it."""
    if not bounds or bounds[0] > RAIL_X_MAX:
        return None
    xml = xml if xml is not None else tree()
    by_label = {v.lower(): k for k, v in RAIL_LABELS.items()}
    for n in nodes(xml):
        key = by_label.get((n["label"] or "").lower())
        if key and n["bounds"]:
            _, cy = _centre(n["bounds"])
            if bounds[1] <= cy <= bounds[3]:
                return key
    return None


def find_text(label, xml=None):
    """Bounds of the first on-screen node whose text/content-desc matches `label`
    (exact, then case-insensitive substring)."""
    xml = xml if xml is not None else tree()
    ns = [(n["label"], n["bounds"]) for n in nodes(xml) if n["label"] and n["bounds"]]
    for t, b in ns:
        if t == label:
            return b
    for t, b in ns:
        if label.lower() in t.lower():
            return b
    return None


def text_bounds_outside_band(bounds, xml=None):
    """Labels inside a focused element whose OWN box leaves the overscan band.
    Judges the text, never the (scaled-outward) container."""
    xml = xml if xml is not None else tree()
    l, t, r, b = bounds
    L, T, R, B = SAFE_BAND
    bad = []
    for n in nodes(xml):
        if not n["label"] or not n["bounds"]:
            continue
        cx, cy = _centre(n["bounds"])
        if l <= cx <= r and t <= cy <= b:
            x0, y0, x1, y1 = n["bounds"]
            if x0 < L or y0 < T or x1 > R or y1 > B:
                bad.append((n["label"], n["bounds"]))
    return bad


# ── navigation ────────────────────────────────────────────────────────────────

def goto_tab(target, max_steps=14):
    """Walk focus onto the rail, then to the target row, then activate it.

    The rail is HIDDEN while a route is pushed, so if LEFT never finds it, press
    BACK to pop to a tab root and retry — one accidental activate otherwise
    strands the whole walk."""
    target = target.lower()
    if target not in RAIL_ORDER:
        print(f"  goto_tab: {target!r} not in RAIL_ORDER {RAIL_ORDER}")
        return False
    for _ in range(3):
        found = False
        for _ in range(6):
            if rail_tab_at(focused_bounds()):
                found = True
                break
            press("KEYCODE_DPAD_LEFT")
        if found:
            break
        press("KEYCODE_BACK", settle=2.0)
    for _ in range(max_steps):
        cur = rail_tab_at(focused_bounds())
        if cur is None:
            press("KEYCODE_DPAD_LEFT")
            continue
        if cur == target:
            press(ACTIVATE, settle=4.0)
            return True
        press("KEYCODE_DPAD_DOWN" if RAIL_ORDER.index(cur) < RAIL_ORDER.index(target)
              else "KEYCODE_DPAD_UP")
    return False


def go(label, max_steps=40):
    """Move focus onto the element labelled `label`, CLOSED-LOOP: after every
    press the focused bounds are re-read; done when the label's centre is inside
    them. A focused node that wandered onto the rail steps back Right first."""
    target = find_text(label)
    if not target:
        # A LazyRow composes only what is on screen: scan the row until drawn.
        for key, n in (("KEYCODE_DPAD_RIGHT", 14), ("KEYCODE_DPAD_LEFT", 28)):
            for _ in range(n):
                press(key, settle=0.6)
                target = find_text(label)
                if target:
                    break
            if target:
                break
    if not target:
        print(f"  go: no on-screen text matching {label!r}")
        return False
    for _ in range(max_steps):
        tx, ty = _centre(target)
        b = focused_bounds()
        if not b:
            return False
        if b[0] <= tx <= b[2] and b[1] <= ty <= b[3]:
            return True
        cx, cy = _centre(b)
        if cx < RAIL_X_MAX <= tx:
            press("KEYCODE_DPAD_RIGHT", settle=0.7)
        else:
            dy, dx = ty - cy, tx - cx
            if abs(dy) > (b[3] - b[1]) / 2:
                press("KEYCODE_DPAD_DOWN" if dy > 0 else "KEYCODE_DPAD_UP", settle=0.7)
            elif abs(dx) > 4:
                press("KEYCODE_DPAD_RIGHT" if dx > 0 else "KEYCODE_DPAD_LEFT", settle=0.7)
            else:
                return True
        target = find_text(label) or target    # the layout may have scrolled
    print(f"  go: could not reach {label!r}")
    return False


def _keycap_map(xml=None):
    xml = xml if xml is not None else tree()
    keys = {}
    for n in nodes(xml):
        if n["bounds"] and re.fullmatch(r"[A-Z0-9]|SPACE|DEL", n["label"] or ""):
            keys[n["label"]] = n["bounds"]
    return keys


def type_text(text):
    """Type on an on-screen keycap keyboard, CLOSED-LOOP: after every press the
    focused bounds are re-read and compared to the target key — blind keycap
    arithmetic failed every time it was tried. Neither `Lit_`-style injection nor
    `input text` reaches a designed Compose key grid. Focus must already be on the
    keyboard."""
    keys = _keycap_map()
    for ch in text.upper():
        label = "SPACE" if ch == " " else ch
        if label not in keys:
            print(f"  type_text: no keycap for {label!r}; have {sorted(keys)[:8]}…")
            return False
        tl, tt, tr, tb = keys[label]
        tx, ty = (tl + tr) // 2, (tt + tb) // 2
        for _ in range(30):
            b = focused_bounds()
            if not b:
                return False
            cx, cy = _centre(b)
            if tl <= cx <= tr and tt <= cy <= tb:
                press(ACTIVATE, settle=0.8)
                break
            if cx < RAIL_X_MAX:
                # Fell out of the keyboard onto the rail (column-0 LEFT exits).
                press("KEYCODE_DPAD_RIGHT", settle=0.6)
                continue
            dy, dx = ty - cy, tx - cx
            # Move along the axis with the larger error; never press LEFT while
            # already in the target column band (column 0 would exit).
            if abs(dy) > (tb - tt) / 2 and abs(dy) >= abs(dx) / 3:
                press("KEYCODE_DPAD_DOWN" if dy > 0 else "KEYCODE_DPAD_UP", settle=0.6)
            elif abs(dx) > (tr - tl) / 2:
                press("KEYCODE_DPAD_RIGHT" if dx > 0 else "KEYCODE_DPAD_LEFT", settle=0.6)
            else:
                press("KEYCODE_DPAD_DOWN" if dy > 0 else "KEYCODE_DPAD_UP", settle=0.6)
        else:
            print(f"  type_text: could not reach {label!r}")
            return False
    return True


# ── capture / OCR / launch ────────────────────────────────────────────────────

def screenshot(name):
    path = QA_DIR / f"{name}.png"

    def grab(p):
        data = adbs("exec-out", "screencap", "-p", timeout=60, binary=True)
        if data:
            Path(p).write_bytes(data)

    ok, why = capture_fresh(path, grab)
    if not ok:
        print(f"  screenshot {name} refused — {why}")
        return None
    return str(path)


def ocr_text(path):
    """Flat text of everything OCR found in the shot, top-to-bottom. Returns None
    (not "") when the instrument could not read — a blind OCR is not an empty
    screen."""
    if not path:
        return None
    ok, why = ensure_ocr()
    if not ok:
        print(f"  OCR unavailable: {why}")
        return None
    lines = []
    for ln in sh(OCR, path, timeout=60).splitlines():
        try:
            j = json.loads(ln)
        except ValueError:
            continue
        for line in sorted(j.get("allText", []), key=lambda l: -l["y"]):
            lines.append(line["text"])
    return "\n".join(lines)


def extras_args(audible=False):
    args = []
    for k, (kind, v) in app_config.ANDROID_DOOR_EXTRAS.items():
        if audible and "mute" in k:
            continue
        args += [f"--{kind}", k, v]
    return args


def launch(deep_link=None, force_stop=False, extra=(), audible=False):
    # The device idles into the system screensaver; a launch fired into that
    # state goes nowhere (a deep link once left the backdrop picker on screen).
    # Wake + dismiss first. A SECURE keyguard is not opened by this — the owner
    # unlocks once and `svc power stayon true` keeps it from re-engaging.
    adbs("shell", "input", "keyevent", "KEYCODE_WAKEUP")
    time.sleep(1.5)
    adbs("shell", "wm", "dismiss-keyguard")
    time.sleep(1.0)
    adbs("shell", "input", "keyevent", "KEYCODE_BACK")
    time.sleep(1.5)
    if force_stop:
        adbs("shell", "am", "force-stop", PKG)
        time.sleep(2)
    if deep_link:
        adbs("shell", "am", "start", "-a", "android.intent.action.VIEW",
             "-d", deep_link, PKG)
    else:
        adbs("shell", "am", "start", "-n", f"{PKG}/{ACTIVITY}",
             *extras_args(audible), *extra)


def logcat_app(lines=200):
    pid = adbs("shell", "pidof", PKG).strip()
    if not pid:
        return ""
    return adbs("shell", "logcat", "-d", f"--pid={pid}", "-t", str(lines))


def print_focus():
    n = focused_node()
    if not n:
        print("focused: NONE")
        return
    inside = texts_inside(n["bounds"])
    print(f"focused: {n['bounds']} text={n['text']!r} desc={n['desc']!r} "
          f"inside={inside[:4]} rail={rail_tab_at(n['bounds'])}")
    bad = text_bounds_outside_band(n["bounds"])
    if bad:
        print(f"  OVERSCAN: text outside the safe band {SAFE_BAND}: {bad[:3]}")


def rail_walk(wait_loading=12):
    launch(force_stop=True)
    time.sleep(15)
    for _ in range(wait_loading):
        text = ocr_text(screenshot("walk-00-home"))
        if text is None or LOADING_TEXT not in text:
            break
        time.sleep(10)
    results = []
    text = ocr_text(screenshot("walk-00-home"))
    results.append(("home", None if text is None else any(e in text for e in HOME_EXPECT)))
    for tab, expects in TAB_EXPECT.items():
        reached = goto_tab(tab)
        text = ocr_text(screenshot(f"walk-{tab}"))
        ok = None if text is None else (
            reached and all(e.lower() in text.lower() for e in expects))
        results.append((tab, ok))
        mark = {True: "PASS", False: "FAIL", None: "BLIND"}[ok]
        print(f"  [{mark}] {tab}: reached={reached} expect={expects}", flush=True)
        if tab in PUSHED_ROUTES:
            press("KEYCODE_BACK", settle=2.0)
    passed = sum(1 for _, ok in results if ok)
    blind = sum(1 for _, ok in results if ok is None)
    print(f"RESULT: {passed}/{len(results)} tabs verified, {blind} unreadable "
          f"— shots in {QA_DIR}")
    return 0 if passed == len(results) else 1


# ── CLI ───────────────────────────────────────────────────────────────────────

VERBS = ("rail_walk", "shot", "focus", "press", "keys", "longpress", "tree", "launch",
         "link", "type", "log", "tab", "go", "select", "ocr")


def dispatch(cmd, a, audible=False):
    if cmd in ("go", "select"):
        ok = go(a[0], int(a[1]) if len(a) > 1 else 40)
        if ok and cmd == "select":
            press(ACTIVATE, settle=3.0)
        print(("reached " if ok else "MISSED ") + a[0])
        print_focus()
        return 0 if ok else 1
    if cmd == "rail_walk":
        return rail_walk()
    if cmd == "shot":
        p = screenshot(a[0] if a else "shot")
        print(p)
        t = ocr_text(p)
        print(t if t is not None else "(OCR could not read the frame)")
        return 0 if p else 1
    if cmd == "focus":
        print_focus()
        return 0
    if cmd == "press":
        n = int(a[1]) if len(a) > 1 else 1
        settle = float(a[2]) if len(a) > 2 else 1.0
        for _ in range(n):
            press(a[0], settle=settle)
        print_focus()
        return 0
    if cmd == "keys":
        for k in a:
            press(k, settle=1.0)
        print_focus()
        return 0
    if cmd == "longpress":
        key = a[0] if a else "ENTER"
        key = key if key.startswith("KEYCODE_") else "KEYCODE_" + key
        adbs("shell", "input", "keyevent", "--longpress", key)
        time.sleep(1.5)
        print_focus()
        return 0
    if cmd == "tree":
        for n in nodes(tree()):
            if n["focusable"] or "--all" in a:
                print(("* " if n["focused"] else "  ") + f"{n['label']!r} {n['bounds']}")
        return 0
    if cmd == "launch":
        adbs("shell", "logcat", "-c")
        launch(force_stop=True, extra=FOCUS_LOG_EXTRA + list(a), audible=audible)
        time.sleep(12)
        print_focus()
        return 0
    if cmd == "link":
        launch(deep_link=a[0])
        time.sleep(8)
        print_focus()
        return 0
    if cmd == "type":
        ok = type_text(a[0])
        print("typed" if ok else "TYPE FAILED")
        print_focus()
        return 0 if ok else 1
    if cmd == "log":
        out = logcat_app(int(a[1]) if len(a) > 1 else 400)
        if a:
            out = "\n".join(l for l in out.splitlines() if re.search(a[0], l))
        print(out)
        return 0
    if cmd == "tab":
        ok = goto_tab(a[0])
        print("reached" if ok else "NOT REACHED")
        print_focus()
        return 0 if ok else 1
    if cmd == "ocr":
        t = ocr_text(a[0])
        print(t if t is not None else "(OCR could not read the frame)")
        return 0 if t is not None else 1
    return 2


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--device", default="androidtv", help="bench name or raw serial")
    ap.add_argument("--owner-ok", action="store_true",
                    help="allow an owner-watches device (ask the owner first)")
    ap.add_argument("--audible", action="store_true",
                    help="launch without the mute door extra (ask the owner first)")
    ap.add_argument("verb", nargs="?", default="rail_walk", choices=VERBS)
    ap.add_argument("args", nargs="*")
    a = ap.parse_args()

    e = bench.require(a.device, allow_owner=a.owner_ok,
                      platforms=("android", "androidtv", "firetv"))
    _entry.update(e)
    if a.audible:
        print("AUDIBLE: the app will make sound on a real device. Ask the owner first.")
    if a.verb == "ocr":                  # pure file work — no device, no lease
        return dispatch(a.verb, a.args)
    try:
        with devlease.hold([bench.lease_name(e)], task=f"gtv_scenario {a.verb}"):
            return dispatch(a.verb, a.args, audible=a.audible)
    except RuntimeError as ex:
        print(f"SKIP — {ex}. Nothing was run on {a.device}.")
        return 2


if __name__ == "__main__":
    sys.exit(main())
