#!/usr/bin/env python3
"""Guard: the teardown's power-off retries and reads the state back.

A run that found Ben Bedroom OFF reported "power: on - did NOT power off" because
one turn_off was sent, one read was taken after a fixed wait, and the TV had
simply not honored it yet; the same command by hand a minute later worked. Wake
polls and retries; power-off must too, and must still report honestly when the
TV never goes off.

    python3 tools/test_atv_power_off.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import apple_device as A  # noqa: E402


class FakeTV(A.ATV):
    """A TV that ignores the first `refusals` turn_off commands."""

    def __init__(self, refusals):
        self.entry = {"name": "fake"}
        self.available = True
        self.refusals = refusals
        self.sent = 0
        self.state = "on"

    def _run(self, *cmd, timeout=40):
        if cmd[0] == "turn_off":
            self.sent += 1
            if self.sent > self.refusals:
                self.state = "off"

    def power_state(self):
        return self.state


def main():
    A.time.sleep = lambda s: None
    fails = []

    ok, state = FakeTV(refusals=1).turn_off_verified()
    if not (ok and state == "off"):
        fails.append(f"a TV that refuses once must still end off: got {(ok, state)}")

    ok, state = FakeTV(refusals=99).turn_off_verified()
    if ok or state != "on":
        fails.append(f"a TV that never turns off must be reported on, not ok: got {(ok, state)}")

    tv = FakeTV(refusals=0)
    ok, _ = tv.turn_off_verified()
    if not ok or tv.sent != 1:
        fails.append(f"a TV that obeys is sent exactly one command: sent {tv.sent}")

    for f in fails:
        print("FAIL:", f)
    print("atv power-off guard:", "FAILED" if fails else "ok (3 cases)")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
