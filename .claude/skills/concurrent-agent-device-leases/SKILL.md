---
name: concurrent-agent-device-leases
description: "Use when more than one agent session drives the same physical test devices (two Claude Code sessions in different repos sharing a bench of phones and TVs), or any runner that force-stops apps and resets device state. Carries the cooperative lease protocol (~/.device-lease, tools/devlease.py), hold-for-the-whole-run with hold() and child_env(), dead-pid reclaim, SKIP-not-pass when leased elsewhere, and the tell that you are fighting a peer rather than a bug. Triggers on device contention, another session, app keeps closing, force-stop, shared test devices, adb/devicectl conflicts, 'the app was in the foreground and I did not put it there'."
---

# Sharing a device bench between concurrent agent sessions

Protocol and rationale for people: `docs/AUTONOMOUS-FLEET-TESTING.md`
section 6. Reference implementation: `tools/devlease.py`.

## The tell

Contention looks like a product bug: your app is not in front though you
launched it, it died mid-run, a screenshot shows another app, a device
stops answering mid-sweep. On the Archive Watch bench a runner spent four
rounds of fixes getting "smarter" at fighting a peer it did not know
existed. **Before debugging inexplicable device behavior, check for a
peer:** `python3 tools/devlease.py` lists who holds what.

## The protocol

```
~/.device-lease/<device>.json   {"owner", "pid", "task", "acquired", "expires"}
```

1. Take a lease before touching a device; release it after.
2. Leases have a TTL (default 900 s). A lease whose pid is dead is free at
   once; a slow live one is never reclaimed.
3. Never take a live lease. Wait (`wait=`/`--lease-wait`) or skip and SAY
   so. Leased elsewhere is SKIP (atv_run exits 2); a SKIP covers nothing.
4. A foreign lease names its holder, so messages blame a peer, not the app.

Env: `DEVICE_LEASE_DIR`, `DEVICE_LEASE_OWNER` (defaults to the repo
directory name), `DEVICE_LEASE_HOLDER_PID`.

## Hold it for the whole run, in one process

A lease per step leaves gaps; a peer took an Apple TV in exactly one.

```python
import devlease

# WRONG: three leases, two gaps
with devlease.lease("atv"): install()
with devlease.lease("atv"): launch()

# RIGHT: every device the run needs, all or nothing, renewed in the background
with devlease.hold(["atv", "ipad"], task="regression sweep", wait=900):
    install(); launch(); shot = capture(); grade(shot); teardown()
```

A suite that shells out to runners holds the lease itself and hands it
down: pass `env=devlease.child_env()` to the subprocess, and the child
treats a lease held by `DEVICE_LEASE_HOLDER_PID` as its own without
renewing or releasing it. `tools/qa_suite.py` does this per device.

## Names

Lease names are the bench manifest keys (`tools/bench.py`): physical
devices, not roles (`atv`, `atv-control`, `ipad`, `iphone`, `pixel`,
`androidtv`, `firetv`, `roku`, `mac`). Put the bench in
`~/.device-bench.json` so every repo on the machine reads the same names.

## Limits

- Two sessions wanting one device at once: one waits. If that is common,
  the bench is too small; do not shorten TTLs until the protocol breaks.
- A person picking up the device is not detected. OCR assertions catch the
  nonsense; the lease does not.
- One machine only: `~/.device-lease` is one filesystem.

## Checklist

- [ ] `devlease.py` copied unchanged into every repo sharing the bench
- [ ] Bench names shared through the machine-wide manifest
- [ ] Every entry point wraps its whole run in one `hold()`
- [ ] Suites hand leases down with `child_env()`
- [ ] Skipped-because-leased is reported, never dropped
