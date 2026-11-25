#!/usr/bin/env python3
"""Fit gate, frames and the whole flow of casting an episode by ear (WEB-DESIGN 4.22, PLAYS-DESIGN 13 item 10), light and
dark, at 320, 375, 768 and 1440 px, in headless Chrome over the DevTools protocol.

Nothing is heard: the episode is a minute and a half of silence served from this Mac, with ?mute=1 and --mute-audio; the speech and
microphone stubs are tools/web_fit_studio.py's. archive.org is never asked: its /cors/ answer is a stub. Signed out
throughout; any account sheet is a failure.

For each width and theme: no times, no door (and the page itself says so, with Try again); the door; looking keeps nothing; a press
plays, at 0.75x, muted, and the end of the episode would start nothing; + Part before the first line; the lit line; a part
tapped and carried; the keys 1 to 9, Space, Left, U and Control-Z; Leave out; a name typed while a line is lit;
a scroll of the person's own, and Back to the line; the line sheet by keyboard (the cut, split, join, one line alone to a part,
Direction, Edit words, Hear it and back to the place, Play from here); Hear a part on a wide screen; a recording that fails, and Try again; a
reload, taken up where it was left; a transcript remade since; offline; a full disk; Done on part of it; its page (N of N
lines cast, Cast by ear, Automatic transcript, no Share); Your scripts; Record this and a take with the stub microphone; the line
with a take refused to another part; the parts page, with Leave out everything below as one step and one Undo; a dock of twelve parts.

Fails on: a sideways scroll; a control under 44 px (a line of the transcript under 30); a control past the edge; the transport off
the screen; the wrong focus order; focus or the keyboard's place lost; a page error; and any of the above not happening.

    python3 tools/web_fit_ear.py                    # exit 1 on any problem
    python3 tools/web_fit_ear.py --shots DIR        # a PNG per frame
    python3 tools/web_fit_ear.py --widths 375,1440 --themes light

Negative controls: --break NAME runs the page with one rule broken and must end in FAIL (see BREAKS).
"""
import base64, json, os, shutil, struct, subprocess, sys, tempfile, time
from urllib.parse import quote

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import web_run  # noqa: E402
import web_fit_studio as FS  # noqa: E402

WIDTHS = (320, 375, 768, 1440)
EP = 'fixture|n5'
SECS = 90
BREAKS = {
    'door': ('js/ear-ui.js', '} catch { return; }', '} catch { /* broken */ }', 'the door stands with no times to be had'),
    'carry': ('js/ear-core.js', 'S.jumped = () => { from = 0; };', 'S.jumped = () => {};', 'a seek carries a part over lines nobody heard'),
    'place': ('js/ear-ui.js', 'Player.seek(s.back.ms / 1000);', '', 'Hear it loses the place'),
    'end': ('js/player.js', "if (held) { emit('ended'); return; }", '', 'the end of the episode starts the queue'),
    'space': ('js/ear-ui.js', "dock.addEventListener('mousedown', (e) => { if (e.target.closest('button')) e.preventDefault(); });", '', 'a press takes the keyboard, and Space presses it again'),
    'rows': ('js/ear-ui.js', 'if (P.drawn.get(r.k) === key) continue;', '', 'every line is drawn again on each step'),
    'foot': ('css/styles.css', 'max-height: 96px; overflow-y: auto;', '', 'twelve parts push the lines off the screen'),
}

WORDS = ['The Planet Man!', 'This is the story of Dantro.', "I'm sorry, Pat.", "There, they're sending us a message.", 'You are on the province of Mars.',
         'Cut your drive when coming aboard.', "Cut your drive immediately or we'll ray you out of space.", "All right, I'm cutting my drive.",
         "Don't fire.", "Pat, don't say a word.", 'Let me handle them.', "They're right alongside.", 'Well, here comes the welcoming party.',
         'Surrender in the name of Marston, ruler of Mars.', 'We surrender.', 'What do you want with this?', "Marston will tell you himself, but I'm afraid you're not going to like it."]


def vtt(n=40, change=''):
    out = ['WEBVTT', '']
    for i in range(n):
        a, b = 1.5 + 2 * i, 3.5 + 2 * i
        t = lambda s: f'{int(s // 60):02d}:{s % 60:06.3f}'
        out += [f'{t(a)} --> {t(b)}', WORDS[i % len(WORDS)] + change, '']
    return '\n'.join(out)


EXTRA = r"""(() => {
  if (window.__extra) return; window.__extra = true;
  window.__asked = []; window.confirm = (t) => { window.__asked.push(t); return true; };
  window.__full = false;
  const put = IDBObjectStore.prototype.put;
  IDBObjectStore.prototype.put = function (...a) { if (window.__full) throw new DOMException('full', 'QuotaExceededError'); return put.apply(this, a); };
  const real = window.fetch.bind(window);
  window.__cors = [];
  window.fetch = (u, o) => {
    const url = String((u && u.url) || u);
    if (!url.startsWith('https://archive.org/cors/')) return real(u, o);
    window.__cors.push(url);
    const mode = sessionStorage.getItem('vtt') || 'ok';
    if (mode === 'throw') return Promise.reject(new TypeError('Failed to fetch'));
    if (mode === 'none') return Promise.resolve(new Response('', { status: 404 }));
    return Promise.resolve(new Response(sessionStorage.getItem('vtt-text') || window.__VTT, { status: 200 }));
  };
})();"""

FIT = r"""JSON.stringify((() => {
  const root = [...document.querySelectorAll('dialog[open] .os-sheet-in')].pop() || document.querySelector('#view-own:not([hidden]) .os') || document.querySelector('.os-own');
  const out = { moved: !document.querySelector('#view-own').hidden && document.querySelector('#main-content').scrollTop > 0, sideways: document.documentElement.scrollWidth > innerWidth, small: [], over: [], off: false };
  if (!root) return out;
  for (const b of root.querySelectorAll('button, a.btn, input:not([type=file]), textarea, select, [role=button]')) {
    const r = b.getBoundingClientRect();
    if (!r.width || !r.height) continue;
    const t = (b.getAttribute('aria-label') || b.textContent || b.id).trim().slice(0, 30);
    if (r.height < (b.classList.contains('ec-line') ? 29.5 : 43.5)) out.small.push(t + ' ' + Math.round(r.height));
    if (r.right > innerWidth + 1 || r.left < -1) out.over.push(t);
  }
  const t = document.querySelector('.ec-transport');
  if (t && t.offsetParent && !document.querySelector('dialog[open]')) { const r = t.getBoundingClientRect(); out.off = r.bottom > innerHeight + 1 || r.top < innerHeight * 0.5; }
  return out; })())"""

SERVER = r"""
import sys, os, http.server, functools
class S(http.server.ThreadingHTTPServer):
    request_queue_size = 256
    daemon_threads = True
class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if not self.path.startswith('/ep.wav'): return super().do_GET()
        p = os.path.join(sys.argv[2], 'ep.wav')
        if os.path.exists(os.path.join(sys.argv[2], 'FAIL')): return self.send_error(404)
        data = open(p, 'rb').read()
        a, b = 0, len(data) - 1
        r = self.headers.get('Range')
        if r:
            x, _, y = r.split('=')[1].partition('-')
            a = int(x or 0); b = int(y) if y else b
        self.send_response(206 if r else 200)
        self.send_header('Content-Type', 'audio/wav'); self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Length', str(b - a + 1))
        if r: self.send_header('Content-Range', f'bytes {a}-{b}/{len(data)}')
        self.end_headers()
        try: self.wfile.write(data[a:b + 1])
        except OSError: pass
S(('127.0.0.1', int(sys.argv[1])), functools.partial(H, directory=sys.argv[2])).serve_forever()
"""


def arg(name, default):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def site(port):
    work = tempfile.mkdtemp(prefix='fit-ear-')
    for f in os.listdir(ROOT):
        if f not in ('index.html', 'js', 'css', 'build', 'android', 'apple', 'docs', 'worker', 'windows', 'data') and not f.startswith('.'):
            os.symlink(os.path.join(ROOT, f), os.path.join(work, f))
    for d in ('js', 'css'):
        shutil.copytree(os.path.join(ROOT, d), os.path.join(work, d))
    shutil.copy(os.path.join(ROOT, 'index.html'), os.path.join(work, 'index.html'))
    os.makedirs(os.path.join(work, 'data', 'plays'))
    os.makedirs(os.path.join(work, 'data', 'episodes'))
    os.symlink(FS.BUNDLE, os.path.join(work, 'data', 'plays', 'castable-scripts.json'))
    fields = {'detail': ['series', 'title', 'date', 'season', 'num', 'network', 'networkSource', 'rights', 'rightsBasis', 'length', 'dateSource', 'aka', 'recordings', 'credits', 'li', 'ltp',
                         'transcript', 'star', 'script', 'arc', 'sponsor', 'scriptUrl', 'scriptSource', 'scriptId'],
              'recording': ['url', 'archiveId', 'format', 'kbps', 'length', 'variant', 'partial'], 'credit': ['name', 'role', 'character', 'person', 'art']}
    row = lambda title: ['fixture', title, None, None, 5, None, None, 'unclaimed', None, SECS, None, None,
                         [[f'http://127.0.0.1:{port}/ep.wav', 'FixtureItem', 'MP3', 64, SECS, None, None]], [], None, None,
                         'https://archive.org/download/FixtureItem/ep.autogenerated.txt'] + [None] * 7
    json.dump({'schemaVersion': 1, 'shard': {'hash': 'fnv1a32-utf8', 'mask': 0, 'digits': 3}, 'fields': fields, 'search': {}, 'counts': {}}, open(os.path.join(work, 'data', 'manifest.json'), 'w'))
    json.dump({EP: row('Marston to Attack Earth'), 'fixture|n6': row('The Council')}, open(os.path.join(work, 'data', 'episodes', '000.json'), 'w'))
    n = SECS * 8000
    with open(os.path.join(work, 'ep.wav'), 'wb') as f:
        f.write(b'RIFF' + struct.pack('<I', 36 + n) + b'WAVEfmt ' + struct.pack('<IHHIIHH', 16, 1, 1, 8000, 8000, 1, 8) + b'data' + struct.pack('<I', n) + b'\x80' * n)
    return work


def main():
    shots = arg('--shots', None)
    if shots:
        os.makedirs(shots, exist_ok=True)
    widths = [int(x) for x in arg('--widths', ','.join(map(str, WIDTHS))).split(',')]
    themes = arg('--themes', 'light,dark').split(',')
    port = 8000 + os.getpid() % 400
    work = site(port)
    broken = arg('--break', None)
    if broken:
        f, a, b, why = BREAKS[broken]
        src = open(os.path.join(work, f)).read()
        assert src.count(a) == 1, (f, a)
        open(os.path.join(work, f), 'w').write(src.replace(a, b))
        print(f'broken on purpose: {why}')
    base = f'http://127.0.0.1:{port}'
    srv = subprocess.Popen([sys.executable, '-c', SERVER, str(port), work], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    problems = []

    def run(w, dark):
        tag = f'{w} {"dark" if dark else "light"}'
        h = 900 if w >= 768 else 760
        wide = w >= 860
        profile = tempfile.mkdtemp(prefix='fit-ear-chrome-')
        proc = cdp = None
        try:
            proc, ws = FS.launch(profile)
            cdp = web_run.CDP(ws)
            cdp.call('Page.enable')
            cdp.call('Network.enable')
            cdp.call('Page.addScriptToEvaluateOnNewDocument', {'source': FS.STUB + f'window.__VTT = {json.dumps(vtt())};' + EXTRA})
            cdp.call('Emulation.setFocusEmulationEnabled', {'enabled': True})
            cdp.call('Emulation.setDeviceMetricsOverride', {'width': w, 'height': h, 'deviceScaleFactor': 1, 'mobile': w < 600})
            cdp.call('Emulation.setEmulatedMedia', {'features': [{'name': 'prefers-color-scheme', 'value': 'dark' if dark else 'light'}]})

            def ev(js, aw=False):
                r = cdp.call('Runtime.evaluate', {'expression': js, 'returnByValue': True, 'awaitPromise': aw, 'userGesture': True}, timeout=40)
                if 'exceptionDetails' in r:
                    raise RuntimeError(f"{r['exceptionDetails'].get('exception', {}).get('description', r['exceptionDetails'].get('text'))[:300]} in {js[:120]}")
                return r.get('result', {}).get('value')
            settle = lambda: ev("document.fonts.ready.then(() => new Promise(r => setTimeout(() => requestAnimationFrame(() => requestAnimationFrame(r)), 300))).then(() => 1)", True)

            def key(k, mods=0):
                vk = {'Tab': 9, 'Enter': 13, 'Escape': 27, ' ': 32, 'ArrowLeft': 37, 'ArrowUp': 38, 'ArrowRight': 39, 'ArrowDown': 40}.get(k, ord(k.upper()) if len(k) == 1 else 0)
                b = {'key': k, 'code': 'Space' if k == ' ' else k, 'windowsVirtualKeyCode': vk, 'modifiers': mods}
                cdp.call('Input.dispatchKeyEvent', {'type': 'keyDown', **b, **({'text': '\r'} if k == 'Enter' else {'text': k} if len(k) == 1 and not mods else {})})
                cdp.call('Input.dispatchKeyEvent', {'type': 'keyUp', **b})
                time.sleep(0.06)

            def click(sel):
                p = json.loads(ev(f"JSON.stringify((() => {{ const e = document.querySelector({json.dumps(sel)}); const r = e.getBoundingClientRect(); return {{ x: r.left + r.width / 2, y: r.top + r.height / 2 }}; }})())"))
                for t in ('mousePressed', 'mouseReleased'):
                    cdp.call('Input.dispatchMouseEvent', {'type': t, 'x': p['x'], 'y': p['y'], 'button': 'left', 'clickCount': 1})
                time.sleep(0.06)

            def shot(name):
                settle()
                if shots:
                    png = cdp.call('Page.captureScreenshot', {'format': 'png'}, timeout=30)
                    open(os.path.join(shots, f'ear-{name}-{w}-{"dark" if dark else "light"}.png'), 'wb').write(base64.b64decode(png['data']))

            def bad(msg):
                problems.append(f'{tag}: {msg}')

            def wait(js, what, secs=15):
                t0 = time.time()
                while not ev(f"!!({js})"):
                    if time.time() - t0 > secs:
                        bad(f'{what} never appeared (page errors: {ev("JSON.stringify(window.__errors || [])")})'); shot('timeout')
                        raise StopIteration
                    time.sleep(0.05)

            def fit(where):
                s = json.loads(ev(FIT))
                if s['sideways']: bad(f'{where}: the page scrolls sideways')
                if s['moved']: bad(f'{where}: the bar has scrolled off the screen')
                if s['small']: bad(f'{where}: under 44 px: {s["small"][:6]}')
                if s['over']: bad(f'{where}: past the edge: {s["over"][:6]}')
                if s['off']: bad(f'{where}: the transport is not at the foot of the screen')

            def go(q):
                cdp.call('Page.navigate', {'url': f'{base}/{q}{"&" if "?" in q else "?"}mute=1'}, timeout=30)
                time.sleep(0.4)
            cast = f'?cast={quote(EP)}'
            page = lambda: wait("document.querySelector('.ec-line')", 'the casting page')
            lit = lambda: ev("(document.querySelector('.ec-lit .ec-line') || { dataset: {} }).dataset.open || ''")
            count = lambda: ev("document.querySelector('.ec .rd-where').textContent")
            who = lambda: json.loads(ev("""JSON.stringify([...document.querySelectorAll('.ec-item')].map(n => { const l = n.querySelector('.rd-name, .sr-only'); return l ? l.textContent : null; }))"""))
            playing = lambda: ev("!Player.audio.paused")
            at = lambda: ev("Player.audio.currentTime")

            def part(name):
                """+ Part, by its own button."""
                ev("document.querySelector('[data-do=add]').click()")
                wait("document.querySelector('dialog[open] .os-form input')", 'the New part sheet')
                if ev("document.activeElement.tagName") != 'INPUT': bad('the New part sheet does not open on its field')
                cdp.call('Input.insertText', {'text': name})
                key('Enter')
                wait("!document.querySelector('dialog[open]')", 'the New part sheet closing')

            def seek(s):
                ev(f"Player.seek({s})")
                time.sleep(0.25)

            # No times: no door, and the page itself says so.
            go('?view=record')
            wait("document.querySelector('#record-body')", 'Record')
            ev("sessionStorage.setItem('vtt', 'none')")
            go(f'?item={quote(EP)}')
            wait("window.__cors.length", 'the read of the times')
            settle()
            if ev("/Record this/.test(document.querySelector('#episode-body').innerText)"): bad('Record this is offered with no times to be had')
            if ev("window.__cors[0]") != 'https://archive.org/cors/FixtureItem/ep.autogenerated.vtt': bad(f'the times are read from {ev("window.__cors[0]")}')
            go(cast)
            wait("/This did not load/.test((document.querySelector('#own-body .state-problem') || {}).textContent || '')", 'the page with no times')
            fit('no times')
            if not ev("!!document.querySelector('.ec [aria-label=Close]')"): bad('the page with no times has no way out')
            if w in (375, 1440): shot('none')
            ev("sessionStorage.setItem('vtt', 'ok'); document.querySelector('#own-body .state-problem button').click()")
            page()

            # The door, and looking.
            go(f'?item={quote(EP)}')
            wait("[...document.querySelectorAll('#episode-body a.btn')].some(a => a.textContent === 'Record this')", 'the door')
            settle()
            if ev("[...document.querySelectorAll('#episode-body a.btn')].find(a => a.textContent === 'Record this').getBoundingClientRect().height") < 43.5: bad('the door is under 44 px')
            if w in (375, 1440): shot('door')
            ev("[...document.querySelectorAll('#episode-body a.btn')].find(a => a.textContent === 'Record this').click()")
            page()
            settle()
            if ev("!!Player.current"): bad('looking puts the episode on the player')
            if count() != '0 of 40 lines cast': bad(f'the count is {count()!r}')
            if 'Automatic transcript' not in ev("document.querySelector('.ec').innerText"): bad('Automatic transcript is not on the page')
            if w < 768 and ev("getComputedStyle(document.querySelector('.tabbar')).display") != 'none': bad('the tab bar stays on a phone')
            fit('start')
            ev("document.querySelector('#own-h').focus()")
            order = []
            for _ in range(5 if not wide else 5):
                key('Tab')
                order.append(ev("(() => { const a = document.activeElement; return a.getAttribute('aria-label') || a.dataset.open && 'line' || (a.textContent || '').trim().slice(0, 30); })()"))
            if order != ['Close', 'Done', 'line', 'Part', 'Back 5 seconds']: bad(f'the focus order is {order}')
            if int(ev("document.querySelectorAll('.ec-line[tabindex=\"0\"]').length")) != 1: bad('the lines are not one tab stop')
            if w in (375, 1440): shot('start')
            ev("document.querySelector('.ec [aria-label=Close]').click()")
            wait("!document.querySelector('#view-episode').hidden", 'the episode after Close')
            if ev("OwnScripts.shared().list().then(r => r.length)", True) != 0: bad('looking kept a script')
            wait("[...document.querySelectorAll('#episode-body a.btn')].some(a => a.textContent === 'Record this')", 'the door, back')
            ev("[...document.querySelectorAll('#episode-body a.btn')].find(a => a.textContent === 'Record this').click()")
            page()

            # A part before the first line; a press plays; the lit line; the keyboard.
            ev("document.querySelector('#own-h').focus()")
            part('announcer')
            if who()[0] is not None: bad('a part named before the first line took one')
            ev("Store.enqueue({ id: 'queued', title: 'Queued', series: 'x', seriesName: 'X', url: 'http://127.0.0.1:1/none.mp3' }); document.activeElement.blur()")
            key(' ')
            wait("!Player.audio.paused && Player.audio.currentTime > 0.1", 'the episode playing after Space')
            if not ev("Player.audio.muted"): bad('the mute door does not hold')
            if ev("Player.audio.playbackRate") != 0.75: bad(f'the speed is {ev("Player.audio.playbackRate")}')
            if ev("getComputedStyle(document.querySelector('#player')).display") != 'none': bad('the mini player stands beside the transport')
            seek(1.6)
            wait("document.querySelector('.ec-lit')", 'the lit line')
            key('1')
            k = int(lit())
            if who()[k - 1] != 'ANNOUNCER': bad('1 gives the lit line to nobody')
            if not playing(): bad('a part pressed stops the episode')
            wait(f"(document.querySelector('.ec-lit .ec-line') || {{ dataset: {{}} }}).dataset.open === '{k + 2}'", 'the second line after', 20)
            if who()[:k + 2] != ['ANNOUNCER'] * (k + 2): bad(f'a part does not carry: {who()[:5]}')
            if who()[k + 2] is not None: bad('a part carries past the line lit')
            # Pointer: a new voice, named while its line is lit, and Space still plays.
            part('Dantro')
            k = int(lit())
            if who()[k - 1] != 'DANTRO': bad(f'the lit line is not the new part\'s: {who()[k - 1]}')
            wait("!Player.audio.paused", 'the episode going on after the sheet')
            click("[data-part=ANNOUNCER]")
            if ev("document.activeElement.dataset.part || ''"): bad('a press takes the keyboard from the page')
            if who()[int(lit()) - 1] != 'ANNOUNCER': bad('a part pressed is not given its line')
            click("[data-part=DANTRO]")
            key(' ')
            if playing(): bad('Space does not pause')
            if who()[int(lit()) - 1] != 'DANTRO': bad('Space pressed a part as well')
            shot('cast')
            fit('cast')
            # Left, U, Control-Z.
            t = at()
            key('ArrowLeft')
            time.sleep(0.2)
            if not 4.5 < t - at() <= 5.01 and at() > 0.01: bad(f'Left goes back {t - at():.1f} s')
            seek(t)
            n = count()
            key('u')
            if count() == n and who()[int(lit()) - 1] == 'DANTRO': bad('U does not undo')
            key('z', 2)
            before = who()
            # A seek carries nothing over what was not heard.
            seek(20.2)
            key(' ')
            wait("Player.audio.currentTime > 20.5", 'the episode after a seek')
            key(' ')
            if who()[8] is not None or who()[9] is not None: bad(f'a seek carried a part: {who()[6:11]}')
            key('2')
            k = int(lit())
            if who()[k - 1] != 'DANTRO': bad('2 gives the lit line to nobody')
            # Leave out, and back.
            seek(24.2)
            click("[data-do=out]")
            k = int(lit())
            if who()[k - 1] != 'Left out': bad('Leave out left the line')
            if ev("document.querySelector('[data-do=out]').getAttribute('aria-pressed')") != 'true': bad('Leave out is not shown pressed on a left-out line')
            shot('out')
            # A scroll of the person's own.
            seek(60.2)
            settle()
            if not ev("(() => { const s = document.querySelector('.ec .os-scroll').getBoundingClientRect(), r = document.querySelector('.ec-lit').getBoundingClientRect(); return r.top >= s.top && r.bottom <= s.bottom; })()"): bad('the lit line is not followed')
            b = json.loads(ev("JSON.stringify((() => { const r = document.querySelector('.ec .os-scroll').getBoundingClientRect(); return { x: r.left + 60, y: r.top + 100 }; })())"))
            cdp.call('Input.dispatchMouseEvent', {'type': 'mouseWheel', 'x': b['x'], 'y': b['y'], 'deltaX': 0, 'deltaY': -700})
            time.sleep(0.4)
            if ev("document.querySelector('.ec-back-line').hidden"): bad('a scroll of the person\'s own offers no way back')
            top = ev("document.querySelector('.ec .os-scroll').scrollTop")
            seek(62.2)
            settle()
            if abs(ev("document.querySelector('.ec .os-scroll').scrollTop") - top) > 2: bad('the page turns after a scroll of the person\'s own')
            fit('away')
            if w in (375, 1440): shot('away')
            ev("document.querySelector('.ec-back-line').click()")
            settle()
            if not ev("(() => { const s = document.querySelector('.ec .os-scroll').getBoundingClientRect(), r = document.querySelector('.ec-lit').getBoundingClientRect(); return r.top >= s.top && r.bottom <= s.bottom; })()"): bad('Back to the line does not go back')
            # The line sheet, by keyboard.
            place = at()
            ev("document.querySelector('[data-open=\"7\"]').focus()")
            key('Enter')
            wait("document.querySelector('dialog.os-line-sheet[open]')", 'the line sheet')
            settle()
            if ev("document.activeElement.getAttribute('role')") != 'slider': bad('the line sheet does not open on the cut')
            for _ in range(4): key('ArrowRight')
            if ev("document.activeElement.getAttribute('aria-valuenow')") != '4': bad('Right does not move the cut a word')
            fit('line sheet')
            shot('line')
            ev("[...document.querySelectorAll('dialog[open] .btn')].find(b => b.textContent === 'Hear it').click()")
            wait("!Player.audio.paused && Player.audio.currentTime > 13 && Player.audio.currentTime < 17", 'the line heard')
            wait(f"Player.audio.paused && Math.abs(Player.audio.currentTime - {place}) < 0.3", 'the place after Hear it', 8)
            ev("[...document.querySelectorAll('dialog[open] .btn')].find(b => b.textContent === 'Split here').click()")
            settle()
            if int(ev("document.querySelectorAll('.ec-item').length")) != 41: bad('Split here made no line')
            if ev("document.activeElement.dataset.open") in (None, '7'): bad('focus is not on the line the split made')
            key('Enter')
            wait("document.querySelector('dialog.os-line-sheet[open]')", 'the line sheet of the new line')
            ev("[...document.querySelectorAll('dialog[open] .btn')].find(b => b.textContent === 'Join to line above').click()")
            settle()
            if int(ev("document.querySelectorAll('.ec-item').length")) != 40 or ev("document.activeElement.dataset.open") != '7': bad('Join to line above')
            key('Enter')
            wait("document.querySelector('dialog.os-line-sheet[open]')", 'the line sheet to give it')
            ev("[...document.querySelectorAll('dialog[open] .os-chip')].find(b => b.textContent === 'DANTRO').click()")
            settle()
            if who()[6] != 'DANTRO' or who()[7] is not None: bad(f'a line given in its sheet is not that line\'s alone: {who()[5:9]}')
            key('Enter')
            wait("document.querySelector('dialog.os-line-sheet[open]')", 'the line sheet for words')
            ev("[...document.querySelectorAll('dialog[open] .btn')].find(b => b.textContent === 'Edit words').click()")
            wait("document.querySelector('.os-edit')", 'the words')
            fit('edit words')
            ev("document.querySelector('.os-edit').value = 'Cut your drive, Dantro.'; [...document.querySelectorAll('dialog[open] .btn')].find(b => b.textContent === 'Save').click()")
            settle()
            if 'Cut your drive, Dantro.' not in ev("document.querySelector('[data-open=\"7\"]').textContent"): bad('Edit words changed nothing')
            key('Enter')
            wait("document.querySelector('dialog.os-line-sheet[open]')", 'the line sheet to play from')
            ev("[...document.querySelectorAll('dialog[open] .btn')].find(b => b.textContent === 'Play from here').click()")
            wait("!Player.audio.paused && Player.audio.currentTime > 13.4 && Player.audio.currentTime < 16", 'the episode playing from the line')
            ev("document.activeElement.blur()")
            key(' ')
            # A part's lines, on a wide screen.
            if wide:
                place = at()
                ev("document.querySelector('[data-hear=ANNOUNCER]').click()")
                wait("!Player.audio.paused && Player.audio.currentTime < 12", 'a part heard')
                if w == 1440: shot('hear')
                wait(f"Player.audio.paused && Math.abs(Player.audio.currentTime - {place}) < 0.3", 'the place after a part is heard', 10)
                if ev("document.querySelector('[data-hear=ANNOUNCER]').getBoundingClientRect().width") < 43.5: bad('Hear is under 44 px')
            # Only what changed is drawn.
            seek(70.2)
            again = ev("(() => { const was = [...document.querySelectorAll('.ec-line')]; document.querySelector('[data-part=DANTRO]').click(); return was.filter(n => !n.isConnected).length; })()")
            if again > 3: bad(f'a tap redrew {again} of 40 lines')
            # A recording that fails.
            time.sleep(0.5)
            n = count()
            open(os.path.join(work, 'FAIL'), 'w').close()
            go(cast)
            page()
            settle()
            if count() != n: bad(f'a reload counts {count()!r}, not {n!r}')
            if ev("Math.round(OwnScripts ? 1 : 0)") and not 69 < (ev("(() => { const t = document.querySelector('.ec-time').textContent.split(':'); return t[0] * 60 + +t[1]; })()") or 0) < 72: bad('the place is not kept')
            if ev("!!Player.current"): bad('a reload plays or loads by itself')
            if ev("[...document.querySelectorAll('.ec-who')].map(b => b.dataset.part).join()") != 'ANNOUNCER,DANTRO': bad('the parts are not kept in their order')
            key(' ')
            wait("/This recording did not load/.test(document.querySelector('.os-problem').textContent)", 'the recording that fails', 20)
            fit('failed')
            if w in (375, 1440): shot('failed')
            os.remove(os.path.join(work, 'FAIL'))
            ev("document.querySelector('.os-problem button').click()")
            wait("!Player.audio.paused && Player.audio.currentTime > 69 && document.querySelector('.os-problem').hidden", 'the episode after Try again', 20)
            # The end of the episode starts nothing.
            seek(SECS - 0.6)
            wait("Player.audio.ended", 'the end', 10)
            time.sleep(0.6)
            if ev("Player.current.id") != EP: bad('the end of the episode starts the queue')
            # A full disk: said, and the work stays.
            seek(72.2)
            ev("window.__full = true")
            ev("document.querySelector('[data-part=ANNOUNCER]').click()")
            wait("/out of space/.test(document.querySelector('.os-problem').textContent)", 'the full disk')
            if w == 375: shot('full')
            ev("window.__full = false; document.querySelector('.os-problem button').click()")
            wait("document.querySelector('.os-problem').hidden", 'the write after Try again')
            # A transcript remade since; offline.
            ev(f"sessionStorage.setItem('vtt-text', {json.dumps(vtt(40, ' Yes.'))})")
            n = count()
            go(cast)
            page()
            wait("/The transcript has changed\\. Your lines are kept\\./.test(document.querySelector('.ec-note').innerText) && document.querySelector('.ec-note').getBoundingClientRect().top > 0", 'the transcript remade')
            if count() != n: bad('a remade transcript changes the lines')
            fit('remade')
            if w in (375, 1440): shot('changed')
            ev("sessionStorage.removeItem('vtt-text')")
            go('?item=fixture%7Cn6')
            wait("[...document.querySelectorAll('#episode-body a.btn')].some(a => a.textContent === 'Record this')", 'another episode')
            cdp.call('Network.emulateNetworkConditions', {'offline': True, 'latency': 0, 'downloadThroughput': 0, 'uploadThroughput': 0})
            ev("sessionStorage.setItem('vtt', 'throw'); API.transcriptCues('https://archive.org/download/FixtureItem/other.autogenerated.txt').catch(() => {}); window.__was = API.transcriptCues; API.transcriptCues = (u) => window.__was(u.replace('/ep.', '/ep2.')); [...document.querySelectorAll('#episode-body a.btn')].find(a => a.textContent === 'Record this').click()")
            wait("/You are offline/.test((document.querySelector('#own-body .state-problem') || {}).textContent || '')", 'the page, offline')
            fit('offline')
            if not ev("!!document.querySelector('.ec [aria-label=Close]')"): bad('the page, offline, has no way out')
            if w == 375: shot('offline')
            cdp.call('Network.emulateNetworkConditions', {'offline': False, 'latency': 0, 'downloadThroughput': -1, 'uploadThroughput': -1})
            ev("sessionStorage.setItem('vtt', 'ok')")
            go('?cast=no-such')
            wait("/Not in the catalog/.test((document.querySelector('#own-body') || {}).textContent || '')", 'an episode the catalog does not serve')
            # Your scripts says how far it is, and opens the casting.
            go('?view=record')
            wait("document.querySelector('[aria-labelledby=own-list-h] a')", 'Your scripts')
            row = ev("document.querySelector('[aria-labelledby=own-list-h]').innerText")
            if 'Marston to Attack Earth' not in row or f'{count_of(n)} of 40 lines cast' not in row: bad(f'the row says {row!r}')
            if w in (375, 1440): shot('record')
            ev("document.querySelector('[aria-labelledby=own-list-h] a').click()")
            page()
            # Twelve parts in the dock.
            for i in range(10): part(f'Voice number {i}')
            settle()
            fit('twelve parts')
            room = ev("document.querySelector('.ec .os-scroll').getBoundingClientRect().height / innerHeight")
            if room < 0.4: bad(f'twelve parts leave the lines {room:.0%} of the screen')
            hid = ev("(() => { const at = (e) => { const r = e.getBoundingClientRect(); return document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2); }; return [...document.querySelectorAll('[data-do], .ec-who[aria-pressed=true]')].filter(b => !b.contains(at(b))).map(b => b.textContent).join(); })()")
            if hid: bad(f'out of reach with twelve parts: {hid}')
            shot('twelve')
            key('u')
            # Done on part of it.
            n = count()
            ev("[...document.querySelectorAll('.ec .btn')].find(b => b.textContent === 'Done').click()")
            wait("document.querySelector('.os-own')", "the script's page")
            settle()
            text = ev("document.querySelector('#view-plays').innerText")
            wait("/lines cast/.test(document.querySelector('.os-own').innerText)", 'how much is cast, on its page')
            text = ev("document.querySelector('#view-plays').innerText")
            for words in (n, 'Cast by ear', 'Automatic transcript', 'Your script', 'Record this', 'Read', 'This script can’t be published.', 'Kept on this device', 'Edit', 'Save as text', 'Delete'):
                if words.lower() not in text.lower(): bad(f"the script's page does not say {words!r}")
            for words in ('Share', 'Read together', 'Publish '):
                if words.lower() in text.lower(): bad(f"{words} is offered on the script's page")
            fit("the script's page")
            ev("document.querySelector('.os-own').scrollIntoView({ block: 'end' })")
            shot('script')
            sid = ev("new URLSearchParams(location.search).get('play')")
            # Read, then a take with the stub microphone.
            go(f'?read={sid}')
            wait("document.querySelector('.rd-line')", 'the reader')
            if w in (375, 1440): shot('read')
            go(f'?play={sid}')
            wait("[...document.querySelectorAll('button')].some(b => /Record this/.test(b.textContent))", 'Record this')
            ev("[...document.querySelectorAll('button')].find(b => /Record this/.test(b.textContent)).click()")
            wait("document.querySelector('button[aria-label^=\"Take part\"]')", 'the cast sheet')
            ev("document.querySelector('button.btn-primary[aria-label^=\"Take part\"], button[aria-label^=\"Take part\"]').click()")
            wait("document.querySelector('.st-dock') && document.querySelector('.rd-line')", 'the studio')
            ev("document.getElementById('st-headphones').click(); document.querySelector('.st-go').click()")
            wait("document.querySelector('.st-mode')", 'the dock after room tone', 20)
            ev("[...document.querySelectorAll('.st-mode input')].find(i => i.value === 'lines').click()")
            settle()
            ev("document.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true, cancelable: true }))")
            wait("document.querySelector('.st-rec')", 'the microphone', 15)
            ev("window.__micGain.gain.value = 0.3")
            time.sleep(0.8)
            ev("window.__micGain.gain.value = 0.0005; document.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true, cancelable: true }))")
            wait("document.querySelectorAll('.rd-take[data-state=chosen]').length >= 1", 'the take kept', 15)
            taken = ev("document.querySelector('.rd-take[data-state=chosen]').dataset.line")
            if w in (375, 1440): shot('take')
            # Taken up again: the line with a take keeps its part.
            go(f'?play={sid}')
            wait("[...document.querySelectorAll('.os-own a.btn')].some(b => b.textContent === 'Cast by ear' && !b.hidden)", 'Cast by ear')
            ev("[...document.querySelectorAll('.os-own a.btn')].find(b => b.textContent === 'Cast by ear').click()")
            page()
            lk = ev(f"OwnScripts.shared().get('{sid}').then(r => String(r.doc.lines.find(l => l.id === '{taken}').k))", True)
            ev(f"document.querySelector('[data-open=\"{lk}\"]').focus()")
            key('Enter')
            wait("document.querySelector('dialog.os-line-sheet[open]')", 'the line with a take')
            acts = json.loads(ev("JSON.stringify([...document.querySelectorAll('dialog[open] .btn, dialog[open] .os-chip')].map(b => b.textContent))"))
            if 'This line has a take.' not in ev("document.querySelector('dialog[open]').innerText") or acts != ['Hear it', 'Edit words', 'Play from here']: bad(f'a line with a take offers {acts}')
            key('Escape')
            ev(f"document.querySelector('[data-open=\"{lk}\"]').click()")
            wait("document.querySelector('dialog.os-line-sheet[open]')", 'the line with a take, to play from')
            ev("[...document.querySelectorAll('dialog[open] .btn')].find(b => b.textContent === 'Play from here').click()")
            wait("!Player.audio.paused", 'the episode from the line with a take')
            ev("document.querySelector('.ec-play').click()")
            was = who()
            other = ev(f"[...document.querySelectorAll('.ec-who')].map(b => b.dataset.part).find(p => p !== {json.dumps(was[int(lk) - 1])})")
            ev(f"document.querySelector('[data-part=\"{other}\"]').click()")
            if count() != 'This line has a take.': bad(f'a recorded line given to another part says {count()!r}')
            if who() != was: bad('a recorded line moved to another part')
            if w in (375, 1440): shot('locked')
            # The parts page: Leave out everything below, one step, one Undo.
            go(f'?script={sid}&edit=parts')
            wait("document.querySelector('.os-list .os-line')", 'the parts page')
            if 'Automatic transcript' not in ev("document.querySelector('.os-page').innerText"): bad('the parts page does not say Automatic transcript')
            lines = int(ev("document.querySelectorAll('.os-list [role=listitem]').length"))
            kk = ev("document.querySelectorAll('.os-list [data-open]')[19].dataset.open")
            ev(f"document.querySelector('[data-open=\"{kk}\"]').focus()")
            key('Enter')
            wait("document.querySelector('dialog.os-line-sheet[open]')", 'the line sheet, parts page')
            ev("[...document.querySelectorAll('dialog[open] .btn')].find(b => b.textContent === 'More').click()")
            settle()
            fit('More')
            if w in (375, 1440): shot('more')
            ev("[...document.querySelectorAll('dialog[open] .btn')].find(b => b.textContent === 'Leave out everything above').click()")
            settle()
            if 'A line there has a take.' not in (ev("(document.querySelector('dialog[open]') || {}).innerText") or ''): bad('everything above, with a take in it, is left out')
            ev("[...document.querySelectorAll('dialog[open] .btn')].find(b => b.textContent === 'Leave out everything below').click()")
            settle()
            if int(ev("document.querySelectorAll('.os-list [role=listitem]').length")) != 20: bad('Leave out everything below left the lines')
            if ev("document.activeElement.dataset.open") != kk: bad('focus is lost after Leave out everything below')
            shot('below')
            ev("document.querySelector('[aria-label=Undo]').click()")
            settle()
            if int(ev("document.querySelectorAll('.os-list [role=listitem]').length")) != lines: bad('one Undo does not bring the lines back')
            if ev("!!document.querySelector('dialog.account-sheet[open]')"): bad('an account is asked for')
            errs = [e for e in json.loads(ev("JSON.stringify(window.__errors)")) if not e.startswith('sync ') and 'full' not in e]
            if errs: bad(f'page errors: {errs[:3]}')
        except StopIteration:
            pass
        except Exception as e:  # a blind instrument says so
            problems.append(f'{tag}: harness error {e!r}')
        finally:
            if os.path.exists(os.path.join(work, 'FAIL')):
                os.remove(os.path.join(work, 'FAIL'))
            if proc:
                web_run._kill(proc)
            shutil.rmtree(profile, ignore_errors=True)

    count_of = lambda line: line.split(' ')[0]
    try:
        for theme in themes:
            for w in widths:
                n = len(problems)
                run(w, theme == 'dark')
                print(('FAIL ' if len(problems) > n else 'ok   ') + f'{w} {theme} {problems[n:] or ""}', flush=True)
    finally:
        srv.terminate()
        shutil.rmtree(work, ignore_errors=True)
    print(f'{"FAIL" if problems else "PASS"}: {len(problems)} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
