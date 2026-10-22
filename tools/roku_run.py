#!/usr/bin/env python3
"""Roku device harness — deploy, drive, and OBSERVE the channel on real hardware.

A platform is verified on the glass, never by the app's own report. Roku gives four
channels of evidence and this file wraps all of them, so a run is one command:

  info       device-info, active-app, and the ECP mode (the first thing to check)
  deploy     sideload a zip of the channel via the developer web installer
  zip        write the sideload zip (+ version.json) without installing
  keys       press remote keys over ECP (Home, Up, Down, Left, Right, Select, Back…)
  type       enter text a character at a time through ECP Lit_ codes
  shot       pull a screenshot of the RUNNING DEV CHANNEL
  log        capture the BrightScript debug console (port 8085) for N seconds
  launch     cold-launch the dev channel, optionally with deep-link params
  playstate  Roku's own account of playback (/query/media-player), sampled 3x

MEASURED CONSTRAINTS (each one cost a run):

* **ECP must be PERMISSIVE.** With `ecp-setting-mode` = `limited`, `/keypress`
  returns 403 and `/query/apps` refuses, while `/query/device-info` and
  `/query/active-app` still answer — so a naive reachability check passes while
  every input is silently rejected. `info` prints the mode for exactly this reason.
  Settings > System > Advanced system settings > Control by mobile apps >
  Network access > Permissive.
* **ECP key names are a CLOSED set.** Roku answers 200 for a name it does not
  recognise and does nothing — `keypress/OK` looked like a working press for
  thirty-odd ticks while the app never saw it. Unknown names are refused here.
* **The screenshot utility only captures a sideloaded DEV channel.** With none
  installed it answers "Screenshot not ok". That is not a broken harness; it means
  nothing of ours is on screen. It also cannot see the video plane (black).
* **The debug console on 8085 is push-only** — no request/response; it emits
  whatever the channel prints. It is the only logcat Roku has.
* **`/launch` on a channel that is already running RESUMES it** — process, parsed
  data and screens survive. `launch` presses Home first so a data check really is
  a cold start.

Device: the bench entry named by --device (default "roku"; tools/bench.py), or
ROKU_HOST. Developer password: ROKU_DEV_PASS (user ROKU_DEV_USER, default rokudev).

  python3 tools/roku_run.py info
  python3 tools/roku_run.py deploy [--dir roku]
  python3 tools/roku_run.py keys Home Down Down Select
  python3 tools/roku_run.py type "search text"
  python3 tools/roku_run.py shot NAME
  python3 tools/roku_run.py log 20
  python3 tools/roku_run.py launch [--params 'contentId=abc&mediaType=movie']
"""
import argparse
import contextlib
import datetime
import io
import json
import os
import re
import socket
import subprocess
import sys
import time
import urllib.parse
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_config  # noqa: E402
import bench  # noqa: E402
import devlease  # noqa: E402

REPO = str(app_config.REPO)
USER = os.environ.get("ROKU_DEV_USER", "rokudev")
CONSOLE_PORT = 8085

# Resolved by configure(); nothing touches the network at import time.
HOST = None
ECP = None
DEV = None
ENTRY = None


def qa_dir():
    d = app_config.QA_ROOT / f"roku-{datetime.date.today().isoformat()}"
    d.mkdir(parents=True, exist_ok=True)
    return d


def configure(device="roku", allow_owner=False):
    """Resolve the device from the bench (refusing a never-touch role) or ROKU_HOST."""
    global HOST, ECP, DEV, ENTRY
    env_host = os.environ.get("ROKU_HOST")
    if env_host and device == "roku" and bench.get("roku") is None:
        ENTRY = bench.require(env_host, allow_owner=allow_owner)
        HOST = env_host
    else:
        ENTRY = bench.require(device, allow_owner=allow_owner, platforms=("roku",))
        HOST = ENTRY.get("address") or env_host
    if not HOST:
        raise SystemExit(f"no address for {device!r}: add one to the bench manifest "
                         "or set ROKU_HOST")
    ECP = f"http://{HOST}:8060"
    DEV = f"http://{HOST}"
    return ENTRY


def lease_key():
    return bench.lease_name(ENTRY) if ENTRY and ENTRY.get("name") else f"roku-{HOST}"


@contextlib.contextmanager
def leased(task):
    """Hold the device for a state-changing verb. Inherited leases are honoured."""
    try:
        with devlease.hold([lease_key()], task=task):
            yield
    except RuntimeError as e:
        raise SystemExit(f"device busy — {e}. Not fighting a peer for it.")


# ECP key names are a CLOSED set; `ok` and `star` are friendly aliases.
KEYS = {"home": "Home", "rev": "Rev", "fwd": "Fwd", "play": "Play", "select": "Select",
        "ok": "Select", "left": "Left", "right": "Right", "down": "Down", "up": "Up",
        "back": "Back", "instantreplay": "InstantReplay", "info": "Info",
        "backspace": "Backspace", "search": "Search", "enter": "Enter", "star": "Info"}


def key_name(key):
    """The ECP name for `key`, or SystemExit. Never trust Roku's 200 for a name."""
    if key.lower() in KEYS:
        return KEYS[key.lower()]
    if key.startswith("Lit_") or key in KEYS.values():
        return key
    raise SystemExit(
        f"unknown ECP key {key!r}. Roku returns HTTP 200 for a name it does not know "
        f"and does nothing, so this would have looked like a press. "
        f"Valid: {', '.join(sorted(set(KEYS.values())))}")


def curl(*args, timeout=30, binary=False):
    r = subprocess.run(["curl", "-s", "--max-time", str(timeout), *args],
                       capture_output=True, timeout=timeout + 15)
    return r.stdout if binary else r.stdout.decode(errors="replace")


def dev_password():
    p = os.environ.get("ROKU_DEV_PASS")
    if not p:
        raise SystemExit("set ROKU_DEV_PASS to the developer-mode password you chose "
                         "when enabling developer mode on the device")
    return p


def dev_curl(*args, timeout=60, binary=False):
    """The developer web installer speaks HTTP DIGEST auth, not basic."""
    return curl("--digest", "-u", f"{USER}:{dev_password()}", *args,
                timeout=timeout, binary=binary)


# ------------------------------------------------------------------ parsers (pure)

def installer_messages(html):
    """Roku's real verdict lives in a JSON blob the page hands its own JS.

    Scraping the rendered HTML does not work: the page's JavaScript contains the
    words "error" and "success" in comments, so any substring test over the raw
    response is true no matter what happened. Each message carries its own `type`,
    and that is the only trustworthy signal."""
    out = []
    for m in re.finditer(r'\{"text":"((?:[^"\\]|\\.)*)","text_type":"[^"]*",'
                         r'"type":"([a-z]+)"\}', html):
        text = m.group(1).encode().decode("unicode_escape").strip()
        out.append((m.group(2), text))
    return out


def install_verdict(msgs):
    """('ok'|'identical'|'failed'|'unverified', lines) from installer_messages()."""
    if any("identical" in t.lower() for _, t in msgs):
        return "identical", [t for _, t in msgs]
    errors = [t for kind, t in msgs if kind == "error"]
    if errors:
        return "failed", errors
    # An EMPTY list is not a pass: the installer answers 200 with a full page on a
    # digest re-challenge or a refused upload, and "no errors" read off an
    # unparseable response let a stale channel run for two test cycles.
    if not msgs:
        return "unverified", ["the installer returned no parseable message"]
    if not any("success" in t.lower() or "received" in t.lower() for _, t in msgs):
        return "unverified", [t for _, t in msgs]
    return "ok", [t for _, t in msgs]


def parse_media_player(xml):
    """Roku's own report on the video plane as a dict, {} when unparseable.

    The element text carries its UNIT ("<position>37871 ms</position>"). A bare
    int() throws on that, which reads downstream as "the device would not tell us"
    rather than "the parser is wrong" — every film once reported an empty position
    list while playing perfectly."""
    import xml.etree.ElementTree as ET
    try:
        root = ET.fromstring(xml)
    except Exception:  # noqa: BLE001
        return {}
    fmt = root.find("format")

    def num(tag):
        t = (root.findtext(tag) or "").strip()
        digits = "".join(c for c in t if c.isdigit())
        return int(digits) if digits else None
    return {
        "state": root.get("state"),
        "error": root.get("error"),
        "position": num("position"),
        "duration": num("duration"),
        "video": fmt.get("video") if fmt is not None else None,
        "audio": fmt.get("audio") if fmt is not None else None,
        "res": fmt.get("video_res") if fmt is not None else None,
    }


def active_app_xml():
    return curl(f"{ECP}/query/active-app")


def channel_foreground(xml=None):
    """Is OUR channel in front? A sideloaded channel is id="dev"; a store build is
    matched by its display name."""
    xml = xml if xml is not None else active_app_xml()
    return 'id="dev"' in xml or (bool(app_config.ROKU_CHANNEL_NAME)
                                 and f">{app_config.ROKU_CHANNEL_NAME}<" in xml)


def media_player():
    return parse_media_player(curl(f"{ECP}/query/media-player"))


# ------------------------------------------------------------------ commands

def press(key, settle=0.9):
    name = key_name(key)
    code = curl("-o", "/dev/null", "-w", "%{http_code}", "-X", "POST",
                f"{ECP}/keypress/{name}").strip()
    if code == "403":
        raise SystemExit(f"keypress {name} -> HTTP 403: ECP is not Permissive "
                         "(Settings > System > Advanced system settings > Control by "
                         "mobile apps > Network access > Permissive)")
    # ECP answers 200 or 202 (accepted, queued); both are fine.
    if not code.startswith("2"):
        raise SystemExit(f"keypress {name} -> HTTP {code or 'no answer'}")
    time.sleep(settle)


def cmd_info(_args):
    xml = curl(f"{ECP}/query/device-info")
    if not xml.strip():
        raise SystemExit(f"no answer from {ECP} — is the device on and reachable?")
    keep = ("model-name", "software-version", "ui-resolution", "ecp-setting-mode",
            "developer-enabled", "power-mode")
    for line in xml.splitlines():
        tag = line.strip().lstrip("<").split(">")[0]
        if tag in keep:
            print(line.strip())
    if "<ecp-setting-mode>permissive" not in xml:
        print("\n!! ECP is not permissive — /keypress will 403 and this harness cannot")
        print("   drive the remote. Settings > System > Advanced system settings >")
        print("   Control by mobile apps > Network access > Permissive")
    print("\nactive-app:", active_app_xml().replace("\n", " ")[:220])


def zip_channel(src_dir, extras=()):
    """Zip the channel with the manifest at the ARCHIVE ROOT.

    Roku rejects a zip whose manifest sits inside a top-level folder, reporting a
    vague failure rather than naming the cause — so walk the directory rather than
    zipping the folder. Documentation and dotfiles are not channel content (static
    analysis reports them as "extraneous file"). `extras` are (src, dest-in-zip)
    pairs for shared data kept in ONE home elsewhere in the repo, so it cannot
    drift from what the other platforms show; put them under a subfolder, since a
    root-level file Roku does not recognise is also "extraneous"."""
    buf = io.BytesIO()
    src = os.path.join(REPO, src_dir)
    if not os.path.isfile(os.path.join(src, "manifest")):
        raise SystemExit(f"no manifest at {src}/manifest — Roku needs it at the zip root")
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk(src):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            for f in files:
                if f.startswith(".") or f.endswith((".swp", ".orig", ".md")):
                    continue
                full = os.path.join(root, f)
                z.write(full, os.path.relpath(full, src))
        for s, dest in extras:
            s = os.path.join(REPO, s)
            if not os.path.isfile(s):
                raise SystemExit(f"--extra source missing: {s}")
            z.write(s, dest)
    return buf.getvalue()


def parse_extras(items):
    out = []
    for it in items or []:
        s, _, d = it.partition(":")
        if not d:
            raise SystemExit(f"--extra wants SRC:DEST, got {it!r}")
        out.append((s, d))
    return out


def post_install(submit, zip_path=None):
    args = ["-F", f"mysubmit={submit}", "-F", f"passwd={dev_password()}"]
    args += ["-F", f"archive=@{zip_path}"] if zip_path else ["-F", "archive="]
    return dev_curl(*args, f"{DEV}/plugin_install", timeout=180)


def cmd_deploy(args):
    blob = zip_channel(args.dir, parse_extras(args.extra))
    tmp = qa_dir() / "sideload.zip"
    tmp.write_bytes(blob)
    print(f"packaged {args.dir} -> {len(blob) / 1024:.0f} KB")
    with leased(f"roku deploy {args.dir}"):
        msgs = installer_messages(post_install("Replace", tmp))
        verdict, lines = install_verdict(msgs)
        # "Identical to previous version" compares against the last UPLOAD, not the
        # last successful INSTALL — after a compile failure a corrected build can be
        # refused as identical while nothing is installed. Delete, install fresh.
        if verdict == "identical":
            print("   (identical upload refused — deleting and installing fresh)")
            post_install("Delete")
            verdict, lines = install_verdict(installer_messages(post_install("Install", tmp)))
    if verdict != "ok":
        print({"failed": "DEPLOY FAILED:", "unverified": "DEPLOY UNVERIFIED:",
               "identical": "DEPLOY REFUSED AS IDENTICAL:"}[verdict])
        for t in lines:
            for line in t.splitlines():
                if line.strip():
                    print("   ", line.strip())
        sys.exit(1)
    for t in lines:
        print("   ", t)
    print("deploy OK")


def cmd_zip(args):
    """The sideload zip + version.json: the SAME source and walk as `deploy`, so a
    downloadable sideload is exactly what the store package was built from."""
    data = zip_channel(args.dir, parse_extras(args.extra))
    out = args.out or str(app_config.REPO / "build" / "roku" / "channel.zip")
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    Path(out).write_bytes(data)
    man = {}
    with open(os.path.join(REPO, args.dir, "manifest"), encoding="utf-8") as fh:
        for line in fh:
            if "=" in line and not line.startswith("#"):
                k, v = line.rstrip("\n").split("=", 1)
                man[k.strip()] = v.strip()
    ver = {"version": f"{man.get('major_version', '0')}.{man.get('minor_version', '0')}."
                      f"{int(man.get('build_version', '0') or 0)}",
           "build_version": man.get("build_version"), "bytes": len(data),
           "built_at": datetime.datetime.now(datetime.timezone.utc)
                                        .strftime("%Y-%m-%dT%H:%M:%SZ")}
    with open(os.path.join(os.path.dirname(out) or ".", "version.json"), "w") as fh:
        json.dump(ver, fh, indent=1)
    print(f"wrote {out} ({len(data) // 1024} KB) version {ver['version']}")


def cmd_playstate(_args):
    """Roku's OWN account of playback — the trustworthy oracle. A screenshot cannot
    prove a film is playing (the video plane is not composited into it); a position
    that ADVANCES between samples can."""
    prev = None
    for i in range(3):
        mp = media_player()
        if not mp:
            print("media-player unavailable")
            return
        codec = f"{mp['video']}/{mp['audio']} {mp['res']}"
        moved = "" if prev is None else ("  advanced" if mp["position"] != prev else "  STALLED")
        print(f"state={mp['state']} error={mp['error']} position={mp['position']}ms "
              f"duration={mp['duration']}ms [{codec}]{moved}")
        prev = mp["position"]
        if i < 2:
            time.sleep(5)


def cmd_keys(args):
    for k in args.keys:
        key_name(k)                       # refuse a bad name before pressing any
    with leased("roku keys " + " ".join(args.keys)):
        for k in args.keys:
            press(k, settle=args.settle)
            print("pressed", k)


def cmd_type(args):
    with leased("roku type"):
        for ch in args.text:
            press("Lit_" + urllib.parse.quote(ch), settle=0.35)
    print(f"typed {args.text!r}")


def cmd_shot(args):
    path = qa_dir() / (args.name + ".jpg")
    # Delete first: a stale file from an earlier attempt must never be read as now.
    with contextlib.suppress(FileNotFoundError):
        path.unlink()
    with leased(f"roku shot {args.name}"):
        page = dev_curl("-F", "mysubmit=Screenshot", "-F", "archive=",
                        "-F", f"passwd={dev_password()}", f"{DEV}/plugin_inspect",
                        timeout=90)
        if "Screenshot ok" not in page:
            print("screenshot not taken — is a DEV channel installed and running? "
                  "(the utility only captures a sideloaded dev channel)")
            sys.exit(1)
        raw = dev_curl(f"{DEV}/pkgs/dev.jpg", timeout=90, binary=True)
    if len(raw) < 4000:
        print(f"screenshot came back empty ({len(raw)} bytes) — refused")
        sys.exit(1)
    path.write_bytes(raw)
    print(path, f"{len(raw) / 1024:.0f} KB")


def cmd_log(args):
    """Drain the BrightScript console for N seconds. Push-only: nothing is sent.
    Note it REPLAYS recent backlog on attach, so old lines arrive first."""
    path = qa_dir() / "console.log"
    deadline = time.time() + args.seconds
    got = []
    try:
        s = socket.create_connection((HOST, CONSOLE_PORT), timeout=5)
    except OSError as e:
        raise SystemExit(f"cannot reach the debug console on {HOST}:{CONSOLE_PORT} — {e}")
    s.settimeout(2)
    while time.time() < deadline:
        try:
            chunk = s.recv(65536)
        except socket.timeout:
            continue
        except OSError:
            break
        if not chunk:
            break
        text = chunk.decode(errors="replace")
        got.append(text)
        sys.stdout.write(text)
        sys.stdout.flush()
    s.close()
    with open(path, "a") as f:
        f.write("".join(got))


def cmd_launch(args):
    with leased(f"roku launch {args.app}"):
        # /launch on a RUNNING channel resumes it; a data check needs a cold start.
        press("Home", settle=3.0)
        url = f"{ECP}/launch/{args.app}"
        if args.params:
            url += "?" + args.params
        code = curl("-o", "/dev/null", "-w", "%{http_code}", "-X", "POST", url).strip()
        print(f"launch {args.app} -> HTTP {code}")
        if not code.startswith("2"):
            sys.exit(1)
        time.sleep(args.settle)


def build_parser():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--device", default="roku", help="bench name (default: roku)")
    ap.add_argument("--owner-ok", action="store_true",
                    help="allow a device whose role is owner-watches (ask first)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("info").set_defaults(fn=cmd_info, net=True)
    sub.add_parser("playstate").set_defaults(fn=cmd_playstate, net=True)
    d = sub.add_parser("deploy")
    d.add_argument("--dir", default="roku")
    d.add_argument("--extra", action="append", help="SRC:DEST extra file into the zip")
    d.set_defaults(fn=cmd_deploy, net=True)
    z = sub.add_parser("zip")
    z.add_argument("--dir", default="roku")
    z.add_argument("--extra", action="append", help="SRC:DEST extra file into the zip")
    z.add_argument("--out", default=None)
    z.set_defaults(fn=cmd_zip, net=False)
    k = sub.add_parser("keys")
    k.add_argument("keys", nargs="+")
    k.add_argument("--settle", type=float, default=0.9)
    k.set_defaults(fn=cmd_keys, net=True)
    t = sub.add_parser("type")
    t.add_argument("text")
    t.set_defaults(fn=cmd_type, net=True)
    s = sub.add_parser("shot")
    s.add_argument("name")
    s.set_defaults(fn=cmd_shot, net=True)
    lg = sub.add_parser("log")
    lg.add_argument("seconds", type=int, nargs="?", default=15)
    lg.set_defaults(fn=cmd_log, net=True)
    la = sub.add_parser("launch")
    la.add_argument("--app", default="dev")
    la.add_argument("--params", default="")
    la.add_argument("--settle", type=float, default=6)
    la.set_defaults(fn=cmd_launch, net=True)
    return ap


def main():
    args = build_parser().parse_args()
    if args.net:
        configure(args.device, allow_owner=args.owner_ok)
    args.fn(args)


if __name__ == "__main__":
    main()
