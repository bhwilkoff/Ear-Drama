#!/usr/bin/env python3
"""Fit gate and frames for the label (Decision 081, WEB-DESIGN 6.4r): the drawn art of everything without a
picture. Opens Home, Browse, a series with a picture, a series without, an episode of that series, a person
without a portrait, and Record, light and dark, at 375 px (inside a 375 px iframe: headless Chrome will not
lay a page out narrower than about 500) and 1440 px. Fails on:

  - a monogram title block left anywhere (svg.g-block), or a window with no picture and no label;
  - a label that drew nothing (an empty SVG, or one with no size);
  - label text that leaves its window, or leaves its label's circle (the 56 px row tile included);
  - a window 64 px or smaller drawn at a tier above S (detail that cannot be read);
  - a page that should draw labels and drew none, or a sideways scroll.

The pages are chosen from the data (never pinned): the most downloaded series with a picture, the most
downloaded dated series without one, its first dated episode, and the voice with the most episodes and no
portrait. Headless Chrome is launched with --mute-audio and --autoplay-policy=user-gesture-required, every URL
carries ?mute=1, and nothing presses Play.

    python3 tools/web_fit_label.py              # exit 1 on any problem
    python3 tools/web_fit_label.py --shots DIR  # also write a PNG per frame
    python3 tools/web_fit_label.py --data URL   # another projection (default https://eardrama.org/data/)

Negative control: in js/app.js fillWindow, draw the old title block (replace the Label.svg(...) call with
svgEl('svg', { class: 'g-block' })); "a monogram title block is drawn" fails on every page.
Second: set "fitW" in design-tokens.json art.label.label to 1.6 and regenerate; the label text overflows its
circle and "text leaves its label" fails (seen 2026-11-19: 56 problems; the first control: 60).
"""
import base64, json, os, re, shutil, subprocess, sys, tempfile, threading, time, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import web_run  # noqa: E402

CHECK = r"""(() => {
  const f = document.querySelector('iframe#fit');
  const doc = f ? f.contentDocument : document, win = f ? f.contentWindow : window;
  const bad = [];
  const shown = (n) => { const r = n.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
  if (doc.querySelector('svg.g-block')) bad.push('a monogram title block is drawn');
  doc.querySelectorAll('.g-window[data-fill="block"]').forEach(w => { if (shown(w) && !w.querySelector('svg.lb')) bad.push('a window with no picture and no label'); });
  const labels = [...doc.querySelectorAll('svg.lb')].filter(shown);
  labels.forEach(svg => {
    const box = svg.getBoundingClientRect();
    if (!svg.childElementCount) bad.push('an empty label');
    if (box.width <= 64.5 && svg.dataset.tier !== 'S') bad.push(`a ${Math.round(box.width)} px label drawn at tier ${svg.dataset.tier}`);
    const r = parseFloat(svg.dataset.r);
    svg.querySelectorAll(':scope > text').forEach(t => {
      const b = t.getBBox();
      if (b.x < -0.5 || b.y < -0.5 || b.x + b.width > 100.5 || b.y + b.height > 100.5) bad.push('label text leaves its window: ' + t.textContent);
      // The rim (tier L) runs on its own arc outside the center label; the window test above holds it.
      if (r > 0 && !t.querySelector('textPath')) {
        // The cap box (from the baseline up by 0.8 em in the display face, 0.73 in the body face) inside the circle.
        const size = parseFloat(t.getAttribute('font-size')), base = parseFloat(t.getAttribute('y'));
        const cap = size * (t.classList.contains('lb-display') ? 0.8 : 0.73);
        for (const y of [base - cap, base]) {
          const dy = Math.abs(y - 50), half = dy < r ? Math.sqrt(r * r - dy * dy) : 0;
          if (b.width / 2 > half + 0.5) bad.push(`text leaves its label at ${Math.round(box.width)} px: ${t.textContent}`);
        }
      }
    });
  });
  if (%s && !labels.length) bad.push('no label drawn on a page that has things without pictures');
  if (doc.documentElement.scrollWidth > win.innerWidth) bad.push(`page scrolls sideways: ${doc.documentElement.scrollWidth} > ${win.innerWidth}`);
  if (doc.querySelector('.state-problem')) bad.push('a problem state: ' + doc.querySelector('.state-problem').textContent.trim().slice(0, 40));
  return JSON.stringify({ bad: [...new Set(bad)], labels: labels.length });
})()"""

FRAME = """<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:#888}</style>
<iframe id="fit" src="%s" width="375" height="%d" style="border:0;display:block"></iframe>"""


def fetch(url):
    return json.loads(urllib.request.urlopen(url, timeout=30).read())


def pages(data):
    idx = fetch(data + 'index/series.json')
    F = {k: i for i, k in enumerate(idx['fields'])}
    rows = sorted(idx['rows'], key=lambda r: (-(r[F['downloads']] or 0), r[F['key']]))
    pic = next(r for r in rows if r[F['picture']])
    nopic = next(r for r in rows if not r[F['picture']] and not r[F['art']] and r[F['first']])
    ser = fetch(data + f"series/{urllib.parse.quote(nopic[F['key']])}.json")
    ep = next(e for e in ser['episodes'] if e[1] and len(e[1]) == 10)
    voices = fetch(data + 'index/voices.json')
    VF = {k: i for i, k in enumerate(voices['fields'])}
    person = next(v for v in sorted(voices['rows'], key=lambda v: -(v[VF['episodes']] or 0)) if not v[VF['art']])
    q = urllib.parse.quote
    return [
        ('home', '?view=home&mute=1', r'Find a show', True),
        ('browse', '?view=browse&mute=1', r'\d shows', True),
        ('series-picture', f"?series={q(pic[F['key']])}&mute=1", re.escape(pic[F['name']]), False),
        ('series-label', f"?series={q(nopic[F['key']])}&mute=1", re.escape(nopic[F['name']]), True),
        ('episode-label', f"?item={q(ep[0])}&mute=1", re.escape(nopic[F['name']]), True),
        ('person-label', f"?person={q(person[VF['id']])}&mute=1", re.escape(person[VF['name']]), True),
        ('record', '?view=record&mute=1', r'Plays', True),
    ]


def launch(profile):
    proc = subprocess.Popen([web_run.CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--mute-audio',
                             '--autoplay-policy=user-gesture-required', '--no-first-run', '--no-default-browser-check',
                             *web_run.QUIET, '--remote-debugging-port=0', f'--user-data-dir={profile}', 'about:blank'],
                            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, errors='replace', start_new_session=True)
    ws, t0 = None, time.time()
    for line in proc.stderr:
        m = re.search(r'DevTools listening on (ws://\S+)', line)
        if m:
            ws = m.group(1)
            break
        if time.time() - t0 > 90:
            break
    if not ws:
        web_run._kill(proc)
        raise RuntimeError('Chrome never announced DevTools')
    threading.Thread(target=lambda: [None for _ in proc.stderr], daemon=True).start()
    port = int(urllib.parse.urlsplit(ws).port)
    while time.time() - t0 < 90:
        targets = json.loads(urllib.request.urlopen(f'http://127.0.0.1:{port}/json/list', timeout=5).read())
        page = next((p for p in targets if p.get('type') == 'page'), None)
        if page:
            return proc, web_run.CDP(page['webSocketDebuggerUrl'])
        time.sleep(0.1)
    web_run._kill(proc)
    raise RuntimeError('Chrome listed no page')


def main():
    shots = sys.argv[sys.argv.index('--shots') + 1] if '--shots' in sys.argv else None
    data = sys.argv[sys.argv.index('--data') + 1] if '--data' in sys.argv else 'https://eardrama.org/data/'
    if shots:
        os.makedirs(shots, exist_ok=True)
    work = tempfile.mkdtemp(prefix='fit-label-')
    for f in os.listdir(ROOT):
        if f not in ('index.html', '.git', 'build', 'android', 'apple', 'catalog', 'docs', 'worker', 'windows', 'data'):
            os.symlink(os.path.join(ROOT, f), os.path.join(work, f))
    html = open(os.path.join(ROOT, 'index.html')).read().replace(
        '<meta name="ed-data" content="data/">', f'<meta name="ed-data" content="{data}">', 1)
    open(os.path.join(work, 'index.html'), 'w').write(html)
    srv_code = ("import sys,http.server,functools\n"
                "class S(http.server.ThreadingHTTPServer):\n request_queue_size=256\n daemon_threads=True\n"
                "class H(http.server.SimpleHTTPRequestHandler):\n def log_message(self,*a): pass\n"
                "S(('127.0.0.1',int(sys.argv[1])),functools.partial(H,directory=sys.argv[2])).serve_forever()\n")
    port = 8800 + os.getpid() % 400
    srv = subprocess.Popen([sys.executable, '-c', srv_code, str(port), work], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    profile = tempfile.mkdtemp(prefix='fit-label-chrome-')
    proc = None
    problems = 0
    try:
        time.sleep(1)
        proc, cdp = launch(profile)
        cdp.call('Page.enable')
        for name, q, ready, want in pages(data):
            for dark in (False, True):
                for w in (375, 1440):
                    h = 1800 if w == 375 else 1100
                    url = f'http://127.0.0.1:{port}/{q}'
                    if w == 375:
                        fn = f'frame-{name}-{"d" if dark else "l"}.html'
                        open(os.path.join(work, fn), 'w').write(FRAME % (url, h))
                        url = f'http://127.0.0.1:{port}/{fn}'
                    cdp.call('Emulation.setDeviceMetricsOverride', {'width': w if w > 600 else 375, 'height': h, 'deviceScaleFactor': 1, 'mobile': False})
                    cdp.call('Emulation.setEmulatedMedia', {'features': [{'name': 'prefers-color-scheme', 'value': 'dark' if dark else 'light'}]})
                    cdp.call('Page.navigate', {'url': url}, timeout=30)
                    t0, rx, ok_ready = time.time(), re.compile(ready, re.I), False
                    while time.time() - t0 < 45:
                        v = cdp.call('Runtime.evaluate', {'expression': "(() => { const f = document.querySelector('iframe#fit'); const d = f ? f.contentDocument : document; return d && d.body ? d.body.innerText : ''; })()", 'returnByValue': True})
                        if rx.search(v.get('result', {}).get('value') or ''):
                            ok_ready = True
                            break
                        time.sleep(0.2)
                    time.sleep(3)   # rows and the series index land one by one; let the last paint
                    cdp.call('Runtime.evaluate', {'expression': "(() => { const f = document.querySelector('iframe#fit'); const d = f ? f.contentDocument : document; return d.fonts.ready.then(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))); })()", 'awaitPromise': True}, timeout=15)
                    r = cdp.call('Runtime.evaluate', {'expression': CHECK % ('true' if want else 'false'), 'returnByValue': True})
                    out = json.loads(r['result']['value'])
                    bad = out['bad'] + ([] if ok_ready else ['never ready'])
                    problems += len(bad)
                    label = f'{name} {w} {"dark" if dark else "light"}'
                    print(('FAIL ' if bad else 'ok   ') + f'{label} ({out["labels"]} labels) {bad or ""}')
                    if shots:
                        params = {'format': 'png'}
                        if w == 375:
                            params['clip'] = {'x': 0, 'y': 0, 'width': 375, 'height': h, 'scale': 1}
                        s = cdp.call('Page.captureScreenshot', params, timeout=30)
                        open(os.path.join(shots, f'{name}-{w}-{"dark" if dark else "light"}.png'), 'wb').write(base64.b64decode(s['data']))
    finally:
        if proc:
            web_run._kill(proc)
        srv.terminate()
        srv.wait(timeout=5)
        shutil.rmtree(profile, ignore_errors=True)
        shutil.rmtree(work, ignore_errors=True)
    print(f'{"FAIL" if problems else "PASS"}: {problems} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
