#!/usr/bin/env python3
"""Roku PLAYBACK audit — does content actually play on the device, or not.

The app is never allowed to grade its own work. Every claim comes from one of two
external oracles:

  1. **ECP `/query/media-player`** — Roku's OWN account of the video plane: state,
     error, codec, resolution, and a position that has to ADVANCE between samples.
     This matters more here than anywhere: the video plane is not composited into a
     Roku screenshot, so a screenshot of a playing film is a black rectangle. A
     screenshot CANNOT prove playback on Roku; an advancing position can.
  2. **The BrightScript console on 8085** — what the channel says it is doing. Used
     only for what ECP cannot see (the deep link was accepted, a failure notice was
     SHOWN, a bookmark was written, how often a stall watchdog fired). When the
     console is unreadable or a marker below is unset, those checks SKIP — they are
     never guessed.

Each item is driven by a DEEP LINK (`/input`), not remote presses, so a run is
deterministic and a failure names an item instead of a key sequence. Items come from
--ids or --ids-file; pick a VARIED sample (content types, shortest and longest):
re-testing one item proves only that one item still works.

  python3 tools/roku_playback_audit.py --ids ID1 ID2 ID3
  python3 tools/roku_playback_audit.py --ids-file build/qa/roku-sample.txt --watch 30
  python3 tools/roku_playback_audit.py --ids ID1 --soak 300    # one item, long watch

Exit is non-zero if any item fails a REQUIRED check, so this can gate a release.
PASS, FAIL and SKIP are reported as three separate numbers — a skip is not a pass.
"""
import argparse
import json
import socket
import sys
import threading
import time
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import devlease  # noqa: E402
import roku_run as roku  # noqa: E402

# ── Console markers — FILL IN with what YOUR channel prints (substring match). ──
# Unset (None) = that console check reports SKIP, never PASS.
MARK_READY = None          # FILL IN: printed once the channel has loaded its data, e.g. "APP ready"
MARK_ACCEPTED = None       # FILL IN: format string with {id}, e.g. "APPDEEP contentId={id}"
MARK_FAILED_NOTICE = None  # FILL IN: printed when the player SHOWS a can't-play message
MARK_BOOKMARK = None       # FILL IN: format string with {id}, printed when progress is saved
MARK_STALL = None          # FILL IN: printed when the channel's stall watchdog fires
MARK_RECOVER = None        # FILL IN: printed when it recovers from a stall
MEDIA_TYPE = "movie"       # the mediaType deep-link parameter your channel expects

# A film starts within 30 seconds or it has failed. The clock starts when the link
# is SENT to a running channel, never at process launch — a cold boot spends many
# seconds parsing data, and charging that to the item measured the wrong thing and
# reported healthy items as broken.
START_DEADLINE = 30.0
MS = 1000.0
REQUIRED = ["channel_up", "started", "advanced", "no_error", "error_shown", "accepted"]
PLAYING = ("play", "buffer", "pause", "startup")


class Console(threading.Thread):
    """Tails the debug console for the length of the run, RECONNECTING on EOF: Roku
    drops the 8085 stream when the channel relaunches, and a reader connected once
    goes silent for everything after. Push-only; nothing is ever sent."""

    def __init__(self, host):
        super().__init__(daemon=True)
        self.host = host
        self.lines = []
        self.lock = threading.Lock()
        self.stop = False
        self.ok = False

    def run(self):
        while not self.stop:
            try:
                s = socket.create_connection((self.host, roku.CONSOLE_PORT), timeout=5)
            except OSError:
                time.sleep(2)
                continue
            self.ok = True
            s.settimeout(1)
            buf = ""
            while not self.stop:
                try:
                    chunk = s.recv(65536)
                except socket.timeout:
                    continue
                except OSError:
                    break
                if not chunk:
                    break
                buf += chunk.decode(errors="replace")
                *whole, buf = buf.split("\n")
                with self.lock:
                    self.lines.extend(l.strip() for l in whole)
            s.close()
            time.sleep(1)

    def mark(self):
        with self.lock:
            return len(self.lines)

    def since(self, mark):
        with self.lock:
            return self.lines[mark:]

    def saw(self, mark, marker):
        """True/False when the marker is set and the console readable, else None."""
        if not marker or not self.ok:
            return None
        return any(marker in l for l in self.since(mark))


def post(path):
    roku.curl("-X", "POST", f"{roku.ECP}{path}")


def warm_channel(console, timeout=45):
    """Get the channel running BEFORE any item is timed. Already in front = warm:
    /launch with no params does not restart a foreground channel, so waiting for a
    fresh ready line that will never print fails a healthy device.

    The console mark is taken BEFORE the launch: the console replays its backlog on
    attach, so a ready line from a PREVIOUS run is already in the buffer."""
    if roku.channel_foreground():
        return 0.0
    mark = console.mark()
    post("/launch/dev")
    t0 = time.time()
    while time.time() - t0 < timeout:
        if roku.channel_foreground():
            ready = console.saw(mark, MARK_READY)
            if ready or (ready is None and time.time() - t0 > 20):
                return round(time.time() - t0, 1)
        time.sleep(1.0)
    return None


def stop_playback(tries=4):
    """Get to a state where NOTHING is playing before timing an item, or the previous
    item's "play" makes the next one "start" in 0.1 s. Back is pressed ONLY while
    something plays, and a bounded number of times: Back walks Player -> Detail ->
    Home -> OUT OF THE CHANNEL, and a blind loop once exited the app and reported a
    healthy item as unplayable."""
    for _ in range(tries):
        mp = roku.media_player()
        if not mp or mp.get("state") not in PLAYING:
            return True
        post("/keypress/Back")
        time.sleep(1.5)
    return False


def audit_item(item, console, watch_seconds, do_replay):
    res = {"id": item, "checks": {}, "notes": []}
    ck = res["checks"]
    # Quiesce FIRST, then re-assert the channel (quiescing is what can close it),
    # then mark the console, so nothing from the previous item is in this window.
    ck["quiesced"] = stop_playback()
    # `/input` on a channel that has exited answers 200 and opens nothing, which
    # reads as "the app rejected this item". Prove the channel is up first.
    ck["channel_up"] = roku.channel_foreground() or warm_channel(console) is not None
    mark = console.mark()

    # /input hands params to the RUNNING channel; /launch restarts it every time.
    q = urllib.parse.urlencode({"contentId": item, "mediaType": MEDIA_TYPE})
    post(f"/input?{q}")

    t0 = time.time()
    started, states, samples = None, [], []
    # `error` is STICKY — it describes the LAST media session — so errors before and
    # after this item starts are counted separately, or one broken item condemns
    # whatever is audited after it.
    err_pre = err_post = None
    while time.time() - t0 < START_DEADLINE:
        mp = roku.media_player()
        if mp:
            if not states or states[-1] != mp["state"]:
                states.append(mp["state"])
            if mp.get("error") not in (None, "false"):
                err_pre = mp.get("error")
            # Reaching "play" IS the start: position/duration are ABSENT for the first
            # seconds of playback, and waiting on them times out a running item.
            if mp["state"] == "play":
                started = time.time() - t0
                samples.append(mp)
                break
        time.sleep(1.0)
    res["states"] = states
    ck["accepted"] = console.saw(mark, MARK_ACCEPTED.format(id=item) if MARK_ACCEPTED else None)
    ck["started"] = started is not None

    if started is None:
        res["notes"].append(f"never reached play in {START_DEADLINE:.0f}s "
                            f"(states: {' -> '.join(s or '?' for s in states) or 'none'})")
        ck["advanced"] = False
        ck["no_error"] = err_pre is None
        # An item that cannot play must SAY SO on screen — dropping the viewer back
        # on Detail with no message is indistinguishable from a dead remote.
        ck["error_shown"] = console.saw(mark, MARK_FAILED_NOTICE)
        return res
    res["ttff"] = round(started, 1)
    ck["error_shown"] = None             # nothing failed, nothing to show

    watch_from = time.time()
    while time.time() < watch_from + watch_seconds:
        time.sleep(5)
        mp = roku.media_player()
        if not mp:
            break
        samples.append(mp)
        if mp.get("error") not in (None, "false"):
            err_post = mp.get("error")
    watched = time.time() - watch_from
    posns = [s["position"] for s in samples if s.get("position") is not None]
    if not posns:
        res["notes"].append("state reached play but ECP never reported a position")
    ck["advanced"] = len(posns) >= 2 and posns[-1] > posns[0]
    res["positions_s"] = [round(p / MS, 1) for p in posns]
    if len(posns) >= 2:
        # Film clock vs ACTUAL wall clock (not the requested watch length — the loop
        # overruns by a sample). 4 s of picture per 10 s watched is "advancing" and
        # unwatchable; this is the number that catches it.
        res["realtime_ratio"] = round((posns[-1] - posns[0]) / MS / max(watched, 1), 2)
    ck["no_error"] = err_post is None
    if err_post:
        res["notes"].append(f"media-player reported error={err_post} during playback")
    last = samples[-1]
    ck["codec"] = bool(last.get("video") and last.get("audio"))
    res["codec"] = f"{last.get('video')}/{last.get('audio')} {last.get('res')}"

    if do_replay:
        before = last.get("position")
        post("/keypress/InstantReplay")
        time.sleep(4)
        mid = roku.media_player()
        after = mid.get("position")
        if before is None or after is None:
            ck["replay"] = None
            res["notes"].append("replay not judged — ECP gave no position")
        else:
            # Went BACK relative to where it would otherwise be, and kept playing.
            ck["replay"] = after < before + 4000 and mid.get("state") == "play"
            res["replay_s"] = f"{round(before / MS)} -> {round(after / MS)}"

    ck["bookmark"] = console.saw(mark, MARK_BOOKMARK.format(id=item) if MARK_BOOKMARK else None)
    log = console.since(mark)
    if MARK_STALL:
        res["stalls"] = sum(MARK_STALL in l for l in log)
    if MARK_RECOVER:
        res["recoveries"] = sum(MARK_RECOVER in l for l in log)
        if res["recoveries"]:
            res["notes"].append(f"stall watchdog recovered {res['recoveries']}x")
    return res


def mark_of(v):
    return {True: "PASS", False: "FAIL", None: "SKIP"}[v]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--device", default="roku")
    ap.add_argument("--owner-ok", action="store_true")
    ap.add_argument("--ids", nargs="*", default=[], help="content ids to audit")
    ap.add_argument("--ids-file", help="file with one content id per line")
    ap.add_argument("--watch", type=float, default=20.0,
                    help="seconds to watch each item after it starts")
    ap.add_argument("--soak", type=float, default=0.0,
                    help="watch ONE item this long instead (exercises the stall watchdog)")
    ap.add_argument("--no-replay", action="store_true", help="skip the InstantReplay check")
    args = ap.parse_args()

    ids = list(args.ids)
    if args.ids_file:
        ids += [l.strip() for l in Path(args.ids_file).read_text().splitlines()
                if l.strip() and not l.startswith("#")]
    if not ids:
        ap.error("give --ids or --ids-file — an audit of nothing is not a pass")
    watch = args.soak or args.watch
    if args.soak:
        ids = ids[:1]

    roku.configure(args.device, allow_owner=args.owner_ok)
    try:
        with devlease.hold([roku.lease_key()], task=f"roku playback audit ({len(ids)})"):
            return run(ids, watch, not args.no_replay)
    except RuntimeError as e:
        print(f"device busy — {e}. This audit covers NOTHING.")
        return 1


def run(ids, watch, do_replay):
    console = Console(roku.HOST)
    console.start()
    time.sleep(1.5)
    if not console.ok:
        print("NOTE: the debug console on 8085 is not readable — console-only checks "
              "will SKIP; every ECP check still runs.")
    results = []
    try:
        boot = warm_channel(console)
        if boot is None:
            print("the channel did not come up — nothing can be measured")
            return 1
        print(f"channel warm in {boot}s\nRoku playback audit — {len(ids)} item(s), "
              f"{watch:.0f}s each, host {roku.HOST}\n")
        for item in ids:
            print(f"-> {item}")
            r = audit_item(item, console, watch, do_replay)
            results.append(r)
            print("  " + "  ".join(f"{k}={mark_of(v)}" for k, v in r["checks"].items()))
            if r.get("ttff") is not None:
                print(f"  start {r['ttff']}s  {r.get('codec')}  pos {r.get('positions_s')}  "
                      f"realtime x{r.get('realtime_ratio')}")
            for n in r["notes"]:
                print("  NOTE:", n)
    finally:
        # Leave as found: nothing playing, the device on its Home screen.
        stop_playback()
        post("/keypress/Home")
        console.stop = True

    vals = [v for r in results for v in r["checks"].values()]
    failed = [(r["id"], k) for r in results for k, v in r["checks"].items() if v is False]
    print(f"\n{vals.count(True)} PASS / {len(failed)} FAIL / "
          f"{sum(v is None for v in vals)} SKIP of {len(vals)} checks across "
          f"{len(results)} item(s)")
    out = roku.qa_dir() / "playback-audit.json"
    out.write_text(json.dumps(results, indent=2))
    print("written:", out)
    hard = [f for f in failed if f[1] in REQUIRED]
    if hard:
        print("\nREQUIRED checks failed:")
        for i, k in hard:
            print(f"   {i}  {k}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
