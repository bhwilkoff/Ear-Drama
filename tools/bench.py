"""The bench manifest: every real device a harness may touch, and what it is FOR.

`app_config.DEVICES` holds one device per kind, which is enough for a first phone.
A working bench is not like that. It has three Apple TVs on two OS versions (one is
the control for an OS-specific fault), an old player that is the hardware FLOOR,
the television the owner actually watches on, and a phone that is somebody's
personal device and must never be driven at all. Each of those facts lived in a
different place — a UDID hardcoded in one runner, an IP in another, the lease keys
only in a docstring, the roles only in prose — so a runner could not know that the
phone it was about to launch an app on belonged to a person.

The manifest is JSON so every tool (Python, shell, Node) can read it:

    $DEVICE_BENCH            an explicit path, if set
    tools/bench.json         this repo's bench (gitignored — it names real devices)
    ~/.device-bench.json     the MACHINE's bench, shared by every repo on it

The machine-wide file is the natural home: the devices belong to the desk, not to a
repo, and the lease directory (~/.device-lease/) is machine-wide for the same reason.
Start from tools/bench.example.json.

Each entry, keyed by its LEASE NAME (the key devlease uses, a cross-repo contract):

    platform      ios | ipados | tvos | macos | android | androidtv | firetv |
                  roku | webos | tizen | windows | web
    udid          devicectl UDID (Apple) — address a TV by UDID, never by name
    serial        adb serial (Android)
    mdns_prefix   Android over wireless debugging: the start of the device's mDNS
                  service name as `adb mdns services` prints it
                  ("adb-XXXXXXXX" of "adb-XXXXXXXX-XXXXXX._adb-tls-connect._tcp").
                  The TLS port rotates after sleep, so tools/gtv_scenario.py matches
                  this prefix plus `address` to find the new port. Needs `address`.
    address       IP / host (pyatv, ECP, adb over TCP, SSH)
    pyatv_id      Companion identifier for atvremote --id
    os            the OS version, as last verified — a claim with a date is a fact
    model         hardware, for "is this the floor device?"
    role          see ROLES
    apple_id      a LABEL for the signed-in account ("test account A"), never the
                  address — two devices on two accounts is what makes a real
                  SharePlay/CloudKit peer, and the harness needs to know which is which
    capabilities  subset of CAPABILITIES the device actually supports
    quirks        free-text capture/driving quirks a reader must know
    verified      YYYY-MM-DD this row last answered a real query

Roles, and what a runner does with each:

    test                         the default — drive freely
    floor                        the oldest hardware/OS you support; drive freely,
                                 and treat a failure here as a real finding
    os-control                   deliberately on an older/newer OS so an OS-specific
                                 claim can be tested rather than inferred
    owner-watches                the owner's everyday TV. Refused unless the run says
                                 --owner-ok (or BENCH_OWNER_OK=1): ask before waking a
                                 television in someone's room
    owner-personal-never-touch   REFUSED, always, by every runner, with no override.
                                 A personal phone is on the bench because it is paired,
                                 not because it is available

    python3 tools/bench.py              # the bench, with roles
    python3 tools/bench.py check        # validate the manifest
    python3 tools/bench.py get atv udid # one field, for shell scripts
"""
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_config  # noqa: E402

ROLES = ("test", "floor", "os-control", "owner-watches", "owner-personal-never-touch")
NEVER = "owner-personal-never-touch"
ASK = "owner-watches"
CAPABILITIES = ("screenshot", "console", "press", "launch", "install", "deeplink",
                "power", "diagfile")
PLATFORMS = ("ios", "ipados", "tvos", "macos", "android", "androidtv", "firetv",
             "roku", "webos", "tizen", "windows", "web")

# How the simple DEVICES dict maps onto manifest entries, so a template that never
# wrote a manifest keeps working exactly as before. The legacy "appletv" key is also
# reachable as "atv", the lease key every runner uses.
_LEGACY = {
    "iphone":  ("ios", "udid"),
    "ipad":    ("ipados", "udid"),
    "appletv": ("tvos", "udid"),
    "android": ("android", "serial"),
    "mac":     ("macos", None),
    "windows": ("windows", "address"),
    "web":     ("web", None),
}
_ALIASES = {"atv": "appletv", "appletv": "atv"}


class RefusedDevice(SystemExit):
    """Raised (as a clean exit, never a traceback) when a runner is asked to touch a
    device its role forbids."""


def manifest_path():
    env = os.environ.get("DEVICE_BENCH")
    for p in ([Path(env)] if env else []) + [app_config.REPO / "tools" / "bench.json",
                                             Path.home() / ".device-bench.json"]:
        if p.is_file():
            return p
    return None


def load():
    """{lease_name: entry}. Manifest first; otherwise synthesized from DEVICES."""
    p = manifest_path()
    if p:
        data = json.loads(p.read_text())
        devs = data.get("devices", data)
        out = {}
        for name, e in devs.items():
            e = dict(e)
            e["name"] = name
            e.setdefault("role", "test")
            e.setdefault("capabilities", [])
            e.setdefault("quirks", [])
            out[name] = e
        return out
    out = {}
    for name, value in app_config.DEVICES.items():
        if value is None:
            continue
        platform, field = _LEGACY.get(name, (name, "address"))
        e = {"name": name, "platform": platform, "role": "test",
             "capabilities": [], "quirks": [], "source": "app_config.DEVICES"}
        if field:
            e[field] = value
        out[name] = e
    return out


def get(name, bench=None):
    """The entry for `name` (lease key), or None. `name` may also be a raw UDID,
    serial or address — a runner passed one directly still gets its ROLE checked,
    which is what stops a personal phone being driven by pasting its UDID."""
    bench = bench if bench is not None else load()
    if name in bench:
        return bench[name]
    alias = _ALIASES.get(name)
    if alias and alias in bench:
        return bench[alias]
    for e in bench.values():
        if name and name in (e.get("udid"), e.get("serial"), e.get("address")):
            return e
    return None


def owner_ok():
    return os.environ.get("BENCH_OWNER_OK") == "1"


def require(name, allow_owner=False, platforms=None, bench=None):
    """The entry a runner may drive, or a clean refusal.

    Refuses a never-touch device ALWAYS — there is no flag for it. Refuses an
    owner-watches device unless the caller passes allow_owner (a CLI --owner-ok) or
    BENCH_OWNER_OK=1 is set. An unknown raw id is allowed through as an ad-hoc
    device with role "test", because a device that is not on the bench is not
    anybody's registered personal device — but it is SAID."""
    e = get(name, bench)
    if e is None:
        print(f"[bench] {name!r} is not on the bench — driving it as an ad-hoc test "
              "device. Add it to the manifest so its role is known.")
        e = {"name": name, "role": "test", "capabilities": [], "quirks": [],
             "udid": name, "serial": name, "address": name}
    role = e.get("role", "test")
    if role == NEVER:
        raise RefusedDevice(
            f"REFUSED: {e['name']} is role {NEVER}. It is somebody's personal device; "
            "no harness drives it, and there is no override.")
    if role == ASK and not (allow_owner or owner_ok()):
        raise RefusedDevice(
            f"REFUSED: {e['name']} is the owner's everyday device (role {ASK}). Ask "
            "first, then re-run with --owner-ok (or BENCH_OWNER_OK=1).")
    if platforms and e.get("platform") and e["platform"] not in platforms:
        raise RefusedDevice(f"REFUSED: {e['name']} is a {e['platform']} device, "
                            f"this runner drives {'/'.join(platforms)}.")
    return e


def lease_name(e):
    """The key devlease uses for this device. The manifest key IS the lease key."""
    return e.get("lease") or e["name"]


def of_platform(*platforms, bench=None):
    bench = bench if bench is not None else load()
    return [e for e in bench.values() if e.get("platform") in platforms]


def check(bench=None):
    """Problems with the manifest, as strings. Empty = valid."""
    bench = bench if bench is not None else load()
    probs = []
    for n, e in bench.items():
        if e.get("role") not in ROLES:
            probs.append(f"{n}: role {e.get('role')!r} not one of {ROLES}")
        if e.get("platform") and e["platform"] not in PLATFORMS:
            probs.append(f"{n}: platform {e['platform']!r} not one of {PLATFORMS}")
        for c in e.get("capabilities", []):
            if c not in CAPABILITIES:
                probs.append(f"{n}: capability {c!r} not one of {CAPABILITIES}")
        p = e.get("platform")
        if p in ("ios", "ipados", "tvos") and not e.get("udid"):
            probs.append(f"{n}: an Apple device needs a udid (address TVs by UDID)")
        if p == "tvos" and "press" in e.get("capabilities", []) and not e.get("pyatv_id"):
            probs.append(f"{n}: 'press' on tvOS needs pyatv_id (and address)")
        if p in ("android", "androidtv", "firetv") and not (e.get("serial") or e.get("address")):
            probs.append(f"{n}: an adb device needs a serial or address")
        if p == "roku" and not e.get("address"):
            probs.append(f"{n}: a Roku needs an address (ECP is http://<address>:8060)")
        if "@" in str(e.get("apple_id", "")):
            probs.append(f"{n}: apple_id should be a LABEL, not an address")
    return probs


def _main(argv):
    bench = load()
    src = manifest_path() or "app_config.DEVICES (no manifest)"
    if argv[:1] == ["get"] and len(argv) >= 3:
        e = get(argv[1], bench)
        v = (e or {}).get(argv[2])
        if v is None:
            return 1
        print(v if not isinstance(v, list) else ",".join(v))
        return 0
    if argv[:1] == ["role"] and len(argv) >= 2:
        e = get(argv[1], bench)
        print((e or {}).get("role", "unknown"))
        return 0
    if argv[:1] == ["check"]:
        probs = check(bench)
        for p in probs:
            print("  " + p)
        print(f"{len(bench)} device(s) from {src}: "
              + ("OK" if not probs else f"{len(probs)} problem(s)"))
        return 1 if probs else 0
    if argv[:1] in (["-h"], ["--help"]):
        print(__doc__)
        return 0
    print(f"bench: {src}")
    for n, e in bench.items():
        ident = e.get("udid") or e.get("serial") or e.get("address") or "-"
        print(f"  {n:16} {e.get('platform', '?'):9} {e.get('role', 'test'):27} "
              f"{str(ident)[:28]:28} {e.get('os', '')}")
    if not bench:
        print("  (empty — fill in app_config.DEVICES or write a manifest)")
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
