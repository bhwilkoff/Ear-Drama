/* test_pulse_render.mjs — run the REAL pulse.js against a reading in a DOM
   shim, and assert every section builds.

   A screenshot proves a screen drew; it cannot prove that switching to the
   Roku tab does not throw, or that a platform with no data renders a sentence
   instead of an empty chart. Those are the two failures this page is most
   likely to have, so they get a test rather than an eyeball.

   The reading is pulse/fixture.json (tools/pulse_make_fixture.py), so the
   test runs before any credential exists. Pass a path to test a real one:

     node tools/test_pulse_render.mjs
     node tools/test_pulse_render.mjs ops/pulse.json
*/
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const readingPath = process.argv[2] ? resolve(process.argv[2]) : join(root, "pulse", "fixture.json");
const isFixture = !process.argv[2];

let pass = 0, fail = 0;
const check = (name, ok, detail = "") => {
  ok ? pass++ : fail++;
  console.log(`  ${ok ? "ok  " : "FAIL"} ${name}${ok ? "" : "  " + detail}`);
};

/* ── the shim ─────────────────────────────────────────────────────────── */
class El {
  constructor(tag = "div") {
    this.tagName = tag.toUpperCase();
    this.children = []; this.attrs = {}; this.style = { setProperty() {} }; this.dataset = {};
    this._text = ""; this._html = ""; this.hidden = false;
    this.classList = { _s: new Set(), add: (c) => this.classList._s.add(c), toggle() {} };
  }
  set className(v) { this.attrs.class = v; }
  get className() { return this.attrs.class || ""; }
  set textContent(v) { this._text = String(v); this.children = []; }
  get textContent() { return this._text + this.children.map((c) => c.textContent).join(""); }
  set innerHTML(v) { this._html = String(v); this.children = []; this._text = ""; }
  get innerHTML() { return this._html + this.children.map((c) => c.outerHTML).join(""); }
  get outerHTML() {
    return `<${this.tagName.toLowerCase()} class="${this.className}">`
      + this.innerHTML + (this._text || "") + `</${this.tagName.toLowerCase()}>`;
  }
  appendChild(c) { this.children.push(c); return c; }
  insertAdjacentHTML(_pos, html) { this._html += html; }
  setAttribute(k, v) { this.attrs[k] = String(v); }
  getAttribute(k) { return this.attrs[k] ?? null; }
  querySelectorAll() { return []; }
  querySelector() { return null; }
}

const IDS = ["product", "when", "status", "needs", "needs-n", "well", "well-n", "stores", "stores-n",
  "tiles", "trend", "said", "said-n", "said-chips", "social", "social-n", "sources", "src-n", "tabs",
  "sec-overview", "sec-reach", "sec-engagement", "sec-health", "sec-voice", "sec-search", "sec-ops",
  "sec-program", "sec-platform", "tiles-reach", "tiles-engagement", "tiles-health", "tiles-voice",
  "tiles-search", "tiles-ops", "tiles-program", "platform-lede", "platform-panels", "platform-rows",
  "platform-h2"];

function freshDom() {
  const byId = new Map(IDS.map((id) => [id, new El("div")]));
  byId.get("status").hidden = true;
  globalThis.document = {
    createElement: (t) => new El(t),
    getElementById: (id) => byId.get(id) ?? null,
    querySelectorAll: () => [],
    createTextNode: (t) => { const e = new El("span"); e.textContent = t; return e; },
  };
  return byId;
}

const g = globalThis;
g.location = { hash: "", pathname: "/pulse/", search: "" };
g.window = g;
g.addEventListener = () => {};
g.scrollTo = () => {};
g.history = { replaceState() {} };
const quiet = console.error;

const charts = readFileSync(join(root, "pulse", "charts.js"), "utf8");
const page = readFileSync(join(root, "pulse", "pulse.js"), "utf8");
function load(data) {
  g.fetch = () => Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(data) });
  return new Function(`${charts}\n${page}\nreturn { platforms, show, tabs, appPlatform, socialPlatform };`)();
}

/* ── the structural invariant, checked against the HTML itself ─────────
   `show()` toggles `hidden` on sections, which only works if none CONTAINS
   another. A refactor once nested #sec-platform inside #sec-overview and every
   platform tab rendered blank — populated, not hidden, and invisible. */
const html = readFileSync(join(root, "pulse", "index.html"), "utf8");
{
  const ovStart = html.indexOf('id="sec-overview"');
  let depth = 1, ovEnd = -1;   // the slice starts at the attribute: the div's own tag is behind us
  for (const m of html.slice(ovStart).matchAll(/<div\b|<\/div>/g)) {
    depth += m[0] === "</div>" ? -1 : 1;
    if (depth === 0) { ovEnd = ovStart + m.index; break; }
  }
  const plat = html.indexOf('id="sec-platform"');
  check("the platform section is a SIBLING of the overview, not inside it",
        plat > ovEnd || plat < ovStart, `overview ${ovStart}-${ovEnd}, platform ${plat}`);
  check("every element pulse.js asks for exists in index.html",
        IDS.every((id) => html.includes(`id="${id}"`)), IDS.filter((id) => !html.includes(`id="${id}"`)).join(", "));
}

/* ── load the real files against the reading ─────────────────────────── */
const DATA = JSON.parse(readFileSync(readingPath, "utf8"));
let byId = freshDom();
let api;
try {
  api = load(DATA);
  check("pulse.js loads and its fetch chain starts", true);
} catch (e) {
  check("pulse.js loads", false, e.message);
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(1);
}
await new Promise((r) => setTimeout(r, 30));   // let the fetch promise settle

check("the page drew without reporting a bug", byId.get("status").hidden === true,
      byId.get("status").textContent);
check("the product name comes from the reading, not the code",
      byId.get("product").textContent === (DATA.app?.name || ""), byId.get("product").textContent);

const list = api.platforms(DATA);
check("the data yields platforms", list.length > 0, String(list.length));

let threw = null;
for (const p of list) {
  try { api.show(DATA, list, p.key); } catch (e) { threw = `${p.key}: ${e.message}`; break; }
}
check("switching to every section renders without throwing", threw === null, threw || "");
for (const v of ["overview", "reach", "engagement", "health", "voice", "search", "program", "ops"]) {
  try { api.show(DATA, list, v); } catch (e) { threw = `${v}: ${e.message}`; break; }
}
check("switching to every view renders without throwing", threw === null, threw || "");

if (isFixture) {
  const appKeys = list.filter((p) => p.family === "app").map((p) => p.name);
  check("every app platform in the reading gets a section",
        ["tvOS", "iOS", "iPadOS", "macOS", "Android", "Web", "Fire TV", "Roku", "webOS"].every((n) => appKeys.includes(n)),
        appKeys.join(", "));
  check("every social platform gets a section",
        list.filter((p) => p.family === "social").length === 4, list.filter((p) => p.family === "social").map((p) => p.name).join(", "));

  /* Needs attention / Going well come from the RULES table. */
  const needs = byId.get("needs").textContent, well = byId.get("well").textContent;
  check("an unreplied 2-star review needs attention", /2★ on App Store/.test(needs), needs.slice(0, 200));
  check("a crash whose fix is in flight says 'in review', not 'fix it'", /Fix in review/.test(needs), needs.slice(0, 300));
  check("a crash with no fix recorded is a live crash", /Live ANR/.test(needs));
  check("a stale export shows as standing on an older reading", /playInstalls is standing on an older reading/.test(needs));
  check("Roku's crash share past 2% needs a decision", /Roku channel crashes/.test(needs));
  check("going well is not empty", well.length > 0 && !/Nothing moved/.test(well), well.slice(0, 120));

  /* A store with no API says so in words. */
  api.show(DATA, list, "webos");
  check("a store with no API says so in words, not an empty chart",
        /publishes no numbers we can read/i.test(byId.get("platform-rows").textContent));
  check("...and its lede names the store", /exposes no API/i.test(byId.get("platform-lede").innerHTML));

  /* Fire TV: Amazon HAS APIs. The no-API sentence is for LG / Samsung only. */
  api.show(DATA, list, "firetv");
  const fire = byId.get("platform-rows").textContent + byId.get("platform-panels").innerHTML;
  check("Fire TV does NOT claim Amazon publishes nothing", !/publishes no numbers we can read/i.test(fire));
  check("Fire TV reports its Vitals API state", /Vitals API/i.test(fire));
  check("Fire TV shows installs read from the sales report", /installs/i.test(byId.get("platform-panels").innerHTML));

  /* Roku: a report that carries crash counts and NO install column must not
     draw a zero. The series keeps only days that carry the column. */
  const roku = list.find((p) => p.key === "roku");
  check("Roku's install series skips days whose report has no install column",
        roku && roku.daily.length === 7 && roku.daily.every((r) => typeof r.v === "number" && r.v >= 0),
        JSON.stringify(roku && roku.daily.slice(-3)));
  api.show(DATA, list, "roku");
  check("Roku's lede says the dashboards are DELIVERED", /delivered to us daily/i.test(byId.get("platform-lede").innerHTML));

  /* Web: a visit and a route view are different things. */
  api.show(DATA, list, "web");
  const web = byId.get("platform-panels").innerHTML;
  check("web separates visits from route views", /Visits/.test(web) && /Route views/.test(web));
  check("...and says the older rows are not comparable", /not compared with visits/.test(web));

  api.show(DATA, list, "android");
  const android = byId.get("platform-panels").innerHTML;
  check("Android draws its installs as a dated chart", /c-time/.test(android));
  check("Android draws where they are as a dot plot", /c-dot/.test(android));
  check("Android draws its crashes as a pareto", /c-pareto/.test(android));

  api.show(DATA, list, "tvos");
  check("tvOS gets its OWN country split, not Apple's total",
        list.find((p) => p.key === "tvos").countries.US === DATA.health.appleDownloads.perDevice["Apple TV"].byCountry.US);

  /* Sources: three states, never two. */
  const src = byId.get("sources").textContent;
  check("a reader that is not configured is not reported as a failure",
        /not configured/.test(src) && !/could not read — not configured/.test(src), src.slice(0, 200));
  check("a reader that could not read says so", /could not read — no Mastodon credential/.test(src));

  /* Engagement: a server-side tally draws, labeled as what it counts. */
  check("a server-side tally draws on Engagement", /Rooms opened/.test(byId.get("tiles-engagement").innerHTML));

  /* Nothing about any real app leaks from the code. */
  const everything = [...byId.values()].map((e) => e.textContent + e.innerHTML).join(" ");
  check("no hard-coded app identity reaches the page",
        !/archive ?watch|archivewatch|bhwilkoff/i.test(everything + page + charts));
}

api.show(DATA, list, "overview");
check("overview comes back", byId.get("sec-overview").hidden === false);
check("and the platform section hides", byId.get("sec-platform").hidden === true);

/* ── a CODE error must not render as a DATA failure ────────────────────
   A renderer that throws once put "Could not load the readings" on the page —
   sending the reader to check data that was fine. It must say it is a bug,
   and the rest of the page must still draw. */
byId = freshDom();
console.error = () => {};
try {
  load({ ...DATA, stores: "not a list" });
  await new Promise((r) => setTimeout(r, 30));
} finally { console.error = quiet; }
const status = byId.get("status");
check("a renderer that throws is reported as a bug in pulse.js",
      status.hidden === false && /bug in pulse\.js, not a data problem/.test(status.textContent), status.textContent);
check("...not as a failure to load the data", !/Could not load/.test(status.textContent));
check("...and the rest of the page still draws", byId.get("sources").textContent.length > 0);

/* ── and a fetch failure IS a data failure ─────────────────────────── */
byId = freshDom();
g.fetch = () => Promise.resolve({ ok: false, status: 404, json: () => Promise.resolve({}) });
new Function(`${charts}\n${page}`)();
await new Promise((r) => setTimeout(r, 30));
check("a missing reading says it could not load, and how to make one",
      /Could not load the reading \(HTTP 404.*pulse_collect\.py --apply/.test(byId.get("status").textContent),
      byId.get("status").textContent);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
