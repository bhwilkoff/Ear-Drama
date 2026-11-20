/* read_frames: frames of reading together and the class page (WEB-DESIGN §4.17-§4.19, T3).
 *
 *   node tools/read_frames.mjs [outDir]     (default docs/research/design/img/t3)
 *
 * One headless Chrome (muted, autoplay needs a gesture, ?mute=1) with a browser context per
 * device: the teacher (who signs in against the stub and leads), two students on seats, and a
 * projector's screen. The stub Worker is this file: the read room's routes run on
 * worker/src/read-protocol.js's own functions (so it holds no rule of its own) over the polling
 * transport, and the class routes answer as docs/WORKER.md says. The site is served from this
 * working tree with js/config.js pointed at the stub. Every page is drawn inside a same-origin
 * iframe of the frame's width (headless Chrome lays a page under ~500 px out wider and crops it),
 * light and dark. The script is picked from the bundled castable plays, never named by a test.
 * Prints each frame's path; read every one before calling a change done.
 *
 *   T5=1 node tools/read_frames.mjs docs/research/design/img/t5
 *
 * draws Record in the room instead (PLAYS-DESIGN §12.10): the stub microphone door (a 160 Hz
 * oscillator never connected to the speakers, its level set by the harness) on each reader, the
 * room's take routes and pickup, the TV pairing routes, names on join, and the ended and unknown
 * room refusals.
 */
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import * as P from "../worker/src/read-protocol.js";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const OUT = path.resolve(process.argv[2] || path.join(ROOT, "docs/research/design/img/t3"));
const PORT = 8700 + (process.pid % 200);
const CDP_PORT = 9500 + (process.pid % 200);
const CHROME = process.env.READ_CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
fs.mkdirSync(OUT, { recursive: true });

/* ---- The play: the smallest castable script with at least six speaking parts ---- */
const bundle = JSON.parse(fs.readFileSync(path.join(ROOT, "catalog/plays/castable-scripts.json"), "utf8"));
const linePart = (l) => (l.kind === "speech" ? `role:${l.role || ""}` : l.kind === "direction" ? "directions" : "sound");
const speaking = (s) => new Set(s.lines.filter((l) => l.kind === "speech").map((l) => l.role)).size;
const script = bundle.scripts.filter((s) => speaking(s) >= 6).sort((a, b) => a.lines.length - b.lines.length)[0];
const cast = script.lines.map((l) => [l.id, linePart(l)]);
const parts = [...new Set(cast.map((c) => c[1]).filter((p) => p.startsWith("role:")))]
  .map((p) => ({ p, n: cast.filter((c) => c[1] === p).length })).sort((a, b) => b.n - a.n).map((x) => x.p);

/* ---- The stub Worker ---- */
const now = () => Date.now();
const seats = ["Lucy", "Tom", "Ana", "Ben", "Mia", "Sam"].map((label, i) => ({ id: `S${i + 1}`, label, claimed: i < 2, claimed_at: i < 2 ? now() : null }));
const klass = { id: "C1", name: "Room 7", code: "K7QM4XRB", under13: false, school_consent: false, members: [], seats };
let assignments = [{ part: parts[0], seat: "S1" }, { part: parts[1], seat: "S2" }, { part: parts[2], seat: "S3" }];
const speechIds = cast.filter((c) => c[1].startsWith("role:"));
const tomLine = cast.find((c) => c[1] === parts[1]);
const lucyLine = cast.find((c) => c[1] === parts[0]);
const takes = [
  { id: "T-LUCY-1", lineID: lucyLine[0], part: parts[0], seat: "S1", frames: 48000, sampleRate: 48000, capture: "room" },
  { id: "T-TOM-1", lineID: tomLine[0], part: parts[1], seat: "S2", frames: 48000, sampleRate: 48000, capture: "room" },
];
const production = () => ({
  id: "P1", scriptID: script.id, scriptRevision: script.revision, title: script.title, class_id: "C1", director: "teacher",
  parts: {}, takes, chosen: Object.fromEntries(takes.map((t) => [t.lineID, t.id])), reviews: {}, assignments,
  members: [], next: null, uploads: true, server_time: now(),
});
const progress = () => ({
  class_id: "C1",
  productions: [{ id: "P1", title: script.title, seats: assignments.map((a) => {
    const lines = cast.filter((c) => c[1] === a.part).length;
    return { seat: a.seat, label: seats.find((s) => s.id === a.seat).label, parts: [{ part: a.part, lines, recorded: a.seat === "S1" ? 4 : a.seat === "S2" ? 1 : 0, approved: a.seat === "S1" ? 2 : 0, again: a.seat === "S1" ? 1 : 0 }] };
  }) }],
});
let inboxSent = false;
function wav(n = 4800) {
  const b = Buffer.alloc(44 + n * 2);
  b.write("RIFF", 0); b.writeUInt32LE(36 + n * 2, 4); b.write("WAVEfmt ", 8); b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22);
  b.writeUInt32LE(48000, 24); b.writeUInt32LE(96000, 28); b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34); b.write("data", 36); b.writeUInt32LE(n * 2, 40);
  return b;
}

const rooms = new Map();
const pairs = new Map();
const pickups = new Map();
const roomTakes = [];
let memberN = 0;
const newMember = (role, seat = null) => { memberN++; return { id: `m${memberN}`, key: `key-${memberN}-${Math.random().toString(36).slice(2)}`, role, seat, joined_at: now(), seen_at: now() }; };
const snapOf = (room, id) => P.joinSnapshot(room.room, cast, room.members, id, now());
const seatKeys = new Map();

function readRoute(method, url, body, headers) {
  if (url.pathname === "/v1/read" && method === "POST") {
    let code;
    do { code = P.codeFromBytes([...Array(6)].map(() => Math.floor(Math.random() * 256))); } while (rooms.has(code));
    const me = newMember("reader");
    const input = { code, kind: body.kind || "adult", script_id: script.id, script_revision: script.revision, mode: body.mode, class_id: body.class_id, production_id: body.production_id };
    if (input.kind === "class") { input.seats = seats.map((s) => ({ id: s.id, label: s.label })); input.assignments = assignments; }
    const made = P.newRoom(input, cast, me.id, now());
    if (made.error) return [400, { error: made.error }];
    const room = { room: made.room, members: [me], keys: new Map([[me.key, me.id]]) };
    rooms.set(code, room);
    return [200, { ...snapOf(room, me.id), member_key: me.key, transport: "poll" }];
  }
  const m = /^\/v1\/read\/([^/]+)(?:\/(join|send|socket))?$/.exec(url.pathname);
  const room = m && rooms.get(P.normalizeCode(decodeURIComponent(m[1])));
  if (!room) return [404, { error: "no_such_room" }];
  if (room.room.ended) return [410, { error: "room_ended" }];
  if (m[2] === "socket") return [409, { error: "poll_only" }];
  if (m[2] === "join") {
    const want = body || {};
    if (want.seat && room.room.kind === "class" && seatKeys.get(want.seat_key) !== want.seat) return [403, { error: "seat_key_required" }];
    const refusal = P.joinRefusal(room.room, room.members, want, now());
    if (refusal) return [refusal === "seat_required" ? 400 : 409, { error: refusal }];
    const me = { ...newMember(want.role || "reader"), name: P.cleanName(room.room, want.name) || null };
    room.members.push(me);
    room.keys.set(me.key, me.id);
    if (want.seat) {
      const t = P.takeSeat(room.room, room.members, me.id, want.seat, !!want.move, now());
      if (t.error) { room.members.pop(); return [409, { error: t.error }]; }
      room.members = t.members;
    }
    return [200, { ...snapOf(room, me.id), member_key: me.key, transport: "poll" }];
  }
  const id = room.keys.get(headers["x-read-key"]);
  if (!id) return [403, { error: "not_a_member" }];
  room.members = room.members.map((x) => (x.id === id ? { ...x, seen_at: now() } : x));
  if (m[2] === "send") {
    const r = P.applyMessage({ room: room.room, cast, members: room.members }, id, body, now());
    if (r.error) return [r.error === "stale" ? 409 : 403, { error: r.error, detail: r.detail }];
    room.room = r.room; room.members = r.members;
    if (room.room.ended) return [200, { ended: true }];
    return [200, r.reply ? { ...snapOf(room, id), reply: r.reply } : snapOf(room, id)];
  }
  return [200, snapOf(room, id)];
}

function apiRoute(method, url, body, headers) {
  const p = url.pathname;
  const session = { user_id: "teacher", provider: "google", access_token: "A", access_expires_at: now() + 3600e3, refresh_token: "R", refresh_expires_at: now() + 30 * 864e5 };
  if (p.startsWith("/v1/read") && !/\/pair(\/|$)/.test(p)) return readRoute(method, url, body, headers);
  if (p === "/v1/auth/google" || p === "/v1/auth/refresh") return [200, session];
  if (p.startsWith("/v1/sync")) return [200, { history: [], follows: [], queue: null, server_time: now(), next_since: now() }];
  if (p === "/v1/account") return [200, { user_id: "teacher", providers: ["google"], counts: { history: 0, follows: 0 } }];
  if (p === "/v1/plays/consent") return [200, { version: "v1", text: "", uploads: true, publishes: false }];
  if (p === "/v1/read/pair" && method === "POST") {
    const code = P.codeFromBytes([...Array(6)].map(() => Math.floor(Math.random() * 256)));
    const key = `pair-${Math.random().toString(36).slice(2)}`;
    pairs.set(code, { key, room: null, expires_at: now() + 600000 });
    return [201, { pair_code: code, pair_key: key, expires_at: now() + 600000, server_time: now() }];
  }
  const pw = /^\/v1\/read\/pair\/([^/]+)$/.exec(p);
  if (pw) {
    const pr = pairs.get(pw[1]);
    if (!pr || pr.key !== headers["x-pair-key"]) return [404, { error: "no_such_pair" }];
    if (!pr.room) return [200, { paired: false, expires_at: pr.expires_at, server_time: now() }];
    pairs.delete(pw[1]);
    const room = rooms.get(pr.room);
    const me = newMember("screen");
    room.members.push(me); room.keys.set(me.key, me.id);
    return [200, { ...snapOf(room, me.id), member_key: me.key, transport: "poll" }];
  }
  const pa = /^\/v1\/read\/([^/]+)\/pair$/.exec(p);
  if (pa) {
    const pr = pairs.get(P.normalizeCode(body.code || ""));
    if (!pr || pr.room) return [404, { error: "no_such_pair" }];
    pr.room = P.normalizeCode(pa[1]);
    return [200, { paired: true }];
  }
  if (p === "/v1/plays/classes" && method === "GET") return [200, { teaching: [{ id: "C1", name: klass.name, code: klass.code, under13: false, school_consent: false }], member_of: [] }];
  if (p === "/v1/plays/classes/C1") return [200, klass];
  if (p === "/v1/plays/classes/C1/progress") return [200, progress()];
  if (p === "/v1/plays/classes/C1/seats" && method === "POST") return [201, { seats: [], refused: [] }];
  if (p === "/v1/plays/productions" && method === "GET") return [200, { productions: [] }];
  if (p === "/v1/plays/productions/P1" && method === "GET") return [200, production()];
  if (p === "/v1/plays/productions/P1/assignments" && method === "PUT") { assignments = body.assignments; return [200, { assignments }]; }
  if (p.startsWith("/v1/plays/productions/P1/takes/") && p.endsWith("/review")) return [200, { take_id: "x", state: body.state, note: body.note || null, reviewed_at: now() }];
  if (p === "/v1/plays/seat/list") return body.code && body.code.replace(/[\s-]/g, "").toUpperCase() === klass.code ? [200, { class: { id: "C1", name: klass.name }, seats: seats.map((s) => ({ id: s.id, label: s.label, taken: false })) }] : [404, { error: "class_not_found" }];
  if (p === "/v1/plays/seat/claim") {
    const key = `seat-${body.seat}-${Math.random().toString(36).slice(2)}`;
    seatKeys.set(key, body.seat);
    return [201, { seat_key: key, seat: { id: body.seat }, class: { id: "C1", name: klass.name, under13: false } }];
  }
  return [404, { error: "not_found" }];
}

const MIME = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".svg": "image/svg+xml", ".png": "image/png", ".woff2": "font/woff2", ".webmanifest": "application/manifest+json" };
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  if (url.pathname === "/v1/plays/productions/P1/takes/inbox") {
    if (!inboxSent) {
      inboxSent = true;
      const t = takes[1];
      res.writeHead(200, { "content-type": "audio/wav", "x-take": JSON.stringify({ id: t.id, lineID: t.lineID, part: t.part, seat: t.seat, frames: 4800, sampleRate: 48000, capture: "room" }), "access-control-expose-headers": "x-take" });
      res.end(wav());
      return;
    }
    await sleep(20000);
    res.writeHead(204); res.end();
    return;
  }
  const tk = /^\/v1\/read\/([^/]+)\/takes\/(.+)$/.exec(url.pathname);
  if (tk) {
    const room = rooms.get(P.normalizeCode(tk[1]));
    const id = room && room.keys.get(req.headers["x-read-key"]);
    const fail = (status, error) => { res.writeHead(status, { "content-type": "application/json" }); res.end(JSON.stringify({ error })); };
    if (!room) return fail(404, "no_such_room");
    if (!id) return fail(403, "not_a_member");
    if (tk[2] === "inbox") {
      if (P.receiverOf(room.room) !== id) return fail(403, "receivers_only");
      const list = pickups.get(room.room.code) || [];
      pickups.set(room.room.code, list);
      const held = { res };
      list.push(held);
      setTimeout(() => { if (list.includes(held)) { list.splice(list.indexOf(held), 1); res.writeHead(204); res.end(); } }, 20000);
      return;
    }
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const bytes = Buffer.concat(chunks);
    const meta = JSON.parse(req.headers["x-take"] || "{}");
    const me = room.members.find((x) => x.id === id);
    const refusal = P.recordRefusal(room.room, cast, me, meta.lineID);
    if (refusal) return fail(refusal === "not_your_line" ? 403 : 409, refusal);
    const held = (pickups.get(room.room.code) || []).shift();
    if (!held) return fail(409, "nobody_receiving");
    const fields = { id: decodeURIComponent(tk[2]), lineID: meta.lineID, part: cast.find((c) => c[0] === meta.lineID)[1], frames: meta.frames, sampleRate: meta.sampleRate, capture: "room", seat: me.seat, member: id };
    roomTakes.push(fields);
    held.res.writeHead(200, { "content-type": "audio/wav", "x-take": JSON.stringify(fields) });
    held.res.end(bytes);
    res.writeHead(201, { "content-type": "application/json" });
    res.end(JSON.stringify({ ...fields, delivered: true }));
    return;
  }
  if (url.pathname.startsWith("/v1/")) {
    let raw = "";
    for await (const c of req) raw += c;
    let body = null;
    try { body = raw ? JSON.parse(raw) : null; } catch { body = null; }
    const [status, out] = apiRoute(req.method, url, body, req.headers);
    res.writeHead(status, { "content-type": "application/json" });
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

/* ---- A minimal CDP client over Node's WebSocket ---- */
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
  const profile = fs.mkdtempSync(path.join(process.env.TMPDIR || "/private/tmp", "read-frames-"));
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
    const d = { name, sessionId, w: 1440, dark: false };
    d.call = (m, p) => cdp.send(m, p, sessionId);
    await d.call("Page.enable");
    await d.call("Runtime.enable");
    // The stub microphone door: an oscillator never connected to the speakers; its level is the harness's (__micGain).
    await d.call("Page.addScriptToEvaluateOnNewDocument", { source: `(() => {
      Object.defineProperty(navigator, 'mediaDevices', { configurable: true, value: {
        enumerateDevices: async () => [],
        async getUserMedia() {
          const ctx = new AudioContext();
          const osc = ctx.createOscillator(); osc.frequency.value = 160;
          const g = ctx.createGain(); g.gain.value = 0.0005;
          const dest = ctx.createMediaStreamDestination();
          osc.connect(g); g.connect(dest); osc.start();
          await ctx.resume();
          window.__micGain = g;
          return dest.stream;
        } } });
      window.confirm = () => true;
    })();` });
    d.open = async (route, w = 1440, dark = false, h = 900) => {
      d.w = w; d.dark = dark;
      await d.call("Emulation.setDeviceMetricsOverride", { width: Math.max(w, 520), height: h, deviceScaleFactor: 1, mobile: false });
      await d.call("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: dark ? "dark" : "light" }] });
      const src = `/${route}${route.includes("?") ? "&" : "?"}mute=1`;
      await d.call("Page.navigate", { url: `http://127.0.0.1:${PORT}/__frame.html?w=${w}&h=${h}&src=${encodeURIComponent(src)}` });
      await sleep(1800);
    };
    /** Runs `js` inside the app's frame (same origin), returning its value. */
    d.eval = async (js) => {
      const r = await d.call("Runtime.evaluate", { expression: `(async () => { const win = document.querySelector('iframe').contentWindow; const doc = win.document; ${js} })()`, awaitPromise: true, returnByValue: true, userGesture: true });
      if (r.exceptionDetails) throw new Error(`${name}: ${r.exceptionDetails.exception ? r.exceptionDetails.exception.description : r.exceptionDetails.text}`);
      return r.result.value;
    };
    d.click = (sel, text) => d.eval(`const els = [...doc.querySelectorAll(${JSON.stringify(sel)})].filter(e => ${text ? `e.textContent.trim() === ${JSON.stringify(text)}` : "true"}); if (!els.length) throw new Error('no ' + ${JSON.stringify(sel + " " + (text || ""))}); els[0].click(); return true;`);
    d.type = (sel, value) => d.eval(`const e = doc.querySelector(${JSON.stringify(sel)}); e.value = ${JSON.stringify(value)}; e.dispatchEvent(new win.Event('input', { bubbles: true })); return true;`);
    d.key = (key) => d.eval(`doc.dispatchEvent(new win.KeyboardEvent('keydown', { key: ${JSON.stringify(key)}, bubbles: true })); return true;`);
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

  try {
    if (process.env.T5) { await recordFrames(device); done(); console.log(`${frames.length} frames`); process.exit(0); }
    const teacher = await device("teacher");
    await teacher.open("?view=library&tab=dramas");
    await teacher.eval("await win.eval(\"API.account.signIn('google', 'id-token', 'nonce')\"); return true;");
    for (const [w, dark] of process.env.ROOM_ONLY ? [] : [[375, false], [1440, false], [375, true], [1440, true]]) {
      await teacher.open("?class=C1", w, dark, w < 600 ? 1500 : 1100);
      await sleep(1500);
      await teacher.shot("class-page");
      await teacher.open("?class=C1&cast=P1", w, dark, w < 600 ? 1700 : 1100);
      await teacher.shot("casting-board");
    }
    // An empty class, as a new teacher sees it.
    const full = klass.seats;
    klass.seats = [];
    await teacher.open("?class=C1", 375, false, 900);
    await teacher.shot("class-empty");
    klass.seats = full;

    // The teacher starts a reading: a class room, the teacher leads.
    await teacher.open("?class=C1", 1440, false, 900);
    await teacher.click("button", "Start a reading");
    await sleep(2000);
    const code = await teacher.eval("return new win.URLSearchParams(win.location.search).get('read-room');");
    if (!code) throw new Error(`no room code after Start a reading: ${await teacher.eval("return [...doc.querySelectorAll('[role=alert]')].map(e => e.textContent).join(' | ') + ' @ ' + win.location.search;")}`);

    const join = async (d, label, w, dark) => {
      await d.open(`?read-room=${code}`, w, dark, 820);
      await d.shot(`${label}-join`);
      await d.click("button", "Join");
      await sleep(800);
      await d.type("input.class-code-input", klass.code);
      await d.eval("doc.querySelector('input.class-code-input').form.requestSubmit(); return true;");
      await sleep(800);
      await d.shot(`${label}-names`);
      await d.click("button.rr-name", label === "lucy" ? "Lucy" : "Tom");
      await sleep(2500);
    };
    const lucy = await device("lucy");
    await join(lucy, "lucy", 375, false);
    const tom = await device("tom");
    await join(tom, "tom", 375, true);
    const screen = await device("screen");
    await screen.open(`?read-room=${code}&screen=1`, 1440, false, 810);
    await screen.click("button", "Show here");
    await sleep(2000);

    // The leader moves the reading on with the keys (a pedal is a keyboard).
    await teacher.open(`?read-room=${code}`, 1440, false, 900);
    await sleep(2500);
    for (let i = 0; i < 3; i++) { await teacher.key("ArrowRight"); await sleep(400); }
    await sleep(1800);
    await teacher.shot("room-leader");
    if (process.env.READ_DEBUG) console.log(await teacher.eval(`return win.eval("JSON.stringify({ c: ReadUI.session.state().snap && ReadUI.session.state().snap.cursor, leads: ReadUI.session.state().snap && ReadUI.session.state().snap.you, bar: !!document.querySelector('.rr-bar'), rd: document.querySelector('.rd') && document.querySelector('.rd').getBoundingClientRect().height, foot: document.querySelector('.rd-bottom') && document.querySelector('.rd-bottom').getBoundingClientRect().top, vh: innerHeight, view: !document.getElementById('view-readroom').hidden })");`));
    await lucy.shot("room-lucy");
    await tom.shot("room-tom");
    await screen.shot("screen");
    await screen.open(`?read-room=${code}&screen=1`, 1440, true, 810);
    await sleep(2500);
    await screen.shot("screen");
    // Rehearse: the leader switches the mode; Lucy gets Hide my lines.
    await teacher.eval("await win.eval(\"ReadUI.session.send({ type: 'mode', mode: 'rehearse' })\"); return true;");
    await sleep(2200);
    await lucy.shot("room-lucy-rehearse");
    await teacher.shot("room-leader-rehearse");
  } finally {
    done();
  }
  console.log(`${frames.length} frames`);
  process.exit(0);
}
/** T5: Record in the room, the Takes sheet, names, the refusals, and pairing a TV (PLAYS-DESIGN §12.10). */
async function recordFrames(device) {
  const teacher = await device("teacher");
  await teacher.open("?view=library&tab=dramas");
  await teacher.eval("await win.eval(\"API.account.signIn('google', 'id-token', 'nonce')\"); return true;");
  await teacher.open("?class=C1", 1440, false, 900);
  await teacher.click("button", "Start a reading");
  await sleep(2000);
  const code = await teacher.eval("return new win.URLSearchParams(win.location.search).get('read-room');");
  if (!code) throw new Error("no room code");
  rooms.get(code).room.production_id = "P1";
  const seatJoin = async (d, label, w, dark) => {
    await d.open(`?read-room=${code}`, w, dark, 820);
    await d.click("button", "Join");
    await sleep(800);
    await d.type("input.class-code-input", klass.code);
    await d.eval("doc.querySelector('input.class-code-input').form.requestSubmit(); return true;");
    await sleep(800);
    // Wait for the class's names (the stub answers in a moment; a fixed sleep raced it once).
    let names = '';
    for (let i = 0; i < 50 && !names.includes(label); i++) {
      names = await d.eval("return [...doc.querySelectorAll('button.rr-name, [role=alert]')].map((e) => e.textContent).join(' | ');");
      if (!names.includes(label)) await sleep(100);
    }
    if (!names.includes(label)) throw new Error(label + ' sees: ' + names);
    await d.click("button.rr-name", label);
    await sleep(2500);
  };
  const lucy = await device("lucy");
  await seatJoin(lucy, "Lucy", 375, false);
  const tom = await device("tom");
  await seatJoin(tom, "Tom", 375, true);
  await teacher.open(`?read-room=${code}`, 1440, false, 900);
  await sleep(2500);
  await teacher.eval("await win.eval(\"ReadUI.session.send({ type: 'mode', mode: 'record' })\"); return true;");
  await sleep(2500);
  await lucy.shot("t5-reader-start");
  for (const d of [lucy, tom]) { await d.click("button.btn-record", "Start recording"); }
  await sleep(6500);
  // The cursor reaches Lucy's line: her microphone opens by itself; she speaks (the stub's level rises).
  const lucyFirst = cast.find((c) => c[1] === assignments.find((a) => a.seat === "S1").part)[0];
  await lucy.eval("if (win.__micGain) win.__micGain.gain.value = 0.3; return true;");
  await teacher.eval(`await win.eval("ReadUI.session.send({ type: 'cursor', line: '${lucyFirst}', base: ReadUI.session.state().snap.cursor_gen })"); return true;`);
  await sleep(2400);
  await lucy.shot("t5-reader-recording");
  await tom.shot("t5-reader-quiet");
  await lucy.eval("if (win.__micGain) win.__micGain.gain.value = 0.0005; return true;");
  await sleep(4000);
  console.log(`  takes through the room: ${roomTakes.map((t) => t.lineID).join(", ") || "none"}`);
  await teacher.shot("t5-leader-recording");
  await teacher.click("button.rr-takes", "Takes");
  await sleep(1500);
  await teacher.shot("t5-takes");
  await teacher.open(`?read-room=${code}`, 375, true, 1100);
  await sleep(3000);
  await teacher.click("button.rr-takes", "Takes");
  await sleep(1500);
  await teacher.shot("t5-takes");
  await teacher.open(`?read-room=${code}`, 1440, false, 900);
  await sleep(2500);
  await teacher.eval("doc.querySelector('.rr-menu').open = true; return true;");
  await sleep(600);
  await teacher.shot("t5-leader-menu");

  // A TV with no code yet shows one; the leader adds it; it becomes the screen.
  const tv = await device("tv");
  await tv.open("?read-room=pair&screen=1", 1440, false, 810);
  await sleep(2000);
  await tv.shot("t5-tv-pairing");
  await tv.open("?read-room=pair&screen=1", 1440, true, 810);
  await sleep(2000);
  await tv.shot("t5-tv-pairing");
  const shown = await tv.eval("return doc.querySelector('.rs-pair-code').textContent.replace(/\\s/g, '');");
  await teacher.type("input.rr-pair-input", shown.toLowerCase());
  await teacher.eval("doc.querySelector('input.rr-pair-input').form.requestSubmit(); return true;");
  await sleep(4500);
  await tv.shot("t5-tv-paired");

  // An adult room: the join page's name; an ended room and an unknown code.
  const host = await device("host");
  await host.open("?view=library&tab=dramas");
  const adult = await host.eval(`return await win.eval("API.read.create({ script_id: '${script.id}', script_revision: '${script.revision}', cast: [] }).then((s) => s.code)");`);
  const ann = await device("ann");
  await ann.open(`?read-room=${adult}`, 375, false, 700);
  await ann.type("input.rr-name-input", "Ann");
  await ann.shot("t5-join-name");
  rooms.get(adult).room.ended = true;
  await ann.click("button", "Join");
  await sleep(1200);
  await ann.shot("t5-join-ended");
  await ann.open("?read-room=ZZZZZZ", 375, false, 700);
  await ann.click("button", "Join");
  await sleep(1200);
  await ann.shot("t5-join-unknown");
}

main().catch((e) => { console.error(e); console.log("FAIL read_frames"); process.exit(1); });
