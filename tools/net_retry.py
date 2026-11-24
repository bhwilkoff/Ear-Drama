"""urlopen that waits out a blip (2026-11-24: one DNS failure on a runner lost a whole Apple build).

A request that never left is safe to repeat whatever its method: the name did not resolve, or the
connection was refused. Anything later may have been acted on, so only a GET is repeated then.
An answer that is an answer (400, 401, 403, 404, 409...) is raised at once.
"""
import socket
import sys
import time
import urllib.error
import urllib.request

WAITS = (2, 5, 15, 30, 60)
GET_AGAIN = {429, 500, 502, 503, 504}


def again(req, err):
    get = (req.get_method() if hasattr(req, "get_method") else "GET") in ("GET", "HEAD")
    if isinstance(err, urllib.error.HTTPError):
        return get and err.code in GET_AGAIN
    reason = getattr(err, "reason", err)
    if isinstance(reason, (socket.gaierror, ConnectionRefusedError)):
        return True
    return get and isinstance(reason, (OSError, TimeoutError))


def urlopen(req, timeout=60, waits=WAITS, opener=urllib.request.urlopen, sleep=time.sleep):
    for wait in (*waits, None):
        try:
            return opener(req, timeout=timeout)
        except (urllib.error.URLError, OSError) as err:
            if wait is None or not again(req, err):
                raise
            print(f"network: {err}; again in {wait} s", file=sys.stderr)
            sleep(wait)
