"""The pipeline step the skill proposes, prototyped: from Commons' 500 px thumbnail, measure each portrait
inside the crop its small slots show and publish a tonal grade (slope, intercept on sRGB-encoded
luminance) plus its tone class. Writes data.js for the contact sheet. Python port of js/api.js cropRect."""
import json, os, sys, urllib.request, hashlib, time
import numpy as np
from PIL import Image

D = sys.argv[1]
UA = {'User-Agent': 'EarDrama-design-research/1.0 (ben@learningischange.com)'}
sheet = json.load(open(os.path.join(D, 'sheet.json')))
os.makedirs(os.path.join(D, 't500'), exist_ok=True)
WIDE = 1.15


def crop_rect(w, h, f):
    if not w or not h:
        return None
    a = w / h
    if not f and a > WIDE:
        return None
    full = min(a, 1)
    cl = lambda v, lo, hi: min(hi, max(lo, v))
    s, left, top = full, 0.5 * (a - full), 0.2 * (1 - full)
    if f:
        s = cl(2 * max(f[2] * a, f[3]), full / 4, full)
        left = cl((f[0] + f[2] / 2) * a - s / 2, 0, a - s)
        top = cl(f[1] + f[3] / 2 - s / 2, 0, 1 - s)
    return dict(x=left / a, y=top, w=s / a, h=s)


def fetch(url):
    fn = os.path.join(D, 't500', hashlib.md5(url.encode()).hexdigest()[:12])
    if not os.path.exists(fn):
        for i in range(4):
            try:
                with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
                    open(fn, 'wb').write(r.read())
                break
            except Exception:
                time.sleep(3 + 4 * i)
    return fn


T0, T1 = 0.04, 0.96          # where the 1st and 99th percentile land
KMIN, KMAX = 1.0, 1.6        # never flatten; at most a 1.6x contrast stretch ("normal limits")
for p in sheet:
    fn = fetch(p['url'] + '?width=500')
    im = Image.open(fn).convert('RGB')
    rgb = np.asarray(im).astype(float) / 255
    c = crop_rect(p['w'], p['h'], p['face'])
    p['crop'] = c
    H, W = rgb.shape[:2]
    reg = rgb
    if c:
        reg = rgb[int(c['y'] * H):max(int((c['y'] + c['h']) * H), int(c['y'] * H) + 1),
                  int(c['x'] * W):max(int((c['x'] + c['w']) * W), int(c['x'] * W) + 1)]
    L = 0.2126 * reg[..., 0] + 0.7152 * reg[..., 1] + 0.0722 * reg[..., 2]
    mx, mn = reg.max(-1), reg.min(-1)
    sat = float(np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0).mean())
    warm = float((reg[..., 0] - reg[..., 2]).mean())
    lo, hi = float(np.percentile(L, 1)), float(np.percentile(L, 99))
    k = (T1 - T0) / max(hi - lo, 1e-3)
    if k <= KMIN:
        k, o = 1.0, 0.0
    elif k >= KMAX:
        k = KMAX
        o = 0.5 - k * (lo + hi) / 2
    else:
        o = T0 - lo * k
    p['grade'] = [round(k, 3), round(o, 3)]
    p['measured'] = dict(lo=round(lo, 3), hi=round(hi, 3), mean=round(float(L.mean()), 3), sat=round(sat, 3), warm=round(warm, 3))
    p['tone'] = 'mono' if sat < 0.06 else ('sepia' if sat < 0.22 and warm > 0.03 else 'color')
    # the crop's side in source pixels: what a small slot can draw without inventing detail
    p['cropPx'] = round((c['h'] if c else 1) * p['h']) if p['h'] else None
    print(f"{p['name'][:20]:20} {p['why']:11} {p['w']}x{p['h']} crop={p['cropPx']} tone={p['tone']:5} lo={lo:.2f} hi={hi:.2f} grade={p['grade']}")
open(os.path.join(D, 'data.js'), 'w').write('window.SHEET = ' + json.dumps(sheet) + ';\n')
