#!/usr/bin/env python3
"""Frames and gate for the read-along (PLAYS-DESIGN 2.11): the reader opened in read-along mode over a
stubbed store and a silent listen-through (no audio, no device voice), at 375 and 1440 px. It plays the
plan to a line well into the script and fails unless the page turned to that line and lit it; then it
turns away (a touch) and fails unless the page stays put while the next line plays and "Back to the
line" shows; then Back to the line must return to the line heard.

    python3 tools/web_fit_along.py --shots DIR --widths 375,1440
"""
import base64, json, os, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import web_run  # noqa: E402

WIDTHS = (320, 375, 430, 1440)
LIB = os.path.join(ROOT, 'catalog', 'out', 'plays-library')
BUNDLE = os.path.join(ROOT, 'catalog', 'plays', 'castable-scripts.json')


def pick_script():
    """A script with contents and a real part, from the data (never a pinned title)."""
    sys.path.insert(0, os.path.join(ROOT, 'catalog', 'tools'))
    import script_parse as P
    def ok(s):
        heads = len(s.get('sections', [])) + sum(1 for l in s['lines'] if l['kind'] != 'speech' and P.section_level(l.get('source')))
        return heads >= 4 and max((r['lines'] for r in s['roles']), default=0) >= 20
    if os.path.exists(os.path.join(LIB, 'index.json')):
        for row in json.load(open(os.path.join(LIB, 'index.json')))['plays']:
            s = json.load(open(os.path.join(LIB, row['path'])))['scripts'][0]
            if ok(s):
                return s
    for s in json.load(open(BUNDLE))['scripts']:
        if ok(s):
            return s
    raise SystemExit('no script with contents in the data')



STUB = r"""(async () => {
  const script = await (await fetch('along-script.json')).json();
  LiveAudio.create = () => ({ startPlayback: async () => {}, stopPlayback() {}, stop() {}, playTake: async () => {} });
  const realVoice = StandInVoice.create;
  StandInVoice.create = (o) => { const v = realVoice(o); return Object.assign(v, { available: () => true, reads: () => true, cancel() {},
    speak: () => new Promise(r => setTimeout(r, window.__stepMs || 60)) }); };
  const store = { production: () => ({ id: 'x', title: 'T', takes: [], chosen: {} }), readTake: async () => new Uint8Array() };
  const body = document.getElementById('reader-body');
  document.querySelectorAll('.view').forEach(v => { v.hidden = v.id !== 'view-reader'; });
  window.addEventListener('error', e => { window.__err = e.message; });
  const ce = console.error; console.error = (...a) => { window.__err = a.map(String).join(' '); ce(...a); };
  window.__h = Reader.open(body, script, { along: { production: 'x', store }, onClose() {} });
  return script.lines.length;
})()"""
HEAR = "document.querySelector('.rd-hear')"
NOW = "(() => { const n = document.querySelector('.rd-now'); return n ? [...document.querySelectorAll('.rd-line')].indexOf(n) : -1; })()"
VIS = ("(() => { const n = document.querySelector('.rd-now'); const cr = document.querySelector('.rd-clip').getBoundingClientRect();"
       " return !!n && [...n.getClientRects()].some(r => r.right > cr.left + 2 && r.left < cr.right - 2 && r.bottom > cr.top && r.top < cr.bottom); })()")
BACK = "document.querySelector('.rd-back-line').hidden"


def main():
    shots = sys.argv[sys.argv.index('--shots') + 1] if '--shots' in sys.argv else None
    if shots:
        os.makedirs(shots, exist_ok=True)
    widths = [int(x) for x in sys.argv[sys.argv.index('--widths') + 1].split(',')] if '--widths' in sys.argv else (375, 1440)
    script = pick_script()
    work = tempfile.mkdtemp(prefix='fit-along-')
    for f in os.listdir(ROOT):
        if f not in ('index.html', '.git', 'build', 'android', 'apple', 'docs', 'worker', 'windows'):
            os.symlink(os.path.join(ROOT, f), os.path.join(work, f))
    open(os.path.join(work, 'index.html'), 'w').write(open(os.path.join(ROOT, 'index.html')).read())
    json.dump(script, open(os.path.join(work, 'along-script.json'), 'w'))
    srv_code = ("import sys,http.server,functools\n"
                "class S(http.server.ThreadingHTTPServer):\n request_queue_size=256\n daemon_threads=True\n"
                "class H(http.server.SimpleHTTPRequestHandler):\n def log_message(self,*a): pass\n"
                "S(('127.0.0.1',int(sys.argv[1])),functools.partial(H,directory=sys.argv[2])).serve_forever()\n")
    port = 8800 + os.getpid() % 400
    srv = subprocess.Popen([sys.executable, '-c', srv_code, str(port), work], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    problems = []
    N = 40

    def run(w, dark):
        tag = f'{w} {"dark" if dark else "light"}'
        h = 900 if w > 600 else 760
        profile = tempfile.mkdtemp(prefix='fit-along-chrome-')
        proc = None
        try:
            proc, ws = web_run._launch(profile)
            cdp = web_run.CDP(ws)
            cdp.call('Page.enable')
            cdp.call('Emulation.setDeviceMetricsOverride', {'width': w, 'height': h, 'deviceScaleFactor': 1, 'mobile': w < 600})
            cdp.call('Emulation.setEmulatedMedia', {'features': [{'name': 'prefers-color-scheme', 'value': 'dark' if dark else 'light'}]})
            ev = lambda js, aw=False: cdp.call('Runtime.evaluate', {'expression': js, 'returnByValue': True, 'awaitPromise': aw}, timeout=30).get('result', {}).get('value')
            bad = lambda m: problems.append(f'{tag}: {m}')

            def shot(name):
                time.sleep(0.5)
                if shots:
                    png = cdp.call('Page.captureScreenshot', {'format': 'png'}, timeout=30)
                    open(os.path.join(shots, f'along-{name}-{"dark" if dark else "light"}-{w}.png'), 'wb').write(base64.b64decode(png['data']))

            cdp.call('Page.navigate', {'url': f'http://127.0.0.1:{port}/?mute=1'}, timeout=30)
            time.sleep(3)
            if not ev(STUB, True):
                bad('the reader did not open')
                return
            time.sleep(1)
            ev('window.__stepMs = 120')
            label = ev(f'{HEAR}.textContent')
            if label != 'Listen through':
                bad(f'the transport reads {label!r}')
            ev(f'{HEAR}.click()')
            t0 = time.time()
            idx = -1
            while idx < N and time.time() - t0 < 60:
                idx = ev(NOW)
                time.sleep(0.05)
            if idx < N:
                bad(f'the plan reached line {idx}, not {N} (now: {ev("document.querySelector(\".rd-hear\").textContent")!r}, console: {ev("String(window.__err)")})')
                return
            if not ev(VIS):
                bad('the lit line is not on the page: the pages did not turn')
            if ev(BACK) is not True:
                bad('Back to the line shows while following')
            shot('following')
            ev("document.querySelector('.rd-stage').dispatchEvent(new Event('touchmove'))")
            ev("document.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true }))")
            time.sleep(1.0)
            if ev(BACK) is not False:
                bad('Back to the line did not show after turning away')
            if ev(VIS):
                bad('the page followed the line after the person turned away')
            shot('away')
            ev("document.querySelector('.rd-back-line').click()")
            time.sleep(0.4)
            if not ev(VIS):
                bad('Back to the line did not return to the line heard')
            if ev(BACK) is not True:
                bad('Back to the line stays after returning')
            shot('back')
            ev(f'{HEAR}.click()')
            time.sleep(0.4)
            if ev(f'{HEAR}.textContent') != 'Listen through':
                bad('Stop did not stop')
        except Exception as e:
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
