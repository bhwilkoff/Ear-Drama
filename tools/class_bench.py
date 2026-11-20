#!/usr/bin/env python3
"""Class bench (R3c section 8, T10-T12): the teacher flows on the web against a local Worker with a test teacher.

    python3 tools/class_bench.py                 # T10, T11, T12; exit 1 on any failed step
    python3 tools/class_bench.py --tests T10 --keep-frames

Production has no test accounts and none are made there, so this runs the Worker in this tree locally
(tools/local_worker.py, `wrangler dev --local` with a fresh D1) with the bench's own sign-in key (LOCAL_TEST_JWKS; the
Worker refuses every public host while it carries one). Two headless Chrome profiles are two devices: the teacher's
and a seat's. Every page is this working tree served locally with `?worker=http://localhost:PORT` (config.js; a deployed
page cannot name another Worker). Muted; the seat's microphone is the read bench's getUserMedia stub (a 160 Hz tone at
-66 dB, nothing heard). Nothing plays.

  T10  sign in as a test teacher (the shared client's own signIn with a minted token), make a class, paste 25 names,
       make a class production, cast it with Fill evenly and Save, Start a reading, switch it to Record; a seat joins
       on the second profile through the seat door, its microphone opens on its first line, the take arrives on the
       teacher's device; on the class page the take is in Review and the teacher presses Approve on it, then Again on a
       second take; the Worker's review rows say approved and again.
  T11  the seat profile ends its session and joins as another seat: none of the first seat's lines are tinted, the
       first seat's name is not shown, no take of the first seat's is counted on this device.
  T12  an under-13 class with no school consent: the seat's take is refused by the Worker, stays on the seat's device,
       and no take reaches the teacher.

Steps are judged from the DOM and the Worker's own answers, never from a trailing exit code. Frames (375 px pages are
not needed here: 600 px) go to --frames for the eyes. Report: docs/research/data/t7c/class-<tag>.json.
"""
import argparse
import json
import shutil
import sys
import threading
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import local_worker  # noqa: E402
from read_bench import REPO, serve_site  # noqa: E402
from webdrive import Browser  # noqa: E402

MIC_HOOK = r"""(() => {
  window.__logs = []; const l = console.log;
  console.log = (...a) => { if (a[0] === '[readdiag]') window.__logs.push(a.join(' ')); l.apply(console, a); };
  const e0 = console.error; console.error = (...a) => { window.__logs.push('error ' + a.map(x => (x && x.stack) || String(x)).join(' ').slice(0, 300)); e0.apply(console, a); };
  window.addEventListener('error', (e) => window.__logs.push('uncaught ' + e.message));
  window.addEventListener('unhandledrejection', (e) => window.__logs.push('rejection ' + ((e.reason && e.reason.stack) || e.reason)));
  Object.defineProperty(navigator, 'mediaDevices', { configurable: true, value: { enumerateDevices: async () => [],
    async getUserMedia() { const ctx = new AudioContext(); const osc = ctx.createOscillator(); osc.frequency.value = 160;
      const g = ctx.createGain(); g.gain.value = 0.0005; const dest = ctx.createMediaStreamDestination(); osc.connect(g); g.connect(dest);
      osc.start(); await ctx.resume(); window.__micOpens = (window.__micOpens || 0) + 1; return dest.stream; } } });
  window.confirm = () => true;
})();"""

NAMES = ["Ada", "Ben", "Cal", "Dee", "Eli", "Fay", "Gus", "Hal", "Ivy", "Jo", "Kit", "Lou", "Max", "Ned", "Oz", "Pip", "Quin", "Rae",
         "Sam", "Tam", "Uma", "Vic", "Wes", "Xan", "Yul"]


class Run:
    def __init__(self, frames):
        self.steps = []
        self.frames = frames

    def step(self, test, name, ok, **facts):
        self.steps.append(dict(test=test, step=name, ok=bool(ok), **facts))
        print(f"[{test}] {'ok  ' if ok else 'FAIL'} {name} {json.dumps(facts) if facts else ''}", flush=True)
        return ok


def wait(b, expr, timeout=30, every=0.5):
    t0 = time.time()
    last = None
    while time.time() - t0 < timeout:
        try:
            last = b.js(expr)
        except RuntimeError as e:  # a navigation in flight
            last = str(e)[:80]
        if last and last is not True or last is True:
            if last:
                return last
        time.sleep(every)
    return None


def browser(port, prof, mic=False):
    shutil.rmtree(prof, ignore_errors=True)
    b = Browser(port=port, profile=str(prof), headless=True)
    if mic:
        b.ws.call("Page.addScriptToEvaluateOnNewDocument", {"source": MIC_HOOK})
    else:
        b.ws.call("Page.addScriptToEvaluateOnNewDocument", {"source": "window.confirm = () => true;"})
    b.ws.call("Emulation.setDeviceMetricsOverride", {"width": 600, "height": 900, "deviceScaleFactor": 1, "mobile": False})
    time.sleep(2)  # a cold profile's first navigation is lost if it races Chrome's own about:blank
    return b


def worker_json(base, method, path, token=None, body=None):
    req = urllib.request.Request(base + path, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={**({"authorization": f"Bearer {token}"} if token else {}), **({"content-type": "application/json"} if body is not None else {})})
    try:
        r = urllib.request.urlopen(req, timeout=20)
        return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"null")


def sign_in(run, b, site, q, lw, sub, test):
    b.goto(f"{site}/?view=record{q}", settle=3)
    tok = lw.mint(sub)
    got = b.js(f"API.account.signIn('apple', {json.dumps(tok)}).then(s => !!(s && s.user_id), e => 'refused ' + (e.code || e.message))", timeout=30)
    run.step(test, "a test teacher signs in through the shared client", got is True, answer=got)
    s, sess = worker_json(lw.local_base, "POST", "/v1/auth/apple", body={"id_token": lw.mint(sub), "device": "bench"})
    return sess.get("access_token") if s == 200 else None


def make_class(run, b, site, q, name, under13, test):
    b.goto(f"{site}/?view=library&tab=dramas{q}", settle=3)
    ready = wait(b, "!!document.querySelector('input[aria-label=\"Class name\"]')", 40)
    if not ready:  # a cold profile can drop a navigation: once more, and say so
        run.step(test, "note: the library page did not draw in 40 s; navigated once more", True)
        b.goto(f"{site}/?view=library&tab=dramas{q}", settle=3)
        ready = wait(b, "!!document.querySelector('input[aria-label=\"Class name\"]')", 40)
    if not run.step(test, "the Classes box shows for a signed-in teacher", ready):
        return None
    b.js(f"""(() => {{ const i = document.querySelector('input[aria-label="Class name"]'); i.value = {json.dumps(name)};
      document.getElementById('class-under13').checked = {str(bool(under13)).lower()}; i.form.requestSubmit(); return true; }})()""")
    link = wait(b, f"""(() => {{ const a = [...document.querySelectorAll('a[href^="?class="]')].find(x => x.textContent === {json.dumps(name)}); return a ? a.getAttribute('href') : null; }})()""", 30)
    cid = link.split("=", 1)[1] if link else None
    code = b.js(f"""(() => {{ const a = [...document.querySelectorAll('a[href^="?class="]')].find(x => x.textContent === {json.dumps(name)});
      const row = a && a.closest('li'); const c = row && row.querySelector('.class-code'); return c ? c.textContent.replace(/\\s/g, '') : null; }})()""")
    run.step(test, f"Make a class ({'under 13' if under13 else '13 and over'})", bool(cid and code), class_id=cid, code=code)
    return (cid, code) if cid and code else None


def class_page(b, site, q, cid):
    b.goto(f"{site}/?class={cid}{q}", settle=3)
    return wait(b, "!!document.querySelector('textarea.cl-names')", 40)


def setup_class(run, b, site, q, lw, cid, test, names):
    if not run.step(test, "the class page opens", class_page(b, site, q, cid)):
        return None
    b.js(f"""(() => {{ const t = document.querySelector('textarea.cl-names'); t.value = {json.dumps(chr(10).join(names))}; t.form.requestSubmit(); return true; }})()""")
    n = wait(b, f"(() => {{ const n = document.querySelectorAll('.cl-remove').length; return n >= {len(names)} ? n : null; }})()", 40)
    run.step(test, f"{len(names)} seats from a pasted list", n == len(names), seats=n)
    script = b.js("""API.castableScripts().then(l => { const s = l.find(x => x.id === 'gut-7364') || l[0]; return s ? s.id : null; })""", timeout=40)
    b.js(f"""(() => {{ const s = document.querySelector('select[aria-label="Pick a play"]'); s.value = {json.dumps(script)}; s.dispatchEvent(new Event('change'));
      s.form.requestSubmit(); return true; }})()""")
    cast = wait(b, """(() => { const a = [...document.querySelectorAll('#cl-plays a.btn')].find(x => x.textContent === 'Cast'); return a ? a.getAttribute('href') : null; })()""", 40)
    pid = cast.split("cast=", 1)[1] if cast else None
    if not run.step(test, "a class production of a castable play", bool(pid), script=script, production=pid):
        return None
    b.goto(f"{site}/{cast}{q}", settle=3)
    filled = wait(b, """(() => { const f = [...document.querySelectorAll('button')].find(x => x.textContent === 'Fill evenly'); if (!f || f.disabled) return null; f.click(); return true; })()""", 40)
    saved = filled and wait(b, """(() => { const s = [...document.querySelectorAll('button')].find(x => x.textContent === 'Save'); if (!s || s.disabled) return null; s.click(); return true; })()""", 20)
    time.sleep(3)
    return pid if run.step(test, "cast with Fill evenly and Save", bool(saved)) else None


def start_reading(run, b, site, q, cid, test):
    class_page(b, site, q, cid)
    go = wait(b, """(() => { const g = [...document.querySelectorAll('button')].find(x => x.textContent === 'Start a reading'); if (!g || g.disabled) return null; g.click(); return true; })()""", 30)
    code = go and wait(b, "(() => { const m = /read-room=([A-Z0-9]+)/.exec(location.search); return m ? m[1] : null; })()", 30)
    run.step(test, "Start a reading", bool(code), room=code)
    if not code:
        return None
    click = """(() => { const d = document.querySelector('details.rr-menu'); if (d) d.open = true;
      const r = document.querySelector('input[name="rr-mode"][value="record"]'); if (!r) return null; if (!r.checked) r.click(); return true; })()"""
    checked = """(() => { const r = document.querySelector('input[name="rr-mode"][value="record"]'); return r && r.checked ? 'record' : null; })()"""
    mode = None
    for _ in range(3):  # the menu is repainted from each snapshot: a click before the first one lands on a node about to go
        if wait(b, click, 30):
            mode = wait(b, checked, 10)
        if mode:
            break
    run.step(test, "the teacher switches the reading to Record", mode == "record")
    return code


def seat_join(run, s, site, q, room, ccode, label, test):
    s.goto(f"{site}/?read-room={room}&seat={ccode}:{label}&readdiag=1&read-record=1&mute=1{q}", settle=4)
    # The join page asks for nothing but Join; a class room then asks for the class code, which the seat door fills.
    go = "(() => { const b = document.querySelector('.rr-go'); if (!b) return null; b.click(); return true; })()"
    if not wait(s, go, 20):  # a cold profile drops its first navigation (read_bench's trap too): once more, and say so
        run.step(test, "note: the join page did not draw in 20 s; navigated once more", True)
        s.goto(f"{site}/?read-room={room}&seat={ccode}:{label}&readdiag=1&read-record=1&mute=1{q}", settle=4)
        wait(s, go, 40)
    mine = wait(s, "(() => { const m = [...document.querySelectorAll('.rd-line.rd-mine')].map(x => x.id); return m.length ? m : null; })()", 40)
    seen = None if mine else s.js("({ url: location.search, text: document.body.innerText.slice(0, 400), logs: (window.__logs || []).slice(-6) })")
    run.step(test, f"seat {label} joins on the second device; its lines are tinted", bool(mine), lines=len(mine or []), first=(mine or [None])[0], **({'page': seen} if seen else {}))
    return mine or []


def take(run, s, line, test):
    """The seat's microphone opens on `line`; after four seconds the reader's own Stop ends the take."""
    opened = wait(s, f"(() => (window.__logs || []).some(x => x.includes('rec {line} ')))()", 30)
    time.sleep(4)
    stop = s.js("(() => { const b = [...document.querySelectorAll('.rr-rec button')].find(x => x.textContent === 'Stop'); if (!b) return false; b.click(); return true; })()")
    ended = wait(s, f"(() => (window.__logs || []).some(x => x.includes('take {line} end')))()", 20)
    run.step(test, f"the seat's microphone opens on {line}, Stop ends the take", bool(opened and ended), stop_pressed=stop)
    return bool(opened and ended)


def press_to(b, line, limit=200):
    for _ in range(limit):
        cur = b.js("(() => { const n = document.querySelector('.rd-line.rd-now'); return n ? n.id : null; })()")
        if cur == line:
            return True
        b.js("(() => { const n = document.querySelector('button.rr-next'); if (n && !n.hidden) n.click(); return true; })()")
        time.sleep(0.35)
    return False


def t10(run, lw, site, q, ports, sp):
    t = "T10"
    b = browser(ports[0], sp / "teacher", mic=False)
    s = browser(ports[1], sp / "seat", mic=True)
    out = {}
    try:
        token = sign_in(run, b, site, q, lw, "bench-teacher-t10", t)
        made = make_class(run, b, site, q, "Bench T10", False, t)
        if not made:
            return out
        cid, ccode = made
        pid = setup_class(run, b, site, q, lw, cid, t, NAMES)
        if not pid:
            return out
        room = start_reading(run, b, site, q, cid, t)
        if not room:
            return out
        b.screenshot(str(run.frames / "class-T10-teacher-room.png"))
        mine = seat_join(run, s, site, q, room, ccode, NAMES[0], t)
        out.update(room=room, class_id=cid, code=ccode, production=pid, seat_lines=mine[:5])
        if not mine:
            return out
        time.sleep(8)  # Start recording: five seconds of room tone on the seat's device
        reached = press_to(b, mine[0])
        run.step(t, "the teacher's Next reaches the seat's first line", reached, line=mine[0])
        take(run, s, mine[0], t)
        run.step(t, "the seat's microphone opened on its line once", s.js(f"(window.__logs || []).filter(x => x.includes('rec {mine[0]} ')).length") == 1)
        time.sleep(4)
        if len(mine) > 1:
            press_to(b, mine[1])
            take(run, s, mine[1], t)
            time.sleep(6)
        s.screenshot(str(run.frames / "class-T10-seat.png"))
        st, prod = worker_json(lw.local_base, "GET", f"/v1/plays/productions/{pid}", token=token)
        takes = (prod or {}).get("takes") or []
        run.step(t, "the take arrives: the Worker holds its row in the class production", len(takes) >= 1, takes=len(takes), status=st)
        class_page(b, site, q, cid)
        rows = wait(b, "(() => { const n = document.querySelectorAll('.cl-review-row').length; return n || null; })()", 30)
        run.step(t, "the take is in the class page's Review", bool(rows), rows=rows)
        b.screenshot(str(run.frames / "class-T10-review.png"))
        appr = b.js("""(() => { const r = document.querySelector('.cl-review-row'); const ok = r && [...r.querySelectorAll('button')].find(x => x.textContent === 'Approve'); if (!ok) return false; ok.click(); return true; })()""")
        time.sleep(2)
        again = b.js("""(() => { const r = document.querySelector('.cl-review-row'); const a = r && [...r.querySelectorAll('button')].find(x => x.textContent === 'Again'); if (!a) return false; a.click(); return true; })()""")
        time.sleep(2)
        st, prod = worker_json(lw.local_base, "GET", f"/v1/plays/productions/{pid}", token=token)
        states = sorted({(r.get("state") if isinstance(r, dict) else r) for r in ((prod or {}).get("reviews") or {}).values()}) if isinstance((prod or {}).get("reviews"), dict) else (prod or {}).get("reviews")
        run.step(t, "Approve, then Again on the next take: the Worker's reviews say so", appr and again and states and "approved" in json.dumps(states) and "again" in json.dumps(states),
                 approve_pressed=appr, again_pressed=again, reviews=states)
        out["review_states"] = states
        return out
    finally:
        out["seat_logs"] = s.js("window.__logs || []") if s else []
        for x in (b, s):
            x.close()


def t11(run, lw, site, q, ports, sp, ctx):
    t = "T11"
    b = browser(ports[0], sp / "teacher11", mic=False)
    s = browser(ports[1], sp / "seat11", mic=True)
    try:
        sign_in(run, b, site, q, lw, "bench-teacher-t11", t)
        made = make_class(run, b, site, q, "Bench T11", False, t)
        if not made:
            return {}
        cid, ccode = made
        if not setup_class(run, b, site, q, lw, cid, t, NAMES[:4]):
            return {}
        room = start_reading(run, b, site, q, cid, t)
        if not room:
            return {}
        a_lines = seat_join(run, s, site, q, room, ccode, NAMES[0], t)
        time.sleep(8)
        if a_lines:
            press_to(b, a_lines[0])
            take(run, s, a_lines[0], t)
            time.sleep(4)
        # The seat ends its session (the reader's Close leaves the room), then the same device joins as another seat.
        closed = s.js("(() => { const c = document.querySelector('button[aria-label=\"Close\"]'); if (!c) return false; c.click(); return true; })()")
        time.sleep(2)
        run.step(t, "seat A ends the session with Close", closed)
        b_lines = seat_join(run, s, site, q, room, ccode, NAMES[1], t)
        if not (a_lines and b_lines):
            run.step(t, "T11 needs both seats joined: not judged", False)
            return dict(a_lines=a_lines, b_lines=b_lines)
        s.screenshot(str(run.frames / "class-T11-seat-b.png"))
        shown = s.js(f"""(() => ({{ text: (() => {{ const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); const hits = [];
            for (let n = w.nextNode(); n; n = w.nextNode()) {{ const e = n.parentElement;
              if (new RegExp('\\b' + {json.dumps(NAMES[0])} + '\\b').test(n.nodeValue) && !e.closest('.rd-line') && e && e.checkVisibility() && !e.closest('.rr-fact')) hits.push(e.className + ': ' + n.nodeValue.slice(0, 60)); }}
            return hits; }})(),
          tinted: [...document.querySelectorAll('.rd-line.rd-mine')].map(x => x.id),
          count: (document.querySelector('.rr-rec') || {{ innerText: '' }}).innerText }}))()""")
        overlap = sorted(set(shown["tinted"]) & set(a_lines))
        run.step(t, "as seat B: none of seat A's lines are tinted", not overlap, overlap=overlap[:5])
        run.step(t, "as seat B: seat A's name is nowhere but the room's own fact (who reads the line at the cursor, shown to every member)", not shown["text"], visible=shown["text"][:5])
        run.step(t, "as seat B: no take of seat A's is counted on this device", "on this device" not in shown["count"], rec_row=shown["count"])
        return dict(a_lines=a_lines[:5], b_lines=b_lines[:5], shown=shown)
    finally:
        for x in (b, s):
            x.close()


def t12(run, lw, site, q, ports, sp):
    t = "T12"
    b = browser(ports[0], sp / "teacher12", mic=False)
    s = browser(ports[1], sp / "seat12", mic=True)
    try:
        token = sign_in(run, b, site, q, lw, "bench-teacher-t12", t)
        made = make_class(run, b, site, q, "Bench T12", True, t)
        if not made:
            return {}
        cid, ccode = made
        pid = setup_class(run, b, site, q, lw, cid, t, NAMES[:3])
        if not pid:
            return {}
        room = start_reading(run, b, site, q, cid, t)
        if not room:
            return {}
        # The teacher's device defaults to One microphone in an under-13 class; this test is the seat's own microphone.
        b.js("""(() => { const d = document.querySelector('details.rr-menu'); if (d) d.open = true;
          const c = [...document.querySelectorAll('.rr-menu-body label.check')].find(l => l.textContent.includes('Record every line here'));
          const i = c && c.querySelector('input'); if (i && i.checked) i.click(); return true; })()""")
        mine = seat_join(run, s, site, q, room, ccode, NAMES[0], t)
        time.sleep(8)
        if not mine:
            return {}
        press_to(b, mine[0])
        rec = take(run, s, mine[0], t)
        time.sleep(8)
        refused = s.js("(window.__logs || []).filter(x => x.includes('refused') || x.includes('consent')).slice(-3)")
        kept = s.js("""PlaysUI.openStore().then(st => { const p = st.productions.find(x => x.room); return p ? p.takes.length : 0; })""", timeout=30)
        st, prod = worker_json(lw.local_base, "GET", f"/v1/plays/productions/{pid}", token=token)
        run.step(t, "the take stays on the seat's device", (kept or 0) >= 1, takes_on_device=kept)
        run.step(t, "no take reaches the Worker or the teacher", not ((prod or {}).get("takes") or []), worker_takes=len((prod or {}).get("takes") or []), status=st)
        s.screenshot(str(run.frames / "class-T12-seat.png"))
        return dict(refusals=refused, kept=kept)
    finally:
        for x in (b, s):
            x.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tests", default="T10,T11,T12")
    ap.add_argument("--port", type=int, default=8799)
    ap.add_argument("--tag", default=time.strftime("%Y%m%d-%H%M%S"))
    ap.add_argument("--out", default=str(REPO / "docs/research/data/t7c"))
    ap.add_argument("--frames", default=str(REPO / "docs/research/design/img/t7c"))
    a = ap.parse_args()
    out, frames = Path(a.out), Path(a.frames)
    out.mkdir(parents=True, exist_ok=True)
    frames.mkdir(parents=True, exist_ok=True)
    sp = Path("/tmp/class-bench")
    run = Run(frames)
    lw = local_worker.LocalWorker(a.port, scratch=sp / "worker", test_auth=True, log=out / f"class-{a.tag}-worker.log").start()
    srv, site = serve_site()
    q = f"&worker={lw.local_base}&mute=1"
    report = dict(tag=a.tag, worker=lw.local_base, site=site, tests={})
    try:
        tests = a.tests.split(",")
        if "T10" in tests:
            report["tests"]["T10"] = t10(run, lw, site, q, (9801, 9802), sp)
        if "T11" in tests:
            report["tests"]["T11"] = t11(run, lw, site, q, (9803, 9804), sp, report["tests"].get("T10"))
        if "T12" in tests:
            report["tests"]["T12"] = t12(run, lw, site, q, (9805, 9806), sp)
    finally:
        report["steps"] = run.steps
        report["worker_stopped"] = lw.stop()
        srv.shutdown()
        (out / f"class-{a.tag}.json").write_text(json.dumps(report, indent=1))
    failed = [x for x in run.steps if not x["ok"]]
    print(f"[class] {len(run.steps) - len(failed)} of {len(run.steps)} steps ok; worker {'stopped' if report['worker_stopped'] else 'STILL RUNNING'}; report {out / ('class-' + a.tag + '.json')}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
