#!/usr/bin/env python3
"""Fit gate for the series and episode pages (WEB-DESIGN 6.4d): every button row stays on one line, nothing
leaves its row, the page never scrolls sideways, and no head or face name overflows, at 320, 375, 390 and
430 px, light and dark. Reads the live catalog (needs the network) in headless Chrome.

    python3 tools/web_fit_actions.py            # exit 1 on any problem
    python3 tools/web_fit_actions.py --list

Negative control: set `.actions-one` to `flex-wrap: wrap` and drop the `@container` fold in css/styles.css;
the Share button drops a line and this fails.
"""
import json, os, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import web_run  # noqa: E402

def routes():
    """The four pages, chosen from the live data (never pinned): the most downloaded series with a picture, a
    series without one, and each one's first dated episode."""
    import urllib.parse, urllib.request
    fetch = lambda u: json.load(urllib.request.urlopen('https://eardrama.org/data/' + u, timeout=30))
    idx = fetch('index/series.json')
    F = {k: i for i, k in enumerate(idx['fields'])}
    rows = sorted(idx['rows'], key=lambda r: (-(r[F['downloads']] or 0), r[F['key']]))

    def dated(row):
        ser = fetch(f"series/{urllib.parse.quote(row[F['key']])}.json")
        EF = {k: i for i, k in enumerate(ser['fields'])}
        return next((e[EF['id']] for e in ser['episodes'] if e[EF['date']] and len(e[EF['date']]) == 10), None)

    rich = next(r for r in rows if r[F['picture']] and r[F['picture']][1] and r[F['picture']][2] and dated(r))
    bare = next(r for r in rows if not r[F['picture']] and r[F['first']] and dated(r))
    q = lambda v: urllib.parse.quote(v, safe='')
    return {
        'series-rich': f"/?series={q(rich[F['key']])}", 'series-sparse': f"/?series={q(bare[F['key']])}",
        'episode-rich': f"/?item={q(dated(rich))}", 'episode-bare': f"/?item={q(dated(bare))}",
    }


JS = r"""(() => {
  if (!document.querySelector('.actions-start') && document.querySelector('.actions-one') && %s) {
    const d = document.createElement('div'); d.className = 'actions actions-one actions-start';
    d.innerHTML = '<span class="start-drama"><button class="btn btn-accent">Start an ear drama</button></span>';
    document.querySelector('.actions-one').after(d);
  }
  const bad = [];
  const rows = [...document.querySelectorAll('.actions-one')];
  if (!rows.length) bad.push('no button row on the page');
  rows.forEach((row, i) => {
    const kids = [...row.querySelectorAll('.btn')].filter(b => b.getBoundingClientRect().width > 0);
    const tops = kids.map(b => Math.round(b.getBoundingClientRect().top));
    const rr = row.getBoundingClientRect();
    if (new Set(tops).size > 1) bad.push(`row ${i} wraps apart: tops ${tops}`);
    kids.forEach(b => { const r = b.getBoundingClientRect(); if (r.right > rr.right + 1 || r.left < rr.left - 1) bad.push(`row ${i} button leaves the row`); });
  });
  const de = document.documentElement;
  if (de.scrollWidth > innerWidth) bad.push(`page scrolls sideways: ${de.scrollWidth} > ${innerWidth}`);
  document.querySelectorAll('.g-head-name, .g-face-name, .ep-heading, .g-kicker').forEach(n => {
    if (n.scrollWidth > n.clientWidth + 1) bad.push(`overflow in ${n.className}: ${n.textContent.slice(0, 30)}`);
  });
  const shown = document.body.innerText + ' ' + [...document.querySelectorAll('[aria-label]')].map(n => n.getAttribute('aria-label')).join(' ');
  const iso = shown.match(/\d{4}[-‑](0[1-9]|1[0-2])([-‑](0[1-9]|[12]\d|3[01]))?(?!\d)/);
  if (iso) bad.push('an ISO date is on screen: ' + iso[0]);
  document.querySelectorAll('.versions .version').forEach(v => {
    const id = v.querySelector('label').textContent.match(/\w*_\w*|[A-Za-z]{4,}\d{3,}|\d{3,}[A-Za-z]{4,}/);
    if (id) bad.push('an archive.org identifier is in the Recordings list: ' + id[0]);
  });
  return JSON.stringify(bad);
})()"""


def main():
    if '--list' in sys.argv:
        print('\n'.join(routes())); return 0
    work = tempfile.mkdtemp(prefix='fit-actions-')
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
    srv = subprocess.Popen([sys.executable, '-c', srv_code, str(port), work], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    state = {'dark': False, 'out': [], 'start': False}
    orig = web_run.CDP.call

    def call(self, method, params=None, timeout=20):
        if method == 'Page.navigate':
            orig(self, 'Emulation.setEmulatedMedia', {'features': [
                {'name': 'prefers-color-scheme', 'value': 'dark' if state['dark'] else 'light'}]})
        if method == 'Page.captureScreenshot':
            r = orig(self, 'Runtime.evaluate', {'expression': JS % ('true' if state['start'] else 'false'), 'returnByValue': True})
            state['out'] = json.loads(r['result']['value'])
        return orig(self, method, params, timeout)
    web_run.CDP.call = call
    shot = os.path.join(work, 'fit.png')
    problems = 0
    try:
        for name, path in routes().items():
            for dark in (False, True):
                for w in (320, 375, 390, 430):
                    state.update(dark=dark, start=name.startswith('episode'), out=['never measured'])
                    web_run.shoot(f'http://127.0.0.1:{port}{path}', w, 900, shot, r'episodes|Recording')
                    problems += len(state['out'])
                    print(('FAIL ' if state['out'] else 'ok   ') + f"{name} {w} {'dark' if dark else 'light'} {state['out'] or ''}")
    finally:
        srv.terminate()
    print(f'{"FAIL" if problems else "PASS"}: {problems} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
