/* _tv_cdp — the shared Chrome DevTools harness behind the web-TV glass tools
 * (tv_glass, tv_reachability, tv_follow_focus, tv_audit_sizes).
 *
 * WHY HEADLESS AT 1920x1080. A laptop display is ~1512 CSS px wide at dpr 2, so a
 * true 1920x1080 CSS viewport CANNOT be opened in a desktop Chrome window on it —
 * every "TV" reading taken that way was taken at three quarters of TV width.
 * Headless Chrome has no physical display, so it renders a real 1920x1080, and
 * --force-device-scale-factor=1 stops the capture coming back at the host's dpr
 * with every size reading doubled.
 *
 * WHY KEY EVENTS. Input goes through Input.dispatchKeyEvent — a genuine key event
 * the app's focus engine sees. Never el.focus() or a synthetic click for
 * NAVIGATION: a mouse (or a script) can reach anything, a remote can reach only
 * what the focus engine finds, in the order it finds it. (tv_reachability focuses
 * nodes programmatically only to EXPLORE the graph; every edge is still a key.)
 *
 * Dependency-free on purpose: Node 22+ has WebSocket, and CDP is JSON over one.
 *
 * Env (shared by every tool):
 *   TV_URL     the whole address, ?tv=1 included (default http://127.0.0.1:8080/?tv=1,
 *              the local dev server — `python3 -m http.server 8080`)
 *   TV_BASE    a base URL; ?tv=1 is appended. Honoured because it is the obvious
 *              guess, and getting it wrong is SILENT: the tool happily measures
 *              PRODUCTION while you believe you are testing your edit.
 *   TV_PORT    the DevTools port        TV_CHROME  the Chrome binary
 *   TV_OUT     output directory (default build/qa/tv-glass-<date>/<tool>-<epoch>)
 */
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export const SITE = process.env.TV_URL
  || (process.env.TV_BASE
        ? process.env.TV_BASE.replace(/\/+$/, "") + "/?tv=1"
        : "http://127.0.0.1:8080/?tv=1");

/** Is this the working tree, or somebody's live site? Say so either way. */
export function noteSite() {
  if (!/\/\/(127\.0\.0\.1|localhost)(:|\/)/.test(SITE)) {
    console.log(`NOTE: measuring a LIVE site (${SITE}), not your working tree — `
              + "set TV_URL=http://127.0.0.1:<port>/?tv=1 to test a local edit.\n");
  }
}

/** A route URL: the site without its hash, plus the route. */
export const routeUrl = (route) => SITE.split("#")[0] + route;

export const KEYS = {
  Up:    { windowsVirtualKeyCode: 38, key: "ArrowUp",    code: "ArrowUp" },
  Down:  { windowsVirtualKeyCode: 40, key: "ArrowDown",  code: "ArrowDown" },
  Left:  { windowsVirtualKeyCode: 37, key: "ArrowLeft",  code: "ArrowLeft" },
  Right: { windowsVirtualKeyCode: 39, key: "ArrowRight", code: "ArrowRight" },
  Enter: { windowsVirtualKeyCode: 13, key: "Enter",      code: "Enter" },
  Back:  { windowsVirtualKeyCode: 8,  key: "Backspace",  code: "Backspace" },
};

export function outDir(tool) {
  const day = new Date().toISOString().slice(0, 10);
  const dir = process.env.TV_OUT
    || path.join(ROOT, "build", "qa", `tv-glass-${day}`, `${tool}-${Math.floor(Date.now() / 1000)}`);
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

const CHROME = process.env.TV_CHROME
  || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

/**
 * Start a fresh headless Chrome and attach to its page. Returns a session:
 *   { cdp, evaluate, press, shot, navigate, close, out }
 * Every exit path kills Chrome — including an exception or a signal — because a
 * browser left on the port poisons the NEXT run (see the guard below).
 */
export async function openTv(tool, { defaultPort = 9230 } = {}) {
  const PORT = Number(process.env.TV_PORT || defaultPort);
  const out = outDir(tool);

  /* A browser left on this port by an earlier run is not a convenience. Chrome
   * cannot bind an occupied port, so the new process serves nothing and
   * /json/list answers from the OLD browser — which still holds the previous
   * run's page AND its stylesheet. A planted control was once reverted on disk and
   * the next run still measured the plant, because it never spoke to a new browser
   * at all. A per-run --user-data-dir does not protect against this; only the
   * port does. */
  try {
    const r = await fetch(`http://127.0.0.1:${PORT}/json/version`,
                          { signal: AbortSignal.timeout(800) });
    if (r.ok) {
      console.log(`FAIL  a browser is already on port ${PORT}. A run that attaches to it`);
      console.log(`      measures that browser's page, not a fresh one. Close it first:`);
      console.log(`      pkill -f "remote-debugging-port=${PORT}"`);
      process.exit(1);
    }
  } catch { /* nothing listening — good */ }

  if (!fs.existsSync(CHROME)) {
    console.log(`FAIL  no Chrome at ${CHROME} (set TV_CHROME)`);
    process.exit(1);
  }

  const chrome = spawn(CHROME, [
    "--headless=new",
    `--remote-debugging-port=${PORT}`,
    "--window-size=1920,1080",
    "--force-device-scale-factor=1",
    "--hide-scrollbars",
    "--no-first-run", "--no-default-browser-check",
    // A FRESH profile every run, under the output dir (never /tmp). A reused one
    // serves a cached stylesheet, and a stale stylesheet does not fail — it
    // reports the OLD layout as the current one.
    `--user-data-dir=${path.join(out, "profile-" + process.pid)}`,
    "about:blank",
  ], { stdio: ["ignore", "ignore", "pipe"] });

  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    try { ws?.close(); } catch { /* already closed */ }
    try { chrome.kill("SIGKILL"); } catch { /* already gone */ }
    // The profile is scratch; the screenshots and traces beside it are the record.
    // SIGKILL is delivered asynchronously and a dying Chrome still writes into its
    // profile, so a delete straight after the kill leaves the directory behind.
    // Wait (synchronously — this also runs from the 'exit' handler) and retry.
    const prof = path.join(out, "profile-" + process.pid);
    for (let i = 0; i < 10 && fs.existsSync(prof); i++) {
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 200);
      try { fs.rmSync(prof, { recursive: true, force: true }); } catch { /* retry */ }
    }
  };
  process.on("exit", close);
  for (const sig of ["SIGINT", "SIGTERM"]) process.on(sig, () => { close(); process.exit(130); });
  process.on("uncaughtException", (e) => { console.error(e?.message || e); close(); process.exit(1); });
  process.on("unhandledRejection", (e) => { console.error(e?.message || e); close(); process.exit(1); });

  let target, ws;
  for (let i = 0; i < 80 && !target; i++) {
    await sleep(250);
    try {
      target = (await fetch(`http://127.0.0.1:${PORT}/json/list`).then((r) => r.json()))
        .find((t) => t.type === "page");
    } catch { /* not up yet */ }
  }
  if (!target) { console.log("FAIL  Chrome did not expose a page target"); close(); process.exit(1); }

  ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  let id = 0;
  const pending = new Map();
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); }
  };
  const cdp = (method, params = {}) => new Promise((res) => {
    const n = ++id; pending.set(n, res);
    ws.send(JSON.stringify({ id: n, method, params }));
  });

  await cdp("Page.enable");
  await cdp("Runtime.enable");
  await cdp("Emulation.setDeviceMetricsOverride",
            { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false });

  const evaluate = async (expr) =>
    (await cdp("Runtime.evaluate", { expression: expr, returnByValue: true, awaitPromise: true }))
      ?.result?.value;

  const press = async (name, settle = 400) => {
    const k = KEYS[name];
    if (!k) throw new Error(`unknown key ${name} (have ${Object.keys(KEYS).join(", ")})`);
    await cdp("Input.dispatchKeyEvent", { type: "keyDown", ...k });
    await cdp("Input.dispatchKeyEvent", { type: "keyUp", ...k });
    await sleep(settle);
  };

  const shot = async (name) => {
    const r = await cdp("Page.captureScreenshot", { format: "png" });
    const file = path.join(out, name + ".png");
    fs.writeFileSync(file, Buffer.from(r.data, "base64"));
    return file;
  };

  const navigate = async (url, settle = 3200) => {
    await cdp("Page.navigate", { url });
    await sleep(settle);
  };

  return { cdp, evaluate, press, shot, navigate, close, out, port: PORT };
}

/** Env list helper: "a,b,c" -> ["a","b","c"], falling back to `dflt`. */
export const envList = (name, dflt) =>
  (process.env[name] || dflt).split(",").map((s) => s.trim()).filter(Boolean);
