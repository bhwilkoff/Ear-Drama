"""Apple device plumbing shared by the iOS and tvOS runners: devicectl + pyatv.

Every function here exists because the obvious one-liner lied at least once:

  * `devicectl device process terminate` takes --pid. Given a bundle id it prints
    its usage text and exits, which LOOKS like output and is not success.
  * `devicectl device info processes` prints EXECUTABLE PATHS, never bundle ids,
    and pads the path column with trailing spaces. A grep for the bundle id never
    matches, and a grep anchored with `$` never matches either — two different
    teardowns reported "not running" about a live process that way. The match is
    the exact executable, padding allowed, with app extensions (PlugIns/) excluded:
    a Top Shelf or widget extension is launched by the SYSTEM and is not ours to kill.
  * A signal sent is not a process gone. Teardown asks the DEVICE afterwards.
  * A sleeping Apple TV returns a valid, black PNG. Power state is checked before
    every launch, press and capture — never inferred from the pixels afterwards.
  * pyatv's `turn_on` only sends a request; a launch into the doze window comes up
    BACKGROUNDED (alive, not frontmost), which mimics an app bug. Wake is POLLED.
  * A fresh single-command Companion connection drops its press. Warm it with
    `power_state` on the same connection first.
  * Launch env is JSON (`-e '{"K":"V"}'`); the KEY=VALUE form fails with
    NSCocoaErrorDomain 3840.

    python3 tools/apple_device.py teardown --device atv   # leave it as found
    python3 tools/apple_device.py power --device atv      # On / Off / unknown
    python3 tools/apple_device.py processes --device ipad
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_config  # noqa: E402
import bench  # noqa: E402
from devharness import capture_fresh, ensure_ocr  # noqa: E402


def sh(cmd, timeout=90, env=None):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env)


def devicectl(*args, timeout=90):
    env = dict(os.environ)
    if app_config.DEVELOPER_DIR:
        env["DEVELOPER_DIR"] = app_config.DEVELOPER_DIR
    return sh(["xcrun", "devicectl", *args], timeout=timeout, env=env)


# ── processes ────────────────────────────────────────────────────────────────

def exe_pattern(executable=None):
    """Matches `<pid>  /…/<Exe>.app/<Exe>` with devicectl's trailing padding."""
    exe = re.escape(executable or app_config.APPLE_EXECUTABLE)
    return re.compile(rf"^\s*(\d+)\s+\S*{exe}\.app/{exe}[ \t]*$", re.M)


def app_pids(udid, executable=None):
    """PIDs of the app's MAIN executable on the device, or None when the device
    could not be asked (which is not the same as "not running")."""
    r = devicectl("device", "info", "processes", "--device", udid, timeout=90)
    if r.returncode != 0 and not r.stdout.strip():
        return None
    return [int(m.group(1)) for m in exe_pattern(executable).finditer(r.stdout)
            if "/PlugIns/" not in m.group(0)]


def app_alive(udid, executable=None):
    pids = app_pids(udid, executable)
    return bool(pids) if pids is not None else None


def terminate_verified(udid, executable=None, settle=3):
    """Terminate by pid, then ASK THE DEVICE. Returns (ok, detail)."""
    pids = app_pids(udid, executable)
    if pids is None:
        return False, "could not list processes on the device"
    if not pids:
        return True, "not running"
    for pid in pids:
        devicectl("device", "process", "terminate", "--device", udid,
                  "--pid", str(pid), timeout=60)
    time.sleep(settle)
    still = app_pids(udid, executable)
    if still is None:
        return False, f"sent terminate to {pids}; could not re-list to verify"
    if still:
        return False, f"STILL RUNNING after terminate: pids {still}"
    return True, f"terminated {pids} — verified gone"


# ── launch / capture ─────────────────────────────────────────────────────────

def launch(udid, bundle, env=None, url=None, terminate_existing=True, timeout=90):
    """Returns (ok, output). env is sent as JSON, the only form devicectl accepts."""
    args = ["device", "process", "launch", "--device", udid]
    if terminate_existing:
        args.append("--terminate-existing")
    if env:
        args += ["-e", json.dumps(env)]
    if url:
        args += ["--payload-url", url]
    args.append(bundle)
    r = devicectl(*args, timeout=timeout)
    out = r.stdout + r.stderr
    return "Launched application" in out, out.strip()[-400:]


def capture(udid, path, timeout=45):
    """A fresh screenshot or a refusal: (ok, why). See devharness.capture_fresh."""
    return capture_fresh(path, lambda p: devicectl(
        "device", "capture", "screenshot", "--device", udid,
        "--destination", str(p), timeout=timeout))


def pull_file(udid, bundle, source, dest, timeout=120):
    """Copy a file out of the app's data container. Pull BEFORE relaunching — a
    launch truncates a diagnostics file the app rewrites on start."""
    dest = Path(dest)
    try:
        dest.unlink()
    except FileNotFoundError:
        pass
    r = devicectl("device", "copy", "from", "--device", udid,
                  "--domain-type", "appDataContainer", "--domain-identifier", bundle,
                  "--source", source, "--destination", str(dest), timeout=timeout)
    return dest.exists(), (r.stdout + r.stderr).strip()[-300:]


def reboot(udid, timeout=120):
    return devicectl("device", "reboot", "--device", udid, timeout=timeout)


# ── pyatv (Apple TV power + remote) ──────────────────────────────────────────

class ATV:
    """The Companion-protocol side of one Apple TV. `entry` is a bench entry; a TV
    with no address/pyatv_id has no remote and no power control, and every method
    says so (returns None) rather than pretending."""

    def __init__(self, entry):
        self.entry = entry
        self.args = []
        if entry.get("address"):
            self.args += ["--address", entry["address"]]
        if entry.get("pyatv_id"):
            self.args += ["--id", entry["pyatv_id"]]
        self.args += ["--protocol", "companion"]
        self.available = bool(entry.get("pyatv_id")) and app_config.PYATV.exists()

    def _run(self, *cmd, timeout=40):
        return sh([str(app_config.PYATV), *self.args, *cmd], timeout=timeout)

    def why_unavailable(self):
        if not self.entry.get("pyatv_id"):
            return f"{self.entry.get('name')} has no pyatv_id in the bench manifest"
        if not app_config.PYATV.exists():
            return (f"{app_config.PYATV} missing — python3.12 -m venv ~/.pyatv-venv && "
                    "~/.pyatv-venv/bin/pip install pyatv (3.14 breaks atvremote)")
        return ""

    def power_state(self):
        """'on', 'off', or None (cannot tell)."""
        if not self.available:
            return None
        try:
            r = self._run("power_state", timeout=40)
        except subprocess.SubprocessError:
            return None
        if "PowerState.On" in r.stdout:
            return "on"
        if "PowerState.Off" in r.stdout:
            return "off"
        return None

    def wake(self, tries=3, polls=8):
        """POLLED wake. True only when the TV reports On. Gives up loudly."""
        if not self.available:
            print(f"[atv] cannot wake: {self.why_unavailable()}")
            return False
        for attempt in range(tries):
            if self.power_state() == "on":
                return True
            print(f"[atv] TV asleep — waking (attempt {attempt + 1})")
            try:
                self._run("turn_on", timeout=40)
            except subprocess.SubprocessError as e:
                print(f"[atv] turn_on failed: {e}")
            for _ in range(polls):
                time.sleep(3)
                if self.power_state() == "on":
                    time.sleep(2)            # let the home screen settle
                    return True
        print("[atv] COULD NOT WAKE THE TV — launches will background and captures "
              "will be blind")
        return False

    def press(self, key):
        """One remote press, WARMED with power_state on the same connection. Refuses
        to press into a sleeping TV (the press would be lost, the frame would lie).
        Presses do NOT reset the TV's sleep timer."""
        if not self.available:
            return False, self.why_unavailable()
        if self.power_state() != "on":
            return False, "TV is not on — press refused"
        r = self._run("power_state", key, timeout=40)
        return r.returncode == 0, (r.stderr or r.stdout).strip()[-160:]

    def launch_app(self, bundle):
        """Bring an ALREADY-RUNNING app to the foreground without relaunching it —
        the process keeps the env it was launched with. The remedy for a launch that
        came up backgrounded, cheaper than a relaunch."""
        if not self.available:
            return False
        r = self._run(f"launch_app={bundle}", timeout=40)
        return r.returncode == 0

    def turn_off_verified(self, settle=4):
        """Power off and READ IT BACK. (ok, state)."""
        if not self.available:
            return False, self.why_unavailable()
        self._run("turn_off", timeout=40)
        time.sleep(settle)
        state = self.power_state()
        return state == "off", state or "unknown"


# ── a launch that survives the bench's known failure modes ───────────────────

class LaunchFailed(RuntimeError):
    pass


LOCKED_RX = re.compile(r"FBSOpenApplicationErrorDomain.*?\b7\b|Locked", re.S)
ASLEEP_RX = re.compile(r"System is asleep|foreground app launch forbidden", re.I)


def launch_guarded(entry, bundle, env, outdir, settle=6, executable=None,
                   probe_foreground=True, allow_reboot=True, log=print):
    """Launch, then prove the app is ALIVE and FRONTMOST before anything is graded.
    Returns a list of event strings for the report. Raises LaunchFailed when the
    device refuses outright (asleep, locked, not installed) — with the reason.

    1. Wake first (tvOS), polled. A launch into the doze window is denied or comes
       up backgrounded.
    2. Foreground probe (tvOS): one frame; if the tvOS home screen owns the glass,
       bring the running app forward with pyatv launch_app (keeps its env), and only
       if that fails relaunch once. An UNKNOWN probe is recorded, never read as "fine".
    3. Death probes at 0, 15 and 30 s. Launches die silently in the first seconds
       about 2 in 10 times, around the screenshot daemon being jetsammed — the
       observer perturbs the system. One relaunch keeps the scenario about the APP;
       a SECOND death escalates to a device reboot (the proven cure for a degraded
       capture daemon) — only on a device whose role allows it."""
    udid = entry["udid"]
    is_tv = entry.get("platform") == "tvos"
    atv = ATV(entry) if is_tv else None
    events = []

    def once():
        if atv is not None:
            if atv.available:
                if not atv.wake():
                    events.append("wake: TV did not report On")
            else:
                events.append(f"wake: unavailable ({atv.why_unavailable()})")
        ok, out = launch(udid, bundle, env)
        if not ok:
            if LOCKED_RX.search(out):
                raise LaunchFailed("device is LOCKED — installs work, launches do not. "
                                   "Owner step: unlock once (passcode off, Auto-Lock "
                                   "never, on a charger). " + out[-160:])
            if ASLEEP_RX.search(out):
                raise LaunchFailed("device is ASLEEP and could not be woken: " + out[-160:])
            raise LaunchFailed(out[-300:])
        time.sleep(settle)

    once()
    if atv is not None and probe_foreground:
        probe = Path(outdir) / "probe-foreground.png"
        ok, why = capture(udid, probe)
        home = frame_is_home_screen(probe) if ok else None
        if not ok:
            events.append(f"foreground probe: capture failed ({why})")
        elif home is None:
            events.append("foreground probe: UNKNOWN (OCR could not read the frame)")
        elif home:
            log("[launch] alive but the tvOS HOME SCREEN owns the glass — "
                "bringing the app forward")
            events.append("foreground probe: launched BACKGROUNDED")
            fronted = False
            if atv.launch_app(bundle):
                time.sleep(4)
                ok2, _ = capture(udid, probe)
                fronted = ok2 and frame_is_home_screen(probe) is False
            if not fronted:
                log("[launch] still backgrounded — wake + relaunch once")
                once()
    deaths = 0
    for wait in (0, 15, 15):
        if wait:
            time.sleep(wait)
        alive = app_alive(udid, executable)
        if alive is None:
            events.append("death probe: could not list processes")
            continue
        if alive:
            continue
        deaths += 1
        events.append(f"death {deaths} in the launch window")
        if deaths >= 2:
            if not allow_reboot or entry.get("role") not in ("test", "floor", "os-control"):
                log("[launch] died AGAIN — not rebooting (role or flag forbids it)")
                break
            log("[launch] died AGAIN — rebooting the device (capture-daemon "
                "degradation; the proven cure)")
            reboot(udid)
            deadline = time.time() + 240
            while time.time() < deadline:
                time.sleep(10)
                if app_pids(udid, executable) is not None:
                    break
            time.sleep(10)
        else:
            log("[launch] app died in the launch window — one retry")
        once()
    return events


# ── leave-as-found ───────────────────────────────────────────────────────────

def teardown(entry, found_power=None, executable=None):
    """Put the device back as it was found. Returns (ok, lines).

    Terminates the app and verifies from the device; for an Apple TV that was OFF
    when the run found it (found_power == "off"), powers it back off and reads the
    state back. A TV that was already on is left on — someone may be using it.
    A teardown is a STEP with an assertion, not an intention: a harness that touches
    someone's living room cleans up or reports that it could not."""
    lines, ok = [], True
    udid = entry.get("udid")
    if udid:
        t_ok, detail = terminate_verified(udid, executable)
        lines.append(f"app: {detail}")
        ok &= t_ok
    if entry.get("platform") == "tvos" and found_power == "off":
        atv = ATV(entry)
        p_ok, state = atv.turn_off_verified()
        lines.append(f"power: {state}" + ("" if p_ok else " — did NOT power off; check it by hand"))
        ok &= p_ok
    return ok, lines


def frame_is_home_screen(png, ocr_bin=None):
    """Does the tvOS HOME SCREEN own the glass? True / False / None.

    None means the probe could not see (OCR failed, frame unreadable) — NEVER a
    confident False. A home-screen probe that returned False on every frame shipped
    for weeks: ScreenOCR's allText entries are {text,x,y,w,h} DICTS, a defensive
    branch treated them as strings, raised, and a bare `except` returned False — so
    the foreground guard it existed to be never fired once, and nothing noticed,
    because "not the home screen" is what a working probe says most of the time.
    """
    if ocr_bin is None:
        ok, why = ensure_ocr()
        if not ok:
            print(f"[probe] {why} — foreground UNKNOWN")
            return None
        ocr_bin = str(app_config.OCR_BIN)
    try:
        r = sh([ocr_bin, str(png)], timeout=120)
        line = next((l for l in r.stdout.splitlines() if l.strip()), None)
        if line is None:
            print(f"[probe] OCR produced nothing for {Path(png).name} "
                  f"(rc={r.returncode}) — foreground UNKNOWN")
            return None
        d = json.loads(line)
    except (OSError, subprocess.SubprocessError, ValueError) as e:
        print(f"[probe] could not OCR {Path(png).name}: {e} — foreground UNKNOWN")
        return None
    entries = d.get("allText") or []
    if not entries:
        return None                     # a blank frame proves nothing either way
    text = " ".join(e.get("text", "") if isinstance(e, dict) else str(e) for e in entries)
    return bool(re.search(app_config.TVOS_HOME_RX, text, re.I))


def _main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("action", choices=["teardown", "power", "wake", "processes", "off"])
    ap.add_argument("--device", required=True, help="bench name (or raw UDID)")
    ap.add_argument("--owner-ok", action="store_true")
    ap.add_argument("--power-off", action="store_true",
                    help="teardown: also power an Apple TV off (default: only if "
                         "--found-off)")
    a = ap.parse_args()
    e = bench.require(a.device, allow_owner=a.owner_ok)
    if a.action == "power":
        print(ATV(e).power_state() or "unknown")
        return 0
    if a.action == "wake":
        return 0 if ATV(e).wake() else 1
    if a.action == "off":
        ok, st = ATV(e).turn_off_verified()
        print(f"power now: {st}")
        return 0 if ok else 1
    if a.action == "processes":
        print(app_pids(e["udid"]))
        return 0
    ok, lines = teardown(e, found_power="off" if a.power_off else None)
    for l in lines:
        print(f"  {l}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(_main())
