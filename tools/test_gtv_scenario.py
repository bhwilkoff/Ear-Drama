#!/usr/bin/env python3
"""Offline test of gtv_scenario's tree parsing — no device is contacted.

The tree fetch is monkeypatched to canned uiautomator XML, including the shape
that hid a whole Home screen once: a MERGED Compose node whose label exists only
in content-desc.

    python3 tools/test_gtv_scenario.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gtv_scenario as G  # noqa: E402

XML = """<?xml version='1.0' encoding='UTF-8'?><hierarchy rotation="0">
<node index="0" text="" content-desc="" class="android.widget.FrameLayout" focusable="false" focused="false" bounds="[0,0][1920,1080]">
<node index="1" text="Home" content-desc="" class="android.widget.TextView" focusable="false" focused="false" bounds="[40,200][300,260]" />
<node index="2" text="" content-desc="" class="android.view.View" focusable="true" focused="false" bounds="[20,190][420,270]" />
<node index="3" text="Search" content-desc="" class="android.widget.TextView" focusable="false" focused="false" bounds="[40,300][300,360]" />
<node index="4" text="" content-desc="" class="android.view.View" focusable="true" focused="true" bounds="[20,290][420,370]" />
<node index="5" text="Settings" content-desc="" class="android.widget.TextView" focusable="false" focused="false" bounds="[40,500][300,560]" />
<node index="6" text="" content-desc="FEATURE FILM, A Title, 1942" class="android.view.View" focusable="true" focused="false" bounds="[480,40][1920,700]" />
<node index="7" text="Play" content-desc="" class="android.widget.TextView" focusable="false" focused="false" bounds="[520,600][640,650]" />
</node></hierarchy>"""

FOCUSED_ON_TILE = XML.replace('focused="true"', 'focused="false"').replace(
    'content-desc="FEATURE FILM, A Title, 1942" class="android.view.View" focusable="true" focused="false"',
    'content-desc="FEATURE FILM, A Title, 1942" class="android.view.View" focusable="true" focused="true"')

fails = []


def check(name, got, want):
    ok = got == want
    print(f"  {'PASS' if ok else 'FAIL'} {name} — got {got!r}, want {want!r}")
    if not ok:
        fails.append(name)


def main():
    G._tree = lambda: XML                 # never touch adb
    n = G.focused_node()
    check("focused node found", n and n["bounds"], (20, 290, 420, 370))
    check("rail row under focus is identified by its LABEL",
          G.rail_tab_at(n["bounds"]), "search")
    check("texts inside the focused box", G.texts_inside(n["bounds"]), ["Search"])
    check("find_text exact", G.find_text("Settings"), (40, 500, 300, 560))
    check("find_text reads content-desc of a merged node",
          G.find_text("A Title"), (480, 40, 1920, 700))
    check("a merged node's label comes from content-desc",
          [x["label"] for x in G.nodes(XML) if x["desc"]], ["FEATURE FILM, A Title, 1942"])

    G._tree = lambda: FOCUSED_ON_TILE
    n = G.focused_node()
    check("focus on the merged tile", n["desc"], "FEATURE FILM, A Title, 1942")
    check("a node right of RAIL_X_MAX is not a rail row", G.rail_tab_at(n["bounds"]), None)
    check("texts inside the tile include its own desc and the Play label",
          G.texts_inside(n["bounds"]), ["FEATURE FILM, A Title, 1942", "Play"])
    bad = G.text_bounds_outside_band(n["bounds"])
    check("overscan judged on TEXT boxes (the full-bleed desc box leaves the band)",
          [b[0] for b in bad], ["FEATURE FILM, A Title, 1942"])

    G._tree = lambda: ""
    G.time.sleep = lambda s: None
    check("an empty tree yields no focus (never a guess)", G.focused_node(), None)
    check("activation key is ENTER, not DPAD_CENTER", G.ACTIVATE, "KEYCODE_ENTER")

    print("\nALL PASS" if not fails else f"\nFAILED: {', '.join(fails)}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
