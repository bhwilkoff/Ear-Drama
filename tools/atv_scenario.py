#!/usr/bin/env python3
"""External-observation PLAYBACK scenario runner for a paired Apple TV (media apps).

Watches what the DEVICE actually outputs — screenshots OCR'd for on-glass captions
and notices, plus a diagnostics file the app writes (playhead / buffer / audio /
caption trace) — and grades explicit assertions. The app's own claims are never
the evidence for what a viewer sees; the screen is.

For non-media scenarios (open a screen, check its text) use tools/atv_run.py.
This runner exists for the playback doctrine in docs/MEDIA-PLAYBACK.md.

Usage:
  python3 tools/atv_scenario.py --item <content-id> --minutes 6
  python3 tools/atv_scenario.py --item <id> --vtt path/or/url/en.vtt
  python3 tools/atv_scenario.py --item <id> --expect-captions no   # silent-film control
  python3 tools/atv_scenario.py --device atv-control --item <id>   # the OS-control TV

The run, in one process under one lease:
  wake (POLLED) -> launch with the start-item + autoplay + diag doors (muted and
  time-bounded unless --audible) -> foreground probe (bring forward / relaunch once)
  -> death probes at 0/15/30 s (one relaunch; a second death reboots a test device)
  -> capture every SHOT_EVERY s, power checked before each, fresh files only ->
  pull the diag file -> grade -> leave as found.

The app side (see app_config.DIAG_*): with HOOK_DIAG_FILE=1 the app appends
`<epoch.millis> <message>` lines to DIAG_CONTAINER_PATH in its container. NO
--console: a console stream cannot coexist with screenshot captures (two devicectl
sessions kill the stream, and killing the console kills the app).

Requires a bench entry with udid (+ address/pyatv_id for wake), pyatv in
~/.pyatv-venv (Python 3.12). The OCR binary is built on first use.
"""
import argparse
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_config as C  # noqa: E402
import apple_device as ad  # noqa: E402
import bench  # noqa: E402
import devlease  # noqa: E402
from devharness import OCR_FAILED, frame_darkness, ocr, qa_dir  # noqa: E402

BUNDLE = C.APPLE_BUNDLE_ID
SHOT_EVERY = 4.0   # 4K captures pressure the device's screenshot daemon;
                   # 2.5s coincided with jetsam events on ~every run
T = C.DIAG_TAGS


def resolve_item(title):
    """FILL IN: map a human title to the id the APP SERVES for it (read the same
    published index the app reads). Never hardcode an id in a scenario: tests once
    ran green against an id the app no longer surfaced while a viewer watched a
    different copy of the same film fail."""
    raise SystemExit("resolve_item() is not implemented for this app — pass --item, "
                     "or fill in resolve_item() to read the index the app reads")


def capture_loop(entry, atv, outdir, minutes, log):
    shots, i = [], 0
    t0 = time.time()
    deadline = t0 + minutes * 60
    while time.time() < deadline:
        # A sleeping TV returns a valid black PNG: ask the TV, not the pixels.
        if atv.available and atv.power_state() == "off":
            print(f"[scenario] TV Off at +{time.time() - t0:.0f}s — doze; re-waking "
                  "(window logged, frame skipped)")
            log.append(f"+{time.time() - t0:.0f}s TV off — blind window")
            atv.wake()
            continue
        p = outdir / f"shot-{i:04d}.png"
        ok, why = ad.capture(entry["udid"], p, timeout=30)
        i += 1
        if not ok:
            print(f"[scenario] capture {p.name}: {why}")
            log.append(f"{p.name}: {why}")
            time.sleep(2)
            continue
        shots.append((time.time(), p))
        dk = frame_darkness(p)
        if dk and dk[1] > 99.5:
            # The doze SIGNATURE, as a second opinion: re-ask the TV.
            log.append(f"{p.name} {dk[1]}% black")
            if atv.available and atv.power_state() != "on":
                atv.wake()
        time.sleep(max(0, SHOT_EVERY - 1.0))
    return shots


def parse_diag(log):
    """wall-time -> playhead map, audio samples, events, displayed captions."""
    buf, aud, events, shown = [], [], [], []
    if not log.exists():
        return buf, aud, events, shown
    for line in open(log, errors="ignore"):
        m = re.match(r"^(\d{10}\.\d{3}) (.*)", line)
        if not m:
            continue
        wall, msg = float(m.group(1)), m.group(2)
        if T["buffer"] in msg:
            bm = re.search(r"t=(\d+) ahead=(\d+)", msg)
            if bm:
                buf.append((wall, int(bm.group(1)), int(bm.group(2))))
        elif T["audio"] in msg:
            rm = re.search(r"rms=([\d.]+)", msg)
            aud.append((wall, float(rm.group(1)) if rm else -1.0))
        elif T["shown"] in msg:
            # `trace t=104.0 show[cue=103.0]: Even ten minutes…` — a pattern that
            # matches NOTHING leaves `shown` empty and every caption assertion
            # silently never grades. An assertion that cannot fire is not one.
            shown.append((wall, msg.split("]: ", 1)[1] if "]: " in msg else msg))
        elif T["stall"] in msg or T["failed"] in msg:
            events.append(f"{wall:.1f} {msg}")
    return buf, aud, events, shown


def playhead_at(buf, wall):
    if not buf:
        return None
    best = min(buf, key=lambda b: abs(b[0] - wall))
    if abs(best[0] - wall) > 12:
        return None
    return best[1] + (wall - best[0])


def parse_vtt(body):
    cues, block = [], []
    for line in body.splitlines():
        m = re.match(r"(\d+):(\d+):(\d+)\.(\d+) --> (\d+):(\d+):(\d+)\.(\d+)", line)
        if m:
            g = list(map(int, m.groups()))
            block = [g[0] * 3600 + g[1] * 60 + g[2] + g[3] / 1000,
                     g[4] * 3600 + g[5] * 60 + g[6] + g[7] / 1000]
        elif block and line.strip() and not line.strip().isdigit() \
                and not line.startswith(("WEBVTT", "X-TIMESTAMP")):
            block.append(line.strip())
        elif not line.strip() and len(block) > 2:
            cues.append((block[0], block[1], " ".join(block[2:])))
            block = []
    if len(block) > 2:
        cues.append((block[0], block[1], " ".join(block[2:])))
    return cues or None


def load_vtt(src):
    """The caption file the APP would show — pass what the app reads. A published
    file the catalog no longer claims is an ORPHAN the app correctly ignores, and
    grading the glass against it scores a correct engine display 0/N."""
    if not src:
        return None
    try:
        if re.match(r"https?://", src):
            body = urllib.request.urlopen(src, timeout=60).read().decode(errors="replace")
        else:
            body = Path(src).read_text(errors="replace")
    except Exception as e:                    # noqa: BLE001
        print(f"[scenario] could not read captions {src}: {e}")
        return None
    return parse_vtt(body)


def norm(s):
    return re.sub(r"[^a-z0-9 ]", "", s.lower()).strip()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--device", default="atv", help="bench name (default atv) or UDID")
    ap.add_argument("--item", help="content id the app serves")
    ap.add_argument("--title", help="resolved via resolve_item() — fill it in first")
    ap.add_argument("--minutes", type=float, default=6)
    ap.add_argument("--outdir", default=None)
    ap.add_argument("--name", default=None, help="run name for the build/qa/ tree")
    ap.add_argument("--env", action="append", default=[], help="K=V extra launch env")
    ap.add_argument("--vtt", help="caption file (path or URL) the app should be showing")
    ap.add_argument("--expect-captions", choices=["auto", "yes", "no"], default="auto",
                    help="'no' = negative control (a silent film generating captions "
                         "is a FAILURE)")
    ap.add_argument("--owner-ok", action="store_true")
    ap.add_argument("--audible", action="store_true",
                    help="drop the mute door — needed for audio-level assertions; "
                         "ask the owner first")
    ap.add_argument("--no-reboot", action="store_true",
                    help="never reboot the device on a second launch-window death")
    ap.add_argument("--lease-wait", type=int, default=0)
    args = ap.parse_args()

    item = args.item or (resolve_item(args.title) if args.title else None)
    if not item:
        ap.error("--item is required (or --title with resolve_item() filled in)")
    entry = bench.require(args.device, allow_owner=args.owner_ok, platforms=("tvos",))
    name = args.name or item[:32]
    outdir = Path(args.outdir) if args.outdir else qa_dir("atv", name)
    outdir.mkdir(parents=True, exist_ok=True)
    print(f"[scenario] item {item} on {entry['name']}  ->  {outdir}")

    env = {C.HOOK_START_ITEM: item, C.HOOK_AUTOPLAY: "1", C.HOOK_DIAG_FILE: "1",
           **C.DOOR_DEFAULTS}
    # A playback run's door must outlive the capture, or the app stops the film
    # mid-scenario and every late frame grades an idle screen.
    env[C.HOOK_DOOR_SECONDS] = str(int(args.minutes * 60) + 90)
    if args.audible:
        env.pop(C.HOOK_MUTE, None)
        print("[scenario] AUDIBLE run — the owner should have been asked first")
    for kv in args.env:
        k, _, v = kv.partition("=")
        env[k] = v

    try:
        with devlease.hold([bench.lease_name(entry)], task=f"atv_scenario {name}",
                           ttl=int(args.minutes * 60) + 900, wait=args.lease_wait):
            return run(entry, item, env, outdir, args)
    except RuntimeError as e:
        print(f"[scenario] SKIP — {e}. Nothing was measured.")
        (outdir / "report.json").write_text(json.dumps({"item": item, "result": "SKIP",
                                                        "why": str(e)}))
        return 2


def run(entry, item, env, outdir, args):
    atv = ad.ATV(entry)
    found_power = atv.power_state()
    report = {"item": item, "device": entry["name"], "found_power": found_power,
              "env": env, "assertions": {}}
    cap_log = []
    shots = []

    def grade(name, ok, evidence):
        report["assertions"][name] = {"pass": bool(ok), "evidence": evidence}
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}: {evidence}")

    log = outdir / "appdiag.log"
    try:
        try:
            report["launch_events"] = ad.launch_guarded(
                entry, BUNDLE, env, outdir, settle=8, allow_reboot=not args.no_reboot)
        except ad.LaunchFailed as e:
            grade("launched", False, str(e))
            return finish(report, outdir)
        shots = capture_loop(entry, atv, outdir, args.minutes, cap_log)
        print(f"[scenario] {len(shots)} screenshots")
        # Pull BEFORE anything relaunches the app: launch truncates the file.
        ok, why = ad.pull_file(entry["udid"], BUNDLE, C.DIAG_CONTAINER_PATH, log)
        if not ok:
            print(f"[scenario] diag copy failed: {why}")
    finally:
        ok_td, lines = ad.teardown(entry, found_power=found_power)
        report["teardown"] = {"ok": ok_td, "lines": lines}
        for l in lines:
            print(f"[scenario] teardown {l}")
    report["shots"] = len(shots)
    report["capture_log"] = cap_log

    texts = ocr(shots)
    if OCR_FAILED in texts:
        grade("ocr_available", False, texts[OCR_FAILED])
        return finish(report, outdir)
    buf, aud, events, shown = parse_diag(log)
    vtt = load_vtt(args.vtt)
    diag_text = log.read_text(errors="ignore") if log.exists() else ""

    # A0. ALIVE for the whole run. A run once graded "captions on 45/52 frames"
    # while the app had crashed 10 s in — the OCR was reading home-screen labels in
    # the caption band. The diag heartbeat is the evidence: the app writes the
    # buffer line every ~5 s while playing, so a last line more than 45 s before
    # capture ended means the process died (or playback ended) mid-scenario.
    last_diag = 0.0
    for line in diag_text.splitlines():
        m = re.match(r"^(\d{10}\.\d{3}) ", line)
        if m:
            last_diag = max(last_diag, float(m.group(1)))
    capture_end = shots[-1][0] if shots else time.time()
    grade("app_alive_to_end", last_diag > 0 and capture_end - last_diag < 45,
          f"last diag heartbeat {capture_end - last_diag:.0f}s before capture end"
          if last_diag else "no diag heartbeats at all (was the diag door honoured?)")

    # B. Playback advances. Startup pre-roll (t=0 while the buffer fills) is the
    # time-to-first-frame bound's domain, not a freeze.
    frozen = sum(1 for (w1, t1, _), (w2, t2, _) in zip(buf, buf[1:])
                 if w2 - w1 > 4 and t2 <= t1 and t1 > 0)
    grade("playhead_advances", frozen == 0 and len(buf) > 10,
          f"{len(buf)} buffer samples, {frozen} frozen intervals")

    # C. Stalls / item failures.
    stalls = [e for e in events if T["stall"] in e or T["failed"] in e]
    grade("no_stalls", not stalls, f"{len(stalls)} stall/failure events")

    # D. Audio continuity — only while the instrument was alive, and only
    # CORROBORATED gaps. A missing sample is not silence: a tap can be fed in
    # decode-ahead bursts while the renderer plays smoothly (11 metronomic 10 s
    # "gaps" on the loudest film of a day, zero stalls). A gap counts when a
    # zero-rms sample sits at an edge or a stall event falls inside it. And a
    # watchdog that re-attached a dead tap WAS a rhythmic dropout — the app
    # reports its blindness instead. With the mute door on, a player-level mute
    # may silence the tap too: an audio claim needs --audible.
    if not args.audible:
        print("[scenario] audio_continuous NOT graded: a muted run's tap can read the "
              "mute. Re-run with --audible (after asking the owner) to grade audio.")
        report["audio"] = "not graded (muted run)"
    else:
        tap_died = T["tap_died"] in diag_text
        ev_times = []
        for e in stalls:
            try:
                ev_times.append(float(e.split()[0]))
            except ValueError:
                pass
        gaps = uncorro = 0
        for (a, ra), (b, rb) in zip(aud, aud[1:]):
            if b - a <= 6:
                continue
            if ra < 0.001 or rb < 0.001 or any(a < t < b for t in ev_times):
                gaps += 1
            else:
                uncorro += 1
        covered = (aud[-1][0] - aud[0][0]) if len(aud) > 2 else 0
        ok = (len(aud) > 10 and gaps == 0) or (tap_died and gaps == 0 and len(aud) >= 2)
        grade("audio_continuous", ok,
              f"{len(aud)} rms samples over {covered:.0f}s, {gaps} corroborated gaps>6s"
              + (f", {uncorro} uncorroborated (tap delivery batching)" if uncorro else "")
              + (" (tap died — blind after that)" if tap_died else ""))

    # E. Captions on the GLASS.
    cap_frames = matches = checks = 0
    for wall, p in shots:
        region = texts.get(p.name, {}).get("captionRegion", [])
        if not region:
            continue
        cap_frames += 1
        t = playhead_at(buf, wall)
        if vtt and t is not None:
            covering = [c for c in vtt if c[0] - 1.5 <= t <= c[1] + 1.5]
            if covering:
                checks += 1
                glass = norm(" ".join(region))
                if any(norm(c[2])[:24] in glass or glass[:24] in norm(c[2])
                       for c in covering if len(norm(c[2])) >= 8):
                    matches += 1
    if args.expect_captions == "no":
        # NEGATIVE CONTROL: a caption where there is no speech is a hallucination
        # shipping to a viewer. Judge what the APP DREW (its display trace), not
        # the caption band — a silent film prints its own intertitles there.
        grade("silent_negative_control", not shown,
              f"engine displayed {len(shown)} lines; caption-band OCR hits on "
              f"{cap_frames}/{len(shots)} frames (the film's own text is not counted)")
    else:
        grade("captions_on_glass", cap_frames >= max(3, len(shots) * 0.15),
              f"caption text on {cap_frames}/{len(shots)} frames")
    if args.expect_captions != "no" and vtt:
        # Fail only on POSITIVE evidence of mismatch. A sparse-dialogue window is
        # thin evidence, not failure: with few checks require a majority; with
        # none, presence (above) carries the claim.
        ratio = matches / max(1, checks)
        ok = ratio >= 0.7 if checks >= 5 else (ratio >= 0.5 if checks >= 1 else True)
        grade("glass_matches_file", ok,
              f"{matches}/{checks} on-glass captions match the cue at the playhead"
              + ("" if checks >= 5 else f" (sparse window — {checks} checkable)"))
    if args.expect_captions != "no" and shown and not vtt:
        # ENGINE captions: the glass must show what the engine says it displayed,
        # close in wall time — the pipe end to end (engine -> overlay -> pixels).
        em = ec = 0
        for wall, p in shots:
            region = texts.get(p.name, {}).get("captionRegion", [])
            near = [s for w, s in shown if abs(w - wall) <= 8]
            if not region or not near:
                continue
            ec += 1
            glass = norm(" ".join(region))
            if any(norm(s)[:20] in glass or glass[:20] in norm(s)
                   for s in near if len(norm(s)) >= 8):
                em += 1
        grade("glass_matches_engine", ec >= 5 and em / max(1, ec) >= 0.6,
              f"{em}/{ec} on-glass captions match an engine-displayed line nearby")

    # F. The caption SCHEDULE never runs backwards. An unbounded drift correction
    # once re-anchored every cue by -12 s so LATER audio mapped EARLIER than what
    # was already on screen — fragments out of order, while the engine's own text
    # was fine. Graded from what was SHOWN, in display order.
    mapped = [float(m.group(1)) for m in re.finditer(r"show\[cue=([\d.]+)\]", diag_text)]
    regressions = [(a, b) for a, b in zip(mapped, mapped[1:]) if b < a - 0.5]
    if mapped:
        grade("caption_schedule_monotonic", not regressions,
              f"{len(mapped)} displayed cues, {len(regressions)} ran backwards")

    # G. A blank caption means SILENCE, not a dropped line. Reconstructing that
    # from the trace does not work (a correction moves the cue list after the
    # trace was written), so the display SELF-REPORTS how many cues bracket the
    # playhead at each blank tick.
    blanks = [int(m.group(1)) for m in
              re.finditer(re.escape(T["blank"]) + r"(\d+)", diag_text)]
    if blanks:
        drops = [b for b in blanks if b > 0]
        grade("blank_captions_are_gaps", not drops,
              f"{len(blanks)} blank ticks, {len(drops)} had a cue that should have shown")

    # H. PACING: a caption replaced faster than anyone reads, or a burst of lines
    # in a few seconds WITH an unreadable one inside it (rapid correctly-timed
    # dialogue is not a burst).
    changes, last_text = [], None
    for w, s in shown:
        ns = norm(s)
        if ns and ns != last_text:
            changes.append((w, ns))
            last_text = ns
    if len(changes) >= 8:
        dwells = [b - a for (a, _), (b, _) in zip(changes, changes[1:])]
        fast = [d for d in dwells if d < 1.2]
        med = sorted(dwells)[len(dwells) // 2]
        bursts = sum(1 for i in range(len(changes) - 2)
                     if changes[i + 2][0] - changes[i][0] < 3.0 and any(
                         changes[j + 1][0] - changes[j][0] < 1.0 for j in (i, i + 1)))
        grade("caption_pacing", med >= 2.0 and len(fast) <= len(dwells) * 0.2
              and bursts == 0,
              f"median dwell {med:.1f}s, {len(fast)}/{len(dwells)} changes <1.2s, "
              f"{bursts} burst windows")

    (outdir / "ocr.json").write_text(json.dumps(texts, indent=1))
    return finish(report, outdir)


def finish(report, outdir):
    failed = [k for k, v in report["assertions"].items() if not v["pass"]]
    if report.get("teardown") and not report["teardown"]["ok"]:
        failed.append("teardown")
    report["result"] = "OK" if not failed else "FAIL"
    (outdir / "report.json").write_text(json.dumps(report, indent=1))
    print(f"\nRESULT: {'OK' if not failed else 'FAIL — ' + ', '.join(failed)}")
    print(f"report: {outdir}/report.json")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
