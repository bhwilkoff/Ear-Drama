"""ios_uitest.dropped_launches against real xcodebuild lines (iPhone 12, 2026-10-28 4:35 PM).

The failing test is the one whose open(URL) the device dropped (CoreDevice 10004): it
must be named, with the step. The passing test right after it, which opened a URL the
same way, and an ordinary assertion failure are the controls: neither may be named.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ios_uitest import dropped_launches  # noqa: E402

DROPPED = """\
Test Case '-[EarDramaUITests.SearchUITests testDateFindsWhatAired]' started.
    t =     0.04s Open app.eardrama
    t =     0.04s     Launch app.eardrama
    t =     5.22s         Wait for app.eardrama to idle
    t =     9.54s Open app.eardrama with URL eardrama://search?q=gangbusters+august+1954
    t =     9.55s     Launch app.eardrama
/Users/x/Ear-Drama/apple/UITests/SearchUITests.swift:10: error: -[EarDramaUITests.SearchUITests testDateFindsWhatAired] : Failed to get launch progress for <XCUIApplicationImpl: 0x15e05a280 app.eardrama at /Users/x/build/uitest-dd/Build/Products/Debug-iphoneos/EarDrama.app>: The process identifier of the launched application could not be determined. It may have already terminated.
Test Case '-[EarDramaUITests.SearchUITests testDateFindsWhatAired]' failed (10.755 seconds).
"""
PASSED = """\
Test Case '-[EarDramaUITests.SearchUITests testTranscriptWordListsTheLineSaid]' started.
    t =     0.02s             Launch app.eardrama
    t =     5.44s         Open app.eardrama with URL eardrama://search?q=zeppelin
    t =     5.46s             Launch app.eardrama
    t =     6.49s                 Wait for app.eardrama to idle
Test Case '-[EarDramaUITests.SearchUITests testTranscriptWordListsTheLineSaid]' passed (10.565 seconds).
"""
ASSERTED = """\
Test Case '-[EarDramaUITests.SiteLinksUITests testCreditsOpensTheSiteAndComesBack]' started.
    t =     0.01s             Launch app.eardrama
/Users/x/apple/UITests/SiteLinksUITests.swift:31: error: -[EarDramaUITests.SiteLinksUITests testCreditsOpensTheSiteAndComesBack] : XCTAssertNotEqual failed: ("XCUIApplicationState(rawValue: 4)") is equal to ("XCUIApplicationState(rawValue: 4)")
Test Case '-[EarDramaUITests.SiteLinksUITests testCreditsOpensTheSiteAndComesBack]' failed (37.788 seconds).
"""


def main():
    bad = []
    got = dropped_launches(DROPPED + PASSED + ASSERTED)
    want = [("SearchUITests/testDateFindsWhatAired",
             "Open app.eardrama with URL eardrama://search?q=gangbusters+august+1954")]
    if got != want:
        bad.append(f"expected {want}, got {got}")
    if dropped_launches(PASSED + ASSERTED):
        bad.append("a passing open(URL) or an assertion failure read as a dropped launch")
    for b in bad:
        print("FAIL", b)
    print(f"{2 - len(bad)}/2 passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
