#!/usr/bin/env python3
"""Fit gate for Now Playing (D3-9): its queue and Share verbs stay on one line, the dialog never scrolls sideways,
and no face name overflows, at 320, 375, 390 and 430 px, light and dark. Reads the live catalog (needs the network)
in headless Chrome, muted, with the media element's play stubbed so nothing is ever heard.

    python3 tools/web_fit_nowplaying.py          # exit 1 on any problem

Negative control: set `.np-verbs` to `flex-wrap: wrap` and `.np-verbs .btn` to `flex: 1 0 70%` in css/styles.css;
the two verbs drop a line apart and this fails.
"""
import json, os, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from webdrive import Browser  # noqa: E402

ITEM = 'abbottandcostelloshow%7C1949-02-03'
JS = r"""(() => {
  const bad = [];
  const dlg = document.getElementById('now-playing');
  const kids = [...document.querySelectorAll('.np-verbs .btn')];
  const tops = kids.map(b => Math.round(b.getBoundingClientRect().top));
  if (kids.length < 2) bad.push('the queue and Share verbs are not both there');
  if (new Set(tops).size > 1) bad.push('verbs wrap apart: tops ' + tops);
  const row = document.querySelector('.np-verbs').getBoundingClientRect();
  kids.forEach(b => { const r = b.getBoundingClientRect(); if (r.right > row.right + 1 || r.left < row.left - 1) bad.push('a verb leaves its row'); });
  if (dlg.scrollWidth > dlg.clientWidth + 1) bad.push('Now Playing scrolls sideways: ' + dlg.scrollWidth + ' > ' + dlg.clientWidth);
  document.querySelectorAll('#now-playing .g-face-name').forEach(n => {
    if (n.scrollWidth > n.clientWidth + 1) bad.push('overflow in a face name: ' + n.textContent.slice(0, 30));
  });
  if (document.getElementById('np-air').hidden) bad.push('On the air is hidden for an episode with credits');
  if (document.getElementById('np-night').hidden) bad.push('That night on the radio is hidden for a date with other broadcasts');
  return JSON.stringify(bad);
})()"""


def main():
    work = tempfile.mkdtemp(prefix='fit-np-')
    for f in os.listdir(ROOT):
        if f not in ('index.html', '.git', 'build', 'android', 'apple', 'catalog', 'docs', 'worker', 'windows'):
            os.symlink(os.path.join(ROOT, f), os.path.join(work, f))
    html = open(os.path.join(ROOT, 'index.html')).read().replace(
        '<head>', '<head><meta name="ed-data" content="https://eardrama.org/data/">', 1)
    open(os.path.join(work, 'index.html'), 'w').write(html)
    srv_code = ("import sys,http.server,functools\n"
                "class H(http.server.SimpleHTTPRequestHandler):\n def log_message(self,*a): pass\n"
                "http.server.ThreadingHTTPServer(('127.0.0.1',int(sys.argv[1])),functools.partial(H,directory=sys.argv[2])).serve_forever()\n")
    port = 8300 + os.getpid() % 300
    srv = subprocess.Popen([sys.executable, '-c', srv_code, str(port), work], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    b = Browser(port=9500 + os.getpid() % 100, profile=os.path.join(work, 'prof'), headless=True)
    b.ws.call('Page.addScriptToEvaluateOnNewDocument', {'source':
        'HTMLMediaElement.prototype.play=function(){return Promise.resolve()};HTMLMediaElement.prototype.load=function(){};'})
    problems = 0
    try:
        for dark in (False, True):
            for w in (320, 375, 390, 430):
                b.ws.call('Emulation.setDeviceMetricsOverride', {'width': w, 'height': 900, 'deviceScaleFactor': 1, 'mobile': True})
                b.ws.call('Emulation.setEmulatedMedia', {'features': [{'name': 'prefers-color-scheme', 'value': 'dark' if dark else 'light'}]})
                b.goto(f'http://127.0.0.1:{port}/?item={ITEM}&mute=1', 5)
                deadline = time.time() + 20
                while time.time() < deadline and not b.js("!!document.querySelector('.btn-play')"):
                    time.sleep(0.5)
                b.js("document.querySelector('.btn-play').click()")
                time.sleep(1.5)
                b.js("document.getElementById('mini-open').click()")
                deadline = time.time() + 12
                while time.time() < deadline and b.js("document.getElementById('np-night').hidden"):
                    time.sleep(0.5)
                out = json.loads(b.js(JS))
                problems += len(out)
                print(('FAIL ' if out else 'ok   ') + f"{w} {'dark' if dark else 'light'} {out or ''}")
    finally:
        b.close()
        srv.terminate()
    print(f'{"FAIL" if problems else "PASS"}: {problems} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
