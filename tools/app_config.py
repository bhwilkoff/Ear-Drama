"""The one place a new app fills in its identity.

Every harness in `tools/` imports from here rather than hardcoding a bundle id, so
adopting the fleet-testing rig in a new app is one file to edit instead of fifteen.

Fill these in when you clone the template. The device ids come from:

    xcrun devicectl list devices          # Apple: iPhone, iPad, Apple TV
    adb devices -l                        # Android
    xcrun simctl list devices available   # simulators

Leave a device as None and the harnesses skip it and SAY they skipped it — a fleet
entry that silently does nothing is the failure this whole rig exists to prevent.

A bench with more than one device of a kind (three Apple TVs on different OS
versions, a floor device, the TV the owner actually watches) does not fit in
DEVICES. Describe it in a bench manifest instead — see tools/bench.py and
tools/bench.example.json. DEVICES keeps working when there is no manifest.
"""
import os
from pathlib import Path

# --- App identity -------------------------------------------------------------
APPLE_BUNDLE_ID = "com.example.appname"           # iOS / iPadOS / tvOS / macOS
APPLE_APP_NAME = "AppName"                        # the .app / scheme name
# The executable inside the .app — what `devicectl device info processes` prints
# (an executable PATH, never the bundle id). Usually the same as the app name.
APPLE_EXECUTABLE = "AppName"
ANDROID_PACKAGE = "com.example.appname"
ANDROID_PACKAGE_DEBUG = "com.example.appname.debug"
ANDROID_MAIN_ACTIVITY = "com.example.appname.MainActivity"
WINDOWS_PROCESS = "AppName"                       # the .exe, minus the extension
WEB_URL = "http://localhost:8080"
# The Roku dev channel's display name, as /query/active-app prints it.
ROKU_CHANNEL_NAME = "AppName"

# --- Product health (tools/pulse_collect.py, /pulse) --------------------------
# The numeric App Store id, from the listing URL or `v1/apps?filter[bundleId]=`.
APPLE_APP_STORE_ID = ""                           # e.g. "1234567890"
GITHUB_REPO = ""                                  # e.g. "owner/Repo"
PRODUCT_NAME = "AppName"                          # how a human writes it
PRODUCT_SITE = "https://example.com"              # the public site, no slash
# What counts as somebody talking about US when searching the open web. The
# LOOSE term is matched only alongside a corroborating word, because a product
# name is usually also two ordinary English words.
MENTION_STRICT = ("example.com", "appname")
MENTION_LOOSE = "app name"
# Play Console -> Download reports -> Statistics -> "Copy Cloud Storage URI".
# NOT derivable from the developer id in the Console URL.
PLAY_REPORTS_BUCKET = ""                          # e.g. "pubsite_prod_rev_0978..."


# --- The bench ----------------------------------------------------------------
# Real hardware, by udid/serial. None = not on this bench. This is the SIMPLE form,
# one device per kind. A manifest (tools/bench.py) overrides it when present.
DEVICES = {
    "iphone":  None,      # devicectl udid
    "ipad":    None,      # devicectl udid
    "appletv": None,      # devicectl udid (paired over the network)
    "android": None,      # adb serial
    "mac":     "local",   # the Mac this runs on
    "windows": None,      # hostname or IP for SSH; see winbox.py
    "web":     "local",   # a local Chrome driven over CDP
}

# --- Tool locations -----------------------------------------------------------
# Durable, never /tmp: /tmp is cleared on reboot, and an instrument that vanishes
# overnight turns the next morning's run into "every frame unreadable". ONE path per
# binary, shared by every runner — two harnesses once looked for the OCR tool under
# two different /tmp names and one of them silently skipped its readability check.
REPO = Path(__file__).resolve().parent.parent
BIN_DIR = Path(os.environ.get("HARNESS_BIN_DIR", REPO / "build" / "bin"))
OCR_BIN = Path(os.environ.get("SCREEN_OCR", BIN_DIR / "screenocr"))
OCR_SRC = REPO / "tools" / "ScreenOCR" / "main.swift"
WINSHOT_BIN = Path(os.environ.get("WINSHOT", BIN_DIR / "winshot"))
WINSHOT_SRC = REPO / "tools" / "mac_window_shot.swift"
QA_ROOT = Path(os.environ.get("QA_ROOT", REPO / "build" / "qa"))
# pyatv lives in its own venv, pinned to Python 3.12: atvremote does not run on 3.14.
#   python3.12 -m venv ~/.pyatv-venv && ~/.pyatv-venv/bin/pip install pyatv
PYATV = Path(os.environ.get("PYATV", Path.home() / ".pyatv-venv" / "bin" / "atvremote"))
ADB = Path(os.environ.get("ADB", Path.home() / "Library/Android/sdk/platform-tools/adb"))
# Empty = inherit `xcode-select -p`. Set it when devicectl must come from a beta Xcode;
# it is passed into every devicectl subprocess explicitly, because a plain os.environ
# copy does not carry it when the parent shell never exported it.
DEVELOPER_DIR = os.environ.get("DEVELOPER_DIR", "")

# --- Env hooks ----------------------------------------------------------------
# The env vars / intent extras your app reads to open a screen directly. These are
# what make surfaces reachable; see docs/AUTONOMOUS-FLEET-TESTING.md section 3.
#
# They must be no-ops in production, and on Android they must be BuildConfig.DEBUG
# gated AND you must install the DEBUG build — against a release build they silently
# do nothing, every scenario lands on Home, and every scenario passes.
HOOK_SKIP_ONBOARD = "APP_SKIP_ONBOARD"
HOOK_START_TAB = "APP_START_TAB"
HOOK_START_ITEM = "APP_START_ITEM"
HOOK_AUTOPLAY = "APP_AUTOPLAY"
# Labels the device's glass with what it is testing (tools/devreset.py label()).
HOOK_QA_LABEL = "APP_QA_LABEL"
# The whole app at one Dynamic Type size (xxxLarge | accessibility2 | ...), so a sweep
# can prove the largest sizes lay out without a human changing a system setting.
HOOK_TYPE_SIZE = "APP_TYPE_SIZE"
# Render the offline UI STATE for a screenshot. It fakes the state, never the network's
# response to it — the real offline proof denies the network to the process.
HOOK_FORCE_OFFLINE = "APP_FORCE_OFFLINE"

# The item every runner's "item" scenario opens with HOOK_START_ITEM (the web's
# ?item=), and text its detail screen renders. FILL IN both with a real id from your
# catalog and a phrase calibrated against a real capture of that item's screen.
QA_ITEM_ID = "example-item"                       # FILL IN
QA_ITEM_RX = r"example-item"                      # FILL IN

# --- Doors are muted and time-bounded by default ------------------------------
# A harness that plays media on someone's television is in their living room. A
# film was once left playing unmuted after a screenshot run and routed to every
# speaker in the house for an hour, because the door that started it polled until
# told to stop and nothing told it to. So every launch a harness makes carries:
#   * MUTE — the app's player is silent unless a run explicitly opts in (--audible),
#     and an audible run is something you ASK the owner about first;
#   * a SECONDS bound — the app ends the door's activity (stops playback, leaves the
#     room) on its own after this long, so a crashed harness cannot leave it running.
# Note: a player-level mute can also silence audio a TAP reads, so an audio-level
# assertion needs --audible (and the owner's say-so), or it measures the mute.
HOOK_MUTE = "APP_MUTE"
HOOK_DOOR_SECONDS = "APP_DOOR_SECONDS"
DOOR_SECONDS = 180
DOOR_DEFAULTS = {HOOK_MUTE: "1", HOOK_DOOR_SECONDS: str(DOOR_SECONDS)}
# The Android spelling: every hook is an intent extra named <prefix><hook minus
# "APP_", lowercased> (APP_START_TAB -> appname_start_tab). Derive it with
# android_extra() rather than retyping it, so the two spellings cannot drift.
ANDROID_EXTRA_PREFIX = "appname_"


def android_extra(hook):
    return ANDROID_EXTRA_PREFIX + hook.removeprefix("APP_").lower()


# The door defaults as intent extras ((type, value) pairs for `am start`).
ANDROID_DOOR_EXTRAS = {android_extra(HOOK_MUTE): ("ez", "true"),
                       android_extra(HOOK_DOOR_SECONDS): ("ei", str(DOOR_SECONDS))}

# --- Diagnostics file (tools/atv_scenario.py) ---------------------------------
# A console stream cannot coexist with screenshot captures on an Apple device (two
# devicectl sessions kill the stream, and killing the console kills the app), so a
# playback run has the app write `<epoch.millis> <message>` lines to a file in its
# container and pulls the file afterwards. Pull BEFORE relaunching: launch truncates it.
HOOK_DIAG_FILE = "APP_DIAG_FILE"
DIAG_CONTAINER_PATH = "Library/Caches/appdiag.log"
# The message tags the scenario grader parses. Rename to match what your app prints.
DIAG_TAGS = {
    "buffer": "APPBUF",        # `APPBUF t=<playhead s> ahead=<buffered s>`, every ~5 s
    "audio": "APPAUD rms",     # `APPAUD rms=<0..1>` while audio flows
    "stall": "APPSTALL",       # a stall the player detected
    "failed": "itemFailed",    # the player item failed
    "tap_died": "tap died",    # the audio instrument went blind (not a dropout)
    "shown": "show[cue=",      # `trace t=.. show[cue=<s>]: <caption text>`
    "blank": "blank, cues bracketing=",
}

# --- Grading ------------------------------------------------------------------
# CALIBRATE these against a real capture from the real device. Never copy a
# threshold from another project: a 0.010 clip threshold ported between two apps
# reported three correctly-rendered headings as clipped on every frame.
CLIP_X = 0.005                 # normalised x below which text is "clipped"
MIN_OCR_LINES = 4              # fewer than this = the frame is unreadable

# The app's own on-screen VOCABULARY — words that prove the right app is showing a
# real screen. The harness grades "is my app on the glass" by matching this, so it
# must be words your UI actually renders (tab titles, primary actions), not the app's
# name. Getting this wrong makes every scenario fail with "wrong app/screen".
APP_ANCHOR_RX = r"Home|Settings|Search"          # FILL IN

# Text that means the app is broken, whatever else is on screen.
FORBIDDEN = (r"No results|Couldn.t load|Something went wrong|"
             r"failed to|\berror\b|couldn.t be")

# What the tvOS HOME SCREEN looks like to OCR — the "alive but not frontmost" probe.
# Streaming-app tiles and the clock are what a backgrounded launch leaves on the glass.
TVOS_HOME_RX = (r"prime video|pluto|fubo|Apple TV\+|Select up for full screen|"
                r"\d{1,2}:\d{2} [AP]M")
