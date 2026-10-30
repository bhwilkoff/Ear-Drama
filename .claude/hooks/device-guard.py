#!/usr/bin/env python3
"""PreToolUse guard for Bash: the device rules are enforced here, not remembered.

Owner, 2026-10-30: "Can you figure out why I keep having to remind you of things that
are in your repository?" A rule that lives only in a doc or a memory is skipped at the
moment of action, so this hook:
  * DENIES booting or creating a simulator/emulator, or an xcodebuild run aimed at a
    simulator destination (owner: "We never use simulators in testing for real devices.");
  * DENIES launching Chrome without --mute-audio (a headless render played an episode
    aloud on the owner's Mac);
  * INJECTS the matching docs/DEVICE-HARNESSES.md section before device commands, once
    per section per session, so the runbook is read before acting, not after failing.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNBOOK = ROOT / "docs" / "DEVICE-HARNESSES.md"
SEEN_DIR = Path("/tmp/claude-device-guard")

DENY = [
    (re.compile(r"\bsimctl\s+(boot|create|clone)\b"), "boots or creates a simulator"),
    (re.compile(r"open\s+(-a\s+)?\"?Simulator\b|Simulator\.app"), "opens the Simulator app"),
    (re.compile(r"\bemulator\s+(@|-avd\b)|\bavdmanager\s+create\b"), "starts or creates an Android emulator"),
    (re.compile(r"-destination\s+['\"]?[^'\"]*Simulator", re.I), "aims xcodebuild at a simulator destination"),
]
SIM_REASON = ("Blocked by .claude/hooks/device-guard.py: this command {what}. Owner rule "
              "(2026-09-03, again 2026-10-30): \"We never use simulators in testing for real "
              "devices. We have the devices to test on.\" Use the bench in tools/app_config.py "
              "DEVICES (iphone, ipad, appletv, android, mac) with tools/ios_run.py, ios_uitest.py, "
              "atv_run.py, adb_run.py or qa_suite.py; build with -destination generic/platform=... "
              "If a device is off, say so and leave that platform unseen.")

CHROME = re.compile(r"(Google Chrome|chromium|chrome-headless|--headless)", re.I)
CHROME_REASON = ("Blocked by .claude/hooks/device-guard.py: Chrome is being launched without "
                 "--mute-audio. A headless render played an episode aloud on the owner's Mac "
                 "(2026-10-30); the owner rule is to ask before any audible run. Add --mute-audio "
                 "--autoplay-policy=user-gesture-required and load pages with ?mute=1.")

# Command pattern -> runbook headings to inject (first match wins per heading).
CONTEXT = [
    (re.compile(r"ios_uitest\.py|EarDramaUITests|xcodebuild\s+test(-without-building)?\b.*-destination\s+['\"]?id="),
     ["### XCUITest is the tap tier", "### The arrangement"]),
    (re.compile(r"ios_run\.py|ios_scenario\.py|devicectl"), ["### The arrangement", "### The tools", "### devicectl recipes"]),
    (re.compile(r"atv_run\.py|atv_scenario|atvremote|pyatv"), ["### Wake, power and presses", "### Alive is not frontmost"]),
    (re.compile(r"\badb\b|adb_run\.py"), ["## Android phone"]),
    (re.compile(r"qa_suite\.py"), ["## The shared tools"]),
    (re.compile(r"mac_run\.py|macapp\.py"), ["## Mac"]),
]
MAX_CHARS = 3500


def section(text, heading):
    lines = text.splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == heading)
    except StopIteration:
        return None
    level = len(heading) - len(heading.lstrip("#"))
    out = [lines[start]]
    for l in lines[start + 1:]:
        m = re.match(r"^(#+)\s", l)
        if m and len(m.group(1)) <= level:
            break
        out.append(l)
    body = "\n".join(out).strip()
    return body if len(body) <= MAX_CHARS else body[:MAX_CHARS] + "\n[... read the rest in docs/DEVICE-HARNESSES.md]"


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    if data.get("tool_name") != "Bash":
        return 0
    raw = (data.get("tool_input") or {}).get("command") or ""
    # Text a command only carries (heredoc bodies, commit messages, echo'd notes) is not a
    # command it runs: a commit message describing this hook was itself denied.
    cmd = re.sub(r"<<-?\s*['\"]?(\w+)['\"]?.*?\n.*?\n\s*\1\b", "<<HEREDOC", raw, flags=re.S)
    cmd = re.sub(r"(git\s+commit[^\n]*?\s-m\s*)(\"(?:\\.|[^\"])*\"|'[^']*')", r"\1MSG", cmd)
    cmd = re.sub(r"(\becho\s+)(\"(?:\\.|[^\"])*\"|'[^']*')", r"\1MSG", cmd)

    for rx, what in DENY:
        if rx.search(cmd):
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse", "permissionDecision": "deny",
                "permissionDecisionReason": SIM_REASON.format(what=what)}}))
            return 0
    if re.search(r"\bsimctl\s+(list|delete|shutdown|erase)\b", cmd) is None and CHROME.search(cmd) \
            and re.search(r"(\bopen\b|\s--|Google Chrome\"?\s*$|Contents/MacOS/Google Chrome)", cmd) \
            and "--mute-audio" not in cmd and re.search(r"(remote-debugging|--headless|--screenshot|--user-data-dir)", cmd):
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": "deny",
            "permissionDecisionReason": CHROME_REASON}}))
        return 0

    headings = []
    for rx, hs in CONTEXT:
        if rx.search(cmd):
            headings += [h for h in hs if h not in headings]
    if not headings or not RUNBOOK.exists():
        return 0
    seen_file = SEEN_DIR / (re.sub(r"[^A-Za-z0-9_-]", "", data.get("session_id") or "nosession") + ".txt")
    seen = set(seen_file.read_text().splitlines()) if seen_file.exists() else set()
    fresh = [h for h in headings if h not in seen]
    if not fresh:
        return 0
    text = RUNBOOK.read_text()
    parts = [s for s in (section(text, h) for h in fresh) if s]
    if not parts:
        return 0
    SEEN_DIR.mkdir(parents=True, exist_ok=True)
    seen_file.write_text("\n".join(sorted(seen | set(fresh))))
    ctx = ("Runbook check (device-guard hook): read before acting on this device command; a "
           "failure it describes is already solved.\n\n" + "\n\n".join(parts))
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": ctx}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
