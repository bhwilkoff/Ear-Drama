"""One place that answers "this tool needs PyJWT or Pillow and this python has neither".

    import pyneeds; pyneeds.need("jwt")        # before the import
"""
import importlib.util
import os
import subprocess
import sys

FALLBACK = "/usr/bin/python3"
_PIP = {"jwt": "pyjwt cryptography", "PIL": "pillow"}


def _has(py, mods):
    code = "import importlib.util as u,sys;sys.exit(any(u.find_spec(m) is None for m in %r))" % (list(mods),)
    return subprocess.run([py, "-c", code], capture_output=True).returncode == 0


def need(*mods):
    if all(importlib.util.find_spec(m) for m in mods):
        return
    if (os.environ.get("EARDRAMA_PYNEEDS") != "1" and os.path.realpath(sys.executable) != os.path.realpath(FALLBACK)
            and os.path.exists(FALLBACK) and _has(FALLBACK, mods)):
        os.environ["EARDRAMA_PYNEEDS"] = "1"
        os.execv(FALLBACK, [FALLBACK] + sys.argv)
    miss = [m for m in mods if importlib.util.find_spec(m) is None]
    sys.exit("%s: this python (%s) lacks %s; run it with %s (pip: %s)"
             % (os.path.basename(sys.argv[0]), sys.executable, ", ".join(miss), FALLBACK,
                " ".join(_PIP.get(m, m) for m in miss)))
