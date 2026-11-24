"""ios_uitest's frame check keys frames on Class/test, and a system overlay blinds every later test.

Two defects from the iPhone 12 run of 2026-11-23 (BACKLOG-LOOP B14):
(a) frames were matched to tests by bare method name, so TabSmokeUITests/testHome's Screen Time
    frame failed LayoutSweepUITests/testHome too, a test whose own frames were clean;
(b) once Screen Time's Time Limit covered the app, the run kept reporting the tests after it as
    PASS or FAIL, though XCUITest matched elements through the overlay and none of them saw the app.

The fixtures are a result-bundle test tree, an attachments manifest, and xcodebuild log lines in
the shape the real run wrote; OCR and the flat-color check are replaced by seams.

    python3 tools/test_ios_uitest_frames.py
"""
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ios_uitest as U  # noqa: E402

ran = failed = 0


def check(name, ok, detail=""):
    global ran, failed
    ran += 1
    if not ok:
        failed += 1
        print(f"FAIL {name}{': ' + detail if detail else ''}")


RUN = [  # execution order, as the log has it: LayoutSweep runs before TabSmoke
    ("LayoutSweepUITests", "testHome"),
    ("LayoutSweepUITests", "testLibrary"),
    ("TabSmokeUITests", "testHome"),
    ("TabSmokeUITests", "testLibrary"),
    ("TabSmokeUITests", "testSearch"),
]


def tree():
    suites = {}
    for cls, m in RUN:
        suites.setdefault(cls, []).append({"nodeType": "Test Case", "name": f"{m}()",
                                           "nodeIdentifier": f"{cls}/{m}()", "result": "Passed"})
    return {"testNodes": [{"nodeType": "Test Plan", "name": "EarDramaUITests", "children": [
        {"nodeType": "UI test bundle", "name": "EarDramaUITests", "children": [
            {"nodeType": "Test Suite", "name": c, "children": kids} for c, kids in suites.items()]}]}]}


def log_text():
    out = []
    for cls, m in RUN:
        out += [f"Test Case '-[EarDramaUITests.{cls} {m}]' started.",
                "    t =     0.01s Start Test at 2026-11-23 19:19:24.174",
                f"Test Case '-[EarDramaUITests.{cls} {m}]' passed (4.100 seconds)."]
    return "\n".join(out) + "\n"


def fixture(overlay_on):
    """A manifest with one frame per test; the frame of `overlay_on` shows Screen Time."""
    d = Path(tempfile.mkdtemp())
    manifest, text = [], {}
    for cls, m in RUN:
        f = f"{cls}-{m}.png"
        (d / f).write_bytes(b"png")
        manifest.append({"testIdentifier": f"{cls}/{m}()", "attachments": [
            {"suggestedHumanReadableName": f"{m} frame", "exportedFileName": f}]})
        text[f] = "Time Limit You've reached your limit on Ear Drama" if f"{cls}/{m}()" == overlay_on \
            else "Home Browse Record Search Library"
    (d / "manifest.json").write_text(json.dumps(manifest))
    U.frame_blind.is_blind = lambda p: False

    def ocr(shots):
        return {p.name: {"allText": [{"text": text[p.name]}]} for _, p in shots}
    tests = []
    for n in tree()["testNodes"]:
        U.collect_tests(n, tests)
    shots = U.read_manifest(d)
    return tests, U.overlay_check(d, shots, ocr=ocr)


def status(lines, test_id):
    for line in lines:
        if not line.startswith(" ") and f" {test_id} " in f"{line} ":
            return line.split(" ", 1)[0]
    return None


def case_keyed_on_class():
    tests, overlays = fixture("TabSmokeUITests/testHome()")
    lines, _ = U.verdicts(tests, overlays, {})
    check("(a) result rows name Class/test",
          any(" TabSmokeUITests/testHome() " in f"{x} " for x in lines), "\n".join(lines))
    check("(a) the test whose frame shows the overlay fails",
          status(lines, "TabSmokeUITests/testHome()") == "FAIL", "\n".join(lines))
    check("(a) a same-named test in another class with clean frames passes",
          status(lines, "LayoutSweepUITests/testHome()") == "PASS", "\n".join(lines))


def case_overlay_blinds_later_tests():
    tests, overlays = fixture("TabSmokeUITests/testHome()")
    try:
        lines, ok = U.verdicts(tests, overlays, {}, order=U.test_order(log_text()))
    except (TypeError, AttributeError) as e:
        check("(b) verdicts takes the run order", False, repr(e))
        return
    check("(b) a run with an overlay is not ok", ok is False)
    check("(b) tests before the overlay keep their result",
          status(lines, "LayoutSweepUITests/testLibrary()") == "PASS", "\n".join(lines))
    for t in ("TabSmokeUITests/testLibrary()", "TabSmokeUITests/testSearch()"):
        check(f"(b) {t}, run after the overlay, is BLIND", status(lines, t) == "BLIND", "\n".join(lines))
    loud = [x for x in lines if x.startswith("DEVICE")]
    check("(b) one line says the device needs the limit lifted",
          len(loud) == 1 and "Screen Time" in loud[0] and "2 later tests" in loud[0], "\n".join(loud))


def case_clean_run_has_no_blind():
    tests, overlays = fixture(None)
    lines, ok = U.verdicts(tests, overlays, {}, order=U.test_order(log_text()))
    check("(control) a clean run passes every test",
          ok and all(x.startswith("PASS") for x in lines), "\n".join(lines))


def case_skip_is_not_a_failure():
    """InkUITests skips itself on an iPhone (XCTSkip): a skip is reported, never a FAIL."""
    lines, ok = U.verdicts([("InkUITests/testInkFollowsItsLine()", "Skipped"),
                            ("TabSmokeUITests/testHome()", "Passed")], {}, {})
    check("(skip) a skipped test reads SKIP and the run stays ok",
          ok and lines[0] == "SKIP InkUITests/testInkFollowsItsLine()", "\n".join(lines))


def main():
    case_keyed_on_class()
    case_skip_is_not_a_failure()
    case_overlay_blinds_later_tests()
    try:
        case_clean_run_has_no_blind()
    except (TypeError, AttributeError) as e:
        check("(control) verdicts takes the run order", False, repr(e))
    print(f"{ran - failed}/{ran} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
