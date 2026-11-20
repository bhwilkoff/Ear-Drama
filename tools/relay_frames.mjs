/* relay_frames: frames of Relay across time and the consent rule (WEB-DESIGN §4.20, PLAYS-DESIGN §12.11, T6).
 *
 *   node tools/relay_frames.mjs [outDir]     (default docs/research/design/img/t6)
 *
 * One headless Chrome (muted, autoplay needs a gesture, ?mute=1) with a browser context per device:
 * a student on a seat (no account) at home, and the teacher. The stub Worker is this file: it answers
 * the seat, class and production routes as docs/WORKER.md says, and its receiver route answers from a
 * switch the harness turns (the teacher's app open or not); a take sent while nobody receives is refused
 * `409 nobody_receiving`, one sent while the teacher's pickup is held passes to it and is kept nowhere.
 * Takes are written into the page's own store with silent samples (no microphone, no sound). Every page
 * is drawn inside a same-origin iframe of the frame's width, light and dark. The script is picked from
 * the bundled castable plays. Prints each frame's path; read every one before calling a change done.
 */
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const OUT = path.resolve(process.argv[2] || path.join(ROOT, "docs/research/design/img/t6"));
const PORT = 8900 + (process.pid % 200);
const CDP_PORT = 9700 + (process.pid % 200);
const CHROME = process.env.READ_CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
fs.mkdirSync(OUT, { recursive: true });

const bundle = JSON.parse(fs.readFileSync(path.join(ROOT, "catalog/plays/castable-scripts.json"), "utf8"));
const linePart = (l) => (l.kind === "speech" ? `role:${l.role || ""}` : l.kind === "direction" ? "directions" : "sound");
const speakers = (s) => new Set(s.lines.filter((l) => l.kind === "speech").map((l) => l.role)).size;
const script = bundle.scripts.filter((s) => speakers(s) >= 4).sort((a, b) => a.lines.length - b.lines.length)[0];
const cast = script.lines.map((l) => [l.id, linePart(l)]);
const parts = [...new Set(cast.map((c) => c[1]).filter((p) => p.startsWith("role:")))]
  .map((p) => ({ p, n: cast.filter((c) => c[1] === p).length })).sort((a, b) => b.n - a.n).map((x) => x.p);
const lucyLines = cast.filter((c) => c[1] === parts[0]).map((c) => c[0]);
const tomLines = cast.filter((c) => c[1] === parts[1]).map((c) => c[0]);

/* ---- The stub Worker ---- */
const now = () => Date.now();
const sw = { receiving: false, pickups: [], remote: [], reviews: {} };
const seats = ["Lucy", "Tom", "Ana"].map((label, i) => ({ id: `S${i + 1}`, label, claimed: i < 2, claimed_at: i < 2 ? now() : null }));
const klass = { id: "C1", name: "Room 7", code: "K7QM4XRB", under13: false, school_consent: false, members: [], seats };
const assignments = [{ part: parts[0], seat: "S1", from: null, to: null }, { part: parts[1], seat: "S2", from: null, to: null }];
const takeOut = (t) => ({ id: t.id, lineID: t.lineID, part: t.part, seat: t.seat, frames: 4800, sampleRate: 48000, capture: "direct", chosen: true, review: sw.reviews[t.id] || null });
const progress = () => ({
  class_id: "C1",
  productions: [{ id: "P1", title: script.title, seats: assignments.map((a) => ({
    seat: a.seat, label: seats.find((s) => s.id === a.seat).label,
    parts: [{ part: a.part, lines: cast.filter((c) => c[1] === a.part).length, recorded: sw.remote.filter((t) => t.seat === a.seat).length, approved: Object.values(sw.reviews).filter((r) => r.state === "approved").length, again: 0 }],
  })) }],
});
const classRecord = () => ({
  id: "P1", scriptID: script.id, scriptRevision: script.revision, title: script.title, class_id: "C1", director: "teacher", parts: {},
  takes: sw.remote, chosen: Object.fromEntries(sw.remote.map((t) => [t.lineID, t.id])), reviews: sw.reviews, assignments,
  members: [], next: null, uploads: true, server_time: now(),
});
const castParts = [...new Set(cast.map((c) => c[1]))];
const adultRecord = () => ({
  id: "P2", scriptID: script.id, scriptRevision: script.revision, title: script.title, director: "teacher",
  parts: Object.fromEntries(castParts.map((p) => [p, p.startsWith("role:") ? { status: "done", user_id: "teacher", performer: "Dee" } : { status: "silent", user_id: "teacher" }])),
  takes: [], chosen: Object.fromEntries(cast.filter((c) => c[1].startsWith("role:")).map((c) => [c[0], `T-${c[0]}`])),
  roomTone: [], listenedThrough: false, members: [{ user_id: "teacher", display_name: "Dee", director: true, performer: true, consented: true }],
  credits: [{ name: "Ann", lines: 3, consented: false }], next: null, hidden_takes: 0, archive: null, uploads: true, server_time: now(),
});
function wav(n = 4800) {
  const b = Buffer.alloc(44 + n * 2);
  b.write("RIFF", 0); b.writeUInt32LE(36 + n * 2, 4); b.write("WAVEfmt ", 8); b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22);
  b.writeUInt32LE(48000, 24); b.writeUInt32LE(96000, 28); b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34); b.write("data", 36); b.writeUInt32LE(n * 2, 40);
  return b;
}

const seatKeys = new Map();
function apiRoute(method, url, body, headers) {
  const p = url.pathname;
  const session = { user_id: "teacher", provider: "google", access_token: "A", access_expires_at: now() + 3600e3, refresh_token: "R", refresh_expires_at: now() + 30 * 864e5 };
  if (p === "/v1/auth/google" || p === "/v1/auth/refresh") return [200, session];
  if (p.startsWith("/v1/sync")) return [200, { history: [], follows: [], queue: null, server_time: now(), next_since: now() }];
  if (p === "/v1/account") return [200, { user_id: "teacher", providers: ["google"], counts: { history: 0, follows: 0 } }];
  if (p === "/v1/plays/consent") return [200, { version: "v1", text: "Words the owner approves.", uploads: true, publishes: true }];
  if (p === "/v1/plays/classes" && method === "GET") return [200, { teaching: [{ id: "C1", name: klass.name, code: klass.code, under13: false, school_consent: false }], member_of: [] }];
  if (p === "/v1/plays/classes/C1") return [200, klass];
  if (p === "/v1/plays/classes/C1/progress") return [200, progress()];
  if (p === "/v1/plays/productions" && method === "GET") return [200, { productions: [] }];
  if (p === "/v1/plays/productions/P1" && method === "GET") return [200, classRecord()];
  if (p === "/v1/plays/productions/P2" && method === "GET") return [200, adultRecord()];
  if (p === "/v1/plays/seat/list") return body.code && body.code.replace(/[\s-]/g, "").toUpperCase() === klass.code ? [200, { class: { id: "C1", name: klass.name }, seats: seats.map((s) => ({ id: s.id, label: s.label, taken: false })) }] : [404, { error: "class_not_found" }];
  if (p === "/v1/plays/seat/claim") {
    const key = `seat-${body.seat}-${Math.random().toString(36).slice(2)}0000000000`;
    seatKeys.set(key, body.seat);
    return [201, { seat_key: key, seat: { id: body.seat }, class: { id: "C1", name: klass.name, under13: false } }];
  }
  const seat = seatKeys.get(headers["x-seat-key"]);
  if (p === "/v1/plays/seat" && seat) {
    return [200, { seat: { id: seat, label: seats.find((s) => s.id === seat).label }, class: { id: "C1", name: klass.name, under13: false },
      productions: [{ id: "P1", title: script.title, scriptID: script.id, scriptRevision: script.revision, assignments: assignments.filter((a) => a.seat === seat),
        takes: sw.remote.filter((t) => t.seat === seat).map(takeOut) }] }];
  }
  if (p === "/v1/plays/seat/productions/P1/receiver" && seat) return [200, { receiving: sw.receiving, name: "Ms. Ortiz" }];
  return [404, { error: "not_found" }];
}

const MIME = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".svg": "image/svg+xml", ".png": "image/png", ".woff2": "font/woff2", ".webmanifest": "application/manifest+json" };
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  const cors = { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*", "access-control-expose-headers": "x-take" };
  if (req.method === "OPTIONS") { res.writeHead(204, cors); res.end(); return; }
  if (url.pathname === "/v1/plays/productions/P1/takes/inbox") {
    const next = sw.pickups.shift();
    if (next) { res.writeHead(200, { ...cors, "content-type": "audio/wav", "x-take": JSON.stringify(next) }); res.end(wav()); return; }
    await sleep(1500);
    res.writeHead(204, cors); res.end();
    return;
  }
  const put = /^\/v1\/plays\/seat\/productions\/P1\/takes\/(.+)$/.exec(url.pathname);
  if (put && req.method === "PUT") {
    const seat = seatKeys.get(req.headers["x-seat-key"]);
    for await (const c of req) void c;
    if (!seat) { res.writeHead(401, { ...cors, "content-type": "application/json" }); res.end('{"error":"seat_key_required"}'); return; }
    if (!sw.receiving) { res.writeHead(409, { ...cors, "content-type": "application/json" }); res.end('{"error":"nobody_receiving"}'); return; }
    const meta = JSON.parse(req.headers["x-take"]);
    const t = { id: put[1], lineID: meta.lineID, part: meta.part, seat };
    sw.remote.push(t);
    sw.pickups.push({ id: t.id, lineID: t.lineID, part: t.part, seat, frames: 4800, sampleRate: 48000, capture: "direct" });
    res.writeHead(201, { ...cors, "content-type": "application/json" }); res.end(JSON.stringify({ id: t.id, delivered: true }));
    return;
  }
  if (url.pathname.startsWith("/v1/")) {
    let raw = "";
    for await (const c of req) raw += c;
    let body = null;
    try { body = raw ? JSON.parse(raw) : null; } catch { body = null; }
    const [status, out] = apiRoute(req.method, url, body, req.headers);
    res.writeHead(status, { ...cors, "content-type": "application/json" });
    res.end(JSON.stringify(out));
    return;
  }
  if (url.pathname === "/__frame.html") {
    const w = Number(url.searchParams.get("w"));
    res.writeHead(200, { "content-type": "text/html" });
    res.end(`<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:#888}iframe{border:0;display:block;width:${w}px;height:${url.searchParams.get("h")}px}</style><iframe src="${url.searchParams.get("src").replace(/"/g, "&quot;")}"></iframe>`);
    return;
  }
  let file = decodeURIComponent(url.pathname);
  if (file === "/" || file === "") file = "/index.html";
  if (file === "/js/config.js") {
    res.writeHead(200, { "content-type": "text/javascript" });
    res.end(`const CONFIG = Object.freeze({ worker: 'http://127.0.0.1:${PORT}', apple: { servicesId: 'REPLACE_WITH', redirectURI: 'REPLACE_WITH' }, google: { clientId: 'REPLACE_WITH' } });`);
    return;
  }
  if (file === "/data/plays/castable-scripts.json") file = "/catalog/plays/castable-scripts.json";
  const abs = path.join(ROOT, file);
  if (!abs.startsWith(ROOT) || !fs.existsSync(abs) || fs.statSync(abs).isDirectory()) { res.writeHead(404); res.end("not found"); return; }
  res.writeHead(200, { "content-type": MIME[path.extname(abs)] || "application/octet-stream" });
  fs.createReadStream(abs).pipe(res);
});

class CDP {
  constructor(ws) { this.ws = ws; this.n = 0; this.wait = new Map(); ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.method === "Runtime.consoleAPICalled" && m.params.type === "error") console.log(`  console.error: ${m.params.args.map((a) => a.description || a.value).join(" ")}`); if (m.id && this.wait.has(m.id)) { const [ok, bad] = this.wait.get(m.id); this.wait.delete(m.id); m.error ? bad(new Error(m.error.message)) : ok(m.result); } }; }
  send(method, params = {}, sessionId) {
    const id = ++this.n;
    this.ws.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
    return new Promise((ok, bad) => this.wait.set(id, [ok, bad]));
  }
}

async function main() {
  await new Promise((r) => server.listen(PORT, "127.0.0.1", r));
  const profile = fs.mkdtempSync(path.join(process.env.TMPDIR || "/private/tmp", "relay-frames-"));
  const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${CDP_PORT}`, "--force-device-scale-factor=1", "--hide-scrollbars",
    "--mute-audio", "--autoplay-policy=user-gesture-required", "--no-first-run", "--no-default-browser-check", `--user-data-dir=${profile}`, "about:blank"], { stdio: "ignore" });
  const done = () => { try { chrome.kill("SIGKILL"); } catch { /* gone */ } server.close(); try { fs.rmSync(profile, { recursive: true, force: true }); } catch { /* left */ } };
  process.on("SIGINT", () => { done(); process.exit(130); });
  let ver = null;
  for (let i = 0; i < 50 && !ver; i++) { try { ver = await (await fetch(`http://127.0.0.1:${CDP_PORT}/json/version`)).json(); } catch { await sleep(200); } }
  const ws = new WebSocket(ver.webSocketDebuggerUrl);
  await new Promise((r) => { ws.onopen = r; });
  const cdp = new CDP(ws);
  const frames = [];

  async function device(name) {
    const { browserContextId } = await cdp.send("Target.createBrowserContext");
    const { targetId } = await cdp.send("Target.createTarget", { url: "about:blank", browserContextId });
    const { sessionId } = await cdp.send("Target.attachToTarget", { targetId, flatten: true });
    const d = { name, sessionId, w: 375, dark: false };
    d.call = (m, p) => cdp.send(m, p, sessionId);
    await d.call("Page.enable");
    await d.call("Runtime.enable");
    await d.call("Page.addScriptToEvaluateOnNewDocument", { source: "window.confirm = () => true;" });
    d.open = async (route, w = 375, dark = false, h = 900) => {
      d.w = w; d.dark = dark;
      await d.call("Emulation.setDeviceMetricsOverride", { width: Math.max(w, 520), height: h, deviceScaleFactor: 1, mobile: false });
      await d.call("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: dark ? "dark" : "light" }] });
      const src = `/${route}${route.includes("?") ? "&" : "?"}mute=1`;
      await d.call("Page.navigate", { url: `http://127.0.0.1:${PORT}/__frame.html?w=${w}&h=${h}&src=${encodeURIComponent(src)}` });
      await sleep(1800);
    };
    d.eval = async (js) => {
      const r = await d.call("Runtime.evaluate", { expression: `(async () => { const win = document.querySelector('iframe').contentWindow; const doc = win.document; ${js} })()`, awaitPromise: true, returnByValue: true, userGesture: true });
      if (r.exceptionDetails) throw new Error(`${name}: ${r.exceptionDetails.exception ? r.exceptionDetails.exception.description : r.exceptionDetails.text}`);
      return r.result.value;
    };
    d.click = (sel, text) => d.eval(`const els = [...doc.querySelectorAll(${JSON.stringify(sel)})].filter(e => ${text ? `e.textContent.trim() === ${JSON.stringify(text)}` : "true"}); if (!els.length) throw new Error('no ' + ${JSON.stringify(sel + " " + (text || ""))}); els[0].click(); return true;`);
    d.type = (sel, value) => d.eval(`const e = doc.querySelector(${JSON.stringify(sel)}); e.value = ${JSON.stringify(value)}; return true;`);
    d.shot = async (label) => {
      await sleep(900);
      const hgt = await d.call("Runtime.evaluate", { expression: "document.querySelector('iframe').getBoundingClientRect().height", returnByValue: true });
      const { data } = await d.call("Page.captureScreenshot", { format: "png", clip: { x: 0, y: 0, width: d.w, height: hgt.result.value, scale: 1 } });
      const file = path.join(OUT, `${label}-${d.dark ? "dark" : "light"}-${d.w}.png`);
      fs.writeFileSync(file, Buffer.from(data, "base64"));
      frames.push(file);
      console.log(file);
    };
    return d;
  }

  /** Writes silent takes for `lineIDs` into the page's own store, linked to the seat as a studio recording would be. */
  const recordAtHome = (d, lineIDs) => d.eval(`
    const store = await win.eval("PlaysUI").openStore();
    const key = JSON.parse(win.sessionStorage.getItem('ed.seats'))[0].seat_key;
    const sc = await win.eval("API").playScript(${JSON.stringify(script.id)});
    let p = await store.create(sc);
    await store.setShare(p.id, { pid: 'P1', seat: { key, class_id: 'C1', label: 'Lucy' }, assignments: ${JSON.stringify(assignments.filter((a) => a.seat === "S1"))} });
    for (const id of ${JSON.stringify(lineIDs)}) {
      const file = await store.writeTake({ samples: new Float32Array(4800), sampleRate: 48000 }, p, id);
      p = win.eval("PlaysCore").addTake(store.production(p.id), { id: 'T-' + id, lineID: id, part: ${JSON.stringify(parts[0])}, file, created: 1, frames: 4800, sampleRate: 48000, capture: 'direct', heard: {}, peak: 0.1, bleed: false });
      await store.save(p);
    }
    win.localStorage.setItem('ed.relay', '1');
    return p.id;`);

  try {
    const lucy = await device("lucy");
    const teacher = await device("teacher");
    for (const [w, dark] of [[375, false], [1440, false], [375, true]]) {
      // A student at home: the class code, then the name; no account.
      if (w === 375 && !dark) {
        await lucy.open("?read-room=parts", w, dark, 800);
        await lucy.shot("parts-code");
        await lucy.type("input.class-code-input", klass.code);
        await lucy.eval("doc.querySelector('input.class-code-input').form.requestSubmit(); return true;");
        await sleep(900);
        await lucy.shot("parts-names");
        await lucy.click("button.rr-name", "Lucy");
        await sleep(1800);
        await lucy.shot("parts-open");
      }
      if (w === 375 && !dark) {
        // Lucy records two lines at home while her teacher is away: the takes wait on her device.
        await recordAtHome(lucy, lucyLines.slice(0, 3));
      }
      await lucy.open("?read-room=parts", w, dark, w < 600 ? 900 : 800);
      await sleep(1200);
      await lucy.shot("parts-waiting");
      if (w === 375 && !dark) {
        // The teacher opens the class page: her pickup is held, so the next ask finds her there and the takes pass through.
        sw.receiving = true;
        await teacher.open("?class=C1", 1440, false, 1100);
        await teacher.eval("await win.eval(\"API.account.signIn('google', 'id-token', 'nonce')\"); return true;");
        await teacher.open("?class=C1", 1440, false, 1100);
        await sleep(6500);
        await lucy.shot("parts-sent");
        await teacher.shot("teacher-progress");
        sw.reviews[`T-${lucyLines[0]}`] = { state: "approved", note: null, reviewed_at: now() };
        sw.reviews[`T-${lucyLines[1]}`] = { state: "again", note: "Slower at the end.", reviewed_at: now() };
        await lucy.open("?read-room=parts", w, dark, 900);
        await lucy.shot("parts-reviewed");
        await teacher.open("?class=C1", 375, false, 1500);
        await teacher.shot("teacher-progress");
        sw.receiving = false;
      }
    }
    // Publish held back by a maker who has not consented.
    await teacher.open("?class=C1", 1440, false, 900);
    const local = await teacher.eval(`
      const store = await win.eval("PlaysUI").openStore();
      const sc = await win.eval("API").playScript(${JSON.stringify(script.id)});
      const p = await store.create(sc);
      await store.setShare(p.id, { pid: 'P2' });
      return p.id;`);
    for (const [w, dark] of [[375, false], [1440, false], [375, true]]) {
      await teacher.open(`?production=${local}`, w, dark, w < 600 ? 1500 : 1100);
      await sleep(1200);
      await teacher.shot("publish-blocked");
    }
  } finally {
    done();
  }
  console.log(`${frames.length} frames`);
  process.exit(0);
}
main().catch((e) => { console.error(e); process.exit(1); });
