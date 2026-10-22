"""Drive the Mac app by PROCESS, never by name.

`tell application "AppName" to activate` looks harmless and is not. The
harnesses exec the app binary directly (that is the only way APP_* env hooks
reach a GUI app), so the running instance is not a LaunchServices-registered
application. AppleScript therefore resolves the NAME instead, which either

  * launches /Applications/AppName.app alongside the build under test —
    two processes with one name, and screenshots of whichever won the race, or
  * hangs indefinitely waiting for a launch that never completes, which killed
    an entire 18-cell lap when the timeout propagated.

Both were observed. Every call here targets a specific unix pid, so the app under
test is the app measured, and a name collision cannot occur.
"""
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_config  # noqa: E402
from devharness import capture_fresh, ensure_winshot  # noqa: E402

PROC = app_config.APPLE_EXECUTABLE


def _osa(script, timeout=15):
    return subprocess.run(["osascript", "-e", script],
                          capture_output=True, text=True, timeout=timeout)


def quit_all():
    subprocess.run(["pkill", "-x", PROC], capture_output=True)
    time.sleep(1.5)


def launch(binary, env=None):
    """Exec the binary directly and return its real pid. Popen with a list (not
    a shell string) is what makes the pid the APP's rather than a shell's."""
    quit_all()
    import os
    e = dict(os.environ)
    e.update(env or {})
    p = subprocess.Popen([str(binary)], env=e,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return p.pid


def close_projectors(pid):
    """Close leftover projector windows (an app-specific secondary WindowGroup).

    Each hosted night opens one, and macOS restores them all on the next launch —
    a measured session had six stacked up. They are 1280x720 and they sit OVER
    the main window's rectangle, so a screen-region grab of the shell captures a
    projector's idle splash instead."""
    closed = 0
    for i, _name, w, h in reversed(_windows(pid)):
        if (w, h) == PROJECTOR_SIZE:
            try:
                _osa('tell application "System Events" to tell '
                     f'(first process whose unix id is {pid}) to '
                     f'click button 1 of window {i}')
                closed += 1
            except subprocess.SubprocessError:
                pass
    return closed


def raise_pid(pid):
    """Bring this process forward AND raise its MAIN window.

    Raising the process alone is not enough: the frontmost window may be a
    projector, which then covers the shell's rectangle and is what -R captures."""
    try:
        _osa('tell application "System Events" to set frontmost of '
             f'(first process whose unix id is {pid}) to true')
        idx = main_window_index(pid)
        if idx is not None:
            _osa('tell application "System Events" to tell '
                 f'(first process whose unix id is {pid}) to '
                 f'perform action "AXRaise" of window {idx}')
        return True
    except subprocess.SubprocessError:
        return False


# The app's PROJECTOR is its own WindowGroup ("appname-bigscreen",
# defaultSize 1280x720) and macOS restores it across launches — one measured
# session had SEVEN windows: six restored projectors titled "the app" at
# 1280x720, plus the real main window titled "Records" at 1180x760. Asking for
# "front window" photographed a projector and read its idle splash ("The host
# will start the night shortly") as the app ignoring every
# launch hook. The app was correct throughout.
PROJECTOR_SIZE = (1280, 720)


def _windows(pid):
    """Every window as (index, name, w, h), 1-based to match AppleScript.

    Delimiters are literal characters, not tab/newline escapes: those become
    real whitespace inside the AppleScript source and the parse comes back empty.
    """
    script = (
        'tell application "System Events" to tell '
        f'(first process whose unix id is {pid})\n'
        '  set out to ""\n'
        '  repeat with i from 1 to (count of windows)\n'
        '    set w to window i\n'
        '    set {ww, hh} to size of w\n'
        '    set out to out & (i as text) & "~" & (name of w) & "~" & '
        '(ww as text) & "~" & (hh as text) & "|"\n'
        '  end repeat\n'
        '  return out\n'
        'end tell'
    )
    try:
        r = _osa(script, timeout=25)
    except subprocess.SubprocessError:
        return []
    out = []
    for rec in r.stdout.strip().split("|"):
        f = rec.split("~")
        if len(f) == 4 and f[0].strip().isdigit():
            out.append((int(f[0]), f[1], int(f[2]), int(f[3])))
    return out


def main_window_index(pid):
    """The app's MAIN window, never a projector. Projectors are identified by
    their fixed 1280x720 default; anything else is the shell."""
    ws = _windows(pid)
    if not ws:
        return None
    for i, name, w, h in ws:
        if (w, h) != PROJECTOR_SIZE:
            return i
    return ws[0][0]      # all projector-sized — fall back rather than guess


def bounds(pid):
    idx = main_window_index(pid)
    if idx is None:
        return None
    try:
        r = _osa('tell application "System Events" to tell '
                 f'(first process whose unix id is {pid}) to '
                 f'get {{position, size}} of window {idx}', timeout=20)
    except subprocess.SubprocessError:
        return None
    n = [int(x) for x in re.findall(r"-?\d+", r.stdout)]
    return tuple(n[:4]) if len(n) >= 4 else None


def capture(pid, path, tries=12):
    """Capture the app's MAIN WINDOW by window id, owned by exactly this pid.

    Never a screen region (`-R`) and never the full screen. A region grab takes
    SCREEN pixels, so anything in front of the app window lands in the frame — which
    has meant personal documents in other windows.
    The window-id capture reads the window's own content whether or not it is in
    front, so it needs no raise either. Restored secondary windows (projectors) are
    skipped by their fixed size."""
    ok, why = ensure_winshot()
    if not ok:
        print(f"[mac] no window-capture instrument: {why}")
        return False
    close_projectors(pid)
    for _ in range(tries):
        ok, why = capture_fresh(path, lambda p: subprocess.run(
            [str(app_config.WINSHOT_BIN), f"pid:{pid}", "", str(p),
             "--min-width", "200",
             "--skip-size", f"{PROJECTOR_SIZE[0]}x{PROJECTOR_SIZE[1]}"],
            capture_output=True, text=True, timeout=40))
        if ok and Path(path).stat().st_size > 5000:
            return True
        time.sleep(1.2)
    print(f"[mac] window capture failed: {why}")
    return False
