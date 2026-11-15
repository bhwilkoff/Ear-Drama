#!/usr/bin/env python3
"""Fit gate and frames for Home and Record (WEB-DESIGN 4.2, 4.15; Decision 075), light and dark, at 320,
375, 390, 430 and 1440 px: Home with no history and with history (Continue leads under On the air),
during tonight's evening and in the day (a genre station leads), and Record. Fails on a door row or
button row that wraps apart, a word broken inside itself, a sideways scroll, an overflowing tile name,
an opening line that runs out sideways, a Home that drew no On the air block, no doors, or no rows, a
Record with no play tiles, or either page without Today's scene and its opening (2026-11-15 review).

Reads the live catalog (network) in headless Chrome, muted; never presses Play.

    python3 tools/web_fit_home.py              # exit 1 on any problem
    python3 tools/web_fit_home.py --shots DIR  # also write a PNG per frame
    python3 tools/web_fit_home.py --data URL   # read another projection (default https://eardrama.org/data/)

Negative control: delete `grid-auto-flow: column` from `.home-doors` in css/styles.css; the doors
stack and "the doors wrap apart" fails.
Second (2026-11-15): delete `flex-wrap: nowrap;` from `.pl-scene-actions`; at 320 px Try a line, Hear
it and Read wrap and "a button row wrap apart" fails (it did, before that rule).
"""
import datetime, json, os, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import web_run  # noqa: E402

SERIES = [('dragnet', 'Dragnet', '1949'), ('gunsmoke', 'Gunsmoke', '1952'), ('suspense', 'Suspense', '1942')]
EPS = [{'id': f'{k}|{y}-0{i + 1}-0{i + 1}', 'title': None, 'series': k, 'seriesName': n, 'date': f'{y}-0{i + 1}-0{i + 1}',
        'url': f'https://archive.org/download/{k}/{y}.mp3', 'length': 1800} for i, (k, n, y) in enumerate(SERIES)]
HISTORY = {'ed.history': [dict(e, at=10**12 - i) for i, e in enumerate(EPS)],
           'ed.positions': {e['id']: {'t': 600, 'd': 1800, 'at': 10**12 - i} for i, e in enumerate(EPS)}}
WIDTHS = (320, 375, 390, 430, 1440)

JS = r"""(() => {
  const bad = [];
  const view = %s;
  const root = document.getElementById(view === 'record' ? 'view-record' : 'view-listen');
  root.querySelectorAll('.btn').forEach(b => { const r = b.getBoundingClientRect(); if (r.width && r.height > 64) bad.push('button wraps: ' + b.textContent.trim().slice(0, 24)); });
  const rowsApart = (sel, name) => root.querySelectorAll(sel).forEach(row => {
    const kids = [...row.children].filter(k => k.getBoundingClientRect().width > 0);
    const tops = new Set(kids.map(k => Math.round(k.getBoundingClientRect().top)));
    if (tops.size > 1) bad.push(name + ' wrap apart');
  });
  rowsApart('.home-doors', 'the doors');
  rowsApart('.home-live-actions', 'On the air’s buttons');
  rowsApart('.actions-one', 'a button row');
  root.querySelectorAll('.pl-scene-said, .pl-open-sp').forEach(n => { if (n.scrollWidth > n.clientWidth + 1) bad.push('an opening line runs out sideways'); });
  const de = document.documentElement;
  if (de.scrollWidth > innerWidth) bad.push(`page scrolls sideways: ${de.scrollWidth} > ${innerWidth}`);
  root.querySelectorAll('.g-name').forEach(n => { if (n.scrollWidth > n.clientWidth + 1) bad.push('tile name overflows: ' + n.textContent.slice(0, 30)); });
  // A word broken inside itself: one word's glyphs on two lines.
  const sel = '.pl-open-said, .pl-scene-said, .pl-scene-who, .home-door-lab, .btn, .g-name, .ep-title, .section-header, .g-kicker, .segmented button, .tab span, .g-facts span, .g-head-name';
  document.querySelectorAll(sel).forEach(n => {
    if (!n.getBoundingClientRect().width) return;
    const walk = document.createTreeWalker(n, NodeFilter.SHOW_TEXT);
    for (let t = walk.nextNode(); t; t = walk.nextNode()) {
      const re = /[^\s\-\u2010-\u2014\/]+/g; let m;   // a break at a hyphen, dash or slash is between words
      while ((m = re.exec(t.data))) {
        const rg = document.createRange(); rg.setStart(t, m.index); rg.setEnd(t, m.index + m[0].length);
        const tops = new Set([...rg.getClientRects()].filter(r => r.width > 0.5).map(r => Math.round(r.top)));
        if (tops.size > 1) bad.push('a word breaks inside itself: ' + m[0]);
      }
    }
  });
  if (view === 'home') {
    if (!root.querySelector('.home-doors')) bad.push('no doors');
    if (%s && !root.querySelector('.home-live')) bad.push('no On the air block');
    if (!root.querySelector('.g-tile')) bad.push('Home drew no tiles');
    if (%s && !root.querySelector('#cont-h')) bad.push('history but no Continue');
  } else if (!root.querySelector('.pl-cast, .pl-open')) bad.push('Record drew no play tiles');
  if (!root.querySelector('.pl-scene .pl-scene-sp')) bad.push('no scene card with its opening');
  if (document.querySelector('.state-problem')) bad.push('a problem state is on screen: ' + document.querySelector('.state-problem').textContent.trim().slice(0, 40));
  return JSON.stringify([...new Set(bad)]);
})()"""


def main():
    shots = sys.argv[sys.argv.index('--shots') + 1] if '--shots' in sys.argv else None
    data = sys.argv[sys.argv.index('--data') + 1] if '--data' in sys.argv else 'https://eardrama.org/data/'
    if shots:
        os.makedirs(shots, exist_ok=True)
    work = tempfile.mkdtemp(prefix='fit-home-')
    for f in os.listdir(ROOT):
        if f not in ('index.html', '.git', 'build', 'android', 'apple', 'catalog', 'docs', 'worker', 'windows'):
            os.symlink(os.path.join(ROOT, f), os.path.join(work, f))
    html = open(os.path.join(ROOT, 'index.html')).read().replace(
        '<meta name="ed-data" content="data/">', f'<meta name="ed-data" content="{data}">', 1)
    open(os.path.join(work, 'index.html'), 'w').write(html)
    srv_code = ("import sys,http.server,functools\n"
                "class S(http.server.ThreadingHTTPServer):\n request_queue_size=256\n daemon_threads=True\n"
                "class H(http.server.SimpleHTTPRequestHandler):\n def log_message(self,*a): pass\n"
                "S(('127.0.0.1',int(sys.argv[1])),functools.partial(H,directory=sys.argv[2])).serve_forever()\n")
    port = 8300 + os.getpid() % 500
    srv = subprocess.Popen([sys.executable, '-c', srv_code, str(port), work],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    state = {'dark': False, 'hist': False, 'view': 'home', 'live': True, 'out': []}
    orig = web_run.CDP.call

    def call(self, method, params=None, timeout=20):
        if method == 'Page.navigate':
            orig(self, 'Emulation.setEmulatedMedia', {'features': [
                {'name': 'prefers-color-scheme', 'value': 'dark' if state['dark'] else 'light'}]})
            seed = ''.join(f"localStorage.setItem({k!r},{json.dumps(json.dumps(v))});"
                           for k, v in HISTORY.items()) if state['hist'] else ''
            orig(self, 'Page.addScriptToEvaluateOnNewDocument', {'source': seed})
        if method == 'Page.captureScreenshot':
            time.sleep(2.5)   # the rows load one by one; let the last land
            js = lambda b: 'true' if b else 'false'
            r = orig(self, 'Runtime.evaluate', {'expression': JS % (
                json.dumps(state['view']), js(state['live']), js(state['hist'])), 'returnByValue': True})
            state['out'] = json.loads(r['result']['value'])
        return orig(self, method, params, timeout)
    web_run.CDP.call = call
    today = datetime.date.today().isoformat()
    # Local clock times through the ?now= door (local servers only): 8 PM is inside every published
    # evening; 11 AM is daytime, when a genre station leads.
    tz = datetime.datetime.now().astimezone().strftime('%z')
    tz = tz[:3] + ':' + tz[3:]
    cases = [('home-evening', 'home', f'?view=home&mute=1&now={today}T20:00:00{tz}', False, True),
             ('home-day-history', 'home', f'?view=home&mute=1&now={today}T11:00:00{tz}', True, True),
             ('record', 'record', '?view=record&mute=1', False, False)]
    problems = 0
    try:
        for name, view, q, hist, live in cases:
            for dark in (False, True):
                for w in WIDTHS:
                    state.update(dark=dark, hist=hist, view=view, live=live, out=['never measured'])
                    fn = f'{name}-{"dark" if dark else "light"}-{w}.png'
                    out = os.path.join(shots, fn) if shots else os.path.join(work, 'fit.png')
                    rec = web_run.shoot(f'http://127.0.0.1:{port}/{q}', w, 2400 if w < 600 else 1600, out,
                                        r'Plays' if view == 'record' else r'Find a show')
                    if rec.get('timed_out'):
                        state['out'].append('timed out waiting')
                    problems += len(state['out'])
                    print(('FAIL ' if state['out'] else 'ok   ') + f"{name} {w} {'dark' if dark else 'light'} {state['out'] or ''}")
    finally:
        srv.terminate()
    print(f'{"FAIL" if problems else "PASS"}: {problems} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
