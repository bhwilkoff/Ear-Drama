#!/usr/bin/env python3
"""Fit gate and frames for marks in the script reader (WEB-DESIGN 4.16 item 15, PLAYS-DESIGN 2.10; Decision
076 S5), light and dark, at 320, 375, 430 and 1440 px, in headless Chrome over the DevTools protocol.

For a stage play, a verse play and a radio play (the three cases of R2-play-typography: The Philanderer at
L0009, Macbeth at L0015, Caesar Rodney's Ride at L0020; a verse play from the bundle stands in for Macbeth
when the data plane has no library), it selects words on the page the way a person does (a DOM Range over
the runs) and makes every kind of mark through the mark bar and its keys: a highlight and an underline on
one speech, a breath and a pause (the P key) on the next, a beat with a label and a note on the third. Then
it taps the highlight and changes its hue, opens the notebook, makes the text larger, hides and shows the
marks, and reloads. Last, the studio attached (the cast sheet's Take part, as tools/web_fit_studio.py
opens it): a highlight and a breath on the current line, and a tap on the highlight opens it without
moving the current line.

Fails on: a sideways scroll; a mark bar off the screen or wrapping; a mark not stored, or stored twice; a
character added to a line's words; a highlight painting other words than its own; a point mark missing; a
mark lost when the text grows or the page reloads; a notebook row missing or a jump that does not go;
marks still drawn after Show marks is off; in the studio, a tap on a mark that changes the current line.

    python3 tools/web_fit_marks.py                       # exit 1 on any problem
    python3 tools/web_fit_marks.py --shots DIR           # also write a PNG per frame
    python3 tools/web_fit_marks.py --data https://eardrama.org/data/
    python3 tools/web_fit_marks.py --widths 375,1440

Negative control (2026-11-15): js/marks.js with setPoint's `t.splitText(p.offset).before(node)` replaced by
`t.before(node)` fails "a breath is not after its word" at every case (seen at 375, light and dark).
"""
import base64, json, os, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import web_run  # noqa: E402
import web_fit_studio as WS  # noqa: E402

WIDTHS = (320, 375, 430, 1440)
CASES = (('stage', 'gut-5071', 'L0009'), ('verse', 'gut-1533', 'L0015'), ('radio', 'gut-28051', 'L0020'))

HELP = r"""(() => {
  const clip = () => document.querySelector('.rd-clip').getBoundingClientRect();
  const vis = (n) => { const cr = clip(); return [...n.getClientRects()].some(r => r.right > cr.left + 2 && r.left < cr.right - 2 && r.bottom > cr.top && r.top < cr.bottom - 4); };
  const runs = (n) => [...n.querySelectorAll('[data-at]')];
  const texts = (s) => { const out = []; const w = document.createTreeWalker(s, NodeFilter.SHOW_TEXT); for (let t = w.nextNode(); t; t = w.nextNode()) out.push(t); return out; };
  function point(n, off, side) {
    for (const r of runs(n)) {
      const at = +r.dataset.at, len = r.textContent.length;
      if (side === 'start' ? (off >= at && off < at + len) : (off > at && off <= at + len)) {
        let rem = off - at;
        for (const t of texts(r)) { if (side === 'start' ? rem < t.length : rem <= t.length) return { node: t, offset: rem }; rem -= t.length; }
      }
    }
    return null;
  }
  window.__mk = {
    vis,
    /** Visible speeches with at least `k` said words, wholly on the page. */
    lines(k) { return [...document.querySelectorAll('.rd-line.rd-speech')].filter(n => vis(n) && this.words(n).length >= k && [...n.getClientRects()].every(r => r.bottom <= clip().bottom + 1 && r.top >= clip().top - 1 && r.left >= clip().left - 1 && r.right <= clip().right + 1)).map(n => n.id); },
    words(n) {
      if (typeof n === 'string') n = document.getElementById(n);
      const out = [];
      for (const s of n.querySelectorAll('.rd-said')) { const at = +s.dataset.at; const t = s.textContent; for (const m of t.matchAll(/[A-Za-z][A-Za-z'’]{2,}/g)) out.push({ start: at + m.index, end: at + m.index + m[0].length, text: m[0] }); }
      return out;
    },
    select(id, start, end) {
      const n = document.getElementById(id);
      const a = point(n, start, 'start'), b = point(n, end, 'end');
      if (!a || !b) return null;
      const r = document.createRange(); r.setStart(a.node, a.offset); r.setEnd(b.node, b.offset);
      const s = getSelection(); s.removeAllRanges(); s.addRange(r);
      return r.toString();
    },
    stored(script) { try { return (JSON.parse(localStorage.getItem('ed.marks.' + script)) || { marks: [] }).marks; } catch { return []; } },
    hl(name) { const h = CSS.highlights.get(name); return h ? [...h].map(r => r.toString()) : []; },
    /** Clicks the middle of the first highlight's first box, as a tap would. */
    tapHighlight() {
      const h = ['yellow', 'green', 'blue', 'pink'].map(k => CSS.highlights.get('ed-mk-' + k)).find(Boolean);
      const r = h ? [...h][0].getClientRects()[0] : null;
      if (!r) return false;
      const x = r.left + r.width / 2, y = r.top + r.height / 2;
      document.elementFromPoint(x, y).dispatchEvent(new MouseEvent('click', { bubbles: true, clientX: x, clientY: y }));
      return true;
    },
    bar() { const b = document.querySelector('.mk-bar'); if (!b || b.hidden) return null; const r = b.getBoundingClientRect(); return { l: Math.round(r.left), r: Math.round(r.right), h: Math.round(r.height), n: b.querySelectorAll('.mk-btn').length }; },
    click(label) { const b = [...document.querySelectorAll('.mk-bar .mk-btn')].find(x => x.getAttribute('aria-label').startsWith(label)); if (b) b.click(); return !!b; },
    key(k) { document.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true })); },
  };
  return true;
})()"""


def main():
    shots = sys.argv[sys.argv.index('--shots') + 1] if '--shots' in sys.argv else None
    data = sys.argv[sys.argv.index('--data') + 1] if '--data' in sys.argv else None
    if shots:
        os.makedirs(shots, exist_ok=True)
    widths = [int(x) for x in sys.argv[sys.argv.index('--widths') + 1].split(',')] if '--widths' in sys.argv else WIDTHS
    bundle = json.load(open(WS.BUNDLE))['scripts']
    ids = {s['id'] for s in bundle}
    cases = []
    for name, sid, line in CASES:
        if data or sid in ids:
            cases.append((name, sid, line))
        elif name == 'verse':
            # No library here: the bundle's first play with verse speeches.
            v = next((s for s in bundle if sum(1 for l in s['lines'] if l['kind'] == 'speech' and any('\n' in (p.get('say') or '') for p in l['parts'])) > 50), None)
            if v: cases.append((name, v['id'], v['lines'][40]['id']))
        else:
            print(f'note: {sid} is not in the bundle and no --data was given; the {name} case is skipped')
    studio_script = WS.pick_script()
    work = tempfile.mkdtemp(prefix='fit-marks-')
    for f in os.listdir(ROOT):
        if f not in ('index.html', '.git', 'build', 'android', 'apple', 'docs', 'worker', 'windows', 'data'):
            os.symlink(os.path.join(ROOT, f), os.path.join(work, f))
    os.makedirs(os.path.join(work, 'data', 'plays'))
    os.symlink(WS.BUNDLE, os.path.join(work, 'data', 'plays', 'castable-scripts.json'))
    html = open(os.path.join(ROOT, 'index.html')).read()
    if data:
        html = html.replace('<meta name="ed-data" content="data/">', f'<meta name="ed-data" content="{data}">', 1)
    open(os.path.join(work, 'index.html'), 'w').write(html)
    srv_code = ("import sys,http.server,functools\n"
                "class S(http.server.ThreadingHTTPServer):\n request_queue_size=256\n daemon_threads=True\n"
                "class H(http.server.SimpleHTTPRequestHandler):\n def log_message(self,*a): pass\n"
                "S(('127.0.0.1',int(sys.argv[1])),functools.partial(H,directory=sys.argv[2])).serve_forever()\n")
    port = 7600 + os.getpid() % 400
    srv = subprocess.Popen([sys.executable, '-c', srv_code, str(port), work], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    print('cases ' + ', '.join(f'{n} {s} at {l}' for n, s, l in cases) + f'; studio on {studio_script["id"]}')
    problems = []

    def run(w, dark):
        tag = f'{w} {"dark" if dark else "light"}'
        theme = 'dark' if dark else 'light'
        h = 900 if w > 600 else 760
        profile = tempfile.mkdtemp(prefix='fit-marks-chrome-')
        proc = None
        try:
            proc, ws = WS.launch(profile)
            cdp = web_run.CDP(ws)
            cdp.call('Page.enable')
            cdp.call('Page.addScriptToEvaluateOnNewDocument', {'source': WS.STUB})
            cdp.call('Emulation.setDeviceMetricsOverride', {'width': w, 'height': h, 'deviceScaleFactor': 1, 'mobile': w < 600})
            cdp.call('Emulation.setEmulatedMedia', {'features': [{'name': 'prefers-color-scheme', 'value': theme}]})
            ev = lambda js, aw=False: cdp.call('Runtime.evaluate', {'expression': js, 'returnByValue': True, 'awaitPromise': aw, 'userGesture': True}, timeout=30).get('result', {}).get('value')
            # Settled: fonts in, the page's slide finished (a measure mid-slide reads the wrong page), two frames painted.
            settle = lambda: ev("document.fonts.ready.then(() => new Promise(r => { const f = document.querySelector('.rd-flow');"
                                " const t0 = performance.now(); const done = () => (!f || !f.getAnimations().length || performance.now() - t0 > 3000)"
                                " ? requestAnimationFrame(() => requestAnimationFrame(r)) : setTimeout(done, 50); setTimeout(done, 300); }))", True)
            J = json.dumps

            def shot(name):
                settle()
                if shots:
                    png = cdp.call('Page.captureScreenshot', {'format': 'png'}, timeout=30)
                    open(os.path.join(shots, f'marks-{name}-{theme}-{w}.png'), 'wb').write(base64.b64decode(png['data']))

            def bad(msg):
                problems.append(f'{tag}: {msg}')

            def wait(js, what, secs=25):
                t0 = time.time()
                while not ev(f"!!({js})"):
                    if time.time() - t0 > secs:
                        bad(f'{what} never appeared (page errors: {ev("JSON.stringify(window.__errors)")})'); shot('timeout'); return False
                    time.sleep(0.2)
                return True

            def open_reader(sid, line):
                cdp.call('Page.navigate', {'url': f'http://127.0.0.1:{port}/?read={sid}&line={line}&mute=1'}, timeout=30)
                if not wait("document.querySelector('.rd-line') && document.querySelector('.rd-page').textContent.length > 0", f'the reader for {sid}'): return False
                settle()
                ev(HELP)
                return True

            def sideways(where):
                if ev("document.documentElement.scrollWidth > innerWidth"): bad(f'{where}: the page scrolls sideways')

            def bar_fits(where, rows=1):
                b = ev('JSON.stringify(__mk.bar())')
                b = json.loads(b) if b else None
                if not b: bad(f'{where}: no mark bar'); return None
                if b['l'] < 0 or b['r'] > w: bad(f'{where}: the mark bar is off the screen ({b})')
                if b['h'] > 56 * rows: bad(f'{where}: the mark bar wraps ({b["h"]} px)')
                return b

            def mark(sid, line, a, b, how, label=None, stored_before=None):
                """Selects [a, b) in `line` and makes a mark by a bar button (or a key); returns the stored count."""
                got = ev(f"__mk.select({J(line)}, {a}, {b})")
                if not got: bad(f'could not select {line} [{a}, {b})'); return None
                settle()
                if how.startswith('key:'): ev(f"__mk.key({J(how[4:])})")
                elif not ev(f"__mk.click({J(how)})"): bad(f'no {how} button on the bar'); return None
                if label is not None:
                    if not wait("document.querySelector('dialog.mk-sheet[open] .mk-field')", f'the {how} sheet', 5): return None
                    ev(f"(() => {{ const f = document.querySelector('dialog.mk-sheet[open] .mk-field'); f.value = {J(label)}; f.dispatchEvent(new Event('input')); document.querySelector('dialog.mk-sheet[open] .btn-primary').click(); }})()")
                settle()
                return len(json.loads(ev(f"JSON.stringify(__mk.stored({J(sid)}))")))

            for name, sid, at_line in cases:
                if not open_reader(sid, at_line): continue
                sideways(f'{name} opened')
                lines = json.loads(ev("JSON.stringify(__mk.lines(5))"))
                if len(lines) < 3:
                    # A narrow page holds fewer whole speeches: turn on until three are showing.
                    for _ in range(12):
                        ev("document.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }))"); settle()
                        lines = json.loads(ev("JSON.stringify(__mk.lines(5))"))
                        if len(lines) >= 3: break
                if len(lines) < 3: bad(f'{name}: fewer than three speeches on the page to mark ({lines})'); continue
                A, B, Cc = lines[:3]
                if os.environ.get('MARKS_DEBUG'):
                    print(name, lines[:3], ev(f"JSON.stringify([{J(A)},{J(B)},{J(Cc)}].map(id => [...document.getElementById(id).getClientRects()].map(r => [Math.round(r.left), Math.round(r.top), Math.round(r.right), Math.round(r.bottom)])).concat([JSON.stringify(document.querySelector('.rd-clip').getBoundingClientRect())]))"))
                before = {l: ev(f"document.getElementById({J(l)}).textContent") for l in (A, B, Cc)}
                wa, wb, wc = (json.loads(ev(f"JSON.stringify(__mk.words({J(l)}))")) for l in (A, B, Cc))
                # The bar on a selection.
                ev(f"__mk.select({J(A)}, {wa[0]['start']}, {wa[1]['end']})")
                settle()
                bar_fits(f'{name} selection')
                if name == 'stage' or w in (375, 1440): shot(f'{name}-bar')
                n = mark(sid, A, wa[0]['start'], wa[1]['end'], 'Highlight')
                if n != 1: bad(f'{name}: {n} marks stored after one highlight')
                want_hl = ev(f"document.getElementById({J(A)}).textContent")  # unchanged words
                n = mark(sid, A, wa[3]['start'], wa[3]['end'], 'Underline')
                n = mark(sid, B, wb[1]['start'], wb[1]['end'], 'Breath')
                n = mark(sid, B, wb[4]['start'] if len(wb) > 4 else wb[-1]['start'], wb[4]['end'] if len(wb) > 4 else wb[-1]['end'], 'key:p')
                n = mark(sid, Cc, wc[2]['start'], wc[2]['end'], 'Beat', label='turn')
                n = mark(sid, Cc, wc[0]['start'], wc[1]['end'], 'Note', label='Say it cold, then warm.')
                if n != 6: bad(f'{name}: {n} marks stored after six, want 6')
                for l in (A, B, Cc):
                    if ev(f"document.getElementById({J(l)}).textContent") != before[l]: bad(f'{name}: a mark added characters to {l}')
                hl = json.loads(ev("JSON.stringify(__mk.hl('ed-mk-yellow').concat(__mk.hl('ed-mk-green'), __mk.hl('ed-mk-blue'), __mk.hl('ed-mk-pink')))"))
                if hl != [ev(f"__mk.select({J(A)}, {wa[0]['start']}, {wa[1]['end']})")]: bad(f'{name}: the highlight paints {hl}')
                ev("getSelection().removeAllRanges()")
                if ev("__mk.hl('ed-mk-under').length") != 1: bad(f'{name}: no underline drawn')
                if ev("__mk.hl('ed-mk-note').length") != 1: bad(f'{name}: no note rule drawn')
                pts = json.loads(ev("JSON.stringify([...document.querySelectorAll('.mk')].map(n => [n.className, n.closest('.rd-line').id]))"))
                if sorted(p[0] for p in pts) != ['mk mk-beat', 'mk mk-breath', 'mk mk-pause', 'mk mk-pin']: bad(f'{name}: point marks drawn {pts}')
                # The breath sits right after its word (its previous text ends with the word).
                after_word = ev(f"(() => {{ const m = document.querySelector('#{B} .mk-breath'); const p = m && m.previousSibling; return p ? p.textContent.replace(/[^A-Za-z'’]+$/, '').slice(-{len(wb[1]['text'])}) : ''; }})()")
                if after_word != wb[1]['text']: bad(f'{name}: a breath is not after its word ({after_word!r} vs {wb[1]["text"]!r})')
                sideways(f'{name} marked')
                shot(f'{name}-marked')
                # A tap on the highlight opens it; a new hue.
                if not ev("__mk.tapHighlight()"): bad(f'{name}: no highlight on the page to tap')
                settle()
                b = bar_fits(f'{name} editing a highlight')
                if b and b['n'] != 5: bad(f'{name}: the highlight bar has {b["n"]} buttons, want four hues and Delete')
                if name == 'stage' or w in (375, 1440): shot(f'{name}-edit')
                ev("__mk.click('Green')")
                settle()
                if ev("__mk.hl('ed-mk-green').length") != 1 or ev("__mk.hl('ed-mk-yellow').length") != 0: bad(f'{name}: the hue did not change')
                ev("__mk.key('Escape')")
                # A tap on the breath, Delete, then Undo: the mark comes back.
                ev(f"document.querySelector('#{B} .mk-breath').click()")
                settle()
                ev("__mk.click('Delete')")
                settle()
                if ev("document.querySelectorAll('.mk-breath').length") != 0: bad(f'{name}: Delete left the breath')
                if not ev("[...document.querySelectorAll('.mk-bar .mk-btn')].some(b => b.textContent === 'Undo')"): bad(f'{name}: no Undo after a delete')
                elif name == 'stage' and w in (375, 1440): shot(f'{name}-undo')
                ev("[...document.querySelectorAll('.mk-bar .mk-btn')].find(b => b.textContent === 'Undo')?.click()")
                settle()
                if ev("document.querySelectorAll('.mk-breath').length") != 1 or len(json.loads(ev(f"JSON.stringify(__mk.stored({J(sid)}))"))) != 6: bad(f'{name}: Undo did not bring the breath back')
                # Larger text: the marks stay on their words.
                ev("document.querySelector('[aria-label=Text]').click()")
                for _ in range(2): ev("document.querySelector('[aria-label=\"Larger text\"]').click()")
                ev("document.querySelector('dialog[open]').close()")
                settle()
                if ev("__mk.hl('ed-mk-green')[0]") != hl[0]: bad(f'{name}: the highlight moved when the text grew')
                if ev("document.querySelectorAll('.mk').length") != 4: bad(f'{name}: point marks lost when the text grew')
                if name == 'verse' and w in (375, 1440): shot(f'{name}-larger')
                ev("document.querySelector('[aria-label=Text]').click()")
                for _ in range(2): ev("document.querySelector('[aria-label=\"Smaller text\"]').click()")
                ev("document.querySelector('dialog[open]').close()")
                # The notebook.
                ev("document.querySelector('[aria-label=Marks]').click()")
                if not wait("document.querySelector('dialog.mk-notebook[open]')", 'the notebook', 5): continue
                rows = ev("document.querySelectorAll('dialog.mk-notebook[open] .mk-nb-row').length")
                if rows != 6: bad(f'{name}: the notebook lists {rows} marks, want 6')
                if ev("(() => { const d = document.querySelector('dialog[open]'); return d.scrollWidth > d.clientWidth + 1; })()"): bad(f'{name}: the notebook scrolls sideways')
                if name == 'stage' or w in (375, 1440): shot(f'{name}-notebook')
                # Show marks off and on.
                ev("document.querySelector('.mk-show-box').click()")
                settle()
                if ev("document.querySelectorAll('.mk').length + __mk.hl('ed-mk-green').length + __mk.hl('ed-mk-under').length") != 0: bad(f'{name}: marks still drawn with Show marks off')
                ev("document.querySelector('.mk-show-box').click()")
                ev("document.querySelector('dialog.mk-notebook[open] li:last-child .mk-nb-row').click()")
                settle()
                if ev("!!document.querySelector('dialog[open]')"): bad(f'{name}: a notebook row did not close the notebook')
                if not ev(f"__mk.vis(document.getElementById({J(Cc)}))"): bad(f'{name}: the notebook jump did not show {Cc}')
                # Reload: the marks come back from the device.
                if not open_reader(sid, A): continue
                if ev("document.querySelectorAll('.mk').length") != 4 or ev("__mk.hl('ed-mk-green').length") != 1: bad(f'{name}: marks not restored after a reload')
                sideways(f'{name} reloaded')

            # The studio attached: marks on my current line, and a tap on a mark keeps the line current.
            if w in (320, 375, 430, 1440):
                cdp.call('Page.navigate', {'url': f'http://127.0.0.1:{port}/?play={studio_script["id"]}&mute=1'}, timeout=30)
                if not wait("[...document.querySelectorAll('button')].some(b => /Record this/.test(b.textContent))", 'Record this'): return
                ev(WS.SIGN_IN)
                ev("[...document.querySelectorAll('button')].find(b => /Record this/.test(b.textContent)).click()")
                if not wait("document.querySelector('button[aria-label^=\"Take part\"]')", 'Take part'): return
                ev("document.querySelector('button.btn-primary[aria-label^=\"Take part\"], button[aria-label^=\"Take part\"]').click()")
                if not wait("document.querySelector('.st-dock') && document.querySelector('.rd-line.rd-cur')", "the reader's studio"): return
                settle()
                ev(HELP)
                cur = ev("document.querySelector('.rd-line.rd-cur').id")
                wc = json.loads(ev(f"JSON.stringify(__mk.words({J(cur)}))"))
                if len(wc) >= 3:
                    mark(studio_script['id'], cur, wc[0]['start'], wc[1]['end'], 'Highlight')
                    mark(studio_script['id'], cur, wc[2]['start'], wc[2]['end'], 'Breath')
                    other = json.loads(ev(f"JSON.stringify([...document.querySelectorAll('.rd-line.rd-mine')].map(n => n.id).filter(id => id !== {J(cur)} && __mk.vis(document.getElementById(id))))"))
                    if other:
                        ev(f"document.querySelector('#{other[0]} .rd-said').click()")
                        settle()
                    now = ev("document.querySelector('.rd-line.rd-cur').id")
                    if not ev("__mk.tapHighlight()"): bad('studio: no highlight on the page to tap')
                    settle()
                    if ev("document.querySelector('.rd-line.rd-cur').id") != now: bad('studio: a tap on a mark changed the current line')
                    if not ev("!!__mk.bar()"): bad('studio: a tap on a mark did not open it')
                    if ev("document.querySelectorAll('.rd-take').length") == 0: bad('studio: the take states are gone')
                    sideways('studio')
                    ev("__mk.key('Escape')")
                    ev(f"document.querySelector('#{cur} .rd-said').click()")
                    shot('studio')
                else:
                    bad(f'studio: the current line {cur} has fewer than three words')
            errs = [e for e in json.loads(ev("JSON.stringify(window.__errors || [])")) if not e.startswith('sync ')]
            if errs: bad(f'page errors: {errs}')
        except Exception as e:  # a blind instrument says so
            problems.append(f'{tag}: harness error {e!r}')
        finally:
            if proc:
                web_run._kill(proc)

    try:
        for dark in (False, True):
            for w in widths:
                n = len(problems)
                run(w, dark)
                print(('FAIL ' if len(problems) > n else 'ok   ') + f'{w} {"dark" if dark else "light"} {problems[n:] or ""}')
    finally:
        srv.terminate()
    print(f'{"FAIL" if problems else "PASS"}: {len(problems)} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
