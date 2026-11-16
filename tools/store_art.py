#!/usr/bin/env python3
"""
store_art.py — Ear Drama's App Store image set, from real device captures.

    python3 tools/store_art.py [--shots build/store-shots] [--only iphone-large,tv] [--sheet]

Reads raw captures from <shots>/raw/<device>/<screen>.png (taken on real
devices with the DEBUG launch doors, docs/store/STORE-SCREENSHOTS.md) and writes
<shots>/final/<slot>/NN-name.png at Apple's exact sizes. Every capture is
composited, never redrawn: the app's pixels are scaled onto an On Air canvas
with a short caption (docs/store/LISTING-DRAFT.md, "Screenshot captions"). On
iPhone and iPad frames the real status bar is painted out row by row with that
row's own background color and a clean one (9:41, full signal and battery, no
carrier) is drawn on top. The header and search assets are built from the same
captures inside Apple's art safe areas (creative-assets-specifications, read
2026-11-16).

Each final is checked: exact size, RGB (no alpha), and not one flat color.
A raw capture that is missing skips its frame and says so; it never draws a
placeholder. Pillow is the only dependency.
"""

import argparse
import os
import sys
from PIL import Image, ImageDraw, ImageFont, ImageStat

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# On Air (design-tokens.json, color.brand, dark): the canvas is the dark page.
INK_BG = (15, 15, 17)        # background.dark #0F0F11
SURFACE = (25, 25, 28)       # surface.dark #19191C
TEXT = (242, 242, 244)       # text.dark #F2F2F4
MUTED = (196, 196, 204)      # textMuted.dark #C4C4CC
BORDER = (52, 52, 58)        # border.dark #34343A

FONT_DISPLAY = os.path.join(ROOT, "apple/Resources/Fonts/BigShoulders-Bold.ttf")
FONT_BODY = os.path.join(ROOT, "branding/fonts/PublicSans[wght].ttf")
FONT_SF = "/System/Library/Fonts/SFNS.ttf"


def display(size):
    return ImageFont.truetype(FONT_DISPLAY, size)


def body(size, weight=600):
    f = ImageFont.truetype(FONT_BODY, size)
    f.set_variation_by_axes([weight])
    return f


def sf(size, name=b"Semibold"):
    f = ImageFont.truetype(FONT_SF, size)
    f.set_variation_by_name(name)
    return f


# ── the set: (file name, caption, [(label, raw screen)]) ─────────────────────
# Slots 1-3 pair a listening screen with a making screen, so the two halves
# carry equal weight in the three thumbnails most shoppers see.
TOUCH_SET = [
    ("01-hear-and-make", "Hear Old Radio.\nMake New Drama.", [("LISTEN", "home"), ("MAKE", "record")]),
    ("02-play-and-record", "Press Play.\nThen Press Record.", [("LISTEN", "playing"), ("MAKE", "studio")]),
    ("03-episodes-and-plays", "73,000 Episodes.\n800 Plays.", [("LISTEN", "series"), ("MAKE", "reader")]),
    ("04-hear-the-cast", "Rehearse With\nDevice Voices", [(None, "hear")]),
    ("05-on-the-air", "A Real Evening\nof Radio, Rebuilt", [(None, "stations")]),
    ("06-your-part", "Follow Your Part,\nLine by Line", [(None, "part")]),
    ("07-sleep", "A Sleep Timer\nfor Bedtime", [(None, "sleep")]),
]

MAC_SET = [
    ("01-hear-and-make", "Hear Old Radio. Make New Drama.", [("LISTEN", "home"), ("MAKE", "record")]),
    ("02-play-and-record", "Press Play. Then Press Record.", [("LISTEN", "playing"), ("MAKE", "studio")]),
    ("03-episodes-and-plays", "73,000 Episodes. 800 Plays.", [("LISTEN", "series"), ("MAKE", "reader")]),
    ("04-on-the-air", "A Real Evening of Radio, Rebuilt", [(None, "stations")]),
    ("05-your-part", "Follow Your Part, Line by Line", [(None, "part")]),
]

# Apple TV has no reader or studio (PARITY): it plays, and reads along with
# ear dramas made on the other devices. The read-along frame waits for a real
# published ear drama: the only way to draw it today is the DEBUG rehearsal
# door, a stand-in production (it also printed "Dec 31, 1969", 2026-11-16).
TV_SET = [
    ("01-on-the-air", "Old-Time Radio, On the Air Tonight", [(None, "home")]),
    ("02-series", "73,000 Episodes to Hear", [(None, "series")]),
    ("03-playing", "Lean Back and Listen", [(None, "playing")]),
    ("04-stations", "A Real Evening of Radio, Rebuilt", [(None, "stations")]),
    ("05-start-a-show", "Find a Show by Genre and Decade", [(None, "browse")]),
]

# slot -> (raw device folder, width, height, kind, set)
SLOTS = {
    "iphone-large": ("iphone", 1320, 2868, "phone", TOUCH_SET),
    "iphone": ("iphone", 1206, 2622, "phone", TOUCH_SET),
    # The open Duo: the inner display in landscape, the device's own pose (Apple accepts 2853x2007 or 2007x2853
    # inner, 1398x2034 or 2034x1398 outer; screenshot-specifications, read 2026-11-16).
    "iphone-duo": ("duo", 2853, 2007, "duo", TOUCH_SET),
    "ipad": ("ipad", 2752, 2064, "ipad", TOUCH_SET),
    "mac": ("mac", 2560, 1600, "wide", MAC_SET),
    "tv": ("tv", 3840, 2160, "wide", TV_SET),
}

# Real status bars, in device pixels: band height, the time's center, scale.
STATUS = {
    "iphone": {"band": 141, "time_cx": 156, "cy": 74, "scale": 3, "right": 1072},
    "ipad": {"band": 48, "time_cx": None, "cy": 22, "scale": 2, "right": None},
    "duo": {"band": 0},
}


# ── status bar ───────────────────────────────────────────────────────────────

def row_mode(img, y, step=6):
    counts = {}
    for x in range(0, img.width, step):
        p = img.getpixel((x, y))[:3]
        q = (p[0] // 4, p[1] // 4, p[2] // 4)
        counts.setdefault(q, []).append(p)
    best = max(counts.values(), key=len)
    return tuple(sum(c[i] for c in best) // len(best) for i in range(3))


def clean_status_bar(img, device):
    spec = STATUS.get(device)
    if not spec or not spec["band"]:
        return img
    img = img.convert("RGB")
    d = ImageDraw.Draw(img)
    band = spec["band"]
    lum_sum = 0
    for y in range(band):
        c = row_mode(img, y)
        lum_sum += 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
        d.line([(0, y), (img.width, y)], fill=c)
    fg = (0, 0, 0) if lum_sum / band > 128 else (255, 255, 255)
    s = spec["scale"]
    cy = spec["cy"]
    if device == "iphone":
        f = sf(17 * s)
        d.text((spec["time_cx"], cy), "9:41", font=f, fill=fg, anchor="mm")
        right = spec["right"]
        draw_battery(d, right, cy, s, fg)
        draw_wifi(d, right - 27 * s - 10 * s, cy, s, fg)
        draw_signal(d, right - 27 * s - 10 * s - 17 * s - 9 * s, cy, s, fg)
    else:  # iPad: time and date at the left, wifi and battery at the right
        f = sf(12 * s)
        d.text((20 * s, cy), "9:41 AM  Mon Nov 16", font=f, fill=fg, anchor="lm")
        right = img.width - 22 * s
        draw_battery(d, right, cy, s * 0.8, fg)
        draw_wifi(d, right - 27 * s * 0.8 - 8 * s, cy, s * 0.8, fg)
    return img


def draw_battery(d, right, cy, s, fg):
    w, h = 24.5 * s, 12 * s
    x0, y0 = right - w - 2 * s, cy - h / 2
    r = 3.6 * s
    d.rounded_rectangle([x0, y0, x0 + w, y0 + h], radius=r, outline=fg, width=max(1, round(1 * s)))
    pad = 2 * s
    d.rounded_rectangle([x0 + pad, y0 + pad, x0 + w - pad, y0 + h - pad], radius=r * 0.6, fill=fg)
    d.rounded_rectangle([x0 + w + 1 * s, cy - 2 * s, x0 + w + 2.4 * s, cy + 2 * s], radius=1 * s, fill=fg)


def draw_wifi(d, right, cy, s, fg):
    cx, base = right - 8 * s, cy + 5 * s
    for i, rad in enumerate((11 * s, 7.4 * s, 3.8 * s)):
        if i < 2:
            d.arc([cx - rad, base - rad, cx + rad, base + rad], 225, 315, fill=fg, width=round(2.2 * s))
        else:
            d.pieslice([cx - rad, base - rad, cx + rad, base + rad], 225, 315, fill=fg)


def draw_signal(d, right, cy, s, fg):
    bw, gap = 3 * s, 1.6 * s
    x = right - 4 * bw - 3 * gap
    for i, hgt in enumerate((4, 6.4, 8.8, 11.2)):
        h = hgt * s
        d.rounded_rectangle([x, cy + 5.6 * s - h, x + bw, cy + 5.6 * s], radius=0.8 * s, fill=fg)
        x += bw + gap


# ── drawing helpers ──────────────────────────────────────────────────────────

def rounded(img, radius, border=BORDER, bw=2):
    img = img.convert("RGB")
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius=radius, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    if bw:
        ImageDraw.Draw(out).rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius=radius,
                                              outline=border + (255,), width=bw)
    return out


def fit(img, w, h):
    s = min(w / img.width, h / img.height)
    return img.resize((max(1, round(img.width * s)), max(1, round(img.height * s))), Image.LANCZOS)


def caption_block(canvas, text, top, size, max_w, line_gap=0.98, align="center"):
    d = ImageDraw.Draw(canvas)
    lines = text.split("\n")
    f = display(size)
    while max(d.textlength(l, font=f) for l in lines) > max_w and size > 20:
        size -= 4
        f = display(size)
    y = top
    for l in lines:
        if align == "center":
            d.text((canvas.width / 2, y), l, font=f, fill=TEXT, anchor="mt")
        else:
            d.text((align, y), l, font=f, fill=TEXT, anchor="lt")
        y += size * line_gap
    return y


def label(canvas, text, cx, y, size):
    d = ImageDraw.Draw(canvas)
    f = body(size, 700)
    spaced = " ".join(text)  # letter-spaced small caps label
    d.text((cx, y), spaced, font=f, fill=MUTED, anchor="ms")


# iPad diptychs show the content column only: the sidebar and the status bar
# are cropped away so two landscape screens side by side stay legible. The crop
# removes chrome, never content.
IPAD_SIDEBAR = 0.205
DUO_STRIP = 0.076  # 216 of 2853 px: the strip's glass and its margin, measured on 1.0.135 frames
IPAD_HAS_SIDEBAR = {"home", "record", "series", "playing", "stations", "sleep", "browse"}


def load(raw_dir, screen, device, paired=False):
    p = os.path.join(raw_dir, f"{screen}.png")
    if not os.path.exists(p):
        return None
    img = Image.open(p).convert("RGB")
    if device == "ipad" and paired:
        x0 = round(img.width * IPAD_SIDEBAR) if screen in IPAD_HAS_SIDEBAR else 0
        return img.crop((x0, STATUS["ipad"]["band"], img.width, img.height))
    if device == "duo" and paired:
        # The open Duo's vertical strip (status, toolbar, tabs) is chrome: a pair shows the content beside it,
        # and a single frame keeps it, so the Duo's own look is in the set.
        return img.crop((0, 0, round(img.width * (1 - DUO_STRIP)), img.height))
    return clean_status_bar(img, device)


# ── compositions ─────────────────────────────────────────────────────────────

def compose_touch(W, H, kind, caption, panes, device):
    c = Image.new("RGB", (W, H), INK_BG)
    landscape = kind in ("ipad", "duo")
    if landscape:
        cap_size, cap_top = round(H * 0.075), round(H * 0.05)
        text = caption.replace("\n", " ")
    else:
        cap_size, cap_top = round(W * (0.105 if kind == "phone" else 0.085)), round(H * 0.045)
        text = caption
    y = caption_block(c, text, cap_top, cap_size, W * 0.9)
    margin = round(W * 0.05)
    top = round(y + H * 0.035)
    if len(panes) == 1:
        _, img = panes[0]
        shot = fit(img, W - 2 * margin, H - top - margin)
        r = round(shot.width * (0.045 if landscape else 0.09))
        x = (W - shot.width) // 2
        c.paste(rounded(shot, r), (x, top), rounded(shot, r))
        return c
    lab_size = round(W * (0.022 if landscape else 0.03))
    top += round(lab_size * 1.6)
    margin = round(W * 0.035)
    gutter = round(W * 0.03)
    pw = (W - 2 * margin - gutter) // 2
    ph = H - top - margin - round(lab_size * 1.6)
    shots = [fit(img, pw, ph) for _, img in panes]
    sh = max(s.height for s in shots)
    free = max(0, ph - sh)
    # Staggered: LISTEN starts high, MAKE answers lower, so the pair fills the frame.
    offsets = [round(free * 0.08), round(free * 0.92)]
    for i, ((lab, _), shot) in enumerate(zip(panes, shots)):
        x = margin + i * (pw + gutter) + (pw - shot.width) // 2
        y0 = top + offsets[i]
        r = round(shot.width * (0.045 if landscape else 0.09))
        rr = rounded(shot, r)
        c.paste(rr, (x, y0), rr)
        if lab:
            label(c, lab, x + shot.width / 2, y0 - round(lab_size * 0.6), lab_size)
    return c


def compose_wide(W, H, caption, panes, kind):
    c = Image.new("RGB", (W, H), INK_BG)
    cap_size = round(H * 0.07)
    y = caption_block(c, caption, round(H * 0.045), cap_size, W * 0.9)
    margin = round(W * 0.04)
    top = round(y + H * 0.03)
    if len(panes) == 1:
        shot = fit(panes[0][1], W - 2 * margin, H - top - margin)
        r = round(shot.width * 0.012)
        rr = rounded(shot, r)
        c.paste(rr, ((W - shot.width) // 2, top), rr)
        return c
    lab_size = round(H * 0.022)
    top += round(lab_size * 1.6)
    gutter = round(W * 0.025)
    pw = (W - 2 * margin - gutter) // 2
    ph = H - top - margin
    shots = [fit(img, pw, ph) for _, img in panes]
    y0 = top + (ph - max(s.height for s in shots)) // 2
    for i, ((lab, _), shot) in enumerate(zip(panes, shots)):
        x = margin + i * (pw + gutter) + (pw - shot.width) // 2
        rr = rounded(shot, round(shot.width * 0.015))
        c.paste(rr, (x, y0), rr)
        if lab:
            label(c, lab, x + shot.width / 2, y0 - round(lab_size * 0.6), lab_size)
    return c


def build_slot(slot, shots_dir):
    device, W, H, kind, shotset = SLOTS[slot]
    raw = os.path.join(shots_dir, "raw", device)
    out = os.path.join(shots_dir, "final", slot)
    written, missing = [], []
    if not os.path.isdir(raw):
        return written, [f"{slot}: no captures in {raw}"]
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith(".png"):
            os.remove(os.path.join(out, f))
    for name, caption, panes in shotset:
        imgs = [(lab, load(raw, scr, device, paired=len(panes) > 1)) for lab, scr in panes]
        gone = [scr for (lab, scr), (_, im) in zip(panes, imgs) if im is None]
        if gone:
            missing.append(f"{slot}/{name}: missing raw {', '.join(gone)}")
            continue
        if kind in ("phone", "duo", "ipad"):
            img = compose_touch(W, H, kind, caption, imgs, device)
        else:
            img = compose_wide(W, H, caption, imgs, kind)
        path = os.path.join(out, f"{name}.png")
        img.save(path, "PNG")
        verify(path, W, H)
        written.append(path)
    return written, missing


# ── header and search assets ─────────────────────────────────────────────────

def creative(shots_dir, kind):
    """Product page header (3840x1646, safe 1646x661 at 1097,493) or search
    results (3840x2560, safe 2168x1030 at 836,765). The words and the two
    screens that say both halves sit inside the safe area; screens that only
    add atmosphere run past it and may be cropped."""
    raw = os.path.join(shots_dir, "raw", "iphone")
    need = ["playing", "studio", "home", "reader"]
    imgs = {n: load(raw, n, "iphone") for n in need}
    if any(v is None for v in imgs.values()):
        return None, [f"{kind}: missing iPhone raws {[k for k, v in imgs.items() if v is None]}"]
    out = os.path.join(shots_dir, "final", kind)
    os.makedirs(out, exist_ok=True)
    if kind == "header":
        W, H, safe = 3840, 1646, (1097, 493, 1646, 661)
    else:
        W, H, safe = 3840, 2560, (836, 765, 2168, 1030)
    sx, sy, sw, shh = safe
    c = Image.new("RGB", (W, H), INK_BG)

    def place(img, h, x, y, dim=1.0):
        s = fit(img, 10_000, h)
        if dim < 1:
            s = Image.blend(Image.new("RGB", s.size, INK_BG), s, dim)
        rr = rounded(s, round(s.width * 0.09))
        c.paste(rr, (round(x), round(y)), rr)
        return s.size

    if kind == "header":
        # Atmosphere beyond the safe area: screens from both halves, cut by the frame.
        ph = round(H * 1.05)
        pw = round(ph * imgs["home"].width / imgs["home"].height)
        place(imgs["home"], ph, sx - 2 * pw - 120, H * 0.18, 0.55)
        place(imgs["playing"], ph, sx - pw - 60, -H * 0.12, 0.9)
        place(imgs["studio"], ph, sx + sw + 60, -H * 0.12, 0.9)
        place(imgs["reader"], ph, sx + sw + pw + 120, H * 0.18, 0.55)
        d = ImageDraw.Draw(c)
        cx = sx + sw / 2
        size = round(shh * 0.46)
        f1 = display(size)
        while d.textlength("Make New Drama.", font=f1) > sw * 0.94:
            size -= 4
            f1 = display(size)
        top = sy + (shh - size * 1.95) / 2
        d.text((cx, top), "Hear Old Radio.", font=f1, fill=TEXT, anchor="mt")
        d.text((cx, top + size * 1.0), "Make New Drama.", font=f1, fill=TEXT, anchor="mt")
    else:
        # Inside the safe area: the words at left, Now Playing and the studio at right.
        ph = shh
        pw = round(ph * imgs["playing"].width / imgs["playing"].height)
        gap = 50
        x2 = sx + sw - pw
        x1 = x2 - gap - pw
        place(imgs["playing"], ph, x1, sy)
        place(imgs["studio"], ph, x2, sy)
        # Atmosphere outside it.
        place(imgs["home"], round(ph * 1.25), sx - 140 - round(pw * 1.25), sy - ph * 0.1, 0.4)
        place(imgs["reader"], round(ph * 1.25), sx + sw + 140, sy - ph * 0.1, 0.4)
        d = ImageDraw.Draw(c)
        tx = sx + 60
        tw = x1 - gap * 2 - tx
        size = round(shh * 0.2)
        f = display(size)
        while d.textlength("Make New Drama.", font=f) > tw:
            size -= 4
            f = display(size)
        ty = sy + shh / 2 - size * 1.05
        d.text((tx, ty), "Hear Old Radio.", font=f, fill=TEXT, anchor="lt")
        d.text((tx, ty + size * 1.05), "Make New Drama.", font=f, fill=TEXT, anchor="lt")
    path = os.path.join(out, f"01-{kind}.png")
    c.save(path, "PNG")
    verify(path, W, H)
    return path, []


# ── checks and the contact sheet ─────────────────────────────────────────────

def verify(path, W, H):
    im = Image.open(path)
    if im.size != (W, H):
        sys.exit(f"FAIL {path}: {im.size}, expected {W}x{H}")
    if im.mode != "RGB":
        sys.exit(f"FAIL {path}: mode {im.mode} (no alpha allowed)")
    small = im.resize((48, 48))
    counts = {}
    for p in small.get_flattened_data():
        counts[p] = counts.get(p, 0) + 1
    if max(counts.values()) / (48 * 48) > 0.97:
        sys.exit(f"FAIL {path}: one flat color (blank frame)")
    if ImageStat.Stat(small.convert("L")).stddev[0] < 6:
        sys.exit(f"FAIL {path}: almost no contrast (blank frame)")


def contact_sheet(paths, out):
    rows = {}
    for p in paths:
        rows.setdefault(os.path.basename(os.path.dirname(p)), []).append(p)
    rh, pad, lab = 520, 24, 60
    rendered = []
    for slot, ps in rows.items():
        ims = [Image.open(p).convert("RGB") for p in sorted(ps)]
        ims = [i.resize((round(i.width * rh / i.height), rh), Image.LANCZOS) for i in ims]
        rendered.append((slot, ims))
    W = max(sum(i.width + pad for i in ims) for _, ims in rendered) + pad
    H = sum(rh + lab + pad for _ in rendered) + pad
    sheet = Image.new("RGB", (W, H), (40, 40, 44))
    d = ImageDraw.Draw(sheet)
    y = pad
    for slot, ims in rendered:
        d.text((pad, y + lab / 2), slot, font=body(36, 700), fill=TEXT, anchor="lm")
        x = pad
        for i in ims:
            sheet.paste(i, (x, y + lab))
            x += i.width + pad
        y += rh + lab + pad
    sheet.save(out)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shots", default=os.path.join(ROOT, "build", "store-shots"))
    ap.add_argument("--only", help="comma-separated slots (also header, search)")
    ap.add_argument("--sheet", action="store_true", help="write final/contact-sheet.png")
    a = ap.parse_args()
    wanted = a.only.split(",") if a.only else list(SLOTS) + ["header", "search"]
    allw, allm = [], []
    for slot in wanted:
        if slot in ("header", "search"):
            p, m = creative(a.shots, slot)
            allw += [p] if p else []
            allm += m
        else:
            w, m = build_slot(slot, a.shots)
            allw += w
            allm += m
    for p in allw:
        print("OK  ", os.path.relpath(p, a.shots))
    for m in allm:
        print("SKIP", m)
    if a.sheet:
        finals = []
        fdir = os.path.join(a.shots, "final")
        for slot in sorted(os.listdir(fdir)):
            sd = os.path.join(fdir, slot)
            if os.path.isdir(sd):
                finals += [os.path.join(sd, f) for f in sorted(os.listdir(sd)) if f.endswith(".png")]
        print("SHEET", contact_sheet(finals, os.path.join(fdir, "contact-sheet.png")))


if __name__ == "__main__":
    main()
