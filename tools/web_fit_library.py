#!/usr/bin/env python3
"""Fit gate and frames for Library (WEB-DESIGN 4.7): every section, empty and full, light and dark, at 320, 375,
390 and 430 px. Button rows stay on one line, the page never scrolls sideways, and no tile name overflows.
Reads the live catalog (network) in headless Chrome, muted; never presses Play.

    python3 tools/web_fit_library.py              # exit 1 on any problem
    python3 tools/web_fit_library.py --shots DIR  # also write a PNG per frame

Negative control: delete `.g-grid` from css/styles.css; Following's tiles lose their grid and the
"Following drew no tiles" or overflow check fails.
"""
import json, os, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import web_run  # noqa: E402

SERIES = [('abbottandcostelloshow', 'The Abbott and Costello Show', 'comedy', '1940', '1949', 125),
          ('dragnet', 'Dragnet', 'drama', '1949', '1957', 312),
          ('gunsmoke', 'Gunsmoke', 'western', '1952', '1961', 480),
          ('suspense', 'Suspense', 'mystery', '1942', '1962', 900),
          ('xminusone', 'X Minus One', 'scifi', '1955', '1958', 126)]


def episode(i, s):
    date = f'{s[3]}-0{i + 1}-0{i + 1}'
    return {'id': f'{s[0]}|{date}', 'title': None, 'series': s[0], 'seriesName': s[1], 'date': date,
            'url': f'https://archive.org/download/{s[0]}/{date}.mp3', 'length': 1800 + i * 60}


EPS = [episode(i, s) for i, s in enumerate(SERIES)]
FULL = {'ed.history': [dict(e, at=10**12 - i) for i, e in enumerate(EPS)],
        'ed.positions': {e['id']: {'t': 600 + i * 120, 'd': 1800, 'at': 10**12 - i} for i, e in enumerate(EPS[:3])},
        'ed.queue': EPS[2:],
        'ed.follows': [{'key': s[0], 'name': s[1], 'genre': s[2], 'first': s[3], 'last': s[4], 'episodes': s[5]}
                       for s in SERIES]}
TABS = ['continue', 'queue', 'following', 'history']
JS = r"""(() => {
  const bad = [];
  document.querySelectorAll('.btn').forEach(b => { const r = b.getBoundingClientRect(); if (r.width && r.height > 64) bad.push('button wraps: ' + b.textContent.slice(0, 20)); });
  const de = document.documentElement;
  if (de.scrollWidth > innerWidth) bad.push(`page scrolls sideways: ${de.scrollWidth} > ${innerWidth}`);
  document.querySelectorAll('.g-name').forEach(n => { if (n.scrollWidth > n.clientWidth + 1) bad.push('tile name overflows: ' + n.textContent.slice(0, 30)); });
  const full = %s;
  const rows = document.querySelectorAll('#library-body .g-row, #library-body .g-tile').length;
  if (full && !rows) bad.push('a full section drew nothing');
  if (!full && rows) bad.push('an empty section drew rows');
  if (!full && !document.querySelector('#library-body .state')) bad.push('an empty section has no caption');
  if (full && %s && !document.querySelector('#library-body .g-grid .g-tile')) bad.push('Following drew no tiles');
  return JSON.stringify(bad);
})()"""


def main():
    shots = sys.argv[sys.argv.index('--shots') + 1] if '--shots' in sys.argv else None
    if shots:
        os.makedirs(shots, exist_ok=True)
    work = tempfile.mkdtemp(prefix='fit-library-')
    for f in os.listdir(ROOT):
        if f not in ('index.html', '.git', 'build', 'android', 'apple', 'catalog', 'docs', 'worker', 'windows'):
            os.symlink(os.path.join(ROOT, f), os.path.join(work, f))
    html = open(os.path.join(ROOT, 'index.html')).read().replace(
        '<head>', '<head><meta name="ed-data" content="https://eardrama.org/data/">', 1)
    open(os.path.join(work, 'index.html'), 'w').write(html)
    srv_code = ("import sys,http.server,functools\n"
                "class S(http.server.ThreadingHTTPServer):\n request_queue_size=256\n daemon_threads=True\n"
                "class H(http.server.SimpleHTTPRequestHandler):\n def log_message(self,*a): pass\n"
                "S(('127.0.0.1',int(sys.argv[1])),functools.partial(H,directory=sys.argv[2])).serve_forever()\n")
    port = 8300 + os.getpid() % 500
    srv = subprocess.Popen([sys.executable, '-c', srv_code, str(port), work],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    state = {'dark': False, 'full': False, 'tab': 'queue', 'out': []}
    orig = web_run.CDP.call

    def call(self, method, params=None, timeout=20):
        if method == 'Page.navigate':
            orig(self, 'Emulation.setEmulatedMedia', {'features': [
                {'name': 'prefers-color-scheme', 'value': 'dark' if state['dark'] else 'light'}]})
            seed = ''.join(f"localStorage.setItem({k!r},{json.dumps(json.dumps(v))});"
                           for k, v in FULL.items()) if state['full'] else ''
            orig(self, 'Page.addScriptToEvaluateOnNewDocument', {'source': seed})
        if method == 'Page.captureScreenshot':
            following = state['full'] and state['tab'] == 'following'
            r = orig(self, 'Runtime.evaluate', {'expression': JS % (
                'true' if state['full'] else 'false', 'true' if following else 'false'), 'returnByValue': True})
            state['out'] = json.loads(r['result']['value'])
        return orig(self, method, params, timeout)
    web_run.CDP.call = call
    problems = 0
    try:
        for tab in TABS:
            for full in (False, True):
                for dark in (False, True):
                    for w in (320, 375, 390, 430):
                        state.update(dark=dark, full=full, tab=tab, out=['never measured'])
                        name = f'library-{tab}-{"full" if full else "empty"}-{"dark" if dark else "light"}-{w}.png'
                        out = os.path.join(shots, name) if shots else os.path.join(work, 'fit.png')
                        web_run.shoot(f'http://127.0.0.1:{port}/?view=library&tab={tab}&mute=1', w, 900, out,
                                      r'Library')
                        problems += len(state['out'])
                        print(('FAIL ' if state['out'] else 'ok   ') +
                              f"{tab} {'full' if full else 'empty'} {w} {'dark' if dark else 'light'} {state['out'] or ''}")
    finally:
        srv.terminate()
    print(f'{"FAIL" if problems else "PASS"}: {problems} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
