#!/usr/bin/env python3
"""Fit gate, frames and the whole flow of adding a script (WEB-DESIGN 4.21, PLAYS-DESIGN 13), light and dark, at
320, 375, 768 and 1440 px, in headless Chrome over the DevTools protocol.

Nothing is heard and nothing is recorded from a real microphone: the speech and microphone stubs are
tools/web_fit_studio.py's. Signed out throughout; any account sheet is a failure.

For each width and theme, with a real play's text (--text FILE; else the cached Gutenberg text, else the bundle's longest play):
an older version of the database holding one production is there first (the migration, in a real browser); Record has Add a
script and no Your scripts; the text is pasted with the Paste button from the real clipboard; a file with no text is refused;
it survives a reload; Next with no title puts the focus on Title; then the parts page: the strip and Next, a one-tap answer,
Undo, the line sheet, the cut placed by keyboard and by a tap, split, join, Edit words, Leave out, rename, Join to;
a full disk (the banner, then Try again); Done; the script's page (Read together on it, nothing shared by looking); Read; Record this, two takes with the
stub microphone; a reload; the locked line (its refusal, and only Edit words); Words changed in the take list; Save as text; Export my
data; Search; Delete with its productions named.

Fails on: the opening on the script's page, or on a bundled play's, cutting a speech or a name; a sideways scroll; a control of these pages under 44 px; the wrong focus order on either page; focus lost after a
step; a step that redraws more than a tenth of the lines
(its time is printed, never graded: this Mac's load decides it); a page error; and any of the above not happening.

    python3 tools/web_fit_own.py                    # exit 1 on any problem
    python3 tools/web_fit_own.py --shots DIR        # a PNG per frame
    python3 tools/web_fit_own.py --widths 375,1440 --themes light

Negative controls (2026-11-24, each run): `.os-chip` at min-height 36px fails "under 44 px"; js/plays-ui.js without READERS on
shareBox fails "who can read it"; js/own-ui.js drawing every line on each step (`fill(n.el, l)` with no test before it) fails "a step redrew".
"""
import base64, json, os, shutil, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import web_run  # noqa: E402
import web_fit_studio as FS  # noqa: E402

WIDTHS = (320, 375, 768, 1440)
BUNDLE = FS.BUNDLE
PLAYS = [s['id'] for s in json.load(open(BUNDLE))['scripts']][:6]
CACHED = os.path.join(ROOT, 'catalog', '.cache', 'gutenberg', 'text', '2765.txt')

EXTRA = r"""(() => {
  window.__asked = []; window.confirm = (t) => { window.__asked.push(t); return true; };
  window.__saved = [];
  const make = URL.createObjectURL.bind(URL);
  URL.createObjectURL = (b) => { if (b && b.type && b.type.startsWith('text/plain')) b.text().then(t => window.__saved.push(t));
    if (b && b.type === 'application/json') b.text().then(t => window.__json = t); return make(b); };
  HTMLAnchorElement.prototype.click = function () { if (this.download) { window.__file = this.download; return; } return HTMLElement.prototype.click.call(this); };
  window.__full = false;
  const put = IDBObjectStore.prototype.put;
  IDBObjectStore.prototype.put = function (...a) { if (window.__full) throw new DOMException('full', 'QuotaExceededError'); return put.apply(this, a); };
})();"""

V1 = r"""new Promise((res, rej) => { const r = indexedDB.open('ed-plays', 1);
  r.onupgradeneeded = () => r.result.createObjectStore('files');
  r.onerror = () => rej(r.error);
  r.onsuccess = () => { const t = r.result.transaction('files', 'readwrite'); const s = t.objectStore('files');
    s.put(JSON.stringify({ id: 'OLD', revision: 'x', title: 'Kept from before', kind: 'stage', roles: [{ name: 'A', lines: 1 }], lines: [{ id: 'L0001', kind: 'speech', role: 'A', parts: [{ say: 'Hello.' }] }], rights: { evidence: [] }, source: {} }), 'OLD/script.json');
    s.put(JSON.stringify({ id: 'OLD', scriptID: 'gut-1', scriptRevision: 'x', title: 'Kept from before', created: 1, parts: { 'role:A': { status: 'open' } }, takes: [{ id: 't', lineID: 'L0001', part: 'role:A', file: 'x.wav', created: 1, frames: 1, sampleRate: 48000 }], chosen: { L0001: 't' }, roomTone: [], listenedThrough: false }), 'OLD/production.json');
    t.oncomplete = () => { r.result.close(); res(1); }; }; })"""

FIT = r"""JSON.stringify((() => {
  const root = [...document.querySelectorAll('dialog[open] .os-sheet-in')].pop() || document.querySelector('#view-own:not([hidden]) .os') || document.querySelector('.os-own');
  const out = { moved: !document.querySelector('#view-own').hidden && document.querySelector('#main-content').scrollTop > 0, sideways: document.documentElement.scrollWidth > innerWidth, small: [], over: [] };
  if (!root) return out;
  for (const b of root.querySelectorAll('button, a.btn, input:not([type=file]), textarea, [role=button]')) {
    const r = b.getBoundingClientRect();
    if (!r.width || !r.height) continue;
    const t = (b.getAttribute('aria-label') || b.textContent || b.id).trim().slice(0, 30);
    if (r.height < 43.5) out.small.push(t + ' ' + Math.round(r.height));
    if (r.right > innerWidth + 1 || r.left < -1) out.over.push(t);
  }
  return out; })())"""


# The opening on a play's page: whole speeches only (WEB-DESIGN 6.4g), above the voice bands at its foot.
OPENING = r"""(() => { const w = document.querySelector('.pl-open-hero'); if (!w) return 'no opening';
  const r = w.getBoundingClientRect(), foot = w.querySelector('.lb-overlay rect'), end = foot ? foot.getBoundingClientRect().top : r.bottom;
  const on = [...w.querySelectorAll('.pl-open-sp')].map(s => [s.querySelector('b').textContent, s.getBoundingClientRect()]).filter(([, q]) => q.left < r.right - 1);
  if (!on.length) return 'every speech';
  return on.filter(([, q]) => q.bottom > end + 1 || q.right > r.right).map(([n]) => n).join(); })()"""


def the_text():
    if '--text' in sys.argv:
        return open(sys.argv[sys.argv.index('--text') + 1], encoding='utf-8').read()
    if os.path.exists(CACHED):
        return open(CACHED, encoding='utf-8').read()
    s = max(json.load(open(BUNDLE))['scripts'], key=lambda x: len(x['lines']))
    word = lambda p: p.get('say') or f"({next(iter(p.values()))})"
    return '\n\n'.join(f"{l['role']}\n{' '.join(word(p) for p in l['parts'])}" if l['kind'] == 'speech' else l['source'] for l in s['lines'])


def arg(name, default):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def main():
    shots = arg('--shots', None)
    if shots:
        os.makedirs(shots, exist_ok=True)
    widths = [int(x) for x in arg('--widths', ','.join(map(str, WIDTHS))).split(',')]
    themes = arg('--themes', 'light,dark').split(',')
    text = the_text()
    work = tempfile.mkdtemp(prefix='fit-own-')
    for f in os.listdir(ROOT):
        if f not in ('index.html', 'build', 'android', 'apple', 'docs', 'worker', 'windows', 'data') and not f.startswith('.'):
            os.symlink(os.path.join(ROOT, f), os.path.join(work, f))
    os.makedirs(os.path.join(work, 'data', 'plays'))
    os.symlink(BUNDLE, os.path.join(work, 'data', 'plays', 'castable-scripts.json'))
    shutil.copy(os.path.join(ROOT, 'index.html'), os.path.join(work, 'index.html'))
    open(os.path.join(work, 'blank.html'), 'w').write('<!doctype html><title>blank</title>')
    srv_code = ("import sys,http.server,functools\n"
                "class S(http.server.ThreadingHTTPServer):\n request_queue_size=256\n daemon_threads=True\n"
                "class H(http.server.SimpleHTTPRequestHandler):\n def log_message(self,*a): pass\n"
                "S(('127.0.0.1',int(sys.argv[1])),functools.partial(H,directory=sys.argv[2])).serve_forever()\n")
    port = 8000 + os.getpid() % 400
    base = f'http://127.0.0.1:{port}'
    srv = subprocess.Popen([sys.executable, '-c', srv_code, str(port), work], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    problems = []
    worst = [0]

    def run(w, dark):
        tag = f'{w} {"dark" if dark else "light"}'
        h = 900 if w >= 768 else 760
        profile = tempfile.mkdtemp(prefix='fit-own-chrome-')
        proc = None
        try:
            proc, ws = FS.launch(profile)
            cdp = web_run.CDP(ws)
            cdp.call('Page.enable')
            cdp.call('Browser.grantPermissions', {'origin': base, 'permissions': ['clipboardReadWrite', 'clipboardSanitizedWrite']})
            cdp.call('Page.addScriptToEvaluateOnNewDocument', {'source': FS.STUB + EXTRA})
            cdp.call('Emulation.setFocusEmulationEnabled', {'enabled': True})
            cdp.call('Emulation.setDeviceMetricsOverride', {'width': w, 'height': h, 'deviceScaleFactor': 1, 'mobile': w < 600})
            cdp.call('Emulation.setEmulatedMedia', {'features': [{'name': 'prefers-color-scheme', 'value': 'dark' if dark else 'light'}]})

            def ev(js, aw=False):
                r = cdp.call('Runtime.evaluate', {'expression': js, 'returnByValue': True, 'awaitPromise': aw, 'userGesture': True}, timeout=40)
                if 'exceptionDetails' in r:
                    raise RuntimeError(f"{r['exceptionDetails'].get('exception', {}).get('description', r['exceptionDetails'].get('text'))[:300]} in {js[:120]}")
                return r.get('result', {}).get('value')
            settle = lambda: ev("document.fonts.ready.then(() => new Promise(r => setTimeout(() => requestAnimationFrame(() => requestAnimationFrame(r)), 300))).then(() => 1)", True)

            def key(k, code=None, mods=0, text_=None):
                vk = {'Tab': 9, 'Enter': 13, 'Escape': 27, 'ArrowLeft': 37, 'ArrowUp': 38, 'ArrowRight': 39, 'ArrowDown': 40, 'End': 35, 'Home': 36}.get(k, ord(k.upper()) if len(k) == 1 else 0)
                base_ = {'key': k, 'code': code or k, 'windowsVirtualKeyCode': vk, 'modifiers': mods}
                cdp.call('Input.dispatchKeyEvent', {'type': 'keyDown', **base_, **({'text': '\r'} if k == 'Enter' else {})})
                cdp.call('Input.dispatchKeyEvent', {'type': 'keyUp', **base_})
                time.sleep(0.05)

            def shot(name):
                settle()
                if shots:
                    png = cdp.call('Page.captureScreenshot', {'format': 'png'}, timeout=30)
                    open(os.path.join(shots, f'own-{name}-{w}-{"dark" if dark else "light"}.png'), 'wb').write(base64.b64decode(png['data']))

            def bad(msg):
                problems.append(f'{tag}: {msg}')

            def wait(js, what, secs=15):
                t0 = time.time()
                while not ev(f"!!({js})"):
                    if time.time() - t0 > secs:
                        bad(f'{what} never appeared (page errors: {ev("JSON.stringify(window.__errors || [])")})'); shot('timeout')
                        raise StopIteration
                    time.sleep(0.1)

            def fit(where):
                s = json.loads(ev(FIT))
                if s['sideways']: bad(f'{where}: the page scrolls sideways')
                if s['moved']: bad(f'{where}: the bar has scrolled off the screen')
                if s['small']: bad(f'{where}: under 44 px: {s["small"][:6]}')
                if s['over']: bad(f'{where}: past the edge: {s["over"][:6]}')

            def go(q):
                cdp.call('Page.navigate', {'url': f'{base}/{q}{"&" if "?" in q else "?"}mute=1'}, timeout=30)
                time.sleep(0.4)

            def tabs(n):
                out = []
                for _ in range(n):
                    key('Tab')
                    out.append(ev("(() => { const a = document.activeElement; return a.getAttribute('aria-label') || a.id || (a.textContent || '').trim().slice(0, 40); })()"))
                return out

            def no_sheet(where):
                if ev("!!document.querySelector('dialog.account-sheet[open]')"): bad(f'{where}: an account is asked for')

            # An older page's database, with a production in it.
            cdp.call('Page.navigate', {'url': f'{base}/blank.html'}, timeout=30)
            time.sleep(0.4)
            ev(V1, True)
            go('?view=record')
            wait("document.querySelector('#record-body .play-row')", 'the production kept from version 1')
            if 'Kept from before' not in ev("document.querySelector('#record-body').innerText"): bad('the migration lost a production')
            ev("PlaysUI.openStore().then(s => s.delete('OLD')).then(() => 1)", True)  # a first production asks for no account (Decision 079)
            if ev("indexedDB.databases().then(d => d.find(x => x.name === 'ed-plays').version)", True) != 2: bad('the database is not version 2')
            if ev("/Your scripts/.test(document.querySelector('#record-body').innerText)"): bad('Your scripts stands with none')
            if ev("document.querySelector('#record-add').getBoundingClientRect().height") < 43.5: bad('Add a script is under 44 px')
            if w in (375, 1440): shot('record-none')

            # The text.
            ev("document.querySelector('#record-add').click()")
            wait("document.querySelector('#os-text')", 'the Add a script page')
            settle()
            if not ev("document.querySelector('.os-next').disabled"): bad('Next is offered with no text')
            if w < 768 and ev("getComputedStyle(document.querySelector('.tabbar')).display") != 'none': bad('the tab bar stays on a phone')
            ev("document.querySelector('#own-h').focus()")
            order = tabs(5)
            want = ['Close', 'os-title', 'os-paste', 'os-open', 'os-text']
            if order != want: bad(f'the Add page focus order is {order}')
            fit('add, empty')
            if w in (375, 1440): shot('add-empty')
            ev("(async () => { const dt = new DataTransfer(); dt.items.add(new File([new Uint8Array([37,80,68,70,45,0])], 'x.pdf')); document.querySelector('.os').dispatchEvent(new DragEvent('drop', { dataTransfer: dt, bubbles: true, cancelable: true })); })()")
            wait("document.querySelector('#os-err').textContent === 'That is not a text file.'", 'the refusal of a file that is not text')
            ev(f"navigator.clipboard.writeText({json.dumps(text)})", True)
            ev("document.querySelector('#os-paste').click()")
            wait("/ parts · /.test(document.querySelector('.os-count').textContent)", 'the count')
            wait("/Kept on this device/.test(document.querySelector('.os-count').textContent)", 'Kept on this device')
            counted = ev("document.querySelector('.os-count .tabular').textContent")
            if ev("document.querySelector('#os-err').textContent"): bad('a refusal stays after the text is there')
            fit('add, filled')
            # It survives a reload; the clipboard paste and a dropped file reach the same place.
            go('?view=record&add=1')
            wait("document.querySelector('.os-count .tabular') && document.querySelector('.os-count .tabular').textContent", 'the kept text')
            if ev("document.querySelector('.os-count .tabular').textContent") != counted: bad('the kept text is not the same')
            ev("document.querySelector('.os-next').click()")
            if ev("document.activeElement.id") != 'os-title': bad('Next with no title does not go to Title')
            if ev("document.querySelector('#os-err').textContent") != 'Add a title.': bad('Next with no title says nothing')
            cdp.call('Input.insertText', {'text': 'The Lady from the Sea'})
            settle()
            if w in (375, 1440): shot('add')
            ev("document.querySelector('.os-next').click()")
            wait("document.querySelector('.os-list .os-line')", 'the parts page')
            settle()
            if ev("document.querySelector('.os-title-btn .rd-where').textContent") != counted: bad('the parts page counts differently')
            total = int(ev("document.querySelectorAll('.os-list [role=listitem]').length"))
            opens = int(ev("document.querySelectorAll('.os-open').length"))
            fit('parts')
            shot('parts')
            # The focus order: the bar, the strip, the chips, then one stop for every line.
            ev("document.querySelector('#own-h').focus()")
            order = tabs(5)
            if order[0] != 'Back' or not order[1].startswith('Title: ') or order[2:4] != ['Done', 'Next']: bad(f'the parts page focus order is {order}')
            if int(ev("document.querySelectorAll('.os-line[tabindex=\"0\"]').length")) != 1: bad('the lines are not one tab stop')

            def step(js, what):
                """A change, timed from the press to the next painted frame's layout."""
                ms, again = json.loads(ev(f"(async () => {{ const was = [...document.querySelectorAll('.os-line')]; const t = performance.now(); {js}; document.body.offsetHeight; const ms = performance.now() - t; return JSON.stringify([ms, was.filter(n => !n.isConnected).length]); }})()", True))
                worst[0] = max(worst[0], ms)
                if again > max(40, total // 10): bad(f'a step redrew {again} of {total} lines: {what}')
                return ms

            if opens:
                # Next, and a one-tap answer.
                ev("document.querySelector('.os-strip-next').click()")
                settle()
                k = ev("document.activeElement.dataset.open")
                if not ev("!!document.activeElement.closest('.os-open')"): bad('Next does not go to a line with no part')
                if not ev("(() => { const r = document.activeElement.getBoundingClientRect(); return r.top > 0 && r.bottom < innerHeight + 200; })()"): bad('Next leaves its line off the screen')
                fit('no part')
                shot('nopart')
                many = ev("document.querySelectorAll('.os-open').length")
                step(f"document.querySelector('.os-item[data-k=\"{k}\"] button[data-role]').click()", 'a one-tap answer')
                if ev("document.querySelectorAll('.os-open').length") != many - 1: bad('a one-tap answer gives no part')
                if ev("document.activeElement.dataset.open") != k: bad('focus is lost after a one-tap answer')
                # Undo by the keyboard.
                key('z', 'KeyZ', 2)
                time.sleep(0.2)
                if ev("document.querySelectorAll('.os-open').length") != many: bad('Control-Z does not undo')
                ev("document.querySelector('.os-strip-next').click()")
                settle()
            # The keyboard, line to line and into the sheet.
            at = ev("document.activeElement.dataset.open")
            key('ArrowDown')
            if ev("document.activeElement.dataset.open") == at: bad('Down does not go to the next line')
            # A speech of several sentences: a line the sheet can cut.
            k = ev("(() => { const l = [...document.querySelectorAll('.os-item:not(.os-open) .rd-speech')].find(n => n.textContent.length > 120 && n.textContent.length < 260); l.closest('.os-line').focus(); return l.closest('.os-line').dataset.open; })()")
            key('Enter')
            wait("document.querySelector('dialog.os-line-sheet[open]')", 'the line sheet')
            settle()
            if ev("document.activeElement.getAttribute('role')") != 'slider': bad('the line sheet does not open on the cut')
            if not ev("[...document.querySelectorAll('.os-sheet .btn')].find(b => b.textContent === 'Split here').disabled"): bad('Split here is offered with no cut')
            fit('line sheet')
            for _ in range(4): key('ArrowRight')
            if ev("document.activeElement.getAttribute('aria-valuenow')") != '4': bad('Right does not move the cut a word')
            # A tap between two words.
            p = json.loads(ev("JSON.stringify((() => { const ws = document.querySelectorAll('.os-w'); const r = ws[6].getClientRects()[0]; return { x: r.left + 3, y: r.top + r.height / 2 }; })())"))
            for t in ('mousePressed', 'mouseReleased'):
                cdp.call('Input.dispatchMouseEvent', {'type': t, 'x': p['x'], 'y': p['y'], 'button': 'left', 'clickCount': 1})
            if ev("document.querySelector('.os-cutline').getAttribute('aria-valuenow')") != '6': bad(f"a tap does not place the cut: {ev('document.querySelector(chr).textContent'.replace('chr', repr('.os-cutline')))[:40]}")
            shot('line')
            ev("document.querySelector('.os-sheet [aria-expanded]').click()")
            settle()
            fit('line sheet, all parts')
            if w in (375, 1440): shot('line-parts')
            n = int(ev("document.querySelectorAll('.os-list [role=listitem]').length"))
            step("[...document.querySelectorAll('.os-sheet .btn')].find(b => b.textContent === 'Split here').click()", 'a split')
            settle()
            if int(ev("document.querySelectorAll('.os-list [role=listitem]').length")) != n + 1: bad('Split here made no line')
            made = ev("document.activeElement.dataset.open")
            if made in (None, k): bad('focus is not on the line the split made')
            key('Enter')
            wait("document.querySelector('dialog.os-line-sheet[open]')", 'the line sheet again')
            step("[...document.querySelectorAll('.os-sheet .btn')].find(b => b.textContent === 'Join to line above').click()", 'a join')
            settle()
            if int(ev("document.querySelectorAll('.os-list [role=listitem]').length")) != n: bad('Join to line above kept two lines')
            if ev("document.activeElement.dataset.open") != k: bad('focus is not on the joined line')
            # Edit words, then Undo.
            key('Enter')
            wait("document.querySelector('dialog.os-line-sheet[open]')", 'the line sheet for words')
            ev("[...document.querySelectorAll('.os-sheet .btn')].find(b => b.textContent === 'Edit words').click()")
            wait("document.querySelector('.os-edit')", 'the words field')
            fit('edit words')
            if w in (375, 1440): shot('words')
            ev("document.querySelector('.os-edit').value = 'Words of my own (she laughs) instead.'")
            step("[...document.querySelectorAll('.os-sheet .btn')].find(b => b.textContent === 'Save').click()", 'Edit words')
            settle()
            if 'Words of my own' not in ev("document.activeElement.textContent"): bad('Edit words changed nothing')
            if not ev("!!document.activeElement.querySelector('.rd-aside')"): bad('a direction in the words is not drawn as one')
            ev("document.querySelector('[aria-label=Undo]').click()")
            # Leave out, and back.
            key('Escape')
            ev(f"document.querySelector('[data-open=\"{k}\"]').focus()")
            key('Enter')
            wait("document.querySelector('dialog.os-line-sheet[open]')", 'the line sheet to leave out')
            step("[...document.querySelectorAll('.os-sheet .btn')].find(b => b.textContent === 'Leave out').click()", 'Leave out')
            settle()
            if int(ev("document.querySelectorAll('.os-list [role=listitem]').length")) != n - 1: bad('Leave out left the line')
            if not ev("document.activeElement.dataset.open"): bad('focus is lost after Leave out')
            step("document.querySelector('[aria-label=Undo]').click()", 'Undo')
            settle()
            if int(ev("document.querySelectorAll('.os-list [role=listitem]').length")) != n: bad('Undo did not bring the line back')
            where = ev(f"(() => {{ const a = [...document.querySelectorAll('.os-list [role=listitem]')].map(x => x.dataset.k); return a.indexOf('{k}') > 0; }})()")
            if not where: bad('Undo put the line back at the top')
            # A part: rename, Join to.
            ev("document.querySelector('.os-chips .os-chip[data-part]').click()")
            wait("document.querySelector('dialog.os-sheet[open] .os-form')", 'the part sheet')
            settle()
            fit('part sheet')
            if w in (375, 1440): shot('part')
            first = ev("document.querySelector('.os-part-h').textContent")
            ev("document.querySelector('.os-sheet .os-form input').value = 'Renamed part'")
            step("document.querySelector('.os-sheet .os-form button').click()", 'a rename')
            settle()
            if ev("document.querySelector('.os-chips .os-chip[data-part]').dataset.part") != 'RENAMED PART': bad('the part is not renamed')
            if ev("!!document.querySelector('dialog[open]')"): bad('the part sheet stays open')
            n_parts = ev("document.querySelector('.rd-where').textContent")
            ev("document.querySelector('.os-chips .os-chip[data-part]').click()")
            wait("document.querySelector('dialog.os-sheet[open] .os-acts')", 'Join to')
            step("document.querySelector('.os-sheet .os-acts .os-chip').click()", 'Join to')
            settle()
            if ev("document.querySelector('.rd-where').textContent") == n_parts: bad('Join to left two parts')
            ev("document.querySelector('[aria-label=Undo]').click()")
            # A new part, named before any line is given to it.
            ev("document.querySelector('.os-chips [data-act=part]').click()")
            wait("document.querySelector('dialog.os-sheet[open] .os-form')", 'the new part sheet')
            ev("document.querySelector('.os-sheet .os-form input').value = 'the gull'; document.querySelector('.os-sheet .os-form button').click()")
            settle()
            if not ev("!!document.querySelector('.os-chip[data-part=\"THE GULL\"]')"): bad('+ Part made no part')
            fit('chips, all')
            # A full disk: said, and the work stays.
            ev("window.__full = true")
            ev("document.querySelector('.os-chip[data-part=\"THE GULL\"]').click()")
            wait("document.querySelector('dialog.os-sheet[open]')", 'the part with no line')
            ev("[...document.querySelectorAll('.os-sheet .btn')].find(b => b.textContent === 'Leave out').click()")
            wait("/out of space/.test((document.querySelector('.os-problem') || {}).textContent || '')", 'the full disk')
            fit('full disk')
            if w in (375, 1440): shot('full')
            ev("window.__full = false; [...document.querySelectorAll('.os-problem .btn')].find(b => b.textContent === 'Try again').click()")
            wait("document.querySelector('.os-problem').hidden", 'the write after Try again')
            # A reload keeps the corrections; the row says what is left to do.
            settle()
            sid = ev("new URLSearchParams(location.search).get('script')")
            go('?view=record')
            wait("[...document.querySelectorAll('#record-body h2')].some(h => h.textContent === 'Your scripts')", 'Your scripts')
            if opens and not ev("/lines? ha(s|ve) no part/.test(document.querySelector('[aria-labelledby=own-list-h]').innerText)"): bad('the row does not say lines have no part')
            settle()
            shot('record')
            ev("document.querySelector('[aria-labelledby=own-list-h] a').click()")
            wait("document.querySelector('.os-list .os-line')", 'the parts page from the row')
            if ev("document.querySelector('.os-chips .os-chip[data-part]').dataset.part") != 'RENAMED PART': bad('a reload lost the rename')
            # A part short enough to record, for the takes.
            ev("[...document.querySelectorAll('.btn')].find(b => b.textContent === 'Done').click()")
            wait("document.querySelector('.os-own')", "the script's page")
            settle()
            page = ev("document.querySelector('#view-plays').innerText")
            for words in ('Your script', 'Record this', 'Read', 'Read together', 'Added by you · Kept on this device', 'This script can’t be published.', 'Edit', 'Save as text', 'Delete'):
                if words.lower() not in page.lower(): bad(f"the script's page does not say {words!r}")
            for words in ('Share', 'Stage play', 'Radio play'):
                if words.lower() in page.lower(): bad(f'{words} is offered on the script\'s page')
            fit("the script's page")
            cut = ev(OPENING)
            if cut: bad(f'the opening cuts {cut}')
            shot('script')
            ev("document.querySelector('.os-own').scrollIntoView({ block: 'end' })")
            if w in (375, 1440): shot('script-foot')
            ev("[...document.querySelectorAll('.os-own .btn')].find(b => b.textContent === 'Save as text').click()")
            wait("window.__saved.length", 'the saved text')
            if 'RENAMED PART\n' not in ev("window.__saved[0]"): bad('Save as text has no names in capitals over their words')
            if ev("window.__file") != 'The Lady from the Sea.txt': bad(f'the saved file is {ev("window.__file")!r}')
            # Offline, and a store that fails: the pages still open, and say so with Try again.
            cdp.call('Network.emulateNetworkConditions', {'offline': True, 'latency': 0, 'downloadThroughput': 0, 'uploadThroughput': 0})
            ev("[...document.querySelectorAll('.os-own a.btn')].find(b => b.textContent === 'Edit').click()")
            wait("document.querySelector('.os-list .os-line')", 'the parts page, offline')
            ev("document.querySelector('.os [aria-label=Back]').click()")
            wait("document.querySelector('.os-own')", "the script's page, offline")
            cdp.call('Network.emulateNetworkConditions', {'offline': False, 'latency': 0, 'downloadThroughput': -1, 'uploadThroughput': -1})
            ev("window.__get = OwnScripts.shared().get; OwnScripts.shared().get = async () => { throw new Error('full stop'); }; [...document.querySelectorAll('.os-own a.btn')].find(b => b.textContent === 'Edit').click()")
            wait("/This did not load/.test((document.querySelector('#own-body .state-problem') || {}).textContent || '')", 'the failed read')
            fit('failed read')
            ev("OwnScripts.shared().get = window.__get; document.querySelector('#own-body .state-problem button').click()")
            wait("document.querySelector('.os-list .os-line')", 'the parts page after Try again')
            ev("document.querySelector('.os [aria-label=Back]').click()")
            wait("document.querySelector('.os-own')", "the script's page again")
            # A bundled play's page draws its opening by the same rule.
            for pid_ in PLAYS:
                go(f'?play={pid_}')
                wait("document.querySelector('#plays-body .g-head-hero')", "a bundled play's page")
                settle()
                if ev("!!document.querySelector('.pl-open-hero')"):
                    cut = ev(OPENING)
                    if cut: bad(f'the opening of {pid_} cuts {cut}')
            go(f'?play={sid}')
            wait("document.querySelector('.os-own')", "the script's page, back")
            # Read.
            ev("[...document.querySelectorAll('#view-plays a.btn')].find(b => b.textContent === 'Read').click()")
            wait("document.querySelector('.rd-line')", 'the reader')
            settle()
            if ev("document.querySelector('.rd-title').textContent") != 'The Lady from the Sea': bad('the reader does not name the script')
            if w in (375, 1440): shot('read')
            # Record this: the cast sheet says who could read it if it were shared; then two takes with the stub microphone.
            go(f'?play={sid}')
            wait("[...document.querySelectorAll('button')].some(b => /Record this/.test(b.textContent))", 'Record this')
            ev("[...document.querySelectorAll('button')].find(b => /Record this/.test(b.textContent)).click()")
            wait("document.querySelector('button[aria-label^=\"Take part\"]')", 'the cast sheet')
            settle()
            if not ev("/Sharing needs an account\\.\\s+Only people you invite can read this script\\./.test(document.querySelector('#view-plays').innerText)"): bad('the cast sheet does not say what sharing needs, and who can read it')
            if w in (375, 1440): shot('cast')
            no_sheet('the cast sheet')
            pid = ev("new URLSearchParams(location.search).get('production')")
            ev("document.querySelector('button.btn-primary[aria-label^=\"Take part\"], button[aria-label^=\"Take part\"]').click()")
            wait("document.querySelector('.st-dock') && document.querySelector('.rd-line')", 'the studio')
            ev("document.getElementById('st-headphones').click(); document.querySelector('.st-go').click()")
            wait("document.querySelector('.st-mode')", 'the dock after room tone', 20)
            ev("[...document.querySelectorAll('.st-mode input')].find(i => i.value === 'lines').click()")
            settle()
            for nth in (1, 2):
                if nth == 2:
                    ev("document.dispatchEvent(new KeyboardEvent('keydown', { key: 'j', bubbles: true, cancelable: true }))")
                    time.sleep(0.4)
                ev("document.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true, cancelable: true }))")
                wait("document.querySelector('.st-rec')", f'the microphone for take {nth}', 15)
                ev("window.__micGain.gain.value = 0.3")
                time.sleep(0.8)
                if nth == 1 and w in (375, 1440): shot('recording')
                ev("window.__micGain.gain.value = 0.0005")
                ev("document.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true, cancelable: true }))")
                wait(f"document.querySelectorAll('.rd-take[data-state=chosen]').length >= {nth}", f'take {nth} kept', 15)
            taken = json.loads(ev("JSON.stringify([...document.querySelectorAll('.rd-take[data-state=chosen]')].map(b => b.dataset.line))"))
            part = ev("new URLSearchParams(location.search).get('part')")
            # A reload, then the locked line.
            go(f'?script={sid}&edit=parts')
            wait("document.querySelector('.os-list .os-line')", 'the parts page after a reload')
            lk = ev(f"OwnScripts.shared().get('{sid}').then(r => String(r.doc.lines.find(l => l.id === '{taken[0]}').k))", True)
            ev(f"document.querySelector('[data-open=\"{lk}\"]').focus()")
            settle()
            key('Enter')
            wait("document.querySelector('dialog.os-line-sheet[open]')", 'the locked line')
            settle()
            sheet = ev("document.querySelector('dialog[open]').innerText")
            acts = json.loads(ev("JSON.stringify([...document.querySelectorAll('dialog[open] .btn, dialog[open] .os-chip')].map(b => b.textContent))"))
            if 'This line has a take.' not in sheet: bad('a line with a take does not say so')
            if acts != ['Edit words']: bad(f'a line with a take offers {acts}')
            fit('locked')
            shot('locked')
            ev("[...document.querySelectorAll('dialog[open] .btn')].find(b => b.textContent === 'Edit words').click()")
            ev("document.querySelector('.os-edit').value = 'Something else entirely.'; [...document.querySelectorAll('.os-sheet .btn')].find(b => b.textContent === 'Save').click()")
            ev("(async () => { const c = [...document.querySelectorAll('.os-chips .os-chip[data-part]')].find(b => 'role:' + b.dataset.part === %s); if (c) c.click(); })()" % json.dumps(part))
            settle()
            if 'A line of this part has a take.' not in (ev("(document.querySelector('dialog[open]') || {}).innerText || ''")): bad('the part of a line with a take can be renamed')
            if w == 375: shot('locked-part')
            key('Escape')
            time.sleep(0.8)
            ev("[...document.querySelectorAll('.btn')].find(b => b.textContent === 'Done').click()")
            wait("document.querySelector('.os-own')", "the script's page after the edit")
            go(f'?read={sid}&production={pid}&part={part}&line={taken[0]}')
            wait("document.querySelector('.st-dock') && document.querySelector('.rd-line')", 'the studio after the edit')
            settle()
            if not ev(f"/Something else entirely/.test(document.getElementById('{taken[0]}').textContent)"): bad('the production does not read the new words')
            if w < 860:
                ev("document.querySelector('.st-open').click()")
                time.sleep(0.5)
            wait("/Words changed/.test(document.querySelector('.st-takes').textContent)", 'Words changed in the take list')
            shot('changed')
            if w < 860: ev("document.querySelector('dialog.st-sheet[open]').close()")
            # Export my data, Search, Delete.
            go('?view=library')
            wait("document.querySelector('#export-row button')", 'Export my data')
            ev("document.querySelector('#export-row button').click()")
            wait("window.__json", 'the export')
            got = json.loads(ev("window.__json"))['scripts']
            if [s['id'] for s in got] != [sid] or len(got[0]['lines']) < 100: bad('the export does not carry the script')
            # Search, over a catalog that answers nothing (the harness has none).
            ev("for (const k of ['searchSeries', 'searchPeople']) API[k] = async () => ({ total: 0, rows: [] }); for (const k of ['searchEpisodeNumbers', 'searchSaidNumbers']) API[k] = async () => []; API.searchAired = async () => null; document.querySelector('[data-nav=search]').click()")
            for q, has in (('lady sea', True), ('zzqx', False)):
                ev(f"(() => {{ const i = document.getElementById('search-q'); i.value = {json.dumps(q)}; i.dispatchEvent(new Event('input', {{ bubbles: true }})); }})()")
                wait("document.querySelector('#search-body #ro-h')" if has else "document.querySelector('#search-body .os-add-link')", f'Search for {q!r}')
                if has and ev("!!document.querySelector('#search-body .os-add-link')"): bad('Search offers Add a script beside the script it found')
                if not has and ev("!!document.querySelector('#search-body #ro-h')"): bad('Search finds a script that does not match')
            if w in (375, 1440): shot('search-none')
            go(f'?play={sid}')
            wait("document.querySelector('.os-own .btn-destructive')", 'Delete')
            ev("document.querySelector('.os-own .btn-destructive').click()")
            wait("location.search.includes('view=record')", 'Record after Delete')
            if ev("window.__asked.slice(-1)[0]") != 'Delete The Lady from the Sea? Its productions keep their copy.': bad(f'Delete asks {ev("window.__asked.slice(-1)[0]")!r}')
            settle()
            if ev("/Your scripts/.test(document.querySelector('#record-body').innerText)"): bad('the deleted script is still listed')
            go(f'?production={pid}')
            wait("document.querySelector('.pl-grid')", 'the production of a deleted script')
            go(f'?play={sid}')
            wait("/This script is not in this browser/.test(document.querySelector('#plays-body').innerText)", 'a deleted script says so')
            fit('gone')
            no_sheet('the end')
            errs = [e for e in json.loads(ev("JSON.stringify(window.__errors)")) if not e.startswith('sync ') and 'full' not in e]
            if errs: bad(f'page errors: {errs[:3]}')
        except StopIteration:
            pass
        except Exception as e:  # a blind instrument says so
            problems.append(f'{tag}: harness error {e!r}; page errors {cdp and ev("JSON.stringify(window.__errors || [])")}')
        finally:
            if proc:
                web_run._kill(proc)
            shutil.rmtree(profile, ignore_errors=True)

    try:
        for theme in themes:
            for w in widths:
                n = len(problems)
                run(w, theme == 'dark')
                print(('FAIL ' if len(problems) > n else 'ok   ') + f'{w} {theme} {problems[n:] or ""}', flush=True)
    finally:
        srv.terminate()
        shutil.rmtree(work, ignore_errors=True)
    print(f'the slowest step: {worst[0]:.0f} ms')
    print(f'{"FAIL" if problems else "PASS"}: {len(problems)} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
