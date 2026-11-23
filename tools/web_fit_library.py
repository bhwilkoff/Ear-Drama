#!/usr/bin/env python3
"""Fit gate and frames for Library, direction B (WEB-DESIGN 4.7, Decision 087): both sides (Listening, Making), a new
person and a heavy one, light and dark, at 320, 375, 390, 430 and 1440 px. Reads the live catalog (network) in
headless Chrome, muted; never presses Play. The Making side's shared productions and classes come from a stub put
over API.plays after the page loads (nothing reaches the Worker); seats and marks are seeded in storage.

Fails on: a wrapped button, a sideways scroll, an overflowing tile name, an empty section that drew a header, an
empty side without exactly one sentence and one button, a heavy side missing a section, more than five Up next rows,
two production rows for one play, the foot out of order, Voices open when the address did not ask for it, the
remembered side not chosen, an ISO date on screen. Then each place a line opens (Up next, History, Marks, one play's
productions) and Voices opened by `?view=library&section=voices`, heavy, at 375 px.

    python3 tools/web_fit_library.py              # exit 1 on any problem
    python3 tools/web_fit_library.py --shots DIR  # also write a full-height PNG per frame

Negative control: in js/plays-ui.js `making`, key each group by the production (`r.local ? r.local.id :
r.remote.id`) instead of `playKey(r)`; the heavy Making frames fail "two production rows for one play".
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


def episode(i, s, n=0):
    date = f'{s[3]}-0{i + 1}-{10 + n}'
    return {'id': f'{s[0]}|{date}', 'title': None, 'series': s[0], 'seriesName': s[1], 'date': date,
            'url': f'https://archive.org/download/{s[0]}/{date}.mp3', 'length': 1800 + i * 60}


EPS = [episode(i, s) for i, s in enumerate(SERIES)]
MORE = [episode(i, s, 1) for i, s in enumerate(SERIES)]
MARK = {'id': 'm1', 'kind': 'highlight', 'line': 'L0001', 'start': 0, 'end': 4, 'text': 'Well'}
HEAVY_LOCAL = {'ed.history': [dict(e, at=10**12 - i) for i, e in enumerate(EPS)],
               'ed.positions': {e['id']: {'t': 600 + i * 120, 'd': 1800, 'at': 10**12 - i} for i, e in enumerate(EPS[:3])},
               'ed.queue': EPS[2:] + MORE,
               'ed.follows': [{'key': s[0], 'name': s[1], 'genre': s[2], 'first': s[3], 'last': s[4], 'episodes': s[5]}
                              for s in SERIES]}
for sid, title in (('gut-albany', 'The Albany Depot'), ('gut-caesar', 'Caesar Rodney’s Ride'), ('gut-paw', 'The Monkey’s Paw')):
    HEAVY_LOCAL[f'ed.marks.{sid}'] = {'format': 1, 'script': sid, 'title': title, 'marks': [MARK]}
HEAVY_SESSION = {'ed.seats': [{'seat_key': 'k1', 'class_id': 'C1', 'label': 'Maya'}]}
REMOTE = ([{'id': f'P{i}', 'title': 'The Albany Depot', 'script_id': 'gut-albany', 'director': 'u-other', 'updated_at': 1763800000000 - i * 1000}
           for i in range(8)] +
          [{'id': 'P9', 'title': 'Caesar Rodney’s Ride', 'script_id': 'gut-caesar', 'director': 'u-other', 'updated_at': 1763700000000},
           {'id': 'P10', 'title': 'The Monkey’s Paw', 'script_id': 'gut-paw', 'director': 'u-other', 'updated_at': 1763600000000}])
CLASSES = {'teaching': [{'id': 'C1', 'name': 'Room 12 Readers', 'code': 'ABCD2345'}],
           'member_of': [{'id': 'C2', 'name': 'Thursday Drama Club', 'code': 'WXYZ6789'}]}
STUB = ("API.account.signedIn = () => true; API.account.state = () => ({ user_id: 'u-me', provider: 'google', last_sync_at: Date.now() - 600000 });"
        f"API.plays.available = () => true; API.plays.list = async () => ({{ productions: {json.dumps(REMOTE)} }});"
        f"API.plays.classes = async () => ({json.dumps(CLASSES)}); dispatchEvent(new PopStateEvent('popstate')); true")

# The places Library's lines open, and Voices disclosed by its deep link: (query, side, what must hold).
PAGES = [('list=upnext', 'listen', "document.getElementById('lib-page-h').textContent === 'Up next' && document.querySelectorAll('#library-body .g-row').length === 10"),
         ('list=history', 'listen', "document.getElementById('lib-page-h').textContent === 'History' && document.querySelectorAll('#library-body .g-row').length === 5"),
         ('side=make&list=marks', 'make', "document.getElementById('lib-page-h').textContent === 'Marks' && document.querySelectorAll('#library-body .play-row').length === 3"),
         ('side=make&productions=gut-albany', 'make', "document.getElementById('lib-page-h').textContent === 'The Albany Depot' && document.querySelectorAll('#library-body .play-row').length === 8"),
         ('section=voices', 'listen', "document.getElementById('voices-more').open && !!document.getElementById('voices-h') && !!document.querySelector('#voices .vs-order')")]
PAGE_READY = ("!document.querySelector('#library-body .spinner') && (!!document.querySelector('#library-body .play-row, #library-body .g-row') "
              "|| !!document.getElementById('voices-h'))")

READY = ("!document.querySelector('#library-body .spinner') && !!document.querySelector("
         "'#library-body .state, #library-body .lib-section, #library-body .lib-lines, #library-body .shelf')")
JS = r"""(() => {
  const side = %s, heavy = %s, asked = %s;
  const bad = [];
  document.querySelectorAll('.btn').forEach(b => { const r = b.getBoundingClientRect(); if (r.width && r.height > 64) bad.push('button wraps: ' + b.textContent.slice(0, 20)); });
  const de = document.documentElement;
  if (de.scrollWidth > innerWidth) bad.push(`page scrolls sideways: ${de.scrollWidth} > ${innerWidth}`);
  document.querySelectorAll('.g-name').forEach(n => { if (n.scrollWidth > n.clientWidth + 1) bad.push('tile name overflows: ' + n.textContent.slice(0, 30)); });
  const on = document.querySelector('#library-sides [aria-pressed="true"]');
  if (!on || on.dataset.side !== side) bad.push(`the ${asked ? 'asked' : 'remembered'} side is not chosen: ${on && on.dataset.side}`);
  const body = document.getElementById('library-body');
  const heads = [...body.querySelectorAll('h2')].map(h => h.textContent);
  if (!heavy) {
    if (heads.length) bad.push('an empty section drew a header: ' + heads.join(', '));
    const st = body.querySelectorAll('.state');
    if (st.length !== 1 || st[0].querySelectorAll('p').length !== 1 || st[0].querySelectorAll('.btn').length !== 1) bad.push('an empty side is not one sentence and one button');
    if (body.querySelector('.lib-line')) bad.push('an empty side drew a line');
  } else if (side === 'listen') {
    for (const h of ['Up next', 'Shows you follow']) if (!heads.includes(h)) bad.push('Listening has no ' + h);
    const up = body.querySelectorAll('#lib-upnext-h ~ * .g-row, section[aria-labelledby="lib-upnext-h"] .g-row').length;
    if (up > 5 || up < 1) bad.push(`Up next drew ${up} rows`);
    if (!/^All \d/.test((document.querySelector('section[aria-labelledby="lib-upnext-h"] .block-head a') || {}).textContent || '')) bad.push('Up next has no All N');
    if (!body.querySelector('.shelf .g-tile')) bad.push('Shows you follow drew no tiles');
    if (![...body.querySelectorAll('.lib-line')].some(l => /^History/.test(l.textContent))) bad.push('no History line');
    if (body.querySelector('.state')) bad.push('a heavy side drew an empty state');
  } else {
    for (const h of ['Waiting on you', 'Productions', 'Classes']) if (!heads.includes(h)) bad.push('Making has no ' + h);
    const titles = [...body.querySelectorAll('.play-list .play-row .body-strong')].map(t => t.textContent);
    if (new Set(titles).size !== titles.length) bad.push('two production rows for one play: ' + titles.join(' | '));
    if (![...body.querySelectorAll('.lib-line')].some(l => /^Marks/.test(l.textContent))) bad.push('no Marks line');
    if (body.querySelector('.state')) bad.push('a heavy side drew an empty state');
  }
  const foot = [...document.querySelectorAll('#library-foot .lib-group > *')].map(n => n.id || n.className.split(' ').pop());
  if (foot.join(',') !== 'account-row,voices-more,together-row,export-row,lib-about') bad.push('the foot is out of order: ' + foot.join(','));
  if (document.getElementById('voices-more').open) bad.push('Voices is open though the address did not ask');
  if (!/·/.test(document.getElementById('voices-state').textContent)) bad.push('the Voices row shows no state');
  const shown = document.body.innerText + ' ' + [...document.querySelectorAll('[aria-label]')].map(n => n.getAttribute('aria-label')).join(' ');
  const iso = shown.match(/\d{4}[-‑](0[1-9]|1[0-2])([-‑](0[1-9]|[12]\d|3[01]))?(?!\d)/);
  if (iso) bad.push('an ISO date is on screen: ' + iso[0]);
  return JSON.stringify(bad);
})()"""


def main():
    shots = sys.argv[sys.argv.index('--shots') + 1] if '--shots' in sys.argv else None
    if shots:
        os.makedirs(shots, exist_ok=True)
    work = tempfile.mkdtemp(prefix='fit-library-')
    for f in sorted(os.listdir(ROOT)):
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
    state = {'dark': False, 'heavy': False, 'side': 'listen', 'asked': True, 'w': 375, 'out': []}
    orig = web_run.CDP.call

    def ev(self, expr, wait=False):
        r = orig(self, 'Runtime.evaluate', {'expression': expr, 'returnByValue': True, 'awaitPromise': wait})
        return r.get('result', {}).get('value')

    def until(self, expr, s=20):
        t0 = time.time()
        while time.time() - t0 < s:
            if ev(self, expr):
                return True
            time.sleep(0.1)
        return False

    def call(self, method, params=None, timeout=20):
        if method == 'Page.navigate':
            orig(self, 'Emulation.setEmulatedMedia', {'features': [
                {'name': 'prefers-color-scheme', 'value': 'dark' if state['dark'] else 'light'}]})
            seed = ''
            if state['heavy']:
                seed += ''.join(f"localStorage.setItem({k!r},{json.dumps(json.dumps(v))});" for k, v in HEAVY_LOCAL.items())
                seed += ''.join(f"sessionStorage.setItem({k!r},{json.dumps(json.dumps(v))});" for k, v in HEAVY_SESSION.items())
            if not state['asked']:
                seed += f"localStorage.setItem('ed.library.side', {state['side']!r});"
            orig(self, 'Page.addScriptToEvaluateOnNewDocument', {'source': seed})
        if method == 'Page.captureScreenshot':
            # "Library" is in the tab bar of every page, so web_run's ready text returns early: wait for the side's own body.
            until(self, "typeof API !== 'undefined' && !!document.querySelector('#view-library:not([hidden])')")
            if state['heavy']:
                ev(self, STUB)
            ready = PAGE_READY if state.get('page') else READY
            until(self, ready)
            time.sleep(0.3)
            until(self, ready)
            ev(self, "document.fonts.ready.then(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))))", True)
            if state.get('page'):
                state['out'] = [] if ev(self, state['page']) else [f'the page did not hold: {state["page"]}']
            else:
                r = ev(self, JS % (json.dumps(state['side']), 'true' if state['heavy'] else 'false', 'true' if state['asked'] else 'false'))
                state['out'] = json.loads(r) if r else ['the check did not run']
            # The frame is the whole page: grow the viewport by what <main> scrolls.
            extra = ev(self, "(() => { const m = document.querySelector('main'); return m ? m.scrollHeight - m.clientHeight : 0; })()") or 0
            if extra > 0:
                orig(self, 'Emulation.setDeviceMetricsOverride', {'width': state['w'], 'height': min(900 + extra, 6000),
                                                                  'deviceScaleFactor': 1, 'mobile': state['w'] < 600})
                ev(self, "new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))", True)
        return orig(self, method, params, timeout)
    web_run.CDP.call = call
    problems = 0
    sides = () if '--pages' in sys.argv else ('listen', 'make')
    try:
        for side in sides:
            for heavy in (False, True):
                for dark in (False, True):
                    for w in (320, 375, 390, 430, 1440):
                        # The Making frames come from the remembered side (no &side=), the Listening ones from the address.
                        asked = side == 'listen'
                        state.update(dark=dark, heavy=heavy, side=side, asked=asked, w=w, out=['never measured'])
                        name = f'library-{side}-{"heavy" if heavy else "new"}-{"dark" if dark else "light"}-{w}.png'
                        out = os.path.join(shots, name) if shots else os.path.join(work, 'fit.png')
                        q = '&side=listen' if asked else ''
                        rec = web_run.shoot(f'http://127.0.0.1:{port}/?view=library{q}&mute=1', w, 900, out, r'Library')
                        if state['out'] == ['never measured']: state['out'] = [f"never measured: {rec.get('error') or ('timed out' if rec.get('timed_out') else 'no frame')}"]
                        problems += len(state['out'])
                        print(('FAIL ' if state['out'] else 'ok   ') +
                              f"{side} {'heavy' if heavy else 'new'} {w} {'dark' if dark else 'light'} {state['out'] or ''}")
        for q, side, check in PAGES:
            for dark in (False, True):
                state.update(dark=dark, heavy=True, side=side, asked=True, w=375, page=check, out=['never measured'])
                name = f'library-page-{q.split("=")[-1]}-{"dark" if dark else "light"}-375.png'
                out = os.path.join(shots, name) if shots else os.path.join(work, 'fit.png')
                rec = web_run.shoot(f'http://127.0.0.1:{port}/?view=library&{q}&mute=1', 375, 900, out, r'Library')
                if state['out'] == ['never measured']: state['out'] = [f"never measured: {rec.get('error') or ('timed out' if rec.get('timed_out') else 'no frame')}"]
                problems += len(state['out'])
                print(('FAIL ' if state['out'] else 'ok   ') + f"page {q} {'dark' if dark else 'light'} {state['out'] or ''}")
        state['page'] = None
    finally:
        srv.terminate()
    print(f'{"FAIL" if problems else "PASS"}: {problems} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
