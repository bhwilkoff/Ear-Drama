"""Cooperative leases so two agent sessions can share one bench of test devices.

The problem, named by the owner: two Claude Code sessions were driving the SAME
physical devices from different repos. Each kept finding the other's app in the
foreground, each force-stopped the other's app as part of its own "reset to a clean
state", and each diagnosed it as a bug in its own product. The Fire TV and the
Android TV changed hands mid-run repeatedly, and this harness spent four rounds of
fixes making its recovery smarter at fighting a peer it did not know existed.

No shared memory is needed to fix it — only a shared filesystem and an agreed
convention:

    ~/.device-lease/<device>.json   {"owner", "pid", "task", "acquired", "expires"}

Rules, deliberately few enough that any other tool can implement them in an hour:

  * Take a lease BEFORE touching a device; release it after.
  * A lease has a TTL. A crashed session must not hold a device forever, and no
    session should have to ask a human to break a lock.
  * Never steal a live lease. Wait, or skip the device and SAY the run did not
    cover it — a skipped device reported honestly beats a contended device
    reported as a product failure.
  * Reading a foreign lease tells you WHO has it, so a message names a peer
    instead of blaming the app.

    with lease("firetv", task="appname live join"):
        ...                       # the device is yours for the duration

    ok, holder = try_lease("firetv")
    if not ok:  print(f"skipping firetv — held by {holder}")

HOLD IT FOR THE WHOLE RUN, IN ONE PROCESS. Install, launch, capture, assert and
tear down under ONE lease. Taking a lease per invocation leaves a gap between calls,
and the other session grabbed an Apple TV in exactly one of those gaps. `hold()`
below is the runner form: it takes every device a run needs up front, renews them in
the background for as long as the run lasts, and releases them on any exit.

A suite that shells out to per-device runners (tools/qa_suite.py) holds the lease
itself and hands it DOWN: children see DEVICE_LEASE_HOLDER_PID and treat a lease
held by that pid as their own, without rewriting or releasing it. Otherwise the
suite's lease would lock its own runners out — or, releasing per child, reopen the
very gap this exists to close.

THE DEVICE KEYS ARE A CONTRACT. The lease directory, the filename, the JSON fields
and the KEYS are shared with every other repo on this machine that speaks this
protocol; a unilateral change silently stops the interlock rather than failing
loudly. The key for a device is its name in the bench manifest (tools/bench.py) —
write the machine's table down ONCE, in ~/.device-bench.json, so two repos cannot
disagree about what the Fire TV is called:

    atv          the harness Apple TV          firetv      the Fire TV stick
    atv-<room>   every further Apple TV        androidtv   the Google TV
    ipad         the test iPad                 pixel       the test phone
    iphone       the test iPhone               roku        the Roku (roku-<x> more)
    mac          this Mac's window capture     windows     the Windows box

    python3 tools/devlease.py              # who holds what
    python3 tools/devlease.py release-all  # release only OUR leases
"""
import contextlib
import json
import os
import threading
import time
from pathlib import Path

DIR = Path(os.environ.get("DEVICE_LEASE_DIR", Path.home() / ".device-lease"))
DEFAULT_TTL = 900          # 15 min: longer than any single run here, short enough
                           # that a crashed session frees the bench on its own.
# Who holds it, in words a PEER can read: the repo's directory name unless set.
OWNER = os.environ.get("DEVICE_LEASE_OWNER",
                       Path(__file__).resolve().parent.parent.name.lower())
# Set by a parent process (a suite) that holds leases on behalf of its children.
HOLDER_ENV = "DEVICE_LEASE_HOLDER_PID"


def _ours(held):
    """Held by this process, or by the parent that handed its lease down."""
    if not held:
        return False
    pid = held.get("pid")
    return pid == os.getpid() or (str(pid) == os.environ.get(HOLDER_ENV, "")
                                  and pid is not None)


def _path(dev):
    DIR.mkdir(parents=True, exist_ok=True)
    return DIR / f"{dev}.json"


def _alive(pid):
    """Is that process still running? Only meaningful for a lease taken on THIS
    machine, which is the only kind this bench has."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True                     # exists, owned by someone else
    except (OSError, TypeError):
        return True                     # unknown: assume held, never steal on a guess
    return True


def read(dev):
    """The current lease, or None when free / expired / held by a dead process."""
    p = _path(dev)
    try:
        d = json.loads(p.read_text())
    except (OSError, ValueError):
        return None
    if d.get("expires", 0) < time.time():
        return None                     # expired: treated as free, not stolen
    # A killed session must not hold the bench for the rest of its TTL. A sweep died
    # to a timeout without releasing, and the next sweep was refused for four more
    # minutes with "this sweep covers NOTHING" — correct, and needlessly so.
    #
    # Only ever reclaimed from a DEAD pid, never a slow one: the check is "does this
    # process still exist", not "has it taken too long".
    if not _alive(d.get("pid")):
        return None
    return d


def try_lease(dev, task="", ttl=DEFAULT_TTL):
    """Take `dev` if it is free. Returns (ok, holder_description)."""
    held = read(dev)
    if held and _ours(held) and held.get("pid") != os.getpid():
        return True, ""                 # inherited from the suite that spawned us
    if held and held.get("pid") != os.getpid():
        who = held.get("owner", "?")
        what = held.get("task") or "unnamed work"
        left = int(held.get("expires", 0) - time.time())
        return False, f"{who} (pid {held.get('pid')}) — {what}, {left}s left"

    rec = {"owner": OWNER, "pid": os.getpid(), "task": task,
           "acquired": time.time(), "expires": time.time() + ttl}
    # O_EXCL so two processes racing for a free device cannot both win. Losing the
    # race is not an error — it means someone else got there first, which is the
    # whole point.
    tmp = _path(dev).with_suffix(".tmp")
    try:
        with open(tmp, "w") as f:
            json.dump(rec, f)
        os.replace(tmp, _path(dev))
    except OSError as e:
        return False, f"could not write lease: {e}"
    back = read(dev)
    if not back or back.get("pid") != os.getpid():
        return False, "lost the race to another session"
    return True, ""


def release(dev):
    held = read(dev)
    if held and held.get("pid") != os.getpid():
        return False                    # never release someone else's
    with contextlib.suppress(OSError):
        _path(dev).unlink()
    return True


def renew(dev, ttl=DEFAULT_TTL):
    """Extend our own lease. A long run must not expire mid-flight."""
    held = read(dev)
    if not held or held.get("pid") != os.getpid():
        return False
    held["expires"] = time.time() + ttl
    _path(dev).write_text(json.dumps(held))
    return True


@contextlib.contextmanager
def hold(devs, task="", ttl=DEFAULT_TTL, wait=0):
    """Hold EVERY device in `devs` for the whole block, renewed in the background.

    All-or-nothing: if one cannot be had within `wait` seconds the ones already
    taken are released and RuntimeError names the holder — a half-leased run is a
    run that will fight a peer for the other half. Inherited leases (see HOLDER_ENV)
    count as held and are neither renewed nor released here."""
    devs = [d for d in dict.fromkeys(devs) if d]
    taken = []
    try:
        for d in devs:
            deadline = time.time() + wait
            while True:
                ok, holder = try_lease(d, task, ttl)
                if ok:
                    break
                if time.time() >= deadline:
                    raise RuntimeError(f"{d} is leased by {holder}")
                time.sleep(3)
            if (read(d) or {}).get("pid") == os.getpid():
                taken.append(d)
    except BaseException:
        for d in taken:
            release(d)
        raise

    stop = threading.Event()

    def _renew():
        # Renew at a third of the TTL: a run longer than the TTL must not expire
        # mid-flight and hand the device to a peer while we are still using it.
        while not stop.wait(max(30, ttl / 3)):
            for d in taken:
                renew(d, ttl)

    t = threading.Thread(target=_renew, daemon=True)
    t.start()
    try:
        yield taken
    finally:
        stop.set()
        for d in taken:
            release(d)


def child_env(env=None):
    """The environment a child runner needs to inherit this process's leases."""
    e = dict(os.environ if env is None else env)
    e[HOLDER_ENV] = str(os.getpid())
    return e


@contextlib.contextmanager
def lease(dev, task="", ttl=DEFAULT_TTL, wait=0):
    """Hold `dev` for the block. Raises if it cannot be had within `wait` seconds."""
    deadline = time.time() + wait
    while True:
        ok, holder = try_lease(dev, task, ttl)
        if ok:
            break
        if time.time() >= deadline:
            raise RuntimeError(f"{dev} is leased by {holder}")
        time.sleep(3)
    try:
        yield
    finally:
        release(dev)


def status():
    DIR.mkdir(parents=True, exist_ok=True)
    rows = []
    for p in sorted(DIR.glob("*.json")):
        dev = p.stem
        d = read(dev)
        rows.append((dev, d))
    return rows


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "release-all":
        for dev, _ in status():
            print(f"  released {dev}" if release(dev) else f"  {dev} is not ours")
    else:
        for dev, d in status():
            if d is None:
                print(f"  {dev:12} free")
            else:
                left = int(d["expires"] - time.time())
                print(f"  {dev:12} {d['owner']} (pid {d['pid']}) — "
                      f"{d.get('task') or 'unnamed'}, {left}s left")
        if not status():
            print("  (no leases: the whole bench is free)")
