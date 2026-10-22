#!/usr/bin/env python3
"""Press Select on every surface and report what the app actually DID.

Deep links prove a screen RENDERS. A Select sweep proves it is CONNECTED. The
original of this tool found, in one pass, Select on an empty list starting
playback, a hero rotating behind every other surface, and a TV scope opening a film
instead of a series — none of which thirty ticks of screenshots had caught.

Each step deep-links to a surface, presses its keys, and reads the channel's own
TRACE lines off the debug console (8085). Read the output: a step with NO TRACE, or
a trace naming a DIFFERENT surface than the one under test, is a dead or mis-routed
control. NO TRACE is a finding and makes the exit status non-zero.

Level two (optional, per surface): `deeper` keys walk INTO what the first control
opened — options panels, lists, the player, and Back — which is where a control that
keeps its focus for the life of the channel, or a panel with no trace at all, hides.

  python3 tools/roku_sweep.py
  python3 tools/roku_sweep.py --only Library,Search --deeper
"""
import argparse
import socket
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import devlease  # noqa: E402
import roku_run as roku  # noqa: E402

# FILL IN: the prefixes your channel's trace lines start with (e.g. "APP", "NAV").
TRACE_PREFIXES = ("APP",)

# FILL IN: (name, deep-link query for /input, keys for level one, keys for level two).
# The query is sent to the RUNNING channel via /input (no restart). Level-two keys
# run after level one when --deeper is given; end them with Back to prove Back works.
SURFACES = [
    # ("Home",    "contentId=go%3Ahome",    ["down", "select"], ["select", "back"]),
    # ("Search",  "contentId=go%3Asearch",  ["select"],         ["back"]),
]


class ConsoleReader(threading.Thread):
    """RECONNECT on EOF: Roku drops the 8085 console when the channel relaunches,
    so a reader connected once went silent for every step after the first relaunch
    and the sweep reported NO TRACE for controls that worked."""

    def __init__(self, host):
        super().__init__(daemon=True)
        self.host, self.lines, self.stop = host, [], False

    def run(self):
        while not self.stop:
            try:
                s = socket.create_connection((self.host, roku.CONSOLE_PORT), timeout=5)
                s.settimeout(1.0)
                buf = b""
                while not self.stop:
                    try:
                        c = s.recv(4096)
                    except socket.timeout:
                        continue
                    if not c:
                        break
                    buf += c
                    while b"\n" in buf:
                        line, buf = buf.split(b"\n", 1)
                        self.lines.append(line.decode(errors="replace").strip())
                s.close()
            except OSError:
                pass
            time.sleep(1.0)

    def mark(self):
        return len(self.lines)

    def since(self, m):
        return [l for l in self.lines[m:] if l.startswith(TRACE_PREFIXES)]


def ensure_channel():
    """A sweep against a channel that is not in front reports every step as NO
    TRACE — indistinguishable from ten dead controls. Prove ours is foreground; if
    it cannot be brought forward the device is in use — stop, don't fight for it."""
    if roku.channel_foreground():
        return True
    print("   [channel was not foreground — launching]")
    roku.curl("-X", "POST", f"{roku.ECP}/launch/dev")
    time.sleep(16)
    if not roku.channel_foreground():
        print("   [could not bring the channel to the foreground — the device is in "
              "use. Stopping rather than fighting for it.]")
        return False
    return True


def step(reader, name, keys, label):
    m = reader.mark()
    for k in keys:
        roku.press(k, settle=1.2)
    time.sleep(2.5)
    ev = reader.since(m)
    print(f"\n=== {name} {label} (keys: {' '.join(keys)})")
    if not ev:
        print("   NO TRACE — the control did nothing")
    for line in ev[-8:]:
        print("    ", line)
    return bool(ev)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--device", default="roku")
    ap.add_argument("--owner-ok", action="store_true")
    ap.add_argument("--only", default="", help="comma list of surface names")
    ap.add_argument("--deeper", action="store_true", help="also run level-two keys")
    a = ap.parse_args()

    want = [s for s in SURFACES if not a.only or s[0] in a.only.split(",")]
    if not want:
        print("no surfaces to sweep — fill in SURFACES (an empty sweep is not a pass)")
        return 1
    for s in want:
        for k in s[2] + (s[3] if len(s) > 3 else []):
            roku.key_name(k)             # refuse a bad key before touching the device

    roku.configure(a.device, allow_owner=a.owner_ok)
    try:
        with devlease.hold([roku.lease_key()], task="roku select sweep"):
            return sweep(want, a.deeper)
    except RuntimeError as e:
        print(f"device busy — {e}. This sweep covers NOTHING.")
        return 1


def sweep(want, deeper):
    reader = ConsoleReader(roku.HOST)
    reader.start()
    time.sleep(1.5)
    dead, ran = [], 0
    try:
        for s in want:
            name, query, keys = s[0], s[1], s[2]
            if not ensure_channel():
                return 1
            roku.curl("-X", "POST", f"{roku.ECP}/input?{query}")
            time.sleep(4.5)
            ran += 1
            if not step(reader, name, keys, "L1"):
                dead.append(f"{name} L1")
            if deeper and len(s) > 3 and s[3]:
                if not step(reader, name, s[3], "L2"):
                    dead.append(f"{name} L2")
    finally:
        reader.stop = True
        roku.press("Home", settle=1.0)           # leave as found
    print(f"\n{ran} surface(s) swept, {len(dead)} with NO TRACE"
          + (f": {', '.join(dead)}" if dead else ""))
    return 1 if dead else 0


if __name__ == "__main__":
    sys.exit(main())
