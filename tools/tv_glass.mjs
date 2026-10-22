/* tv_glass — see the web-TV app the way a TV shows it, and drive it the way a
 * remote drives it.
 *
 * WHY THIS EXISTS. TV "testing" in a desktop Chrome window with a mouse is not TV
 * testing: the window cannot be a true 1920x1080 on a laptop display, and a mouse
 * can reach anything. A remote reaches only what the focus engine finds, by
 * pressing a direction — which is how a hero with no focusable child and four
 * dead filters both passed a "check" and failed on a real television.
 *
 * So: a real 1920x1080 (headless, see _tv_cdp.mjs), real key events, and a
 * SCREENSHOT OF EVERY PRESS plus a trace of what had focus and whether the viewer
 * could see it — the question a screenshot alone cannot answer, and the one a
 * "the screen doesn't follow the selection" report is about.
 *
 *   node tools/tv_glass.mjs                       # walk "#/", Down x12
 *   node tools/tv_glass.mjs '#/browse' 24         # a route and a press count
 *   TV_KEYS=Down,Down,Right,Enter node tools/tv_glass.mjs
 *   TV_URL=http://127.0.0.1:8099/?tv=1 node tools/tv_glass.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { openTv, noteSite, routeUrl, KEYS, sleep, envList } from "./_tv_cdp.mjs";

const ROUTE = process.argv[2] || "#/";
const PRESSES = Number(process.argv[3] || 12);
const HYDRATE = Number(process.env.TV_SETTLE || 9000);

noteSite();
const tv = await openTv("tv_glass", { defaultPort: 9223 });

// Hydrate is measured, not a guess: shots taken earlier show an empty shell while
// the app is still fetching its data.
await tv.navigate(routeUrl(ROUTE), HYDRATE);

const probe = `(() => {
  const a = document.activeElement;
  if (!a || a === document.body) return { focused: null, viewport: innerWidth + 'x' + innerHeight };
  const b = a.getBoundingClientRect();
  return {
    focused: (a.textContent || '').trim().replace(/\\s+/g, ' ').slice(0, 40) || a.tagName,
    tag: a.tagName,
    top: Math.round(b.top), bottom: Math.round(b.bottom),
    left: Math.round(b.left), right: Math.round(b.right),
    inView: b.top >= 0 && b.bottom <= innerHeight && b.left >= 0 && b.right <= innerWidth,
    offBy: b.top < 0 ? Math.round(b.top)
         : b.bottom > innerHeight ? Math.round(b.bottom - innerHeight) : 0,
    viewport: innerWidth + 'x' + innerHeight,
  };
})()`;

const keys = envList("TV_KEYS", Array(PRESSES).fill("Down").join(","));
const unknown = keys.filter((k) => !KEYS[k]);
if (unknown.length) {
  // An unknown key silently skipped would look like a press that did nothing.
  console.log(`FAIL  unknown key(s) ${unknown.join(", ")} — have ${Object.keys(KEYS).join(", ")}`);
  tv.close(); process.exit(1);
}

const log = [];
await tv.shot("00-start");
log.push({ step: 0, key: "(start)", ...(await tv.evaluate(probe)) });

for (let i = 0; i < keys.length; i++) {
  await tv.press(keys[i], 500);
  log.push({ step: i + 1, key: keys[i], ...(await tv.evaluate(probe)) });
  await tv.shot(String(i + 1).padStart(2, "0") + "-" + keys[i]);
}
fs.writeFileSync(path.join(tv.out, "trace.json"), JSON.stringify(log, null, 1));
tv.close();

// The verdict, in the terminal, so a failure does not need the images opened.
console.log(`viewport ${log[0].viewport}   shots -> ${tv.out}`);
console.log("step key    focused                                   top  inView");
for (const r of log) {
  console.log(`${String(r.step).padStart(4)} ${r.key.padEnd(6)} `
    + `${String(r.focused ?? "—").padEnd(41)} ${String(r.top ?? "").padStart(5)}  `
    + `${r.focused == null ? "" : (r.inView ? "yes" : `NO (off by ${r.offBy})`)}`);
}
const blind = log.filter((r) => r.focused && !r.inView);
const none = log.filter((r) => r.step > 0 && r.focused == null);
console.log(blind.length
  ? `\n!! ${blind.length} of ${log.length} presses left focus OFF SCREEN`
  : "\nevery focused element was visible");
if (none.length) console.log(`!! ${none.length} press(es) left NOTHING focused`);
await sleep(0);
process.exit(blind.length || none.length ? 1 : 0);
