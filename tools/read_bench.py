#!/usr/bin/env python3
"""Read-room bench (R3c section 8, T4-T9): one adult room on the deployed Worker, opened on every reachable real device.

    python3 tools/read_bench.py                       # every device it can reach, 100 presses, both transports
    python3 tools/read_bench.py --only pixel,web1 --presses 20
    python3 tools/read_bench.py --list                # the device table and what each one is for

Doctrine (docs/DEVICE-HARNESSES.md "Read-room bench"):
  * Real devices only. Never a simulator or emulator. The Mac app is driven only with --owner-ok.
  * The leader is tools/read_bench_leader.mjs: a protocol leader that times each press on the Worker's clock. Every
    device prints, with APP_READ_DIAG / appname_read_diag / ?readdiag=1, one line per cursor it drew: `lit <line> gen <g>
    at <local ms> offset <server minus local ms>`. Cursor delay is the device's lit instant (offset corrected) minus the
    press instant. Logs, not OCR; frames are for the eyes and for T9.
  * Deterministic: a fixed play, a fixed press schedule, no retry until pass. A device that cannot be reached is SKIP with
    the reason, never dropped from the report.
  * Muted, never Play or Listen Live, never sleep a device, TVs left on. Each app is terminated at the end and the device is
    asked whether it is gone. Leases held for the whole run (tools/devlease.py).
"""
import argparse
import contextlib
import json
import math
import os
import queue
import re
import shutil
import statistics
import subprocess
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_config  # noqa: E402
import apple_device as ad  # noqa: E402
import devlease  # noqa: E402
from webdrive import Browser  # noqa: E402

REPO = app_config.REPO
ADB = str(app_config.ADB)
PKG = app_config.ANDROID_PACKAGE_DEBUG
ACTIVITY = app_config.ANDROID_MAIN_ACTIVITY
BASE_URL = "https://eardrama-api.benwilkoff.workers.dev"
DOOR_SECONDS = "1500"
SP = Path(os.environ.get("READ_BENCH_TMP", "/tmp/read-bench"))

DEVICES = {
    # name: (kind, lease key, address, role, what it is)
    "pixel":  dict(kind="android", lease="android", serial="adb-3B211JEKB14516-4M5scf._adb-tls-connect._tcp", role="reader", what="Pixel 8a"),
    "gtv":    dict(kind="android", lease="gtv", serial="10.0.0.55:5555", role="screen", what="Google TV Streamer (10.0.0.55)", tv=True),
    "atv2":   dict(kind="android", lease="atv2", serial="10.0.0.139:5555", role="screen", what="Android TV (10.0.0.139)", tv=True),
    "iphone": dict(kind="apple", lease="iphone", udid="00008101-000339320188801E", role="reader", what="iPhone 12"),
    "duo":    dict(kind="apple", lease="duo", udid="00008160-001814623AA00036", role="reader", what="open iPhone Duo"),
    "ipad":   dict(kind="apple", lease="ipad", udid="00008103-0019388E3CF1001E", role="reader", what="iPad Pro 12.9"),
    "atv":    dict(kind="apple", lease="atv", udid="00008110-001979813499801E", pyatv_id="7A:3F:0C:4E:20:1E", address="10.0.0.223", role="screen", what="Apple TV 4K Ben Bedroom", tv=True),
    "web1":   dict(kind="web", lease=None, role="reader", what="Chrome headless, muted, reader"),
    "web2":   dict(kind="web", lease=None, role="reader", what="Chrome headless, muted, second reader"),
    "webpoll": dict(kind="web", lease=None, role="reader", what="Chrome headless, muted, WebSocket removed (polling)", polling=True),
    "webscr": dict(kind="web", lease=None, role="screen", what="Chrome headless, muted, shared screen"),
}

LIT = re.compile(r"\[readdiag\]\s+lit\s+(\S+)\s+gen\s+(\S+)\s+at\s+(\S+)\s+offset\s+(\S+)")
OFF = re.compile(r"\[readdiag\]\s+clock offset\s+(\S+)")
TRANS = re.compile(r"\[readdiag\]\s+transport\s+(\S+)")


def num(s):
    try:
        v = float(s)
        return None if math.isnan(v) else v
    except ValueError:
        return None


class Events:
    """Parsed [readdiag] lines for one device, stamped with the host's receive time."""

    def __init__(self):
        self.lit, self.transports, self.raw = [], [], []
        self.lock = threading.Lock()
        self.last_offset = None
        self.seen = set()

    def feed(self, text):
        for ln in text.splitlines():
            if "[readdiag]" not in ln:
                continue
            host = time.time() * 1000
            with self.lock:
                if ln in self.seen:
                    continue
                self.seen.add(ln)
                self.raw.append(ln.strip()[-200:])
                m = LIT.search(ln)
                if m:
                    off = num(m.group(4))
                    self.lit.append(dict(line=m.group(1), gen=num(m.group(2)), at=num(m.group(3)), offset=off, host=host))
                    continue
                m = OFF.search(ln)
                if m and num(m.group(1)) is not None:
                    self.last_offset = num(m.group(1))
                    self.fill_offsets()
                    continue
                m = TRANS.search(ln)
                if m:
                    self.transports.append((host, m.group(1)))

    def fill_offsets(self):
        # An early lit can precede the first ping; it takes the first offset measured afterwards (same device, same clock).
        for e in self.lit:
            if e["offset"] is None and self.last_offset is not None:
                e["offset"] = self.last_offset

    def snapshot(self):
        with self.lock:
            self.fill_offsets()
            return [dict(e) for e in self.lit]


class Leader:
    def __init__(self, base, script):
        self.p = subprocess.Popen(["node", str(REPO / "tools/read_bench_leader.mjs"), "--base", base, "--script", script],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
        self.q = queue.Queue()
        threading.Thread(target=self._pump, daemon=True).start()
        self.ready = self.recv(60)
        if not self.ready or not self.ready.get("ready"):
            raise RuntimeError(f"leader did not open a room: {self.ready}")
        self.code = self.ready["code"]

    def _pump(self):
        for ln in self.p.stdout:
            with contextlib.suppress(ValueError):
                self.q.put(json.loads(ln))

    def recv(self, timeout):
        try:
            return self.q.get(timeout=timeout)
        except queue.Empty:
            return None

    def cmd(self, c, timeout=60):
        self.p.stdin.write(json.dumps(c) + "\n")
        self.p.stdin.flush()
        return self.recv(timeout)

    def close(self):
        with contextlib.suppress(Exception):
            self.cmd({"cmd": "end"}, 10)
        with contextlib.suppress(Exception):
            self.p.stdin.close()
            self.p.wait(timeout=5)
        if self.p.poll() is None:
            self.p.kill()


# --------------------------------------------------------------------------- devices

class Device:
    def __init__(self, name, spec):
        self.name, self.spec = name, spec
        self.ev = Events()
        self.skip = None
        self.note = []

    def preflight(self):
        return None

    def start(self, code, screen=False):
        raise NotImplementedError

    def frame(self, path):
        return False

    def stop(self):
        return True, ""


class AndroidDevice(Device):
    def adb(self, *a, timeout=60):
        return subprocess.run([ADB, "-s", self.spec["serial"], *a], capture_output=True, text=True, timeout=timeout)

    def preflight(self):
        s = self.spec["serial"]
        out = subprocess.run([ADB, "devices"], capture_output=True, text=True, timeout=30).stdout
        if not re.search(rf"^{re.escape(s)}\s+device", out, re.M):
            subprocess.run([ADB, "connect", s], capture_output=True, text=True, timeout=30)
            out = subprocess.run([ADB, "devices"], capture_output=True, text=True, timeout=30).stdout
            if not re.search(rf"^{re.escape(s)}\s+device", out, re.M):
                return "adb cannot reach it"
        self.adb("shell", "svc", "power", "stayon", "true")
        self.adb("shell", "input", "keyevent", "KEYCODE_WAKEUP")
        time.sleep(1)
        self.adb("shell", "wm", "dismiss-keyguard")
        if self.adb("shell", "pm", "list", "packages", PKG).stdout.strip() == "":
            return f"{PKG} not installed"
        return None

    def start(self, code, screen=False):
        self.adb("logcat", "-c")
        self.log = subprocess.Popen([ADB, "-s", self.spec["serial"], "logcat", "-v", "brief", "System.out:I", "*:S"],
                                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
        threading.Thread(target=lambda: [self.ev.feed(l) for l in self.log.stdout], daemon=True).start()
        self.adb("shell", "am", "force-stop", PKG)
        time.sleep(0.8)
        args = ["shell", "am", "start", "-n", f"{PKG}/{ACTIVITY}",
                "--ez", "appname_skip_onboard", "true", "--ez", "appname_mute", "true", "--ei", "appname_door_seconds", DOOR_SECONDS,
                "--ez", "appname_read_diag", "true", "--es", "appname_start_read_room", code]
        if screen:
            args += ["--ez", "appname_start_screen", "true"]
        else:
            args += ["--es", "appname_start_seat", f"bench-{self.name}"]  # a DEBUG door: any value joins an adult room without the form
        r = self.adb(*args, timeout=90)
        if "Error" in r.stdout + r.stderr or "Exception" in r.stdout + r.stderr:
            return f"launch failed: {(r.stdout + r.stderr)[-200:]}"
        return None

    def foreground(self):
        r = self.adb("shell", "dumpsys", "window", "windows")
        m = re.search(r"mCurrentFocus=.*", r.stdout)
        return m.group(0) if m else ""

    def frame(self, path):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        r = subprocess.run([ADB, "-s", self.spec["serial"], "exec-out", "screencap", "-p"], capture_output=True, timeout=60)
        if r.returncode == 0 and len(r.stdout) > 1000:
            Path(path).write_bytes(r.stdout)
            return True
        return False

    def resync(self):
        """Wireless adb dies with the radio and takes the streaming logcat with it; the device kept its log, so read it back."""
        for _ in range(20):
            if "device" in subprocess.run([ADB, "-s", self.spec["serial"], "get-state"], capture_output=True, text=True).stdout:
                break
            subprocess.run([ADB, "connect", self.spec["serial"]], capture_output=True, text=True, timeout=30)
            time.sleep(3)
        self.ev.feed(self.adb("logcat", "-d", "-v", "brief", "System.out:I", "*:S", timeout=60).stdout)

    def drop(self, seconds):
        """Airplane mode for `seconds`, switched back ON THE DEVICE: wireless adb dies with the radio, so the restore must not
        depend on the host (a phone left in airplane mode is the owner's problem)."""
        sh = f"nohup sh -c 'cmd connectivity airplane-mode enable; sleep {seconds}; cmd connectivity airplane-mode disable' >/dev/null 2>&1 &"
        self.adb("shell", sh, timeout=30)

    def stop(self):
        self.adb("shell", "am", "force-stop", PKG, timeout=45)
        time.sleep(1.5)
        for _ in range(3):
            pid = self.adb("shell", "pidof", PKG, timeout=45).stdout.strip()
            if not pid:
                break
            time.sleep(1.5)
        with contextlib.suppress(Exception):
            self.log.terminate()
        return (not pid), ("gone (pidof empty)" if not pid else f"STILL RUNNING pid {pid}")


class AppleDevice(Device):
    def preflight(self):
        r = ad.devicectl("device", "info", "details", "--device", self.spec["udid"], timeout=60)
        txt = r.stdout + r.stderr
        if r.returncode != 0:
            return "devicectl cannot reach it: " + txt.strip()[-120:]
        if self.spec.get("pyatv_id"):
            atv = ad.ATV({"name": self.name, "address": self.spec["address"], "pyatv_id": self.spec["pyatv_id"]})
            if not atv.wake():
                return "Apple TV would not wake over Companion"
        return None

    def start(self, code, screen=False):
        env = {"APP_SKIP_ONBOARD": "1", "APP_MUTE": "1", "APP_DOOR_SECONDS": DOOR_SECONDS, "APP_READ_DIAG": "1", "APP_START_READ_ROOM": code}
        if screen:
            env["APP_START_SCREEN"] = "1"
        else:
            env["APP_START_SEAT"] = f"bench-{self.name}"
        cmd = ["xcrun", "devicectl", "device", "process", "launch", "--device", self.spec["udid"], "--terminate-existing", "--console",
               "-e", json.dumps(env), app_config.APPLE_BUNDLE_ID]
        e = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
        self.console = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1, env=e)
        self.head = []

        def pump():
            for ln in self.console.stdout:
                if len(self.head) < 40:
                    self.head.append(ln.rstrip())
                self.ev.feed(ln)
        threading.Thread(target=pump, daemon=True).start()
        for _ in range(40):
            time.sleep(1)
            h = "\n".join(self.head)
            if "Launched application" in h or "[readdiag]" in h:
                time.sleep(3)
                p = SP / f"{self.name}-probe.png"
                if ad.capture(self.spec["udid"], p)[0] and p.stat().st_size < 20000:
                    return "frame is black: the screen is off or locked (blind instrument)"
                return None
            if self.console.poll() is not None:
                break
        h = "\n".join(self.head)
        if "Locked" in h or "locked" in h:
            return "device is locked (passcode); needs the owner to unlock"
        return "launch did not confirm: " + h[-200:]

    def frame(self, path):
        ok, why = ad.capture(self.spec["udid"], path)
        return ok

    def stop(self):
        with contextlib.suppress(Exception):
            self.console.terminate()
        ok, detail = ad.terminate_verified(self.spec["udid"])
        return ok, detail


class WebDevice(Device):
    PORT = [9701]
    SITE = None  # set by main(): the local static server serving this working tree

    def preflight(self):
        if not Path("/Applications/Google Chrome.app").exists():
            return "no Chrome"
        return None

    def start(self, code, screen=False):
        polling = bool(self.spec.get("polling"))
        self.polling = polling
        port = WebDevice.PORT[0]
        WebDevice.PORT[0] += 1
        prof = SP / f"chrome-{self.name}-{port}"
        shutil.rmtree(prof, ignore_errors=True)
        self.b = Browser(port=port, profile=str(prof), headless=True)
        raw_call, lock = self.b.ws.call, threading.RLock()

        def locked(*a, **k):
            with lock:
                return raw_call(*a, **k)
        self.b.ws.call = locked
        hook = r"""(() => {
          window.__logs = []; const l = console.log;
          console.log = (...a) => { if (a[0] === '[readdiag]') window.__logs.push(a.join(' ')); l.apply(console, a); };
          Object.defineProperty(navigator, 'mediaDevices', { configurable: true, value: { enumerateDevices: async () => [],
            async getUserMedia() { const ctx = new AudioContext(); const osc = ctx.createOscillator(); osc.frequency.value = 160;
              const g = ctx.createGain(); g.gain.value = 0.0005; const dest = ctx.createMediaStreamDestination(); osc.connect(g); g.connect(dest);
              osc.start(); await ctx.resume(); window.__micGain = g; window.__micOpens = (window.__micOpens || 0) + 1; window.__micLog = (window.__micLog || []); window.__micLog.push(Date.now()); return dest.stream; } } });
          window.confirm = () => true;
          POLL
        })();""".replace("POLL", "window.WebSocket = undefined;" if polling else "")
        self.b.ws.call("Page.addScriptToEvaluateOnNewDocument", {"source": hook})
        self.b.ws.call("Emulation.setDeviceMetricsOverride", {"width": 600, "height": 844, "deviceScaleFactor": 1, "mobile": False} if not screen else
                       {"width": 1280, "height": 720, "deviceScaleFactor": 1, "mobile": False})
        url = f"{WebDevice.SITE}/?read-room={code}&readdiag=1&mute=1" + ("&screen=1" if screen else "")
        time.sleep(2)  # a cold profile's first navigation is lost if it races Chrome's own about:blank
        self.b.goto(url, settle=3)
        ok = False
        for i in range(100):
            if i == 30:
                self.note.append("page blank after 15 s on a cold profile: navigated once more")
                self.b.goto(url, settle=3)
            try:
                ok = self.b.js("(()=>{const b=document.querySelector('.rr-go'); if(!b) return false; b.click(); return true})()")
            except Exception:
                ok = False
            if ok:
                break
            time.sleep(0.5)
        if not ok:
            return "no Join button on the page: " + (self.b.text()[:120] if self.b else "")
        self.pump_stop = False

        def pump():
            seen = 0
            while not self.pump_stop:
                try:
                    logs = self.b.js("window.__logs") or []
                except Exception:
                    time.sleep(0.2)
                    continue
                if len(logs) > seen:
                    self.ev.feed("\n".join(logs[seen:]))
                    seen = len(logs)
                time.sleep(0.05)
        threading.Thread(target=pump, daemon=True).start()
        return None

    def frame(self, path):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        return self.b.screenshot(str(path))

    def stop(self):
        self.pump_stop = True
        time.sleep(0.2)
        with contextlib.suppress(Exception):
            self.b.close()
        for _ in range(10):
            r = subprocess.run(["pgrep", "-f", f"remote-debugging-port={self.b.port}"], capture_output=True, text=True)
            if not r.stdout.strip():
                break
            time.sleep(0.5)
        return (not r.stdout.strip()), ("chrome gone" if not r.stdout.strip() else f"chrome still running {r.stdout.split()}")


MAKE = {"android": AndroidDevice, "apple": AppleDevice, "web": WebDevice}


# --------------------------------------------------------------------------- numbers

def pct(xs, p):
    if not xs:
        return None
    s = sorted(xs)
    return s[min(len(s) - 1, max(0, math.ceil(p / 100 * len(s)) - 1))]


def delays(presses, lits):
    """Per press: this device's lit instant (server clock) minus the press instant. The first lit at or after the press with
    the pressed line id; presses nobody lit are `missing`."""
    by_line = {}
    for e in lits:
        by_line.setdefault(e["line"], []).append(e)
    out, missing = [], 0
    for p in presses:
        cands = [e for e in by_line.get(p["line"], []) if e["at"] is not None and e["offset"] is not None and e["at"] + e["offset"] >= p["press_server_ms"] - 50]
        if not cands:
            missing += 1
            continue
        e = min(cands, key=lambda e: e["at"] + e["offset"])
        out.append(e["at"] + e["offset"] - p["press_server_ms"])
    return out, missing


def summarize(ds, missing, n):
    return dict(n=n, got=len(ds), missing=missing, p50=pct(ds, 50), p95=pct(ds, 95), max=max(ds) if ds else None, min=min(ds) if ds else None,
                mean=round(statistics.mean(ds), 1) if ds else None)


# --------------------------------------------------------------------------- run

def serve_site():
    import http.server
    import socketserver

    class H(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *a, **k):
            super().__init__(*a, directory=str(REPO), **k)

        def translate_path(self, path):
            # The deployed site serves the castable plays under /data; the working tree keeps them in catalog/.
            if path.split("?")[0] == "/data/plays/castable-scripts.json":
                path = "/catalog/plays/castable-scripts.json"
            return super().translate_path(path)

        def log_message(self, *a):
            pass
    socketserver.TCPServer.allow_reuse_address = True
    srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, f"http://127.0.0.1:{srv.server_address[1]}"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--only", help="comma list of device names")
    ap.add_argument("--skip", help="comma list of device names to leave out")
    ap.add_argument("--base", default=BASE_URL, help="the Worker (the deployed one by default; `wrangler dev` on the LAN works too)")
    ap.add_argument("--script", default="gut-7364")
    ap.add_argument("--presses", type=int, default=100)
    ap.add_argument("--interval-ms", type=int, default=1500)
    ap.add_argument("--poll-presses", type=int, default=100)
    ap.add_argument("--no-poll", action="store_true")
    ap.add_argument("--owner-ok", action="store_true", help="allow the Mac app (not implemented here: the owner's Mac is never driven)")
    ap.add_argument("--tests", default="T5,T4,T4poll,T6,T8,T9,T7", help="which tests to run")
    ap.add_argument("--out", default=str(REPO / "docs/research/data/t7"))
    ap.add_argument("--frames", default=str(REPO / "docs/research/design/img/t7"))
    ap.add_argument("--tag", default=time.strftime("%Y%m%d-%H%M%S"))
    a = ap.parse_args()
    if a.list:
        for k, v in DEVICES.items():
            print(f"{k:8} {v['kind']:8} {v['role']:7} lease={v['lease']} {v['what']}")
        return 0
    names = [n for n in (a.only.split(",") if a.only else DEVICES) if n not in (a.skip.split(",") if a.skip else [])]
    tests = set(a.tests.split(","))
    out, frames = Path(a.out), Path(a.frames)
    out.mkdir(parents=True, exist_ok=True)
    frames.mkdir(parents=True, exist_ok=True)
    SP.mkdir(parents=True, exist_ok=True)
    report = dict(tag=a.tag, base=a.base, script=a.script, devices={}, tests={})

    srv, site = serve_site()
    WebDevice.SITE = site
    report["site"] = site

    with contextlib.ExitStack() as stack:
        devs = []
        for n in names:
            spec = DEVICES[n]
            d = MAKE[spec["kind"]](n, spec)
            if spec["lease"]:
                try:
                    stack.enter_context(devlease.hold([spec["lease"]], task="read-bench", ttl=3600))
                except RuntimeError as e:
                    d.skip = f"lease busy: {e}"
            if not d.skip:
                try:
                    why = d.preflight()
                except Exception as e:  # noqa: BLE001
                    why = f"preflight error: {e}"
                if why:
                    d.skip = why
            report["devices"][n] = dict(what=spec["what"], role=spec["role"], skip=d.skip)
            print(f"[bench] {n:8} {'SKIP: ' + d.skip if d.skip else 'ok'}", flush=True)
            if not d.skip:
                devs.append(d)

        leader = Leader(a.base, a.script)
        code = leader.code
        report["room"] = dict(code=code, transport=leader.ready.get("transport"), leader_socket=leader.ready.get("socket"), leader_offset=leader.ready.get("offset"))
        print(f"[bench] room {code} (leader socket={leader.ready.get('socket')})", flush=True)
        started = []
        try:
            # ---- T5: join on every device
            for d in devs:
                is_screen = d.spec["role"] == "screen"
                why = d.start(code, screen=is_screen) if not isinstance(d, WebDevice) else d.start(code, screen=is_screen)
                if why:
                    d.skip = why
                    report["devices"][d.name]["skip"] = why
                    print(f"[bench] {d.name:8} SKIP at launch: {why}", flush=True)
                    d.stop()
                else:
                    started.append(d)
            time.sleep(8)
            snap = (leader.cmd({"cmd": "snapshot"}) or {}).get("snapshot") or {}
            members = snap.get("members") or []
            t5 = dict(members=[dict(role=m.get("role"), present=m.get("present"), name=m.get("name")) for m in members], devices={})
            for d in started:
                lits = d.ev.snapshot()
                joined = bool(lits) or bool(d.ev.transports)
                t5["devices"][d.name] = dict(joined_by_log=joined, transports=[t for _, t in d.ev.transports], first_lit=(lits[0]["line"] if lits else None), log_tail=d.ev.raw[-3:])
                if not joined:
                    print(f"[bench] {d.name:8} no [readdiag] after join", flush=True)
            t5["room_members"] = len(members)
            t5["started"] = len(started)
            report["tests"]["T5"] = t5
            for d in started:
                d.frame(frames / f"{a.tag}-{d.name}-T5-joined.png")

            # ---- T4 socket
            if "T4" in tests:
                r = leader.cmd({"cmd": "press", "n": a.presses, "interval_ms": a.interval_ms, "via": "socket"}, timeout=a.presses * (a.interval_ms / 1000 + 6) + 60)
                presses = (r or {}).get("presses") or []
                time.sleep(3)
                t4 = dict(presses=len(presses), leader_ack_ms=summarize([p["ack_local_ms"] - p["press_local_ms"] for p in presses if p.get("ack_local_ms")], 0, len(presses)), devices={})
                for d in started:
                    lits = d.ev.snapshot()
                    ds, miss = delays(presses, lits)
                    t4["devices"][d.name] = dict(transport=(d.ev.transports[-1][1] if d.ev.transports else None), **summarize(ds, miss, len(presses)))
                    (out / f"{a.tag}-T4-socket-{d.name}.json").write_text(json.dumps(dict(delays_ms=ds, lit=lits[-len(presses):]), indent=1))
                (out / f"{a.tag}-T4-presses.json").write_text(json.dumps(presses, indent=1))
                report["tests"]["T4"] = t4
                for k, v in t4["devices"].items():
                    print(f"[T4 socket] {k:8} {v}", flush=True)
                for d in started:
                    d.frame(frames / f"{a.tag}-{d.name}-T4-after.png")

            # ---- T9: shared screens and presence (frames only; read by eye)
            if "T9" in tests:
                snap = (leader.cmd({"cmd": "snapshot"}) or {}).get("snapshot") or {}
                report["tests"]["T9"] = dict(cursor=snap.get("cursor"), members=len(snap.get("members") or []), roles=[m.get("role") for m in snap.get("members") or []],
                                             frames=[f"{a.tag}-{d.name}-T4-after.png" for d in started if d.spec["role"] == "screen"])

            # ---- T6: follow, stop following, Back to the line (web readers: DOM; the Pixel by uiautomator text)
            if "T6" in tests:
                t6 = {}
                for d in started:
                    if isinstance(d, WebDevice) and d.spec["role"] == "reader" and not d.spec.get("polling"):
                        js = lambda e: d.b.js(e)  # noqa: E731
                        t6[d.name] = {"following_at_start": js("(()=>{const b=document.querySelector('.rd-back-line'); return !!b && b.hidden})()")}
                        js("(()=>{const e=document.scrollingElement; window.scrollTo(0, e.scrollHeight); for (const t of ['wheel','touchstart','pointerdown']) document.dispatchEvent(new Event(t, {bubbles:true})); return 1})()")
                        time.sleep(1.5)
                        t6[d.name]["back_button_shown_after_scroll"] = js("(()=>{const b=document.querySelector('.rd-back-line'); return !!b && !b.hidden})()")
                        d.frame(frames / f"{a.tag}-{d.name}-T6-away.png")
                        leader.cmd({"cmd": "press", "n": 2, "interval_ms": 1200, "via": "socket"}, timeout=30)
                        js("(()=>{const b=document.querySelector('.rd-back-line'); if(b && !b.hidden) b.click(); return 1})()")
                        time.sleep(1.5)
                        t6[d.name]["following_after_back"] = js("(()=>{const b=document.querySelector('.rd-back-line'); return !!b && b.hidden})()")
                        t6[d.name]["lit_line_in_view"] = js("(()=>{const l=document.querySelector('.rd-lit, [aria-current=true], .rd-now'); if(!l) return null; const r=l.getBoundingClientRect(); return r.bottom>0 && r.top<innerHeight})()")
                        d.frame(frames / f"{a.tag}-{d.name}-T6-back.png")
                report["tests"]["T6"] = t6
                print(f"[T6] {t6}", flush=True)

            # ---- T8: drop and rejoin (the Pixel's radio, the web twin's network)
            if "T8" in tests:
                t8 = {}
                for d in started:
                    if isinstance(d, AndroidDevice) and not d.spec.get("tv"):
                        before = len(d.ev.snapshot())
                        d.drop(25)
                        t_drop = time.time()
                        time.sleep(3)
                        r = leader.cmd({"cmd": "press", "n": 6, "interval_ms": 2500, "via": "socket"}, timeout=60)
                        last = (r or {}).get("presses", [])[-1:] or [{}]
                        d.frame(frames / f"{a.tag}-{d.name}-T8-offline.png")
                        time.sleep(max(0, 25 - (time.time() - t_drop)) + 20)
                        d.resync()
                        lits = d.ev.snapshot()
                        got_last = any(e["line"] == last[0].get("line") for e in lits)
                        t8[d.name] = dict(lit_events_before=before, lit_events_after=len(lits), reached_last_line_after_rejoin=got_last, last_line=last[0].get("line"),
                                          transports=[t for _, t in d.ev.transports][-3:])
                        d.frame(frames / f"{a.tag}-{d.name}-T8-rejoined.png")
                    elif isinstance(d, WebDevice) and not d.spec.get("role") == "screen":
                        d.b.ws.call("Network.enable")
                        d.b.ws.call("Network.emulateNetworkConditions", {"offline": True, "latency": 0, "downloadThroughput": -1, "uploadThroughput": -1})
                        time.sleep(2)
                        r = leader.cmd({"cmd": "press", "n": 4, "interval_ms": 2000, "via": "socket"}, timeout=60)
                        last = (r or {}).get("presses", [])[-1:] or [{}]
                        d.frame(frames / f"{a.tag}-{d.name}-T8-offline.png")
                        txt_off = d.b.text()[:300]
                        d.b.ws.call("Network.emulateNetworkConditions", {"offline": False, "latency": 0, "downloadThroughput": -1, "uploadThroughput": -1})
                        time.sleep(25)
                        lits = d.ev.snapshot()
                        t8[d.name] = dict(offline_text=txt_off, reached_last_line_after_rejoin=any(e["line"] == last[0].get("line") for e in lits), last_line=last[0].get("line"),
                                          transports=[t for _, t in d.ev.transports][-3:])
                        d.frame(frames / f"{a.tag}-{d.name}-T8-rejoined.png")
                        break
                report["tests"]["T8"] = t8
                print(f"[T8] {t8}", flush=True)
        finally:
            leader.close()
            td = {}
            for d in started + [x for x in devs if x not in started]:
                try:
                    ok, detail = d.stop()
                except Exception as e:  # noqa: BLE001
                    ok, detail = False, f"stop error {e}"
                td[d.name] = dict(gone=ok, detail=detail)
                print(f"[bench] teardown {d.name:8} {'OK ' if ok else 'FAIL '}{detail}", flush=True)
            report["teardown"] = td
            (out / f"{a.tag}-report.json").write_text(json.dumps(report, indent=1))
            srv.shutdown()
    print(f"[bench] report {out / (a.tag + '-report.json')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
