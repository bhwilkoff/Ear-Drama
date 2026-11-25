#!/usr/bin/env python3
"""reports.yml's script against a stub OIDC server, Worker and GitHub: the one issue, its emails, and its privacy.

    python3 tools/test_reports_issue.py [-v]

Each step runs the shipped script as its own process, as the workflow does.
"""
import http.server
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import threading
import urllib.parse

HERE = pathlib.Path(__file__).resolve().parent
VERBOSE = "-v" in sys.argv
ORIGIN_TOKEN = "stub-oidc-jwt"
PLANT = ["Zelda Plantperson", "PLANTED-NOTE-7", "harassment", "Hamlet", "2026-11-24", "take-9"]
failed = []


class Stub:
    def __init__(self):
        self.open, self.worker, self.oidc, self.extra = 0, [], [], {}
        self.issues, self.comments, self.calls, self.assign = [], [], [], True
        stub = self

        class H(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def go(self):
                body = self.rfile.read(int(self.headers.get("content-length") or 0))
                code, out = stub.answer(self.command, self.path, self.headers, json.loads(body) if body else None)
                data = json.dumps(out).encode()
                self.send_response(code)
                self.send_header("content-length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            do_GET = do_POST = do_PATCH = go

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.base = f"http://127.0.0.1:{self.server.server_port}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def answer(self, method, path, headers, body):
        u = urllib.parse.urlsplit(path)
        q = dict(urllib.parse.parse_qsl(u.query))
        if u.path == "/oidc":
            if q.get("audience") != self.base or headers["authorization"] != "bearer request-token":
                return 401, {}
            return (self.oidc.pop(0), {}) if self.oidc else (200, {"value": ORIGIN_TOKEN})
        if u.path == "/v1/operator/reports/count":
            self.calls.append(("COUNT", path))
            if headers["authorization"] != "Bearer " + ORIGIN_TOKEN:
                return 403, {}
            return (self.worker.pop(0), {"detail": PLANT}) if self.worker else (200, {"open": self.open, **self.extra})
        m = re.fullmatch(r"/repos/bhwilkoff/Ear-Drama/issues(?:/(\d+)(/comments)?)?", u.path)
        if not m or headers["authorization"] != "Bearer gh-token":
            return 404, {}
        if method == "GET":
            page = int(q.get("page", 1))
            rows = [i for i in reversed(self.issues) if i["state"] == q["state"] and i["user"]["login"] == q["creator"]]
            return 200, rows[(page - 1) * 100:page * 100]
        self.calls.append((method, path))
        if method == "POST" and m[2]:
            self.comments.append((int(m[1]), body["body"]))
            return 201, {}
        if method == "POST":
            return 201, self.issue(body["title"], body["body"], assignees=body["assignees"] if self.assign else [])
        i = next(x for x in self.issues if x["number"] == int(m[1]))
        i.update({k: v for k, v in body.items() if k in ("title", "body", "state")})
        return 200, i

    def issue(self, title, body, login="github-actions[bot]", assignees=(), pull=False):
        i = {"number": len(self.issues) + 1, "title": title, "body": body, "state": "open", "user": {"login": login},
             "assignees": [{"login": a} for a in assignees], **({"pull_request": {}} if pull else {})}
        self.issues.append(i)
        return i

    def run(self, n=None, script=HERE / "reports_issue.py"):
        if n is not None:
            self.open = n
        env = {"PATH": os.environ["PATH"], "REPORTS_ORIGIN": self.base, "GITHUB_API_URL": self.base, "REPORTS_WAITS": "0,0",
               "ACTIONS_ID_TOKEN_REQUEST_URL": self.base + "/oidc?v=1", "ACTIONS_ID_TOKEN_REQUEST_TOKEN": "request-token",
               "GH_TOKEN": "gh-token", "GITHUB_REPOSITORY": "bhwilkoff/Ear-Drama", "GITHUB_REPOSITORY_OWNER": "bhwilkoff"}
        r = subprocess.run([sys.executable, str(script)], env=env, capture_output=True, text=True, timeout=60)
        if VERBOSE:
            print(f"  count {self.open}: exit {r.returncode} | {r.stdout.strip().splitlines()[-1:]} {r.stderr.strip()[:120]}")
        return r

    def live(self):
        return [i for i in self.issues if i["state"] == "open"]

    def public(self):
        return json.dumps([self.issues, self.comments])


def check(name, ok):
    if not ok:
        failed.append(name)
        print("FAIL", name)


# 0, 1, 2, 2, 0: opened and assigned, commented once, left alone, closed.
s = Stub()
r = s.run(0)
check("0: green, and it says it asked", r.returncode == 0 and "[reports] asked: open=0, issue no issue needed" in r.stdout)
check("0: nothing written", s.issues == [] and [c for c in s.calls if c[0] != "COUNT"] == [])
r = s.run(1)
check("1: opened, assigned to the owner", r.returncode == 0 and [(i["title"], i["assignees"]) for i in s.live()] == [("1 report is waiting", [{"login": "bhwilkoff"}])])
check("1: mentions the owner and nobody else", re.findall(r"@[\w-]+", s.issues[0]["body"]) == ["@bhwilkoff"])
check("1: no comment, the opening is the email", s.comments == [])
s.run(2)
check("2: one comment, the title follows", s.comments == [(1, "@bhwilkoff: 2 reports are waiting.")] and s.live()[0]["title"] == "2 reports are waiting")
calls = len(s.calls)
s.run(2)
check("2 again: nothing written", [c for c in s.calls[calls:] if c[0] != "COUNT"] == [] and len(s.comments) == 1)
s.run(0)
check("0: closed, no comment", s.live() == [] and len(s.comments) == 1 and len(s.issues) == 1)
s.run(0)
check("0 again: nothing", len(s.issues) == 1)
check("the Worker was asked once a run", len([c for c in s.calls if c[0] == "COUNT"]) == 6)

# Falls without an email; a rise after a fall sends one; a closed issue is not reused.
s.run(3)
check("a new wait opens a new issue", [i["number"] for i in s.live()] == [2])
s.run(1)
check("a fall edits and does not comment", s.live()[0]["title"] == "1 report is waiting" and len(s.comments) == 1)
s.run(2)
check("a rise after a fall comments", len(s.comments) == 2)
s.live()[0]["state"] = "closed"
s.run(2)
check("closed by hand while reports wait: one new issue", len(s.live()) == 1 and len(s.issues) == 3)

# Races and strangers.
s = Stub()
s.issue("x", "<!-- reports-waiting:9 -->", login="stranger")
s.issue("bot's other issue", "nothing here")
s.issue("a pull request", "<!-- reports-waiting:9 -->", pull=True)
s.run(1)
check("a stranger's marker, another bot issue and a pull request are not ours", len(s.live()) == 4)
for _ in range(2):
    s.issue("1 report is waiting", "<!-- reports-waiting:1 -->")
s.run(1)
mine = [i for i in s.live() if "reports-waiting" in i["body"] and i["user"]["login"].endswith("[bot]") and "pull_request" not in i]
check("duplicates are closed, the first kept", [i["number"] for i in mine] == [4])
s = Stub()
for k in range(120):
    s.issue(f"noise {k}", "other", login="github-actions[bot]")
s.issues[0]["body"] = "<!-- reports-waiting:1 -->"
s.run(1)
check("an issue past the first page is found, not opened again", len(s.issues) == 120)

# Failing: a blip is retried in the step, a refusal is red, and neither leaks the answer's body.
s = Stub()
s.worker, s.oidc = [503, 429], [503]
check("a blip is waited out", s.run(1).returncode == 0 and len(s.live()) == 1)
for code in (403, 404):
    s.worker = [code]
    r = s.run(0)
    check(f"{code} is red", r.returncode != 0 and f"HTTP {code}" in r.stderr)
    check(f"{code}: the open issue is left alone", len(s.live()) == 1)
s.worker = [503, 503, 503]
check("an outage past the retries is red", s.run(0).returncode != 0 and len(s.live()) == 1)
for bad in ("1", None, -1, True, 1.5):
    s.extra = {"open": bad}
    check(f"an answer of {bad!r} is red", s.run(1).returncode != 0)
s.extra = {}
s.assign = False
s.run(0)
r = s.run(1)
check("an issue GitHub did not assign is said", "::warning::" in r.stdout)

# Privacy: the Worker's answer carries more than a count, and none of it is public.
s = Stub()
s.extra = {"who": PLANT[0], "note": PLANT[1], "reason": PLANT[2], "play": PLANT[3], "date": PLANT[4], "take": PLANT[5]}
out = "".join(r.stdout.replace(f"::add-mask::{ORIGIN_TOKEN}", "") + r.stderr for r in (s.run(1), s.run(2)))
s.worker = [403]
r = s.run(2)
out += r.stdout.replace(f"::add-mask::{ORIGIN_TOKEN}", "") + r.stderr
check("nothing but the number is public", not [p for p in PLANT + [ORIGIN_TOKEN] if p in s.public() + out])
check("the issue is these words", s.issues[0]["body"] == "@bhwilkoff: 2 reports are waiting.\n\nRead and answer on your Mac: `python3 tools/reports.py list` (`docs/runbooks/reports.md`).\n\n<!-- reports-waiting:2 -->")

# Negative controls: a leak, a comment every hour, and a duplicate must each be caught.
src = (HERE / "reports_issue.py").read_text()
c = Stub()
c.extra = {"note": PLANT[1]}
with tempfile.TemporaryDirectory() as d:
    (pathlib.Path(d) / "net_retry.py").write_text((HERE / "net_retry.py").read_text())
    leaky = pathlib.Path(d) / "leaky.py"
    at = 'n = ask(ORIGIN + "/v1/operator/reports/count", {"Authorization": "Bearer " + oidc()}).get("open")'
    check("the control still finds its line", src.count(at) == 1)
    leaky.write_text(src.replace(at, at.replace('.get("open")', "") + '; print(n); n = n["open"]'))
    r = c.run(1, leaky)
    check("CONTROL: a leak put in place is seen", PLANT[1] in r.stdout)
    noisy = pathlib.Path(d) / "noisy.py"
    noisy.write_text(src.replace("    if n == before:\n        return \"unchanged\"\n", "").replace("    if n > before:\n", "    if n >= before:\n"))
    c.run(1, noisy)
    check("CONTROL: a comment at an unchanged count is seen", len(c.comments) == 1)
    twice = pathlib.Path(d) / "twice.py"
    twice.write_text(src.replace("    mine = ours()\n", "    mine = []\n"))
    c.run(1, twice)
    check("CONTROL: a second issue is seen", len(c.live()) == 2)

print("FAIL" if failed else "PASS", "reports issue:", f"{len(failed)} failed" if failed else "every rule")
sys.exit(1 if failed else 0)
