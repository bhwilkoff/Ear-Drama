#!/usr/bin/env python3
"""Fit gate and frames for Stations, Surprise, Search and a person's page (WEB-DESIGN 4.6, 4.9, 4.13, 4.14; D3-8): light and
dark, at 320, 375, 390 and 430 px. Rows are 64 px with a 48 px window, button rows stay on one line, the page never
scrolls sideways, and no tile or head name overflows.
Reads the live catalog (network) in headless Chrome, muted; never presses Play.

    python3 tools/web_fit_pages.py              # exit 1 on any problem
    python3 tools/web_fit_pages.py --shots DIR  # also write a PNG per frame

Negative control: delete the `.g-round` rule from css/styles.css; a person's window stops being round and the check fails.
"""
import json, os, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import web_run  # noqa: E402

def after_the_evening():
    """An instant (ISO, UTC) one hour after today's published evening ends, for the harness's ?now= door."""
    import datetime, urllib.request
    day = json.load(urllib.request.urlopen('https://eardrama.org/data/tonight.json', timeout=30))['days'][time.strftime('%Y-%m-%d')]
    last = max(datetime.datetime.fromisoformat(s['utc_end'].replace('Z', '+00:00')) for s in day['slots'])
    return (last + datetime.timedelta(hours=1)).strftime('%Y-%m-%dT%H:%M:%SZ')


ROUTES = [('stations', '?view=radio&mute=1', r'Stations', '.station.g-row', 1),
          ('stations-ended', '?view=radio&mute=1&now=' + after_the_evening(), r'Stations',
           '.station.g-row .btn-primary[aria-label^="Replay"]', 1),
          ('surprise', '?view=surprise&mute=1', r'Surprise', '.pick .g-head', 2),
          ('search', '?view=search&q=welles&mute=1', r'People', '#search-body .g-row .g-window', 2),
          ('person-portrait', '?person=otrr:6237&mute=1', r'Webb', '.g-head .g-window img', 1),
          ('person-monogram', '?person=otrr:6267&mute=1', r'Welles', '.g-head .g-window[data-fill="block"]', 1)]
JS = r"""(async () => {
  const bad = [];
  await new Promise(r => setTimeout(r, 2500));
  const de = document.documentElement;
  if (de.scrollWidth > innerWidth) bad.push(`page scrolls sideways: ${de.scrollWidth} > ${innerWidth}`);
  document.querySelectorAll('.btn').forEach(b => { const r = b.getBoundingClientRect(); if (r.width && r.height > 64) bad.push('button wraps: ' + b.textContent.slice(0, 20)); });
  document.querySelectorAll('.g-name, .g-head-name').forEach(n => { if (n.scrollWidth > n.clientWidth + 1) bad.push('name overflows: ' + n.textContent.slice(0, 30)); });
  const view = document.querySelector('.view:not([hidden])');
  view.querySelectorAll('.g-row').forEach(r => {
    const h = r.getBoundingClientRect().height, w = r.querySelector('.g-window, .g-date');
    if (h < 63.5) bad.push('row under 64 px: ' + r.textContent.slice(0, 30));
    if (!w) bad.push('row without its visual: ' + r.textContent.slice(0, 30));
    else if (Math.abs(w.getBoundingClientRect().width - 48) > 1) bad.push('visual is not 48 px: ' + r.textContent.slice(0, 30));
  });
  view.querySelectorAll('a[href*="person="] > .g-window').forEach(w => { if (getComputedStyle(w).borderRadius !== '50%%') bad.push('a person window is not round'); });
  if (!view.querySelector(%r)) bad.push('nothing drew for %s');
  return JSON.stringify(bad);
})()"""


def main():
    shots = sys.argv[sys.argv.index('--shots') + 1] if '--shots' in sys.argv else None
    if shots:
        os.makedirs(shots, exist_ok=True)
    work = tempfile.mkdtemp(prefix='fit-pages-')
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
    state = {'dark': False, 'js': '', 'out': []}
    orig = web_run.CDP.call

    def call(self, method, params=None, timeout=20):
        if method == 'Page.navigate':
            orig(self, 'Emulation.setEmulatedMedia', {'features': [
                {'name': 'prefers-color-scheme', 'value': 'dark' if state['dark'] else 'light'}]})
        if method == 'Page.captureScreenshot':
            r = orig(self, 'Runtime.evaluate', {'expression': state['js'], 'returnByValue': True,
                                                'awaitPromise': True}, 30)
            state['out'] = json.loads(r['result']['value'])
        return orig(self, method, params, timeout)
    web_run.CDP.call = call
    problems = 0
    try:
        for name, query, ready, sel, _ in ROUTES:
            for dark in (False, True):
                for w in (320, 375, 390, 430):
                    state.update(dark=dark, js=JS % (sel, name), out=['never measured'])
                    png = f'{name}-{"dark" if dark else "light"}-{w}.png'
                    out = os.path.join(shots, png) if shots else os.path.join(work, 'fit.png')
                    web_run.shoot(f'http://127.0.0.1:{port}/{query}', w, 900, out, ready)
                    problems += len(state['out'])
                    print(('FAIL ' if state['out'] else 'ok   ') + f"{name} {w} {'dark' if dark else 'light'} {state['out'] or ''}")
    finally:
        srv.terminate()
    print(f'{"FAIL" if problems else "PASS"}: {problems} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
