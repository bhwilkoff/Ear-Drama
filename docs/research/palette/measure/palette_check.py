#!/usr/bin/env python3
"""Ear Drama palette directions: measure (default) or tune genre hues (--search).

Measures, per direction and mode:
  - WCAG 2.x contrast for every chrome text pair, the token test's own pairs
    (tools/test_design_tokens.mjs) plus the extra pairs the screens use;
  - APCA Lc for small text (Human Shaped checks APCA as well as WCAG);
  - genre hues as non-text marks (>= 3:1) on background, surface, surfaceAlt;
  - CIEDE2000 between every two genre hues, in normal vision and under
    Machado 2009 (severity 1.0) protanopia, deuteranopia, and tritanopia;
  - CIEDE2000 from every genre hue to every Archive Watch genre hue;
  - CIEDE2000 from every genre hue to the direction's chrome and status colors;
  - the nearest brand colors in Simple Icons to each chrome color.
"""
import json, math, random, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------- color math ----------
def hex2rgb(h):
    h = h.lstrip('#'); return tuple(int(h[i:i+2], 16) / 255 for i in (0, 2, 4))
def rgb2hex(c):
    return '#' + ''.join('%02X' % max(0, min(255, round(v * 255))) for v in c)
def lin(v): return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
def delin(v):
    v = max(0.0, min(1.0, v))
    return v * 12.92 if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055
def lum(h):
    r, g, b = (lin(v) for v in hex2rgb(h)); return 0.2126 * r + 0.7152 * g + 0.0722 * b
def contrast(a, b):
    la, lb = lum(a), lum(b); hi, lo = max(la, lb), min(la, lb); return (hi + 0.05) / (lo + 0.05)

def apca(txt, bg):
    # APCA 0.0.98G-4g, returns |Lc|
    def y(h):
        r, g, b = hex2rgb(h)
        return 0.2126729 * r ** 2.4 + 0.7151522 * g ** 2.4 + 0.0721750 * b ** 2.4
    yt, yb = y(txt), y(bg)
    clamp = lambda v: v if v > 0.022 else v + (0.022 - v) ** 1.414
    yt, yb = clamp(yt), clamp(yb)
    if abs(yb - yt) < 0.0005: return 0.0
    if yb > yt:
        s = (yb ** 0.56 - yt ** 0.57) * 1.14
        out = 0 if s < 0.1 else s - 0.027
    else:
        s = (yb ** 0.65 - yt ** 0.62) * 1.14
        out = 0 if s > -0.1 else s + 0.027
    return abs(out * 100)

def lin_rgb(h): return tuple(lin(v) for v in hex2rgb(h))
def xyz_from_lin(r, g, b):
    return (0.4124564 * r + 0.3575761 * g + 0.1804375 * b,
            0.2126729 * r + 0.7151522 * g + 0.0721750 * b,
            0.0193339 * r + 0.1191920 * g + 0.9503041 * b)
def lab_from_lin(r, g, b):
    x, y, z = xyz_from_lin(r, g, b)
    xn, yn, zn = 0.95047, 1.0, 1.08883
    f = lambda t: t ** (1 / 3) if t > 216 / 24389 else (24389 / 27 * t + 16) / 116
    fx, fy, fz = f(x / xn), f(y / yn), f(z / zn)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
def lab(h): return lab_from_lin(*lin_rgb(h))

def de2000(l1, l2):
    L1, a1, b1 = l1; L2, a2, b2 = l2
    C1, C2 = math.hypot(a1, b1), math.hypot(a2, b2); Cb = (C1 + C2) / 2
    G = 0.5 * (1 - math.sqrt(Cb ** 7 / (Cb ** 7 + 25 ** 7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = math.hypot(a1p, b1), math.hypot(a2p, b2)
    h1p = math.degrees(math.atan2(b1, a1p)) % 360; h2p = math.degrees(math.atan2(b2, a2p)) % 360
    dLp, dCp = L2 - L1, C2p - C1p
    if C1p * C2p == 0: dhp = 0
    else:
        dhp = h2p - h1p
        if dhp > 180: dhp -= 360
        elif dhp < -180: dhp += 360
    dHp = 2 * math.sqrt(C1p * C2p) * math.sin(math.radians(dhp / 2))
    Lbp, Cbp = (L1 + L2) / 2, (C1p + C2p) / 2
    if C1p * C2p == 0: hbp = h1p + h2p
    elif abs(h1p - h2p) <= 180: hbp = (h1p + h2p) / 2
    elif h1p + h2p < 360: hbp = (h1p + h2p + 360) / 2
    else: hbp = (h1p + h2p - 360) / 2
    T = (1 - 0.17 * math.cos(math.radians(hbp - 30)) + 0.24 * math.cos(math.radians(2 * hbp))
         + 0.32 * math.cos(math.radians(3 * hbp + 6)) - 0.20 * math.cos(math.radians(4 * hbp - 63)))
    dth = 30 * math.exp(-((hbp - 275) / 25) ** 2)
    Rc = 2 * math.sqrt(Cbp ** 7 / (Cbp ** 7 + 25 ** 7))
    Sl = 1 + 0.015 * (Lbp - 50) ** 2 / math.sqrt(20 + (Lbp - 50) ** 2)
    Sc, Sh = 1 + 0.045 * Cbp, 1 + 0.015 * Cbp * T
    Rt = -math.sin(math.radians(2 * dth)) * Rc
    return math.sqrt((dLp / Sl) ** 2 + (dCp / Sc) ** 2 + (dHp / Sh) ** 2 + Rt * (dCp / Sc) * (dHp / Sh))
def de(h1, h2): return de2000(lab(h1), lab(h2))

# Machado, Oliveira & Fernandes 2009, severity 1.0, applied to linear RGB.
CVD = {
    'protan': [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
    'deutan': [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
    'tritan': [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
}
def sim(h, kind):
    r, g, b = lin_rgb(h); m = CVD[kind]
    out = [max(0, min(1, m[i][0] * r + m[i][1] * g + m[i][2] * b)) for i in range(3)]
    return lab_from_lin(*out)

# OKLCH -> sRGB hex (None when out of gamut)
def oklch_hex(L, C, h):
    a, b = C * math.cos(math.radians(h)), C * math.sin(math.radians(h))
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
    r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    bb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    if min(r, g, bb) < -0.0005 or max(r, g, bb) > 1.0005: return None
    return rgb2hex((delin(r), delin(g), delin(bb)))
def hex_oklch(h):
    r, g, b = lin_rgb(h)
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l_, m_, s_ = l ** (1 / 3), m ** (1 / 3), s ** (1 / 3)
    L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
    a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
    b2 = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    return L, math.hypot(a, b2), math.degrees(math.atan2(b2, a)) % 360

# ---------- the data ----------
ARCHIVE_WATCH_GENRES = {  # Archive Watch css/whats-new.css, Discover_macOS.swift, Channels.swift
    'AW Feature Film': '#FF5C35', 'AW Classic TV': '#2D5BFF', 'AW Ephemeral': '#7C5BBA',
    'AW Silent Era': '#C9A66B', 'AW Animation': '#FF4D8D', 'AW Newsreel': '#8A8F98',
    'AW Documentary': '#3FA796', 'AW Short Film': '#E8A317',
}
GENRES = ['drama', 'mystery', 'scifi', 'western', 'comedy', 'news', 'documentary', 'serials']
GENRE_NAMES = {'drama': 'Drama and anthology', 'mystery': 'Mystery and crime', 'scifi': 'Science fiction and fantasy',
               'western': 'Western', 'comedy': 'Comedy and variety', 'news': 'News and wartime',
               'documentary': 'Documentary and education', 'serials': 'Serials and soaps'}

DIRECTIONS = json.load(open(os.path.join(HERE, 'directions.json')))

# ---------- checks ----------
def chrome_pairs(c):
    # (label, fg, bg, min, kind)  kind: text | mark
    P = [
        ('text on background', 'text', 'background', 4.5, 'text'),
        ('text on surface', 'text', 'surface', 4.5, 'text'),
        ('text on surfaceAlt', 'text', 'surfaceAlt', 4.5, 'text'),
        ('textMuted on background', 'textMuted', 'background', 4.5, 'text'),
        ('textMuted on surface', 'textMuted', 'surface', 4.5, 'text'),
        ('textMuted on surfaceAlt', 'textMuted', 'surfaceAlt', 4.5, 'text'),
        ('onPrimary on primary', 'onPrimary', 'primary', 4.5, 'text'),
        ('primary fill on background', 'primary', 'background', 3.0, 'mark'),
        ('primary fill on surface', 'primary', 'surface', 3.0, 'mark'),
        ('link on background', 'link', 'background', 4.5, 'text'),
        ('link on surface', 'link', 'surface', 4.5, 'text'),
        ('onSecondary on secondary', 'onSecondary', 'secondary', 4.5, 'text'),
        ('secondary mark on background', 'secondary', 'background', 3.0, 'mark'),
        ('secondary mark on surface', 'secondary', 'surface', 3.0, 'mark'),
        ('focus ring on background', 'focus', 'background', 3.0, 'mark'),
        ('focus ring on surface', 'focus', 'surface', 3.0, 'mark'),
        ('error on errorSurface', 'error', 'errorSurface', 4.5, 'text'),
        ('error on background', 'error', 'background', 4.5, 'text'),
        ('success on background', 'success', 'background', 4.5, 'text'),
        ('warning on background', 'warning', 'background', 4.5, 'text'),
    ]
    return P

def genre_score(gl, gd, d, verbose=False):
    """Return (feasible, objective, details) for genre dicts gl/gd (light/dark hex)."""
    pen = 0.0
    for mode, G in (('light', gl), ('dark', gd)):
        c = d[mode]
        for g, hx in G.items():
            if hx is None: return False, -1e9, None
            for bg in ('background', 'surface', 'surfaceAlt'):
                r = contrast(hx, c[bg])
                if r < 3.1: pen += (3.1 - r) * 50
            for k, v in ARCHIVE_WATCH_GENRES.items():
                e = de(hx, v)
                if e < 12: pen += (12 - e) * 4
            for k in ('primary', 'secondary', 'link', 'error', 'success', 'warning'):
                e = de(hx, c[k])
                if e < 10: pen += (10 - e) * 4
    objs = []
    for G in (gl, gd):
        keys = list(G)
        n = min(de(G[a], G[b]) for i, a in enumerate(keys) for b in keys[i + 1:])
        cv = min(de2000(sim(G[a], k), sim(G[b], k)) for k in ('protan', 'deutan')
                 for i, a in enumerate(keys) for b in keys[i + 1:])
        chroma = sum(hex_oklch(G[g])[1] for g in keys) / len(keys)
        objs.append(min(n, 22) + 1.0 * min(cv, 11) + 0.02 * n + 25 * chroma)
    return pen == 0, sum(objs) - pen, None

def search(name, iters=2500, seed=1):
    """Nudge a hand-designed seed (directions.json genreSeed: [h, Llight, Clight, Ldark, Cdark] in OKLCH)
    within a small window until every constraint holds, keeping the designer's hue families."""
    d = DIRECTIONS[name]; seedspec = d['genreSeed']
    rnd = random.Random(seed)
    W = (8, 0.05, 0.03, 0.05, 0.03)
    def build(state):
        gl, gd = {}, {}
        for g in GENRES:
            h, Ll, Cl, Ld, Cd = state[g]
            gl[g] = oklch_hex(Ll, Cl, h); gd[g] = oklch_hex(Ld, Cd, h)
        return gl, gd
    def ok(st):
        gl, gd = build(st); return None not in gl.values() and None not in gd.values()
    state = {g: list(seedspec[g]) for g in GENRES}
    while not ok(state):
        for g in GENRES:
            gl, gd = build({g: state[g] for g in GENRES})
            if gl[g] is None: state[g][2] *= 0.95
            if gd[g] is None: state[g][4] *= 0.95
    best = state; bl, bd = build(best); bf, bs, _ = genre_score(bl, bd, d)
    for it in range(iters):
        cand = {g: list(v) for g, v in best.items()}
        g = rnd.choice(GENRES); v = cand[g]; s0 = seedspec[g]
        k = rnd.randrange(5)
        step = (3, 0.015, 0.01, 0.015, 0.01)[k]
        v[k] = max(s0[k] - W[k], min(s0[k] + W[k], v[k] + rnd.gauss(0, step)))
        if k in (2, 4): v[k] = max(0.02, v[k])
        if not ok(cand): continue
        cl, cd = build(cand); f, s, _ = genre_score(cl, cd, d)
        if s >= bs: best, bs, bf = cand, s, f
    gl, gd = build(best)
    return gl, gd, bf, bs

# ---------- report ----------
def report():
    sip = os.path.join(HERE, 'si', 'si.json')
    if not os.path.exists(sip):
        sys.exit('Fetch the brand colors first:\n  mkdir -p si && curl -sSL -o si/si.json '
                 'https://raw.githubusercontent.com/simple-icons/simple-icons/develop/data/simple-icons.json')
    si = json.load(open(sip))
    AUDIO = {'Spotify', 'iHeartRadio', 'SiriusXM', 'Audible', 'Pandora', 'TuneIn', 'Apple Podcasts', 'Pocket Casts',
             'Overcast', 'Castbox', 'Deezer', 'SoundCloud', 'NPR', 'BBC', 'Audiomack', 'Tidal', 'Podcast Index',
             'Castro', 'Stitcher', 'Radio.com', 'Last.fm', 'Shazam', 'YouTube Music', 'Amazon Music', 'Libby'}
    fails = 0
    summary = []
    for name, d in DIRECTIONS.items():
        print('=' * 78); print(f"{d['title']}  ({name})"); print('=' * 78)
        for mode in ('light', 'dark'):
            c = d[mode]
            print(f'\n-- {mode}: chrome --')
            for label, fg, bg, mn, kind in chrome_pairs(c):
                r = contrast(c[fg], c[bg]); ok = r >= mn; fails += (not ok)
                lc = apca(c[fg], c[bg]) if kind == 'text' else None
                print(f"  {'PASS' if ok else 'FAIL'}  {label:32s} {c[fg]} on {c[bg]}  {r:5.2f}:1 (needs {mn})"
                      + (f"  APCA Lc {lc:4.1f}" if lc is not None else ''))
            print(f'  ground chroma (OKLCH C): background {hex_oklch(c["background"])[1]:.4f}, '
                  f'surface {hex_oklch(c["surface"])[1]:.4f}')
            G = d['genres'][mode]
            print(f'\n-- {mode}: genre marks (>= 3:1 on background / surface / surfaceAlt) --')
            for g in GENRES:
                hx = G[g]; rs = [contrast(hx, c[b]) for b in ('background', 'surface', 'surfaceAlt')]
                ok = min(rs) >= 3.0; fails += (not ok)
                aw = min(ARCHIVE_WATCH_GENRES.items(), key=lambda kv: de(hx, kv[1]))
                ch = min(((k, c[k]) for k in ('primary', 'secondary', 'link', 'error', 'success', 'warning')), key=lambda kv: de(hx, kv[1]))
                L, C, h = hex_oklch(hx)
                print(f"  {'PASS' if ok else 'FAIL'}  {GENRE_NAMES[g]:28s} {hx}  oklch({L:.2f} {C:.3f} {h:5.1f})  "
                      f"{rs[0]:4.2f} / {rs[1]:4.2f} / {rs[2]:4.2f}   nearest AW {aw[0][3:]} dE {de(hx, aw[1]):4.1f}   nearest chrome {ch[0]} dE {de(hx, ch[1]):4.1f}")
            keys = GENRES
            pairs = [(a, b) for i, a in enumerate(keys) for b in keys[i + 1:]]
            def mn(fn):
                v = [(fn(a, b), a, b) for a, b in pairs]; return min(v)
            n = mn(lambda a, b: de(G[a], G[b]))
            res = {'normal': n}
            for k in ('protan', 'deutan', 'tritan'):
                res[k] = mn(lambda a, b, k=k: de2000(sim(G[a], k), sim(G[b], k)))
            awmin = min((de(G[g], v), g, k) for g in keys for k, v in ARCHIVE_WATCH_GENRES.items())
            chmin = min((de(G[g], c[k]), g, k) for g in keys for k in ('primary', 'secondary', 'link', 'error', 'success', 'warning'))
            print(f'  min CIEDE2000 between genres: normal {n[0]:.1f} ({n[1]}/{n[2]}), '
                  + ', '.join(f"{k} {res[k][0]:.1f} ({res[k][1]}/{res[k][2]})" for k in ('protan', 'deutan', 'tritan')))
            print(f'  min CIEDE2000 genre to Archive Watch genre: {awmin[0]:.1f} ({awmin[1]} vs {awmin[2]})')
            print(f'  min CIEDE2000 genre to own chrome/status:   {chmin[0]:.1f} ({chmin[1]} vs {chmin[2]})')
            summary.append((d['title'], mode, n[0], res['protan'][0], res['deutan'][0], res['tritan'][0], awmin[0], chmin[0]))
        print('\n-- nearest brand colors (Simple Icons, 3,400+ marks), for the chrome --')
        for k in ('primary', 'secondary'):
            for mode in ('light', 'dark'):
                hx = d[mode][k]
                near = sorted(((de(hx, '#' + b['hex']), b['title'], b['hex']) for b in si))[:4]
                aud = sorted(((de(hx, '#' + b['hex']), b['title'], b['hex']) for b in si if b['title'] in AUDIO))[:2]
                print(f"  {k:9s} {mode:5s} {hx}: " + '; '.join(f"{t} #{x} {e:.1f}" for e, t, x in near)
                      + '  | nearest audio brand: ' + '; '.join(f"{t} #{x} {e:.1f}" for e, t, x in aud))
        print()
    print('=' * 78); print('SUMMARY (min CIEDE2000)'); print('=' * 78)
    print(f"  {'direction':22s} {'mode':5s} {'normal':>7s} {'protan':>7s} {'deutan':>7s} {'tritan':>7s} {'vs AW':>6s} {'vs chrome':>9s}")
    for t, m, n, p, dd, tr, aw, ch in summary:
        print(f"  {t:22s} {m:5s} {n:7.1f} {p:7.1f} {dd:7.1f} {tr:7.1f} {aw:6.1f} {ch:9.1f}")
    print(f"\n{fails} contrast check(s) failed")

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--search':
        for name in sys.argv[2:] or DIRECTIONS:
            best = None
            for seed in range(1, 3):
                gl, gd, f, s = search(name, seed=seed)
                if best is None or (f, s) > (best[2], best[3]): best = (gl, gd, f, s)
            gl, gd, f, s = best
            print(name, 'feasible' if f else 'INFEASIBLE', round(s, 2))
            print(json.dumps({'light': gl, 'dark': gd}, indent=1))
            DIRECTIONS[name]['genres'] = {'light': gl, 'dark': gd}
        json.dump(DIRECTIONS, open(os.path.join(HERE, 'directions.json'), 'w'), indent=1)
    else:
        report()
