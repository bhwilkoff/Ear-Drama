#!/usr/bin/env python3
"""Own scripts shared (PLAYS-DESIGN 13 items 11 to 16, WEB-DESIGN 4.21 item 10; R4-5): two real Chrome profiles at a time
against a LOCAL Worker, every page at 320, 375, 768 and 1440 px in light and dark.

    nice -n 15 python3 tools/own_share_bench.py                      # all; exit 1 on any failed step
    nice -n 15 python3 tools/own_share_bench.py --tests share,class  # some
    nice -n 15 python3 tools/own_share_bench.py --shots DIR --widths 375 --themes light

The Worker in this tree runs under `wrangler dev --local` with a fresh D1 (tools/local_worker.py); the site is this tree,
served here with `?worker=`. Sign-in is the bench's own key, which the Worker refuses on any public host. Nothing is
deployed, nothing plays, and no real microphone opens (class_bench.py's stub). What the owner's operator route would do
(removing a script, answering a report) is done to the local database, since that route takes GitHub's own token.

  share   signed out: "Sharing needs an account." and who can read it; a script added in the page and shared: the text in
          the database is the bytes that were hashed; Publish absent with its reason; the script frozen (its parts page is
          its page), Edit a copy; offline, a full server and a never-passing refusal (words, Try again, what is undone);
          an invite opened by a person with no account and no script; a text that did not arrive whole; the part taken, a
          take sent, and its details received by the director (x-take, read across origins); a full disk on joining.
  room    Read together from the production; a person with no account and a screen fetch the script with their member
          keys; a take recorded in the room reaches the leader with its details.
  report  Report script (Copyright): hidden from the reporter, "This script has been reported." on Invite and to the
          invite's holder, members going on.
  remove  the owner's removal: the director's page, a member's, an invite, and the reading each say so.
  class   a teacher's own script in Pick a play; a seat's parts from it; the board; a class reading a seat joins; the
          class export with the lines; a script owed, then sent; a removed one at the seat.

Every step is judged from the page and from the Worker's own answers. Each page drawn is checked for a sideways scroll, a
control under 44 px and one past the edge. Negative controls (2026-11-24, each run): js/plays-share.js `fit` always false
fails "an invite opened by a person with no account"; `.own-share .btn { min-height: 30px }` fails "under 44 px"; the
Worker's `Access-Control-Expose-Headers` without x-take fails "the director received the take with its details".
"""
import argparse
import base64
import json
import shutil
import sqlite3
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import local_worker  # noqa: E402
from class_bench import MIC_HOOK, Run, browser, make_class, wait, worker_json  # noqa: E402
from read_bench import REPO, serve_site  # noqa: E402

SP = Path("/tmp/own-share-bench")

EXTRA = r"""(() => {
  window.__asked = []; window.confirm = (t) => { window.__asked.push(t); return true; };
  window.__errors = []; addEventListener('error', (e) => window.__errors.push(String(e.message)));
  addEventListener('unhandledrejection', (e) => window.__errors.push(String((e.reason && e.reason.stack) || e.reason)));
  window.__copied = null; if (navigator.clipboard) navigator.clipboard.writeText = async (t) => { window.__copied = t; };
  navigator.share = undefined;
  window.__calls = []; window.__fail = null;
  const f0 = window.fetch;
  window.fetch = async (u, o = {}) => {
    const url = String(u && u.url || u), method = (o.method || 'GET');
    if (/\/v1\//.test(url)) {
      window.__calls.push(method + ' ' + url.replace(/^https?:\/\/[^/]+/, ''));
      const f = window.__fail && window.__fail.find(x => method + ' ' + url && new RegExp(x.match).test(method + ' ' + url) && (x.times === undefined || x.times-- > 0));
      if (f) {
        if (f.offline) throw new TypeError('Failed to fetch');
        if (f.status) return new Response(JSON.stringify({ error: f.error, detail: f.detail }), { status: f.status, headers: { 'content-type': 'application/json' } });
        if (f.damage) { const r = await f0(u, o); const t = await r.text(); return new Response(t.replace('a', 'o'), { status: r.status, headers: r.headers }); }
      }
    }
    const r = await f0(u, o);
    // What a page on this origin is let read of a take that arrived: its fields are x-take's.
    if (/\/takes\/inbox$/.test(url)) { const x = r.headers.get('x-take'); window.__inbox.push({ status: r.status, take: x ? JSON.parse(x) : null }); }
    return r;
  };
  window.__inbox = [];
  window.__full = false;
  for (const m of ['put', 'add']) { const was = IDBObjectStore.prototype[m];
    IDBObjectStore.prototype[m] = function (...a) { if (window.__full) throw new DOMException('full', 'QuotaExceededError'); return was.apply(this, a); }; }
  window.__saved = [];
  const make = URL.createObjectURL.bind(URL);
  URL.createObjectURL = (b) => { if (b && b.type === 'application/json') b.text().then(t => window.__saved.push(t)); return make(b); };
})();"""

# A take of the first speaking line, written as the recorder writes one.
TAKE = """(async () => { const s = await PlaysUI.openStore(); const p = s.production(%s); const script = await s.script(p);
  const l = script.lines.find(x => x.kind === 'speech');
  const file = await s.writeTake({ samples: new Float32Array(4800), sampleRate: 48000 }, p, l.id);
  await s.save(PlaysCore.addTake(s.production(p.id), { id: PlaysCore.uuid(), lineID: l.id, part: PlaysCore.linePart(l), file, created: PlaysCore.now(), frames: 4800, sampleRate: 48000, capture: 'direct', heard: {}, peak: 0.1, bleed: false })); return l.id; })()"""

FIT = r"""JSON.stringify((() => {
  const out = { sideways: document.documentElement.scrollWidth > innerWidth, small: [], over: [], clipped: [] };
  const d = document.querySelector('dialog[open]');
  const root = d || [...document.querySelectorAll('main > section, #main-content section.view')].find(v => !v.hidden && v.getBoundingClientRect().height > 0) || document.body;
  for (const b of root.querySelectorAll('button, a.btn, input, select, textarea')) {
    const r = b.getBoundingClientRect();
    if (!r.width || !r.height || ['checkbox', 'radio', 'file'].includes(b.type) || b.closest('.sr-only, [inert]')) continue;
    const t = (b.getAttribute('aria-label') || b.textContent || b.id || b.name || '').trim().slice(0, 30);
    // The cast sheet's own cards and chips keep the sizes their rules give them (WEB-DESIGN 4.10b); what this batch drew is judged.
    if (r.height < 43.5 && b.closest('.own-share, .share-box, .os-own, .cl-own, .report-form, .os, dialog, .state, .take-form, .parts-prod') && !b.closest('.pl-part')) out.small.push(t + ' ' + Math.round(r.height));
    if (r.right > innerWidth + 1 || r.left < -1) out.over.push(t);
    if (b.scrollWidth > b.clientWidth + 1 && /^(BUTTON|A)$/.test(b.tagName) && getComputedStyle(b).overflow === 'hidden') out.clipped.push(t);
  }
  return out; })())"""

CLICK = "(() => {{ const b = [...document.querySelectorAll({sel})].filter(x => !x.disabled && x.checkVisibility()).find(x => x.textContent.trim() === {text} || x.getAttribute('aria-label') === {text}); if (!b) return false; b.click(); return true; }})()"


def click(b, text, sel="button, a", secs=20):
    return wait(b, CLICK.format(sel=json.dumps(sel), text=json.dumps(text)), secs, 0.3)


def says(b, words, secs=20):
    return wait(b, f"(() => {{ const v = document.body.innerText.replace(/\\u2019/g, \"'\"); return v.includes({json.dumps(words)}); }})()", secs, 0.3)


def has(b, text, sel="button, a"):
    return b.js(f"[...document.querySelectorAll({json.dumps(sel)})].some(x => x.checkVisibility() && x.textContent.trim() === {json.dumps(text)})")


class Bench:
    def __init__(self, a):
        self.a = a
        self.run = Run(Path(a.shots))
        self.widths = [int(x) for x in a.widths.split(",")]
        self.themes = a.themes.split(",")
        self.lw = local_worker.LocalWorker(a.port, scratch=SP / "worker", test_auth=True, log=SP / "worker.log").start()
        self.srv, self.site = serve_site()
        self.q = f"&worker={self.lw.local_base}&mute=1"
        self.open = []
        self.port = 9850
        self.fits = 0
        self.frames = 0

    def step(self, t, name, ok, **facts):
        return self.run.step(t, name, ok, **facts)

    def device(self, name, mic=False):
        self.port += 1
        b = browser(self.port, SP / name, mic=mic)
        b.name = name
        if not mic:
            b.ws.call("Page.addScriptToEvaluateOnNewDocument", {"source": EXTRA})
        else:
            b.ws.call("Page.addScriptToEvaluateOnNewDocument", {"source": EXTRA})
        self.size(b, 600)
        self.open.append(b)
        return b

    def close(self, *bs):
        for b in bs:
            b.close()
            if b in self.open:
                self.open.remove(b)

    def size(self, b, w, dark=False):
        b.ws.call("Emulation.setDeviceMetricsOverride", {"width": w, "height": 900 if w >= 768 else 760, "deviceScaleFactor": 1, "mobile": w < 600})
        b.ws.call("Emulation.setEmulatedMedia", {"features": [{"name": "prefers-color-scheme", "value": "dark" if dark else "light"}]})

    def go(self, b, path, settle=2.0):
        path = path or "/"
        hash_ = ""
        if "#" in path:
            path, hash_ = path.split("#", 1)
            hash_ = "#" + hash_
        b.js("location.href = 'about:blank'") if hash_ else None
        b.goto(f"{self.site}{path}{'&' if '?' in path else '?'}{self.q.lstrip('&')}{hash_}", settle=settle)
        if not wait(b, "typeof PlaysUI !== 'undefined' && document.readyState === 'complete'", 20):
            b.goto(f"{self.site}{path}{'&' if '?' in path else '?'}{self.q.lstrip('&')}{hash_}", settle=settle + 2)

    def look(self, t, b, name, at=".own-share, .cl-own, .os-own", full=True):
        """The page as it stands, at each width and theme: checked, and a frame of each."""
        self.fits += 1
        bad = []
        for dark in [x == "dark" for x in self.themes]:
            for w in self.widths:
                self.size(b, w, dark)
                time.sleep(0.45)
                s = json.loads(b.js(FIT))
                for k in ("sideways", "small", "over", "clipped"):
                    if s[k]:
                        bad.append(f"{w}{'d' if dark else 'l'} {k} {s[k] if s[k] is not True else ''}")
                # What this batch drew is what the frame shows.
                b.js("(() => { const n = document.querySelector(" + json.dumps(at) + "); if (n && !document.querySelector('dialog[open]')) n.scrollIntoView({ block: 'center' }); return 1; })()") if full else None
                time.sleep(0.15)
                b.screenshot(str(Path(self.a.shots) / f"{t}-{name}-{w}-{'dark' if dark else 'light'}.png"))
                self.frames += 1
        self.size(b, 600)
        self.step(t, f"{name}: no sideways scroll, nothing under 44 px or past the edge", not bad, **({"bad": bad[:6]} if bad else {}))
        errs = b.js("window.__errors || []")
        if errs:
            self.step(t, f"{name}: no page error", False, errors=errs[:3])

    def sign_in(self, t, b, sub, over13=True):
        got = b.js(f"API.account.signIn('apple', {json.dumps(self.lw.mint(sub))}).then(s => !!(s && s.user_id), e => 'refused ' + (e.code || e.message))", timeout=30)
        if over13:
            b.js("localStorage.setItem('ed.over13', '1')")
        self.step(t, f"{sub} signs in through the shared client", got is True, answer=got)
        return worker_json(self.lw.local_base, "POST", "/v1/auth/apple", body={"id_token": self.lw.mint(sub), "device": "bench"})[1].get("access_token")

    def db(self, sql, *args):
        path = next((SP / "worker" / "state").rglob("miniflare-D1DatabaseObject/*.sqlite"))
        for p in (SP / "worker" / "state").rglob("miniflare-D1DatabaseObject/*.sqlite"):
            c = sqlite3.connect(p, timeout=20)
            try:
                c.execute("SELECT 1 FROM play_scripts LIMIT 1")
                path = p
                c.close()
                break
            except sqlite3.OperationalError:
                c.close()
        c = sqlite3.connect(path, timeout=20)
        try:
            rows = c.execute(sql, args).fetchall()
            c.commit()
            return rows
        finally:
            c.close()

    def play_text(self, name=""):
        """A real play's text; `name` makes it a text of its own, since the Worker remembers one that was removed."""
        scripts = json.load(open(REPO / "catalog/plays/castable-scripts.json"))["scripts"]
        s = min((x for x in scripts if 4 <= len(x["roles"]) <= 9 and len(x["lines"]) > 80), key=lambda x: len(x["lines"]))
        word = lambda p: p.get("say") or f"({next(iter(p.values()))})"
        return s["title"], (f"{name}\n\n" if name else "") + "\n\n".join(f"{l['role']}\n{' '.join(word(p) for p in l['parts'])}" if l["kind"] == "speech" else l["source"] for l in s["lines"])

    def add_script(self, t, b, title, text):
        """Add a script, Next, Done: in the page."""
        self.go(b, "/?view=record&add=1")
        wait(b, "!!document.querySelector('#os-text')", 30)
        b.js(f"(() => {{ for (const [i, v] of [['os-title', {json.dumps(title)}], ['os-text', {json.dumps(text)}]]) {{ const e = document.getElementById(i); e.value = v; e.dispatchEvent(new Event('input')); }} return 1; }})()")
        wait(b, "!document.querySelector('.os-next').disabled", 20)
        click(b, "Next")
        wait(b, "!!document.querySelector('.os-list .os-line')", 20)
        click(b, "Done")
        sid = wait(b, "(() => { const m = /play=(own-[0-9a-f-]+)/.exec(location.search); return m ? m[1] : null; })()", 20)
        self.step(t, "a script is added in the page", bool(sid), script=sid)
        return sid

    def record_production(self, b):
        click(b, "Record this")
        return wait(b, "(() => { const m = /production=([^&]+)/.exec(location.search); return m ? decodeURIComponent(m[1]) : null; })()", 20)

    def share(self, b):
        b.js("(() => { const i = document.querySelector('input[name=director]'); i.value = 'Ana'; return 1; })()")
        return click(b, "Share", ".share-box button")

    def pid_of(self, b, local):
        return wait(b, f"PlaysUI.openStore().then(s => (s.share({json.dumps(local)}) || {{}}).pid || null)", 20)

    def shared(self, t, sub, title="The Landing"):
        """A director with a shared production of an own script, as the other tests need one: made through the same client, not the page."""
        b = self.device(f"{t}-{sub}")
        self.go(b, "/?view=record")
        token = self.sign_in(t, b, sub)
        _, text = self.play_text(f"For {sub}.")
        got = b.js(f"""(async () => {{
          const store = OwnScripts.shared();
          const rec = await store.create({{ title: {json.dumps(title)}, text: {json.dumps(text)} }});
          rec.doc = OwnCore.done(rec.doc); rec.done = true; await store.keep(rec);
          const script = await store.script(rec.id);
          const plays = await PlaysUI.openStore();
          const local = await plays.create(script);
          const r = await PlaysShare.share({{ api: API.plays, store: plays, local, script, displayName: 'Ana' }});
          return {{ sid: rec.id, local: local.id, pid: r.id, unsent: r.unsent ? (r.unsent.code || String(r.unsent)) : null }};
        }})()""", timeout=60)
        self.step(t, "a production of an own script is shared", bool(got and got["pid"] and not got["unsent"]), **(got or {}))
        return b, token, got

    def invite_token(self, token, pid):
        st, r = worker_json(self.lw.local_base, "POST", f"/v1/plays/productions/{pid}/invites", token=token, body={})
        return r.get("token") if st == 201 else (st, r)

    # ---- share ----

    def t_share(self):
        t = "share"
        a = self.device("ana")
        title, text = self.play_text()
        sid = self.add_script(t, a, title, text)
        self.look(t, a, "own-page", full=False)
        local = self.record_production(a)
        wait(a, "!!document.querySelector('.share-box')", 20)
        # A try with no take is not kept past a reload (Decision 079), so it has one.
        a.js(TAKE % json.dumps(local), timeout=40)
        self.go(a, f"/?production={local}")
        wait(a, "!!document.querySelector('.share-box')", 20)
        self.step(t, "signed out: Sharing needs an account., and who can read it", says(a, "Sharing needs an account.") and says(a, "Only people you invite can read this script."))
        self.look(t, a, "cast-signed-out", at=".share-box")
        # Read together, signed out.
        self.go(a, f"/?play={sid}")
        click(a, "Read together")
        self.step(t, "signed out: Read together asks for an account and shares nothing", says(a, "Sharing needs an account.") and not a.js("window.__calls.some(c => c.startsWith('POST /v1/plays') || c.startsWith('POST /v1/read'))"))
        a.js("document.querySelectorAll('dialog[open]').forEach(d => d.close())")
        token = self.sign_in(t, a, "ana")
        # The script's page is the person's own; a second production asks for an account, which it now has.
        self.go(a, f"/?production={local}")
        wait(a, "!!document.querySelector('.share-box form')", 20)
        self.step(t, "nothing has left the device", not self.db("SELECT COUNT(*) FROM play_scripts")[0][0])

        def refused(name, fail, words, left):
            self.go(a, f"/?production={local}")
            wait(a, "!!document.querySelector('.share-box form')", 20)
            a.js(f"window.__fail = {json.dumps(fail)}")
            self.share(a)
            ok = says(a, words, 25)
            self.step(t, f"{name}: \"{words}\"", ok, asked=a.js("window.__calls.slice(-4)"))
            pid = a.js(f"PlaysUI.openStore().then(s => (s.share({json.dumps(local)}) || {{}}).pid || null)")
            rows = self.db("SELECT COUNT(*) FROM play_productions")[0][0]
            self.step(t, f"{name}: {'shared, the script owed' if left else 'nothing is left shared, here or there'}", bool(pid) == left and rows == (1 if left else 0), pid=pid, productions=rows)

        refused("offline", [{"match": "POST .*/productions$", "offline": True}], "Ear Drama could not be reached.", False)
        refused("a title the filter refuses", [{"match": "POST .*/productions$", "status": 422, "error": "bad_name", "detail": "title"}], "The title is not allowed.", False)
        refused("a part the filter refuses", [{"match": "POST .*/productions$", "status": 422, "error": "bad_name", "detail": "role:KIEFT"}], "The part name KIEFT is not allowed.", False)
        self.look(t, a, "refused-part", at=".share-box")
        refused("twenty shared", [{"match": "POST .*/productions$", "status": 409, "error": "too_many_scripts", "detail": 20}], "You have shared 20 scripts.", False)
        refused("a text that can never be sent", [{"match": "PUT .*/script$", "status": 413, "error": "script_too_long", "times": 1}], "This script is too long to share.", False)
        refused("a full server", [{"match": "PUT .*/script$", "status": 503, "error": "scripts_full"}], "The script was not sent.", True)
        self.step(t, "a full server: Sharing scripts is full., no Invite", says(a, "Sharing scripts is full.") and not has(a, "Invite"))
        self.look(t, a, "owed")
        click(a, "Try again")
        time.sleep(1.5)
        self.step(t, "Try again says it again", says(a, "Sharing scripts is full."))
        a.js("window.__fail = null")
        click(a, "Try again")
        pid = self.pid_of(a, local)
        self.step(t, "Try again sends it: Invite is there", wait(a, CLICK.format(sel='"button"', text='"nothing"').replace("return false", "return [...document.querySelectorAll('button')].some(x => x.textContent === 'Invite')"), 20))
        row = self.db("SELECT body, bytes FROM play_scripts WHERE production_id = ?", pid)[0]
        same = a.js(f"PlaysUI.openStore().then(s => s.script(s.production({json.dumps(local)}))).then(x => OwnCore.canonicalLines(x.lines) === {json.dumps(row[0])})", timeout=40)
        self.step(t, "the text in the database is the bytes that were hashed", same is True, bytes=row[1])
        self.step(t, "who can read it, and no Publish with the reason", says(a, "Only people you invite can read this script.") and says(a, "This script can't be published.") and not has(a, "Publish"))
        self.step(t, "Ana is named as who added it", says(a, "added this script"))
        self.look(t, a, "cast-director")
        # Frozen.
        self.go(a, f"/?script={sid}&edit=parts")
        self.step(t, "its parts page is its page now, with Edit a copy", wait(a, f"location.search.includes('play={sid}')", 15) and click(a, "nothing", secs=0.1) is None and has(a, "Edit a copy") and not has(a, "Edit"))
        self.step(t, "it says it is shared", says(a, "Added by you · Shared"))
        self.look(t, a, "own-page-shared")
        click(a, "Edit a copy")
        copy = wait(a, "(() => { const m = /script=(own-[0-9a-f-]+)/.exec(location.search); return m ? m[1] : null; })()", 20)
        self.step(t, "Edit a copy opens a new script", bool(copy) and copy != sid, copy=copy)
        wait(a, "!!document.querySelector('.os-list .os-line')", 20)
        self.look(t, a, "copy-parts", full=False)

        # The invite, by the page.
        self.go(a, f"/?production={local}")
        wait(a, "[...document.querySelectorAll('button')].some(x => x.textContent === 'Invite')", 20)
        click(a, "Invite")
        link = wait(a, "(() => { const i = document.querySelector('input[aria-label=\"Invite link\"]'); return i ? i.value : null; })()", 20)
        tok = link.split("#")[1] if link else None
        self.step(t, "Invite makes a link", bool(tok))

        b = self.device("bea", mic=True)
        # What did not arrive whole is never drawn.
        self.go(b, "/")
        b.js(f"sessionStorage.setItem('ed.invite', {json.dumps(tok)})")
        b.ws.call("Page.addScriptToEvaluateOnNewDocument", {"source": "window.__damage = sessionStorage.getItem('damage') === '1'; if (window.__damage) window.__fail = [{ match: 'GET .*/open/invite/script', damage: true }];"})
        b.js("sessionStorage.setItem('damage', '1')")
        self.go(b, f"/?x=1#invite={tok}")
        self.step(t, "an invite whose text did not arrive whole says so and draws no part", says(b, "This script did not arrive whole.") and not b.js("!!document.querySelector('.pl-part')"))
        self.look(t, b, "invite-damaged", full=False)
        b.js("sessionStorage.removeItem('damage')")
        self.go(b, f"/?x=1#invite={tok}")
        drawn = wait(b, "(() => { const n = document.querySelectorAll('#invite-body .pl-part').length; return n || null; })()", 30)
        self.step(t, "an invite opened by a person with no account and no script: the play and its parts are drawn", bool(drawn), parts=drawn, asked=b.js("window.__calls.slice(-3)"))
        self.step(t, "it was fetched by the invite alone", b.js("window.__calls.includes('GET /v1/plays/open/invite/script')"))
        self.look(t, b, "invite", full=False)
        self.sign_in(t, b, "bea")
        self.go(b, f"/?x=1#invite={tok}")
        wait(b, "!!document.querySelector('#invite-body .pl-part button')", 30)
        # A full disk on joining: said, and Open goes on from there.
        b.js("window.__full = true")
        b.js("(() => { const i = document.querySelector('#pl-performer'); if (i) i.value = 'Bea'; document.querySelector('#invite-body .pl-part button').click(); return 1; })()")
        self.step(t, "a full disk on joining: This browser is out of space.", says(b, "This browser is out of space."))
        b.js("window.__full = false")
        self.go(b, f"/?x=1#invite={tok}")
        opened = click(b, "Open")
        local_b = wait(b, "(() => { const m = /production=([^&]+)/.exec(location.search); return m ? decodeURIComponent(m[1]) : null; })()", 20)
        self.step(t, "Open goes on from there", bool(opened and local_b))
        wait(b, "!!document.querySelector('.own-share')", 30)
        b.js("window.__n = window.__calls.length")
        kept = b.js(f"PlaysUI.openStore().then(s => s.script(s.production({json.dumps(local_b)}))).then(x => [x.id === {json.dumps(sid)}, x.kind, x.source.name, x.lines.length])")
        self.step(t, "her copy is kept in the production, and is not one of her scripts", bool(kept and kept[0] and kept[1] == "own") and b.js("OwnScripts.shared().list().then(r => r.length)") == 0, kept=kept)
        self.step(t, "she may report it; she has no Edit a copy, no Read together and no Publish", has(b, "Report script") and not has(b, "Edit a copy") and not has(b, "Read together") and not has(b, "Publish"))
        self.look(t, b, "cast-member")
        # The read-along and the studio read her production's copy.
        part = b.js("(() => { const a = [...document.querySelectorAll('.cast-row a.btn')].find(x => x.textContent === 'Record'); return a ? a.getAttribute('href') : null; })()")
        self.step(t, "her part is hers to record", bool(part), href=part)
        self.go(b, f"/{part}")
        self.step(t, "the studio opens on the fetched script", wait(b, "!!document.querySelector('.rd-line')", 30))
        # A take, sent by her, received by him with its details.
        self.go(a, f"/?production={local}")
        wait(a, "!!document.querySelector('.listen')", 20)
        time.sleep(2)
        b.js(f"""(async () => {{ const s = await PlaysUI.openStore(); const p = s.production({json.dumps(local_b)}); const script = await s.script(p);
          const part = Object.keys(p.parts).find(k => p.parts[k].status === 'recording'); const l = PlaysCore.linesFor(script, part)[0];
          const file = await s.writeTake({{ samples: new Float32Array(48000).map((_, i) => 0.1 * Math.sin(i / 20)), sampleRate: 48000 }}, p, l.id);
          await s.save(PlaysCore.addTake(s.production(p.id), {{ id: PlaysCore.uuid(), lineID: l.id, part, file, created: PlaysCore.now(), frames: 48000, sampleRate: 48000, capture: 'direct', heard: {{}}, peak: 0.1, bleed: false }})); return l.id; }})()""", timeout=40)
        self.go(b, f"/?production={local_b}")
        up = click(b, "Upload 1 take", secs=25)
        sent_by_relay = None if up else says(b, "Sent", 20)
        got = wait(a, "(() => { const g = (window.__inbox || []).find(x => x && x.take); return g ? JSON.stringify(g.take) : null; })()", 45)
        self.step(t, "the director received the take with its details (x-take, read across origins in real Chrome)", bool(got), upload_pressed=bool(up), relay=sent_by_relay, got=json.loads(got) if got else a.js("(window.__inbox || []).slice(0, 5)"))
        home = wait(a, f"PlaysUI.openStore().then(s => {{ const x = s.production({json.dumps(local)}).takes.find(k => k.file.startsWith('m-')); return x ? [x.lineID, x.part, s.production({json.dumps(local)}).chosen[x.lineID] === x.id] : null; }})", 25)
        self.step(t, "and it stands in his production, chosen on its line", bool(home and home[2]), home=home)
        self.close(a, b)

    # ---- room ----

    def t_room(self):
        t = "room"
        a, token, p = self.shared(t, "ray")
        self.go(a, f"/?production={p['local']}")
        wait(a, "!!document.querySelector('.own-share')", 20)
        click(a, "Read together")
        code = wait(a, "(() => { const m = /read-room=([A-Z0-9]+)/.exec(location.search); return m ? m[1] : null; })()", 30)
        self.step(t, "Read together on the production opens a room that carries it", bool(code), room=code)
        self.step(t, "its reader is drawn", wait(a, "!!document.querySelector('.rd-line')", 30))
        c = self.device("cam", mic=True)
        self.go(c, f"/?read-room={code}")
        click(c, "Join")
        self.step(t, "a person with no account and no script follows: the script came by the member key", wait(c, "!!document.querySelector('.rr-bar') && !!document.querySelector('.rd-line')", 40) and c.js("window.__calls.some(x => /^GET .v1.read.[A-Z0-9]+.script$/.test(x))"), asked=c.js("window.__calls.slice(0, 4)"))
        self.look(t, c, "reader", full=False)
        # Record in the room.
        for _ in range(3):
            wait(a, "(() => { const d = document.querySelector('details.rr-menu'); if (d) d.open = true; const r = document.querySelector('input[name=\"rr-mode\"][value=\"record\"]'); if (!r) return null; if (!r.checked) r.click(); return true; })()", 20)
            if wait(a, "(() => { const r = document.querySelector('input[name=\"rr-mode\"][value=\"record\"]'); return r && r.checked ? 1 : null; })()", 8):
                break
        a.js("document.querySelector('details.rr-menu').open = false")
        role = c.js("(() => { const l = document.querySelector('.rd-line .rd-name, .rd-name'); return l ? l.textContent.trim() : null; })()")
        first = c.js("(() => { const n = document.querySelector('.rd-line.rd-now'); return n ? n.id : null; })()")
        self.go(c, f"/?read-room={code}&readdiag=1&read-record=1&read-part={role}")
        # A part whose line comes soon: the one speaking first.
        joined = wait(c, "(() => { const m = [...document.querySelectorAll('.rd-line.rd-mine')].map(x => x.id); return m.length ? m : null; })()", 40)
        self.step(t, "she takes a part; its lines are tinted", bool(joined), part=role, now=first, lines=len(joined or []))
        if joined:
            time.sleep(3)
            armed = c.js("document.querySelector('.rr-rec').innerText")
            if "Start recording" in (armed or ""):
                click(c, "Start recording")
            time.sleep(8)
            from class_bench import press_to, take
            press_to(a, joined[0])
            if not take(self.run, c, joined[0], t):  # Start recording is pressed above: the door that presses it races the page
                c.screenshot(str(Path(self.a.shots) / "room-take-failed.png"))
            got = wait(a, "(() => { const g = (window.__inbox || []).find(x => x && x.take); return g ? JSON.stringify(g.take) : null; })()", 45)
            self.step(t, "the leader received the room's take with its details (x-take)", bool(got), got=json.loads(got) if got else a.js("(window.__inbox || []).slice(0, 4)"))
            n = wait(a, "PlaysUI.openStore().then(s => { const p = s.productions.find(x => x.room); return p && p.takes.length ? [p.scriptID.slice(0, 4), p.takes[0].lineID, !!p.takes[0].member] : null; })", 20)
            self.step(t, "and it stands in the room's production, of the own script", bool(n and n[0] == "own-"), home=n)
        a.js("document.querySelector('details.rr-menu').open = false")
        self.close(c)
        # A screen.
        d = self.device("screen")
        self.go(d, f"/?read-room={code}&screen=1")
        click(d, "Show here")
        self.step(t, "a screen with nothing on it shows the reading", wait(d, "!!document.querySelector('.rs-current .rs-words') && document.querySelector('.rs-current .rs-words').textContent.length > 0", 30))
        self.look(t, d, "screen", full=False)
        # A room whose script did not arrive whole.
        d.ws.call("Page.addScriptToEvaluateOnNewDocument", {"source": "if (sessionStorage.getItem('damage') === '1') window.__fail = [{ match: 'GET .*/script$', damage: true }];"})
        d.js("sessionStorage.setItem('damage', '1')")
        self.go(d, f"/?read-room={code}")
        wait(d, "!!document.querySelector('.rr-go') || document.body.innerText.includes('arrive')", 20)
        click(d, "Join", secs=5)
        self.step(t, "a reading whose script did not arrive whole says so, with Try again", says(d, "This script did not arrive whole.") and has(d, "Try again"))
        self.look(t, d, "reader-refused", full=False)
        # Read together from the script's page uses the production already shared.
        self.go(a, f"/?play={p['sid']}")
        before = self.db("SELECT COUNT(*) FROM play_productions")[0][0]
        click(a, "Read together")
        again = wait(a, "(() => { const m = /read-room=([A-Z0-9]+)/.exec(location.search); return m ? m[1] : null; })()", 30)
        self.step(t, "Read together on the script's page uses the production already shared", bool(again) and again != code and self.db("SELECT COUNT(*) FROM play_productions")[0][0] == before)
        self.close(a, d)

    # ---- report, remove ----

    def member(self, t, sub, tok, part_index=0):
        b = self.device(f"{t}-{sub}")
        self.go(b, "/")
        token = self.sign_in(t, b, sub)
        self.go(b, f"/?x=1#invite={tok}")
        wait(b, "!!document.querySelector('#invite-body .pl-part button')", 30)
        b.js("document.querySelector('#invite-body .pl-part button').click()")
        local = wait(b, "(() => { const m = /production=([^&]+)/.exec(location.search); return m ? decodeURIComponent(m[1]) : null; })()", 25)
        self.step(t, f"{sub} joins by the invite", bool(local))
        wait(b, "!!document.querySelector('.own-share')", 20)
        return b, token, local

    def t_report(self):
        t = "report"
        a, token, p = self.shared(t, "rob")
        tok = self.invite_token(token, p["pid"])
        b, _, local_b = self.member(t, "rita", tok)
        click(b, "Report script")
        wait(b, "!!document.querySelector('.report-form')", 10)
        reasons = b.js("[...document.querySelectorAll('.report-form option')].map(x => x.textContent)")
        self.step(t, "Copyright is among the reasons, and first", bool(reasons) and reasons[0] == "Copyright", reasons=reasons)
        self.look(t, b, "form", at=".report-form")
        click(b, "Report", ".report-form button")
        self.step(t, "Reported. This production is hidden from you.", says(b, "Reported. This production is hidden from you."))
        self.look(t, b, "reported", full=False)
        self.step(t, "the Worker holds the report as of the script", self.db("SELECT script, reason FROM play_reports") == [(1, "copyright")])
        self.go(b, f"/?production={local_b}")
        self.step(t, "opened again, it is not shared with her; Delete production is there", says(b, "This production is not shared with you.") and has(b, "Delete production"))
        self.go(a, f"/?production={p['local']}")
        wait(a, "[...document.querySelectorAll('button')].some(x => x.textContent === 'Invite')", 20)
        click(a, "Invite")
        self.step(t, "the director's Invite: This script has been reported.", says(a, "This script has been reported."))
        click(a, "Read together")
        time.sleep(1)
        self.step(t, "and Read together is refused in the same words", a.js("[...document.querySelectorAll('.own-share .refusal')].some(x => x.textContent === 'This script has been reported.')"))
        self.look(t, a, "director")
        b.js("API.account.signOut()", timeout=20)
        self.go(b, f"/?x=1#invite={tok}")
        self.step(t, "the invite's holder: This script has been reported.", says(b, "This script has been reported.") and not b.js("!!document.querySelector('.pl-part')"))
        self.look(t, b, "invite", full=False)
        self.db("UPDATE play_reports SET status = 'dismissed'")
        self.go(a, f"/?production={p['local']}")
        wait(a, "[...document.querySelectorAll('button')].some(x => x.textContent === 'Invite')", 20)
        click(a, "Invite")
        self.step(t, "dismissed: Invite works again", wait(a, "!!document.querySelector('input[aria-label=\"Invite link\"]')", 15))
        self.close(a, b)

    def t_remove(self):
        t = "remove"
        a, token, p = self.shared(t, "remy")
        tok = self.invite_token(token, p["pid"])
        b, _, local_b = self.member(t, "rosa", tok)
        self.db("UPDATE play_scripts SET body = NULL, bytes = 0, held_at = ? WHERE production_id = ?", int(time.time() * 1000), p["pid"])
        self.go(a, f"/?production={p['local']}")
        self.step(t, "the director: This script was removed., no Invite, no Read together, no Take part", says(a, "This script was removed.") and not has(a, "Invite") and not has(a, "Read together") and not has(a, "Take part"))
        self.step(t, "Edit a copy stays: the words on his device are his", has(a, "Edit a copy"))
        self.look(t, a, "director")
        self.go(b, f"/?production={local_b}")
        self.step(t, "a member: the same, and her copy is still here", says(b, "This script was removed.") and not has(b, "Take part") and not has(b, "Report script") and b.js("!!document.querySelector('.listen')"))
        self.look(t, b, "member")
        b.js("API.account.signOut()", timeout=20)
        c = self.device("rene")
        self.go(c, f"/?x=1#invite={tok}")
        self.step(t, "an invite: This script was removed.", says(c, "This script was removed.") and not c.js("!!document.querySelector('.pl-part')") and not has(c, "Try again"))
        self.look(t, c, "invite", full=False)
        self.go(a, f"/?play={p['sid']}")
        # Shared once more: the Worker remembers what was removed.
        n = self.db("SELECT COUNT(*) FROM play_productions")[0][0]
        self.db("INSERT OR IGNORE INTO play_removed_scripts (key, removed_at) SELECT 'revision:' || script_revision, 1 FROM play_productions WHERE id = ?", p["pid"])
        click(a, "Read together")
        self.step(t, "shared again, it is refused: This script was removed.", says(a, "This script was removed.") and self.db("SELECT COUNT(*) FROM play_productions")[0][0] == n)
        left = a.js(f"PlaysUI.openStore().then(s => s.productions.filter(x => x.scriptID === {json.dumps(p['sid'])}).length)")
        self.step(t, "and leaves no empty production behind", left == 1, productions=left)
        # With its bringer's account: members go on.
        a2, token2, p2 = self.shared(t, "ria", "Another Landing")
        self.close(a, b, c)
        tok2 = self.invite_token(token2, p2["pid"])
        b2, _, local_b2 = self.member(t, "rolf", tok2)
        self.db("DELETE FROM play_scripts WHERE production_id = ?", p2["pid"])
        self.go(b2, f"/?production={local_b2}")
        self.step(t, "gone with its bringer's account: said, and he may still record his part", says(b2, "This script was removed.") and has(b2, "Record"))
        self.look(t, b2, "gone")
        self.close(a2, b2)

    # ---- class ----

    def t_class(self):
        t = "class"
        b = self.device("teacher")
        self.go(b, "/?view=record")
        token = self.sign_in(t, b, "mso")
        made = make_class(self.run, b, self.site, self.q, "Period 3", False, t)
        if not made:
            return
        cid, code = made
        title, text = self.play_text("For a class.")
        sid = self.add_script(t, b, title, text)
        page = f"/?class={cid}"
        self.go(b, page)
        wait(b, "!!document.querySelector('textarea.cl-names')", 30)
        b.js("(() => { const t = document.querySelector('textarea.cl-names'); t.value = 'Ada\\nBen\\nCy'; t.form.requestSubmit(); return 1; })()")
        wait(b, "[...document.querySelectorAll('.cl-remove')].length >= 3", 20)
        opts = wait(b, f"(() => {{ const g = document.querySelector('optgroup[label=\"Your scripts\"]'); return g ? [...g.children].map(x => x.textContent) : null; }})()", 20)
        self.step(t, "Pick a play has the teacher's own script, after the plays", opts == [title], options=opts)
        b.js(f"(() => {{ const s = document.querySelector('select[aria-label=\"Pick a play\"]'); s.value = {json.dumps(sid)}; s.dispatchEvent(new Event('change')); return 1; }})()")
        self.step(t, "who can read it is said while it is picked", says(b, "Only this class can read this script."))
        self.look(t, b, "pick", at="#cl-plays form")
        # Owed first.
        b.js("window.__fail = [{ match: 'PUT .*/script$', offline: true }]")
        b.js(f"(() => {{ const s = document.querySelector('select[aria-label=\"Pick a play\"]'); s.value = {json.dumps(sid)}; s.dispatchEvent(new Event('change')); s.form.requestSubmit(); return 1; }})()")
        self.step(t, "offline while sending: The script was not sent., Try again", says(b, "The script was not sent.") and has(b, "Try again"))
        self.look(t, b, "owed")
        click(b, "Start a reading")
        self.step(t, "Start a reading waits for it: This script has not been sent yet.", says(b, "This script has not been sent yet."))
        st, klass = worker_json(self.lw.local_base, "GET", f"/v1/plays/classes/{cid}/progress", token=token)
        pid = klass["productions"][0]["id"]
        b.js("window.__fail = null")
        click(b, "Try again")
        self.step(t, "Try again sends it", wait(b, "!document.querySelector('.cl-own')", 20) and self.db("SELECT bytes > 0 FROM play_scripts WHERE production_id = ?", pid)[0][0] == 1)
        # Casting, with the script dropped from this browser: from the Worker.
        self.go(b, f"/?class={cid}&cast={pid}")
        wait(b, "document.querySelectorAll('.cb-part').length > 0", 30)
        click(b, "Fill evenly")
        click(b, "Save")
        time.sleep(1.5)
        self.look(t, b, "board", full=False)
        seats = worker_json(self.lw.local_base, "POST", "/v1/plays/seat/list", body={"code": code})[1]["seats"]
        s = self.device("seat", mic=True)
        self.go(s, "/?read-room=parts")
        wait(s, "!!document.querySelector('.class-code-input')", 20)
        s.js(f"(() => {{ const i = document.querySelector('.class-code-input'); i.value = {json.dumps(code)}; i.form.requestSubmit(); return 1; }})()")
        click(s, "Ada")
        got = wait(s, "(() => { const n = document.querySelectorAll('.parts-line').length; return n || null; })()", 30)
        self.step(t, "a seat with no account sees its lines, fetched by its key", bool(got) and s.js("window.__calls.some(x => /^GET .v1.plays.seat.productions.[^/]+.script$/.test(x))"), lines=got)
        self.look(t, s, "seat", full=False)
        click(s, "Record", ".parts-part button")
        self.step(t, "Record opens the studio on it", wait(s, "!!document.querySelector('.rd-line')", 30))
        # A class reading.
        self.go(b, page)
        click(b, "Start a reading", secs=30)
        room = wait(b, "(() => { const m = /read-room=([A-Z0-9]+)/.exec(location.search); return m ? m[1] : null; })()", 30)
        s2 = self.device("seat2")
        self.go(s2, f"/?read-room={room}&seat={code}:Ben")
        click(s2, "Join")
        self.step(t, "a class reading opens, and a seat that lacks the script follows it", bool(room) and wait(s2, "!!document.querySelector('.rr-bar') && !!document.querySelector('.rd-line')", 40), room=room)
        self.close(s2)
        # Export: the lines, here from this browser and, with the script gone, from the Worker.
        for where in ("this browser", "the Worker"):
            if where == "the Worker":
                b.js(f"OwnScripts.shared().remove({json.dumps(sid)})")
            self.go(b, page)
            wait(b, "[...document.querySelectorAll('button')].some(x => x.textContent === 'Export class')", 30)
            b.js("window.__saved = []")
            click(b, "Export class")
            n = wait(b, "(() => { const d = window.__saved.length ? JSON.parse(window.__saved[0]) : null; return d ? [(d.productions[0].script || {}).title, ((d.productions[0].script || {}).lines || []).length] : null; })()", 30)
            self.step(t, f"the class export has the script's lines, from {where}", bool(n and n[0] == title and n[1] > 80), export=n)
        b.js("window.__saved = []; window.__fail = [{ match: 'GET .*/script$', offline: true }]; PlaysShare.forgetFetched()")
        click(b, "Export class")
        self.step(t, "lines that do not load are said, and the rest is saved", says(b, "did not load.") and wait(b, "window.__saved.length > 0", 10))
        self.look(t, b, "export-partial", at="#cl-class .actions")
        b.js("window.__fail = null")
        # Removed.
        self.db("UPDATE play_scripts SET body = NULL, bytes = 0, held_at = 5 WHERE production_id = ?", pid)
        self.go(b, page)
        self.step(t, "removed: the class page says so", says(b, "This script was removed."))
        self.look(t, b, "removed", at="#cl-plays")
        s3 = self.device("seat3")
        self.go(s3, "/?read-room=parts")
        wait(s3, "!!document.querySelector('.class-code-input')", 20)
        s3.js(f"(() => {{ const i = document.querySelector('.class-code-input'); i.value = {json.dumps(code)}; i.form.requestSubmit(); return 1; }})()")
        click(s3, "Cy", secs=10)
        self.step(t, "removed: a seat that never had it says so", says(s3, "This script was removed."), seats=len(seats))
        self.look(t, s3, "seat-removed", full=False)
        self.close(b, s, s3)

    # ---- the device half: R4-2c ----

    def t_add(self):
        t = "add"
        a = self.device("adder")
        self.go(a, "/?view=record&add=1")
        wait(a, "!!document.querySelector('#os-text')", 30)
        long = "ANNA: Yes.\n\nBEN: No.\n\n" * 2990
        a.js(f"(() => {{ for (const [i, v] of [['os-title', 'Long'], ['os-text', {json.dumps(long)}]]) {{ const e = document.getElementById(i); e.value = v; e.dispatchEvent(new Event('input')); }} return 1; }})()")
        self.step(t, "a 66 KB text whose lines would be over 400 KB is refused at Next", says(a, "That text is too long.") and a.js("document.querySelector('.os-next').disabled"))
        self.look(t, a, "too-long", full=False)
        a.js("(() => { const e = document.getElementById('os-text'); e.value = 'ANNA: Who is there?\\n\\nBEN: Only me.\\n\\nANNA: Come in.\\n\\nBEN: I will.\\n\\nSomebody knocks.'; e.dispatchEvent(new Event('input')); return 1; })()")
        wait(a, "!document.querySelector('.os-next').disabled", 15)
        click(a, "Next")
        wait(a, "!!document.querySelector('.os-list .os-line')", 20)
        sid = a.js("new URLSearchParams(location.search).get('script')")
        a.js("document.querySelector('.os-title-btn').click()")
        wait(a, "!!document.querySelector('dialog[open]')", 10)
        self.step(t, "a script not yet Done has Delete in its title's sheet", has(a, "Delete", "dialog button"))
        self.look(t, a, "title-sheet", full=False)
        click(a, "Delete", "dialog button")
        wait(a, "location.search.includes('view=record')", 15)
        time.sleep(1.5)
        self.step(t, "Delete removes it, and nothing writes it again", a.js("OwnScripts.shared().list().then(r => r.length)") == 0 and a.js(f"OwnScripts.shared().get({json.dumps(sid)})") is None)
        self.go(a, f"/?script={sid}&edit=parts")
        self.step(t, "a script not here: the words, and Close on the page", says(a, "This script is not in this browser.") and a.js("!!document.querySelector('.os-bar [aria-label=Close]')"))
        self.look(t, a, "missing", full=False)
        a.js("sessionStorage.setItem('broken', '1')")
        a.ws.call("Page.addScriptToEvaluateOnNewDocument", {"source": "if (sessionStorage.getItem('broken') === '1') { const g = IDBObjectStore.prototype.get; IDBObjectStore.prototype.get = function (k) { if (/doc\\.json$/.test(k)) throw new DOMException('x', 'UnknownError'); return g.call(this, k); }; }"})
        self.go(a, f"/?script={sid}&edit=parts")
        self.step(t, "a failed read: This did not load., Try again, and Close on a phone", says(a, "This did not load.") and has(a, "Try again") and a.js("!!document.querySelector('.os-bar [aria-label=Close]')"))
        self.look(t, a, "failed", full=False)
        click(a, "Close")
        self.step(t, "Close goes back to Record", wait(a, "location.search.includes('view=record') && !location.search.includes('add')", 10))
        # The parts label with its "+N".
        a.js("sessionStorage.removeItem('broken')")
        self.go(a, "/?view=record")
        many = "\n\n".join(f"PART {i:02d}: One.\n\nPART {i:02d}: Two.\n\nPART {i:02d}: Three." for i in range(1, 59))
        a.js(f"""(async () => {{ const s = OwnScripts.shared(); const rec = await s.create({{ title: 'Fifty-eight parts', text: {json.dumps(many)} }}); rec.doc = OwnCore.done(rec.doc); rec.done = true; await s.keep(rec); return 1; }})()""", timeout=30)
        self.go(a, "/?view=record")
        wait(a, "document.body.innerText.includes('Fifty-eight parts')", 20)
        a.js("[...document.querySelectorAll('.ep-title')].find(x => x.textContent === 'Fifty-eight parts').scrollIntoView({ block: 'center' })")
        over = json.loads(a.js("""JSON.stringify((() => { const row = [...document.querySelectorAll('.series-row')].find(x => x.textContent.includes('Fifty-eight parts'));
          const t = [...row.querySelectorAll('svg text')].find(x => x.textContent.startsWith('+')); if (!t) return { none: row.querySelector('svg') ? row.querySelector('svg').outerHTML.slice(0, 200) : 'no svg' };
          const r = t.getBoundingClientRect(); const hit = [...row.querySelectorAll('svg rect')].filter(x => { const q = x.getBoundingClientRect(); return q.height < r.height * 2.5 && q.right > r.left && q.left < r.right && q.bottom > r.top && q.top < r.bottom; }).length;
          return { text: t.textContent, hit }; })())"""))
        self.step(t, "the label's +51 stands on no bar, measured as drawn", over.get("text") == "+51" and over.get("hit") == 0, **over)
        self.look(t, a, "label", full=False)
        self.close(a)

    def end(self):
        for b in list(self.open):
            self.close(b)
        self.srv.shutdown()
        return self.lw.stop()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tests", default="add,share,room,report,remove,class")
    ap.add_argument("--port", type=int, default=8797)
    ap.add_argument("--shots", default=str(SP / "frames"))
    ap.add_argument("--widths", default="320,375,768,1440")
    ap.add_argument("--themes", default="light,dark")
    a = ap.parse_args()
    shutil.rmtree(SP, ignore_errors=True)
    SP.mkdir(parents=True, exist_ok=True)
    Path(a.shots).mkdir(parents=True, exist_ok=True)
    bench = Bench(a)
    stopped = False
    try:
        for name in a.tests.split(","):
            try:
                getattr(bench, f"t_{name}")()
            except Exception as e:  # noqa: BLE001
                bench.step(name, "the test ran to its end", False, error=f"{type(e).__name__}: {e}"[:300])
                for b in list(bench.open):
                    try:
                        b.screenshot(str(Path(a.shots) / f"{name}-stopped-{b.name}.png"))
                    except Exception:  # noqa: BLE001
                        pass
                    bench.close(b)
    finally:
        stopped = bench.end()
    failed = [x for x in bench.run.steps if not x["ok"]]
    print(f"[own-share] {len(bench.run.steps) - len(failed)} of {len(bench.run.steps)} steps ok; {bench.frames} frames in {a.shots}; worker {'stopped' if stopped else 'STILL RUNNING'}")
    for x in failed:
        print("  FAIL", x["test"], x["step"])
    return 1 if failed or not stopped else 0


if __name__ == "__main__":
    sys.exit(main())
