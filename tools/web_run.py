"""Real-browser harness for the web app — the other platform with no coverage.

Every route is captured at BOTH 375px and 1440px. The project's density rule is
"test at 375px before 1440px", and a desktop-only sweep cannot see the failure
that rule exists to prevent: a layout that is fine wide and clipped narrow. The
clip detector reads the narrow frame, which is where clipping actually happens.

    python3 tools/web_run.py --list
    python3 tools/web_run.py --only home,item
    python3 tools/web_run.py --base https://example.com       # a deployed site

No device lease: the browser is a private headless instance with its own profile,
so nothing here is shared with another session.

The capture waits for the PAGE, not for a clock. It used to be
`--virtual-time-budget=9000 --screenshot`, which shoots when virtual time runs
out whether or not the shard fetch has landed: five loads of the item route on
2026-10-23 gave the episode three times, an empty episode view once, and no view
at all once. Now Chrome is driven over the DevTools protocol (tools/webdrive.py's
stdlib WebSocket, no new dependency): set a real viewport, navigate, poll
document.body.innerText until the route's `ready` regex matches, then capture.
A route that never becomes ready is still shot, and graded red as "timed out
waiting" — a blind instrument says so instead of grading whatever was on screen.
"""
from app_config import *  # app identity + calibrated thresholds

import argparse
import base64
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
from devharness import Grader, ocr, qa_dir  # noqa: E402
from webdrive import WS  # noqa: E402

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
# The local dev server by default: a sweep of production while you believe you are
# testing your edit is a silent wrong answer. Pass --base for a deployed site.
BASE = WEB_URL
# Calibrated against a real capture, not assumed: a full-screen view (a player, a
# quiz question) can carry NO site chrome at all, and anchoring on the wordmark
# alone once called a correctly-rendered full-screen view "the wrong app".
ANCHOR = APP_ANCHOR_RX  # see tools/app_config.py

VIEWPORTS = [("narrow", 375, 812), ("wide", 1440, 900)]

# How long a route may take to show its ready text. Real time, not virtual: a
# local load is ready in well under a second, so this only bounds a broken page.
READY_DEADLINE_S = 20.0

# route -> (path, expect_any, ready). `expect_any` is graded against OCR of the
# frame. `ready` is matched against document.body.innerText before the shot, and
# must be text that exists ONLY once the route has rendered: the tab bar carries
# "Home" and "Search" on every page, so waiting for those would shoot an empty
# view the instant the static shell parsed.
#
# The query params js/app.js reads in init(): ?view=<tab>, ?item=<id>, ?mute=1,
# ?door_seconds=<n> (the twins of APP_START_TAB / _START_ITEM / _MUTE /
# _DOOR_SECONDS): real, shareable URLs, not hash routes.
ROUTES = {
    "home":        ("/", r"Home", r"This day in radio"),
    # The search view's label is visually hidden but in innerText only while the
    # view is shown; the placeholder OCR reads is not in innerText at all.
    "search":      ("/?view=search", r"Search", r"Search titles, series, and people"),
    "item":        (f"/?item={QA_ITEM_ID}&mute=1", QA_ITEM_RX, QA_ITEM_RX),
    # The door navigates to Home after 2 s; Home's own section appears only
    # once it has, so the frame shows where the door ended, not where it began.
    "door-return": (f"/?item={QA_ITEM_ID}&mute=1&door_seconds=2", r"Home",
                    r"This day in radio"),
}
# Routes that are EXPECTED to land on another route's screen, so the distinct-
# screen check below must not call them duplicates.
SAME_SCREEN_AS = {"door-return": "home"}


class CDP(WS):
    """webdrive.WS, keeping the events it would otherwise drop while waiting for
    a reply — Network.loadingFailed is how a reset connection is seen at all."""

    def __init__(self, url, timeout=20):
        super().__init__(url, timeout)
        self.events = []

    def call(self, method, params=None, timeout=20):
        self._id += 1
        mid = self._id
        self.send({"id": mid, "method": method, "params": params or {}})
        deadline = time.time() + timeout
        while time.time() < deadline:
            msg = self.recv()
            if not msg:
                continue
            if msg.get("id") == mid:
                if "error" in msg:
                    raise RuntimeError(f"{method}: {msg['error']}")
                return msg.get("result", {})
            if "method" in msg:
                self.events.append(msg)
        raise TimeoutError(method)


# Startup work a capture never needs, each measured as a stall on a loaded Mac (2026-11-14): the macOS
# Keychain read for a fresh profile's "Safe Storage" key, which serializes against every other Chrome and
# agent session, and the first-run fetches (components, field trials, sync).
QUIET = ["--use-mock-keychain", "--password-store=basic", "--disable-background-networking",
         "--disable-component-update", "--disable-sync", "--disable-default-apps", "--disable-extensions",
         "--no-service-autorun", "--metrics-recording-only"]
# How long Chrome may take to announce its DevTools endpoint. It bounds a wedged browser, not a slow one:
# on 2026-11-14, under a load average of 8 to 15, a fresh profile took 0.4 s to 31 s to serve /json/list,
# so the old fixed 20 s read "never exposed a debuggable page" on a browser that was merely starting.
LAUNCH_DEADLINE_S = 90.0


def _launch(profile, deadline_s=LAUNCH_DEADLINE_S):
    """Headless Chrome on a fresh profile, in its own process group (so _kill can wait for every helper
    process, not only the browser). Port 0 lets Chrome pick a free port, so two sweeps never collide on one.
    Ready is Chrome's own announcement on stderr ("DevTools listening on ws://..."), then a page target
    from /json/list; a failure says which stage it reached and when."""
    proc = subprocess.Popen(
        [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--mute-audio", "--autoplay-policy=user-gesture-required",
         "--no-first-run", "--no-default-browser-check", *QUIET,
         "--disable-features=Translate,MediaRouter,OptimizationHints",
         "--remote-debugging-port=0", f"--user-data-dir={profile}", "about:blank"],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, errors="replace",
        start_new_session=True)
    announced = []
    ready = threading.Event()

    def drain():
        # Read stderr to the end, so a chatty Chrome never blocks on a full pipe.
        for line in proc.stderr:
            m = re.search(r"DevTools listening on (ws://\S+)", line)
            if m and not announced:
                announced.append(m.group(1))
                ready.set()

    threading.Thread(target=drain, daemon=True).start()
    t0 = time.time()
    while not ready.wait(0.1):
        if proc.poll() is not None:
            raise RuntimeError(f"Chrome exited at launch (rc={proc.returncode})")
        if time.time() - t0 > deadline_s:
            _kill(proc)
            raise RuntimeError(f"Chrome never announced DevTools in {deadline_s:.0f} s")
    t_ws = time.time() - t0
    port = int(urlsplit(announced[0]).port)
    last = None
    while time.time() - t0 < deadline_s:
        if proc.poll() is not None:
            raise RuntimeError(f"Chrome exited after announcing DevTools (rc={proc.returncode})")
        try:
            pages = json.loads(urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list", timeout=5).read())
            page = next((p for p in pages if p.get("type") == "page"), None)
            if page:
                return proc, page["webSocketDebuggerUrl"]
            last = f"{len(pages)} target(s), no page"
        except (OSError, ValueError) as e:
            last = f"{type(e).__name__}: {e}"
        time.sleep(0.1)
    _kill(proc)
    raise RuntimeError(f"Chrome announced DevTools at {t_ws:.1f} s but listed no page in {deadline_s:.0f} s ({last})")


def _kill(proc):
    """Stop Chrome and wait until its whole process group is gone. Waiting on the browser process alone
    left helper processes running into the next launch (3 of them once, 2026-11-14)."""
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait(timeout=5)
    deadline, killed = time.time() + 5, False
    while True:
        try:
            os.killpg(proc.pid, 0)
        except (ProcessLookupError, PermissionError):
            return
        if time.time() > deadline:
            if killed:
                raise RuntimeError(f"Chrome's helper processes (group {proc.pid}) outlived SIGKILL")
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                return
            deadline, killed = time.time() + 5, True
        time.sleep(0.05)


def shoot(url, w, h, path, ready_rx, deadline_s=READY_DEADLINE_S):
    """Capture `url` at a true w x h once `ready_rx` is in the page's text.

    Returns a dict for the report: ok (a PNG was written), ready_ms (time from
    navigate until ready_rx matched, None if it never did), timed_out, and
    failed_loads (same-origin requests the network layer failed: a dev server
    that resets connections serves a page that is not the page under test)."""
    Path(path).unlink(missing_ok=True)
    rec = {"ok": False, "ready_ms": None, "timed_out": False, "failed_loads": []}
    # A fresh profile per shot, so no route inherits another's service worker or
    # storage; removed every time, whatever happened.
    profile = tempfile.mkdtemp(prefix="web_run-")
    proc = None
    try:
        proc, ws_url = _launch(profile)
        cdp = CDP(ws_url)
        cdp.call("Page.enable")
        cdp.call("Network.enable")
        # Emulation, not --window-size: headless Chrome floors its window near
        # 500 px, so a "375 px" window-size shot was a 500 px layout.
        cdp.call("Emulation.setDeviceMetricsOverride",
                 {"width": w, "height": h, "deviceScaleFactor": 1, "mobile": w < 600})
        t0 = time.time()
        cdp.call("Page.navigate", {"url": url}, timeout=30)
        rx = re.compile(ready_rx, re.I)
        while True:
            r = cdp.call("Runtime.evaluate", {
                "expression": "document.body ? document.body.innerText : ''",
                "returnByValue": True})
            if rx.search(r.get("result", {}).get("value") or ""):
                rec["ready_ms"] = round((time.time() - t0) * 1000)
                break
            if time.time() - t0 > deadline_s:
                rec["timed_out"] = True
                break
            time.sleep(0.1)
        # The text is in the DOM; let fonts settle and two frames paint it.
        cdp.call("Runtime.evaluate", {
            "expression": "document.fonts.ready.then(() => new Promise(r => "
                          "requestAnimationFrame(() => requestAnimationFrame(r))))",
            "awaitPromise": True}, timeout=10)
        shot = cdp.call("Page.captureScreenshot", {"format": "png"}, timeout=30)
        Path(path).write_bytes(base64.b64decode(shot["data"]))
        origin = urlsplit(url).netloc
        reqs = {}
        for e in cdp.events:
            p = e.get("params", {})
            if e["method"] == "Network.requestWillBeSent":
                reqs[p.get("requestId")] = p.get("request", {}).get("url", "")
            elif e["method"] == "Network.loadingFailed" and not p.get("canceled"):
                u = reqs.get(p.get("requestId"), "?")
                if urlsplit(u).netloc == origin:
                    rec["failed_loads"].append(f"{urlsplit(u).path} {p.get('errorText')}")
        rec["ok"] = Path(path).exists() and Path(path).stat().st_size > 3000
    except (OSError, RuntimeError, TimeoutError, ConnectionError) as e:
        rec["error"] = f"{type(e).__name__}: {e}"
    finally:
        if proc:
            _kill(proc)
        shutil.rmtree(profile, ignore_errors=True)
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--base", default=BASE)
    ap.add_argument("--list", action="store_true", help="print the routes and exit")
    a = ap.parse_args()

    if a.list:
        for k, (path, _, ready) in ROUTES.items():
            print(f"  {k:12s} {path}   ready: /{ready}/")
        return 0

    names = [n for n in (a.only.split(",") if a.only else ROUTES) if n in ROUTES]
    out = qa_dir("web", "sweep")
    g = Grader(out, platform="web", base=a.base, routes=names,
               capture="cdp", ready_deadline_s=READY_DEADLINE_S,
               viewports={label: [w, h] for label, w, h in VIEWPORTS})
    g.report["timing"] = {}

    seen = {}
    for n in names:
        path, sig, ready = ROUTES[n]
        print(f"\n=== {n} ({path}) ===")
        d = out / n
        d.mkdir(parents=True, exist_ok=True)
        shots, recs = [], {}
        for label, w, h in VIEWPORTS:
            p = d / f"{label}.png"
            recs[label] = shoot(a.base + path, w, h, p, ready)
            if recs[label]["ok"]:
                shots.append((label, p))
        g.report["timing"][n] = recs
        waited = [f"{label} {r['ready_ms']} ms" if r["ready_ms"] is not None
                  else f"{label} timed out waiting {READY_DEADLINE_S:.0f} s"
                  + (f" ({r['error']})" if r.get("error") else "")
                  for label, r in recs.items()]
        g.grade(f"{n}.ready", all(r["ready_ms"] is not None for r in recs.values()),
                f"/{ready}/ in page text: " + ", ".join(waited))
        failed = sorted({f for r in recs.values() for f in r["failed_loads"]})
        g.grade(f"{n}.loads_complete", not failed, "every same-origin request loaded"
                if not failed else f"the server failed {len(failed)} request(s), so the "
                f"page shot is not the page: {'; '.join(failed[:4])}")
        if not shots:
            g.grade(f"{n}.captured", False, "chrome produced no screenshot")
            continue
        texts = ocr(shots)
        sub = Grader(out, platform="web")
        sub.grade_glass(shots, texts, {"expect_any": sig}, ANCHOR)
        for k, v in sub.report["assertions"].items():
            g.grade(f"{n}.{k}", v["pass"], v["evidence"])
        seen[n] = " ".join(t["text"] for t in
                           texts.get((d / "wide.png").name, {}).get("allText", []))[:150]

    # Distinct routes must show distinct content. Fifteen passing captures of the
    # same screen pass every per-route check ever written.
    dupes = {}
    for n, txt in seen.items():
        if n in SAME_SCREEN_AS:
            continue
        if txt and txt in dupes:
            g.grade(f"{n}.distinct_screen", False, f"identical to {dupes[txt]}")
        dupes[txt] = n
    return g.finish()


if __name__ == "__main__":
    sys.exit(main())
