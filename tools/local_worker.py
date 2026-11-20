#!/usr/bin/env python3
"""A local Worker for the benches: `wrangler dev --local` on this Mac, reachable on the home network, never deployed.

    python3 tools/local_worker.py --port 8799            # runs until Ctrl-C; prints the base URLs
    from local_worker import LocalWorker                  # read_bench.py --local-worker, class_bench.py

What it is for (docs/DEVICE-HARNESSES.md "Read-room bench", "Class bench"): a protocol change can be run on the real
devices before it is deployed (read_bench T7 against `--base http://<this Mac>:<port>`, the devices pointed at it by the
DEBUG Worker-URL doors), and the teacher flows (T10-T12) can run with a test teacher, which production never has.

  * Fresh state every run: the local D1 lives in a scratch directory and the migrations are applied to it first.
  * READ_DIAG=1: the Worker prints a `[readdiag] worker ...` line per cursor-moving message (read-rooms.js engine.send).
  * Test sign-in only with --test-auth: a key pair is made for the run (tools/local_worker_keys.mjs), its public set
    passed as LOCAL_TEST_JWKS; the Worker refuses every public host while it carries one (worker/src/auth.js).
  * SESSION_SECRET is random per run. Nothing here touches Cloudflare: no deploy, no remote resource, no account.
"""
import argparse
import json
import os
import re
import secrets
import shutil
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
WORKER = REPO / "worker"


def lan_ip():
    for iface in ("en0", "en1"):
        r = subprocess.run(["ipconfig", "getifaddr", iface], capture_output=True, text=True)
        if r.stdout.strip():
            return r.stdout.strip()
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    finally:
        s.close()


class LocalWorker:
    def __init__(self, port=8799, scratch=None, test_auth=False, log=None):
        self.port = port
        self.scratch = Path(scratch or (Path(os.environ.get("TMPDIR", "/tmp")) / f"local-worker-{port}"))
        self.test_auth = test_auth
        self.log_path = Path(log) if log else self.scratch / "wrangler.log"
        self.proc = None
        self.private = None
        self.lines = []

    @property
    def local_base(self):
        return f"http://localhost:{self.port}"

    @property
    def lan_base(self):
        return f"http://{lan_ip()}:{self.port}"

    def start(self, timeout=120):
        shutil.rmtree(self.scratch, ignore_errors=True)
        self.scratch.mkdir(parents=True, exist_ok=True)
        persist = self.scratch / "state"
        env = dict(os.environ, CI="1", WRANGLER_SEND_METRICS="false")
        mig = subprocess.run(["npx", "--no-install", "wrangler", "d1", "migrations", "apply", "eardrama", "--local", "--persist-to", str(persist)],
                             cwd=WORKER, capture_output=True, text=True, timeout=180, env=env)
        if mig.returncode != 0:
            raise RuntimeError("migrations failed: " + (mig.stdout + mig.stderr)[-600:])
        vars_ = ["--var", f"SESSION_SECRET:{secrets.token_hex(32)}", "--var", "READ_DIAG:1"]
        if self.test_auth:
            pair = json.loads(subprocess.run(["node", str(REPO / "tools/local_worker_keys.mjs"), "pair"], capture_output=True, text=True, check=True).stdout)
            self.private = self.scratch / "bench-private.json"
            self.private.write_text(json.dumps(pair["private"]))
            vars_ += ["--var", "LOCAL_TEST_JWKS:" + json.dumps(pair["jwks"], separators=(",", ":"))]
        cmd = ["npx", "--no-install", "wrangler", "dev", "--local", "--ip", "0.0.0.0", "--port", str(self.port), "--persist-to", str(persist),
               "--test-scheduled", "--show-interactive-dev-session=false", *vars_]
        fh = self.log_path.open("w")
        self.proc = subprocess.Popen(cmd, cwd=WORKER, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1, env=env)

        def pump():
            for ln in self.proc.stdout:
                self.lines.append(ln.rstrip())
                fh.write(ln)
                fh.flush()
        threading.Thread(target=pump, daemon=True).start()
        t0 = time.time()
        while time.time() - t0 < timeout:
            if self.proc.poll() is not None:
                raise RuntimeError("wrangler dev exited: " + "\n".join(self.lines[-20:]))
            if any(re.search(r"Ready on", ln) for ln in self.lines):
                return self
            time.sleep(0.5)
        raise RuntimeError("wrangler dev not ready: " + "\n".join(self.lines[-20:]))

    def mint(self, sub):
        if not self.private:
            raise RuntimeError("start with test_auth=True to mint a token")
        return subprocess.run(["node", str(REPO / "tools/local_worker_keys.mjs"), "mint", str(self.private), sub], capture_output=True, text=True, check=True).stdout.strip()

    def diag(self):
        return [ln for ln in self.lines if "[readdiag]" in ln]

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        gone = self.proc is None or self.proc.poll() is not None
        if self.private and self.private.exists():
            self.private.unlink()
        return gone


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8799)
    ap.add_argument("--test-auth", action="store_true")
    a = ap.parse_args()
    w = LocalWorker(a.port, test_auth=a.test_auth).start()
    print(f"local Worker ready: {w.local_base} (this Mac), {w.lan_base} (home network); log {w.log_path}", flush=True)
    try:
        while w.proc.poll() is None:
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        print("stopped" if w.stop() else "STILL RUNNING", flush=True)


if __name__ == "__main__":
    sys.exit(main())
