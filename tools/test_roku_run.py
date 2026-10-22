#!/usr/bin/env python3
"""Offline tests for the Roku harness's pure parsers and the design lint.

No device, no network. Each lint rule gets a PLANTED violation it must catch, plus
a clean file it must not flag — a rule nobody has seen fire is a rule nobody knows
works.

    python3 tools/test_roku_run.py
"""
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import roku_design_lint as lint  # noqa: E402
import roku_run as roku  # noqa: E402

fails = []


def check(name, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'} {name}" + (f" — {detail}" if detail and not ok else ""))
    if not ok:
        fails.append(name)


# ── installer verdict ────────────────────────────────────────────────────────
# The page's own JS mentions "error" and "success" in comments; only the typed
# message blob is the verdict.
PAGE_OK = """<script>// on error show red; on success show green
var params = JSON.parse('{"messages":[{"text":"Received 412345 bytes.","text_type":"text","type":"info"},{"text":"Install Success.","text_type":"text","type":"success"}]}');
</script>"""
PAGE_ERR = """<script>// success path below
x = [{"text":"Install Failure: Compilation Failed.","text_type":"text","type":"error"}]</script>"""
PAGE_IDENT = """[{"text":"Identical to previous version -- not replacing.","text_type":"text","type":"info"}]"""
PAGE_BLANK = "<html><body>401 Unauthorized — the words error and success appear here</body></html>"

check("success-typed message is OK despite 'error' in a JS comment",
      roku.install_verdict(roku.installer_messages(PAGE_OK))[0] == "ok")
check("error-typed message is FAILED despite 'success' in a JS comment",
      roku.install_verdict(roku.installer_messages(PAGE_ERR))[0] == "failed")
check("identical refusal is recognised",
      roku.install_verdict(roku.installer_messages(PAGE_IDENT))[0] == "identical")
check("an unparseable page is UNVERIFIED, never OK",
      roku.install_verdict(roku.installer_messages(PAGE_BLANK))[0] == "unverified")

# ── media-player units ───────────────────────────────────────────────────────
MP = """<?xml version="1.0" encoding="UTF-8" ?>
<player error="false" state="play"><format audio="aac" captions="none" container="mp4"
 drm="none" video="mpeg4 avc" video_res="1920x1080" /><buffering current="1000" max="1000"
 target="0" /><position>37871 ms</position><duration>5412000 ms</duration></player>"""
mp = roku.parse_media_player(MP)
check("position parsed through its unit", mp.get("position") == 37871, mp)
check("duration parsed through its unit", mp.get("duration") == 5412000, mp)
check("state/error/codec read", (mp["state"], mp["error"], mp["video"]) == ("play", "false", "mpeg4 avc"))
check("garbage is {} (not a crash)", roku.parse_media_player("not xml") == {})
check("absent position is None, not 0",
      roku.parse_media_player('<player state="startup" error="false"/>')["position"] is None)

# ── ECP key names are a closed set ───────────────────────────────────────────
check("alias ok -> Select", roku.key_name("ok") == "Select")
check("Lit_ passes through", roku.key_name("Lit_a") == "Lit_a")
try:
    roku.key_name("OKAY")
    check("unknown key name is refused", False, "no exception")
except SystemExit as e:
    check("unknown key name is refused", "HTTP 200" in str(e))

# ── channel foreground ───────────────────────────────────────────────────────
check("dev channel id counts as ours",
      roku.channel_foreground('<active-app><app id="dev" type="appl">X</app></active-app>'))
check("another app is not ours",
      not roku.channel_foreground('<active-app><app id="12" type="appl">Other</app></active-app>'))

# ── design lint: one planted control per rule ────────────────────────────────
PLANTS = {
    "system-font": 'm.l.font = "font:MediumSystemFont"',
    "narration": 'm.hint.text = "Press OK to play"',
    "raw-slug": f"m.kind.text = UCase(item.{lint.SLUG_FIELD})",
    "accent-focus": f"m.title.color = {lint.ACCENT}",
    "ring-bitmap": f'm.ring.uri = "pkg:/images/{lint.RETIRED_RING_BITMAPS[0]}"',
    "flat-plate": f'p = m.top.CreateChild("Rectangle")\n    p.height = {lint.BUTTON_PLATE_HEIGHT}',
    "pure-white": 'm.l.color = "0xFFFFFFFF"',
    "emoji": 'm.b.text = "⏩ Skip"',
}
with tempfile.TemporaryDirectory() as d:
    root = Path(d)
    for rule, code in PLANTS.items():
        (root / f"{rule}.brs").write_text(f"sub init()\n    {code}\nend sub\n")
    (root / "Clean.brs").write_text(
        "sub init()\n"
        "    ' Press OK to play  <- a comment, not UI\n"
        '    m.l.font = "pkg:/fonts/Text-Regular.ttf"\n'
        '    m.l.color = "0xEBEBEBFF"\n'
        "    m.kind.text = KindLabel(item)\n"
        "end sub\n")
    (root / "Clean.xml").write_text('<component name="C"><!-- "Press OK to play" --></component>\n')
    _, findings = lint.lint(root)
    by_file = {}
    for fn, _line, rule, _snip in findings:
        by_file.setdefault(fn, set()).add(rule)
    for rule in PLANTS:
        check(f"lint rule fires on its plant: {rule}", rule in by_file.get(f"{rule}.brs", set()),
              f"got {by_file.get(f'{rule}.brs')}")
    check("clean files have zero findings",
          not by_file.get("Clean.brs") and not by_file.get("Clean.xml"), by_file)
    check("a missing root is not a pass",
          lint.main(["--root", str(root / "nope")]) == 1)
    check("--allow-missing makes a missing root exit 0",
          lint.main(["--root", str(root / "nope"), "--allow-missing"]) == 0)

print("\nALL PASS" if not fails else f"\nFAILED: {', '.join(fails)}")
sys.exit(1 if fails else 0)
