#!/usr/bin/env python3
"""Source checks for Apple design-doc rules that no unit test can reach
(menus, the TV shell, haptics call sites). Each check runs on the real source
and on a broken copy; a check that passes the broken copy is itself a failure.

    python3 tools/test_apple_design_rules.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPLE = ROOT / "apple"


def read(rel):
    return (ROOT / rel).read_text()


def controls_menu(text):
    m = re.search(r"struct PlaybackCommands_macOS.*?\n}\n", text, re.S)
    return m.group(0) if m else ""


def no_bare_space_in_controls(text):
    """macOS-DESIGN §5.3: no Controls item takes a bare key."""
    menu = controls_menu(text)
    return bool(menu) and "modifiers: [])" not in menu and ".onKeyPress(.space)" in text


def go_and_help_menus(text):
    """macOS-DESIGN §5.5, §5.6."""
    return all(s in text for s in (
        'CommandMenu("Go")', 'keyboardShortcut("f", modifiers: .command)',
        'keyboardShortcut("[", modifiers: .command)', "CommandGroup(replacing: .help)",
        "SiteLinks.credits", "SiteLinks.privacy", "SiteLinks.takedown"))


def tv_way_back(text):
    """tvOS-DESIGN §5.4: every tab root carries the Now Playing entry."""
    stack = re.search(r"private func stack<.*?\n    }\n", text, re.S)
    return bool(stack) and "NowPlayingEntry_tvOS()" in stack.group(0) and "store.isPlayerPresented = true" in text


def tv_versions(text):
    """tvOS-DESIGN §4.4, R5."""
    return "VersionsSection_tvOS(detail: detail)" in text and "recording: recording, presentPlayer: true" in text


def detail_share_twin(text):
    """iOS-DESIGN §4.4: Share carries the https twin."""
    return "ShareLink(item: SiteLinks.episode(episode.id)" in text


def phone_shell_is_five_verbs(text, home):
    """iOS-DESIGN §3.1 (Decision 068): iPhone's bar is Home, Browse, Stations,
    Search, Library; Surprise is listed only at regular width, hidden from the
    bar, and Home's toolbar pushes it."""
    tabs = re.findall(r"Tab\(AppTab\.(\w+)\.title", text)
    at = text.find("Tab(AppTab.surprise.title")
    gate = text.rfind("if hSize == .regular", 0, at)
    return (tabs == ["home", "browse", "stations", "search", "library", "surprise"]
            and gate != -1 and ".defaultVisibility(.hidden, for: .tabBar)" in text[at:]
            and "store.push(Route.surprise)" in home)


def haptics_through_mapping(files):
    """iOS-DESIGN §6.5: no feedback call names the system's feedback directly."""
    bad = []
    for path, text in files.items():
        if path.endswith("Core/Haptics.swift"):
            continue
        if re.search(r"\.sensoryFeedback\(\s*\.", text) or "FeedbackGenerator" in text:
            bad.append(path)
    return not bad


def player_numbers_named_once(files):
    """iOS-DESIGN §5.7: no player-number literal outside PlayerNumbers."""
    audio = files["apple/Core/Player/AudioPlayer.swift"]
    sleep = files["apple/Core/Player/SleepTimer.swift"]
    return ("skip(by: -3)" not in audio and ">= 5 {" not in audio and "[0.75" not in audio
            and "fadeSeconds: TimeInterval = 10" not in sleep)


def main():
    failed = 0

    def ok(cond, msg):
        nonlocal failed
        print(f"  {'ok  ' if cond else 'FAIL'}  {msg}")
        if not cond:
            failed += 1

    mac = read("apple/macOS/ContentView_macOS.swift")
    phone = read("apple/iOS/ContentView_iOS.swift")
    tv = read("apple/tvOS/ContentView_tvOS.swift")
    detail = read("apple/Shared/ListScreens.swift")
    swift = {str(p.relative_to(ROOT)): p.read_text() for p in APPLE.rglob("*.swift") if "/Tests/" not in str(p)}

    cases = [
        ("Controls menu takes no bare key; Space is the window's", no_bare_space_in_controls, mac,
         mac.replace("Button(player.isPlaying ? \"Pause\" : \"Play\") { player.togglePlayPause() }",
                     "Button(player.isPlaying ? \"Pause\" : \"Play\") { player.togglePlayPause() }\n"
                     "                .keyboardShortcut(.space, modifiers: [])")),
        ("Go and Help menus", go_and_help_menus, mac, mac.replace('CommandMenu("Go")', 'CommandMenu("View")')),
        ("tvOS tab roots carry Now Playing", tv_way_back, tv,
         tv.replace("                        NowPlayingEntry_tvOS()\n", "")),
        ("tvOS Detail has Versions", tv_versions, tv, tv.replace("VersionsSection_tvOS(detail: detail)", "EmptyView()")),
        ("iPhone's bar is five verbs; Surprise from Home", lambda t: phone_shell_is_five_verbs(t, detail), phone,
         phone.replace("if hSize == .regular {", "if true {")),
        ("Detail shares the https twin", detail_share_twin, detail,
         detail.replace("SiteLinks.episode(episode.id)", "episode.transcriptURL!")),
        ("haptics go through Haptic", haptics_through_mapping, swift,
         {**swift, "x.swift": ".sensoryFeedback(.success, trigger: x)"}),
        ("player numbers named once", player_numbers_named_once, swift,
         {**swift, "apple/Core/Player/AudioPlayer.swift":
          swift["apple/Core/Player/AudioPlayer.swift"].replace(
              "-PlayerNumbers.interruptionRewindSeconds", "-3")}),
    ]
    for name, check, real, broken in cases:
        ok(check(real), name)
        ok(broken != real and not check(broken), f"{name}: catches a broken copy")

    print(f"{failed} check(s) FAILED" if failed else f"all {len(cases)} Apple design rules hold, each with a negative control")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
