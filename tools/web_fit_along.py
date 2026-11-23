#!/usr/bin/env python3
"""Frames and gate for the read-along (PLAYS-DESIGN 2.11 rewritten 2026-11-23; WEB-DESIGN 4.16a): the reader opened
in read-along mode over a stubbed store, with `speechSynthesis` replaced by a stub that sends `boundary` events
for each word of the string it is given (no audio, no device voice), at 375 and 1440 px.

The real StandInVoice, Along and Reader run. The gate fails unless: the reading starts at once; the word heard is
marked (CSS Custom Highlight) and is a printed word of the line lit, and it moves; the page turns itself to the
line and to the word (the lit line and the marked word are inside the page or spread); Pause holds the line (still
lit, nothing heard) and Play restarts that line; Next and Previous move the line; Speed changes the next line's
rate and is kept in localStorage; Space plays and pauses; a touch turns the turning off and shows Back to the line,
which returns to it; Stop ends the light and gives the bar back.

    python3 tools/web_fit_along.py --shots DIR --widths 375,1440
"""
import base64, json, os, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import web_run  # noqa: E402

LIB = os.path.join(ROOT, 'catalog', 'out', 'plays-library')
BUNDLE = os.path.join(ROOT, 'catalog', 'plays', 'castable-scripts.json')


def pick_script():
    """A script with several parts and long speeches, from the data (never a pinned title)."""
    def ok(s):
        return len([r for r in s['roles'] if r['lines'] >= 8]) >= 3 and len(s['lines']) >= 60
    if os.path.exists(os.path.join(LIB, 'index.json')):
        for row in json.load(open(os.path.join(LIB, 'index.json')))['plays']:
            s = json.load(open(os.path.join(LIB, row['path'])))['scripts'][0]
            if ok(s):
                return s
    for s in json.load(open(BUNDLE))['scripts']:
        if ok(s):
            return s
    raise SystemExit('no script with three speaking parts in the data')


# A speech stub: each utterance sends a `boundary` event per printed word (charIndex and charLength in the string given),
# then `end`; cancel() sends an error, as Chrome does. Nothing is played.
VOICE = r"""(() => {
  const V = (name, lang) => ({ name, voiceURI: name, lang, localService: true, default: false });
  const all = [V('Samantha', 'en-US'), V('Daniel', 'en-GB'), V('Ava (Premium)', 'en-US'), V('Zoe (Enhanced)', 'en-US')];
  window.__spoken = []; window.__cur = null; window.__err = [];
  window.addEventListener('error', (e) => window.__err.push(String(e.message)));
  window.addEventListener('unhandledrejection', (e) => window.__err.push(String(e.reason)));
  const ms = () => Number(window.__wordMs || 90);
  const synth = {
    getVoices: () => all.slice(),
    speak(u) {
      const rec = { text: u.text, rate: u.rate, volume: u.volume, done: false };
      window.__spoken.push(rec);
      const words = [...u.text.matchAll(/[^\s—–]+/g)];
      let i = 0;
      const tick = () => {
        if (window.__cur !== rec || rec.done) return;
        if (i < words.length) {
          const w = words[i++];
          if (u.onboundary) u.onboundary({ name: 'word', charIndex: w.index, charLength: w[0].length });
          rec.t = setTimeout(tick, ms() / (u.rate || 1));
        } else { rec.done = true; window.__cur = null; if (u.onend) u.onend({}); }
      };
      window.__cur = rec; rec.u = u;
      rec.t = setTimeout(tick, 30);
    },
    cancel() { const r = window.__cur; window.__cur = null; if (r && !r.done) { r.done = true; clearTimeout(r.t); if (r.u.onerror) setTimeout(() => r.u.onerror({ error: 'interrupted' }), 0); } },
    pause() {}, resume() {}, speaking: false, pending: false, addEventListener() {}, removeEventListener() {},
  };
  Object.defineProperty(window, 'speechSynthesis', { value: synth, configurable: true });
  window.SpeechSynthesisUtterance = function (text) { this.text = text; };
  try { localStorage.removeItem('ed.along.speed'); } catch (e) {}
})();"""

OPEN = r"""(async () => {
  const script = await (await fetch('along-script.json')).json();
  const store = { production: () => ({ id: 'x', title: 'T', takes: [], chosen: {}, roomTone: [] }), readTake: async () => new Uint8Array() };
  const body = document.getElementById('reader-body');
  document.querySelectorAll('.view').forEach(v => { v.hidden = v.id !== 'view-reader'; });
  window.__h = Reader.open(body, script, { along: { production: 'x', store }, onClose() {} });
  return script.lines.length;
})()"""
MARKS = ("(() => { const out = []; if (!CSS.highlights) return out; for (const [n, h] of CSS.highlights) for (const r of h) out.push([n, r.toString()]); return out; })()")
NOW = "(() => { const n = document.querySelector('.rd-now'); return n ? [...document.querySelectorAll('.rd-line')].indexOf(n) : -1; })()"
NOWTEXT = "(() => { const n = document.querySelector('.rd-now'); return n ? n.textContent : null; })()"
PAGE = "(() => { const p = document.querySelector('.rd-page'); const m = p ? /^\\d+/.exec(p.textContent) : null; return m ? m[0] : ''; })()"
VIS = ("(() => { const n = document.querySelector('.rd-now'); const cr = document.querySelector('.rd-clip').getBoundingClientRect();"
       " return !!n && [...n.getClientRects()].some(r => r.right > cr.left + 2 && r.left < cr.right - 2 && r.bottom > cr.top && r.top < cr.bottom); })()")
WORDVIS = ("(() => { if (!CSS.highlights) return null; const cr = document.querySelector('.rd-clip').getBoundingClientRect();"
           " for (const [n, h] of CSS.highlights) for (const r of h) { const q = r.getClientRects()[0]; if (q) return q.right > cr.left + 2 && q.left < cr.right - 2; } return null; })()")
TIME = "document.querySelector('.rd-speed') ? document.querySelector('.rd-speed').value : null"
BACK = "document.querySelector('.rd-back-line').hidden"
BAR = "!document.querySelector('.rd-transport').hidden"
PLAYLAB = "document.querySelector('.rd-t-play').getAttribute('aria-label')"
SPOKEN = "window.__spoken.length"


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
    print(f'script {script["id"]} ({len(script["lines"])} lines)')
    problems = []

    def run(w, dark):
        tag = f'{w} {"dark" if dark else "light"}'
        h = 900 if w > 600 else 760
        profile = tempfile.mkdtemp(prefix='fit-along-chrome-')
        proc = None
        try:
            proc, ws = web_run._launch(profile)
            cdp = web_run.CDP(ws)
            cdp.call('Page.enable')
            cdp.call('Page.addScriptToEvaluateOnNewDocument', {'source': VOICE})
            cdp.call('Emulation.setDeviceMetricsOverride', {'width': w, 'height': h, 'deviceScaleFactor': 1, 'mobile': w < 600})
            cdp.call('Emulation.setEmulatedMedia', {'features': [{'name': 'prefers-color-scheme', 'value': 'dark' if dark else 'light'}, {'name': 'prefers-reduced-motion', 'value': 'reduce'}]})
            ev = lambda js, aw=False: cdp.call('Runtime.evaluate', {'expression': js, 'returnByValue': True, 'awaitPromise': aw, 'userGesture': True}, timeout=30).get('result', {}).get('value')
            bad = lambda m: problems.append(f'{tag}: {m}')

            def shot(name):
                if shots:
                    png = cdp.call('Page.captureScreenshot', {'format': 'png'}, timeout=30)
                    open(os.path.join(shots, f'along-{name}-{"dark" if dark else "light"}-{w}.png'), 'wb').write(base64.b64decode(png['data']))

            def until(js, want, secs=40):
                t0 = time.time()
                while time.time() - t0 < secs:
                    v = ev(js)
                    if want(v):
                        return v
                    time.sleep(0.04)
                return ev(js)

            cdp.call('Page.navigate', {'url': f'http://127.0.0.1:{port}/?mute=1'}, timeout=30)
            time.sleep(3)
            if not ev(OPEN, True):
                bad('the reader did not open')
                return
            ev('window.__wordMs = 30')
            # 1. It starts at once: a transport, a line lit, a word marked inside it.
            marks = until(MARKS, lambda m: bool(m), 20)
            if not marks:
                bad(f'no word was marked (errors: {ev("String(window.__err)")})')
                return
            if not ev(BAR):
                bad('the transport did not take the bar')
            if ev(PLAYLAB) != 'Pause':
                bad(f'the play button reads {ev(PLAYLAB)!r} while reading')
            line = ev(NOWTEXT) or ''
            word = marks[0][1]
            if word not in line:
                bad(f'the word marked ({word!r}) is not in the line lit')
            if ev(f'window.__spoken[0].volume') != 0:
                bad('the stub voice was not muted (?mute=1)')
            shot('word-a')
            first = word
            seen = {word}
            t0 = time.time()
            while time.time() - t0 < 6 and len(seen) < 4:
                m = ev(MARKS)
                if m:
                    seen.add(m[0][1])
                time.sleep(0.03)
            if len(seen) < 3:
                bad(f'the word did not move (saw {sorted(seen)})')
            shot('word-b')
            # 2. Pages turn themselves: run until the page label changes, the lit line and the word stay on the page.
            page0 = ev(PAGE)
            changed = until(PAGE, lambda p: p != page0, 120)
            if changed == page0:
                bad(f'the page never turned by itself (line {ev(NOW)}, page {changed})')
            time.sleep(0.5)
            if not ev(VIS):
                bad('the lit line is not on the page after a turn')
            if ev(WORDVIS) is False:
                bad('the word marked is outside the page after a turn')
            if ev(BACK) is not True:
                bad('Back to the line shows while following')
            shot('turned')
            if os.environ.get('ALONG_DEBUG'):
                print(ev('JSON.stringify(window.__dbg)'))
                print(tag, 'turned: page', ev(PAGE), 'line', ev(NOW), 'word visible', ev(WORDVIS), 'line visible', ev(VIS))
                print(ev("(() => { const f = document.querySelector('.rd-flow'); const c = document.querySelector('.rd-clip').getBoundingClientRect(); let q = null; for (const [n, h] of CSS.highlights) for (const r of h) q = q || r.getClientRects()[0]; const l = document.querySelector('.rd-now'); return JSON.stringify({ flowLeft: f.getBoundingClientRect().left, tf: getComputedStyle(f).transform, clip: [c.left, c.right], word: q && [q.left, q.right], lineRects: [...l.getClientRects()].map(r => [Math.round(r.left), Math.round(r.right)]), lineChars: l.textContent.length, label: document.querySelector('.rd-page').textContent, inline: f.style.transform, lineIdx: [...document.querySelectorAll('.rd-line')].indexOf(l), nlines: document.querySelectorAll('.rd-line').length }); })()"))
            # 3. Pause holds the line.
            if os.environ.get('ALONG_DEBUG'):
                print(tag, 'before pause: page', ev(PAGE), 'line', ev(NOW))
            lit = ev(NOW)
            ev("document.querySelector('.rd-t-play').click()")
            time.sleep(0.4)
            if ev(PLAYLAB) != 'Play':
                bad('Pause did not become Play')
            n = ev(SPOKEN)
            time.sleep(0.5)
            if ev(SPOKEN) != n or ev('window.__cur !== null'):
                bad('something was still being said after Pause')
            if ev(NOW) != lit:
                bad('Pause moved the line')
            if ev(MARKS):
                bad('a word stays marked while paused')
            shot('paused')
            # 4. Play starts that line again from its beginning.
            ev("document.querySelector('.rd-t-play').click()")
            time.sleep(0.3)
            spoken = ev('window.__spoken.slice(-2).map(s => s.text)')
            if ev(NOW) != lit or not spoken or ev('window.__spoken.length') <= n:
                bad('Play did not start the held line again')
            # 5. Next and Previous.
            ev("document.querySelector('.rd-t-next').click()")
            time.sleep(0.3)
            nxt = ev(NOW)
            if nxt <= lit:
                bad(f'Next did not move on ({lit} -> {nxt})')
            ev("document.querySelector('.rd-t-prev').click()")
            time.sleep(0.3)
            if ev(NOW) >= nxt:
                bad('Previous did not move back')
            # 6. Speed: kept, and the next line at the new rate.
            ev("(() => { const s = document.querySelector('.rd-speed'); s.value = '2'; s.dispatchEvent(new Event('change')); })()")
            if ev("localStorage.getItem('ed.along.speed')") != '2':
                bad('the speed was not kept (ed.along.speed)')
            ev("document.querySelector('.rd-t-next').click()")
            time.sleep(0.4)
            rate = ev('window.__spoken.slice(-1)[0].rate')
            if not rate or rate < 1.9:
                bad(f'the next line was not read at 2x (rate {rate})')
            ev("(() => { const s = document.querySelector('.rd-speed'); s.value = '1'; s.dispatchEvent(new Event('change')); })()")
            # 7. Space plays and pauses.
            ev("document.querySelector('.rd-stage').focus(); document.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true }))")
            time.sleep(0.3)
            if ev(PLAYLAB) != 'Play':
                bad('Space did not pause')
            ev("document.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true }))")
            time.sleep(0.3)
            if ev(PLAYLAB) != 'Pause':
                bad('Space did not play')
            # 8. A touch turns the turning off; Back to the line returns.
            ev("document.querySelector('.rd-stage').dispatchEvent(new Event('touchmove'))")
            ev("document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Home', bubbles: true }))")
            time.sleep(0.6)
            if ev(BACK) is not False:
                bad('Back to the line did not show after turning away')
            if ev(VIS):
                bad(f'the page followed the line after the person turned away (page {ev(PAGE)!r}, line {ev(NOW)}, away {ev(BACK)})')
            shot('away')
            ev("document.querySelector('.rd-back-line').click()")
            time.sleep(0.5)
            if not ev(VIS):
                bad('Back to the line did not return to the line heard')
            if ev(BACK) is not True:
                bad('Back to the line stays after returning')
            # 9. Stop ends the light and gives the bar back.
            ev("document.querySelector('.rd-t-stop').click()")
            time.sleep(0.4)
            if ev(NOW) != -1 or ev(MARKS) or ev(BAR):
                bad('Stop left the light or the transport')
            if ev("document.querySelector('.rd-hear').textContent.trim()") != 'Read along' and w >= 560:
                bad('the bar did not give Read along back')
            shot('stopped')
            errs = ev('window.__err')
            if errs:
                bad(f'errors: {errs}')
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
