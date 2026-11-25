#!/usr/bin/env python3
import io
import os
import socket
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import net_retry as N

GET = urllib.request.Request("https://example.test/a")
POST = urllib.request.Request("https://example.test/a", data=b"{}", method="POST")
dns = lambda: urllib.error.URLError(socket.gaierror(8, "nodename nor servname provided, or not known"))
reset = lambda: urllib.error.URLError(ConnectionResetError(54, "reset"))
http = lambda code: urllib.error.HTTPError("u", code, "x", {}, io.BytesIO(b""))


def run(req, *fails):
    """(answer or the exception type, tries, waits) when the first calls raise `fails`."""
    calls, slept, queue = [], [], list(fails)

    def opener(r, timeout):
        calls.append(r)
        if queue:
            raise queue.pop(0)
        return "ok"
    try:
        out = N.urlopen(req, opener=opener, sleep=slept.append)
    except Exception as e:
        out = type(e).__name__ + str(getattr(e, "code", ""))
    return out, len(calls), slept


cases = [
    ("a GET waits out a DNS failure", run(GET, dns(), dns()), ("ok", 3, [2, 5])),
    ("a POST waits out a DNS failure: it never left", run(POST, dns()), ("ok", 2, [2])),
    ("a POST cut off midway is not sent twice", run(POST, reset()), ("URLError", 1, [])),
    ("a GET cut off midway is asked again", run(GET, reset()), ("ok", 2, [2])),
    ("a GET waits out a 503", run(GET, http(503)), ("ok", 2, [2])),
    ("a POST's 503 is raised", run(POST, http(503)), ("HTTPError503", 1, [])),
    ("a 409 is an answer", run(GET, http(409)), ("HTTPError409", 1, [])),
    ("an outage still fails", run(GET, *[dns() for _ in range(9)]), ("URLError", 6, list(N.WAITS))),
]
bad = [f"{name}: {got} not {want}" for name, got, want in cases if got != want]
for b in bad:
    print("FAIL", b)
print(f"{len(cases) - len(bad)} of {len(cases)} passed")
sys.exit(bool(bad))
