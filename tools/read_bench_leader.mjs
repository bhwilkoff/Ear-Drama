/* read_bench_leader: the read-room bench's protocol leader (T7; docs/DEVICE-HARNESSES.md "Read-room bench").
 *
 *   node tools/read_bench_leader.mjs --base https://eardrama-api.benwilkoff.workers.dev [--script gut-7364]
 *
 * Opens an adult room (no account), leads it, and answers JSON lines on stdin with JSON lines on stdout. It is the
 * one place a press is timed: the press instant is the leader's own clock plus its measured offset from the Worker's
 * clock (ReadCore.clockOffset's rule: the smallest round trip wins), so every device's lit time can be put on the
 * same axis. It plays nothing and records nothing. Commands:
 *
 *   {"cmd":"press","n":100,"interval_ms":1500,"via":"socket"|"http","from":<index>}  -> {"presses":[...]}
 *   {"cmd":"snapshot"}                                                                -> {"snapshot":{...}}
 *   {"cmd":"mode","mode":"record"}                                                    -> {"snapshot":{...}}
 *   {"cmd":"pair","code":"ABC123"}                                                    -> {"paired":true}
 *   {"cmd":"inbox","wait_ms":30000}                                                   -> {"take":{...},"bytes":n} or {"take":null}
 *   {"cmd":"collect","on":true|false}                                                 -> hold the pickup in the background (a take is only accepted
 *                                                                                         while a receiver is there); every take lands in the list below
 *   {"cmd":"takes"}                                                                   -> {"takes":[{take,bytes,at}]} collected so far
 *   {"cmd":"end"}                                                                     -> closes the room and exits
 */
import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const arg = (k, d) => { const i = process.argv.indexOf(`--${k}`); return i > 0 ? process.argv[i + 1] : d; };
const BASE = arg("base", "https://eardrama-api.benwilkoff.workers.dev").replace(/\/$/, "");
const SCRIPT = arg("script", "gut-7364");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const out = (o) => process.stdout.write(JSON.stringify(o) + "\n");

const bundle = JSON.parse(fs.readFileSync(path.join(ROOT, "catalog/plays/castable-scripts.json"), "utf8"));
const script = bundle.scripts.find((s) => s.id === SCRIPT);
if (!script) { out({ error: "no_such_script", script: SCRIPT }); process.exit(2); }
const linePart = (l) => (l.kind === "speech" ? `role:${l.role || ""}` : l.kind === "direction" ? "directions" : "sound");
const cast = script.lines.map((l) => ({ id: l.id, part: linePart(l) }));

let samples = [];
const offsetNow = () => {
  let best = null;
  for (const s of samples) {
    const rtt = s.t1 - s.t0;
    if (!best || rtt < best.rtt) best = { rtt, offset: s.server_time - (s.t0 + s.t1) / 2 };
  }
  return best;
};
async function http(method, p, { key, body, raw, headers } = {}) {
  const t0 = Date.now();
  const r = await fetch(BASE + p, {
    method, headers: { ...(key ? { "x-read-key": key } : {}), ...(body ? { "content-type": "application/json" } : {}), ...(headers || {}) },
    body: raw ?? (body ? JSON.stringify(body) : undefined),
  });
  const t1 = Date.now();
  if (r.status === 204) return { status: 204 };
  const ct = r.headers.get("content-type") || "";
  if (!ct.includes("json")) return { status: r.status, response: r };
  const j = await r.json();
  if (typeof j.server_time === "number") samples.push({ t0, server_time: j.server_time, t1 });
  if (samples.length > 16) samples.shift();
  return { status: r.status, json: j };
}

const made = await http("POST", "/v1/read", { body: { script_id: SCRIPT, script_revision: script.revision, cast, mode: "read", owner_name: "Bench" } });
if (made.status !== 201 && made.status !== 200) { out({ error: "create_failed", status: made.status, body: made.json }); process.exit(3); }
const code = made.json.code;
const key = made.json.member_key;
let snap = made.json;
let ws = null;
let wsOpen = false;
const pending = [];
const wait = new Map();

function openSocket() {
  return new Promise((resolve) => {
    ws = new WebSocket(`${BASE.replace(/^http/, "ws")}/v1/read/${code}/socket`);
    ws.onopen = () => { ws.send(JSON.stringify({ type: "hello", key })); wsOpen = true; resolve(true); };
    ws.onerror = () => resolve(false);
    ws.onclose = () => { wsOpen = false; };
    ws.onmessage = (ev) => {
      const t1 = Date.now();
      let m; try { m = JSON.parse(ev.data); } catch { return; }
      if (m.type === "snapshot") {
        snap = m;
        if (typeof m.server_time === "number") { /* a snapshot's clock is not a round trip; only pongs are samples */ }
        for (const [line, f] of wait) if (m.cursor === line) { f(t1); wait.delete(line); }
      } else if (m.type === "pong") samples.push({ t0: m.t0, server_time: m.server_time, t1 });
    };
  });
}
const socketOk = await openSocket();
async function clockRounds(n = 8) {
  for (let i = 0; i < n; i++) {
    const t0 = Date.now();
    if (wsOpen) { ws.send(JSON.stringify({ type: "ping", t0 })); await sleep(120); }
    else { const r = await http("POST", `/v1/read/${code}/send`, { key, body: { type: "ping", t0 } }); void r; await sleep(60); }
  }
}
await clockRounds();
out({ ready: true, code, key, script: SCRIPT, revision: script.revision, lines: cast.map((c) => c.id), socket: socketOk, offset: offsetNow(), transport: made.json.transport });

const keep = setInterval(() => { if (wsOpen) ws.send(JSON.stringify({ type: "ping", t0: Date.now() })); }, 5000);

async function press(n, intervalMs, via, from) {
  const presses = [];
  let i = from ?? Math.max(0, cast.findIndex((c) => c.id === snap.cursor));
  for (let k = 0; k < n; k++) {
    i = (i + 1) % cast.length;
    const line = cast[i].id;
    const base = snap.cursor_gen;
    const t0 = Date.now();
    const off = offsetNow();
    let ack = null;
    const acked = new Promise((res) => { wait.set(line, res); setTimeout(() => res(null), 5000); });
    let err = null;
    if (via === "socket" && wsOpen) ws.send(JSON.stringify({ type: "cursor", line, base }));
    else {
      const r = await http("POST", `/v1/read/${code}/send`, { key, body: { type: "cursor", line, base } });
      if (r.json && r.json.type === "snapshot") { snap = r.json; wait.delete(line); ack = Date.now(); } else err = r.json || r.status;
    }
    if (via === "socket") ack = await acked;
    presses.push({ n: k + 1, line, base, press_local_ms: t0, press_server_ms: t0 + (off ? off.offset : NaN), ack_local_ms: ack, err });
    await sleep(intervalMs);
  }
  return presses;
}

let collecting = false;
const collected = [];
const collectErrors = [];
async function collectLoop() {
  while (collecting) {
    try {
      const r = await http("GET", `/v1/read/${code}/takes/inbox`, { key });
      if (r.status === 204 || !r.response) { if (r.status !== 204) collectErrors.push({ status: r.status, body: r.json, at: Date.now() }); await sleep(r.status === 204 ? 500 : 2000); continue; }
      let take = null; try { take = JSON.parse(r.response.headers.get("x-take") || "null"); } catch { /* none */ }
      collected.push({ take, bytes: (await r.response.arrayBuffer()).byteLength, at: Date.now() });
    } catch { await sleep(1000); }
  }
}

const rl = readline.createInterface({ input: process.stdin });
for await (const raw of rl) {
  let c; try { c = JSON.parse(raw); } catch { out({ error: "bad_json" }); continue; }
  try {
    if (c.cmd === "press") out({ presses: await press(c.n || 1, c.interval_ms ?? 1500, c.via || "socket", c.from), offset: offsetNow() });
    else if (c.cmd === "snapshot") { const r = await http("GET", `/v1/read/${code}`, { key }); out({ snapshot: r.json, status: r.status }); }
    else if (c.cmd === "mode") { const r = await http("POST", `/v1/read/${code}/send`, { key, body: { type: "mode", mode: c.mode } }); out({ snapshot: r.json, status: r.status }); }
    else if (c.cmd === "pair") { const r = await http("POST", `/v1/read/${code}/pair`, { key, body: { code: c.code } }); out({ ...r.json, status: r.status }); }
    else if (c.cmd === "inbox") {
      const t0 = Date.now(); const got = [];
      while (Date.now() - t0 < (c.wait_ms || 30000)) {
        const r = await http("GET", `/v1/read/${code}/takes/inbox`, { key });
        if (r.status === 204 || !r.response) { if (r.status !== 204) break; await sleep(500); continue; }
        let take = null; try { take = JSON.parse(r.response.headers.get("x-take") || "null"); } catch { /* none */ }
        const bytes = (await r.response.arrayBuffer()).byteLength;
        got.push({ take, bytes, at: Date.now() });
        if (got.length >= (c.count || 1)) break;
      }
      out({ takes: got });
    } else if (c.cmd === "collect") { const was = collecting; collecting = !!c.on; if (collecting && !was) void collectLoop(); out({ collecting }); }
    else if (c.cmd === "takes") out({ takes: collected.slice(), errors: collectErrors.slice(-5) });
    else if (c.cmd === "end") { await http("POST", `/v1/read/${code}/send`, { key, body: { type: "end" } }); out({ ended: true }); break; }
    else out({ error: "unknown_cmd" });
  } catch (e) { out({ error: String(e && e.message || e) }); }
}
clearInterval(keep);
try { ws && ws.close(); } catch { /* closed */ }
process.exit(0);
