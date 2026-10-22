/* tv_reachability — can a remote actually REACH every control on the screen?
 *
 * "The screen follows the selection" is measured by tv_follow_focus.mjs. This is
 * the other half: "it is easy to navigate to ALL of the interface elements". They
 * are different properties. A screenshot shows a control; it does not show whether
 * four arrow keys can get to it. (A dead select on every leftmost element, and a
 * `.clickable` class that drew a whole programme guide while making it unreachable
 * by remote, both looked perfect in screenshots.)
 *
 * HOW. Every focusable is focused programmatically in turn and the four arrows are
 * pressed from it, recording where focus lands. That builds the real focus GRAPH.
 * A breadth-first walk from wherever the app puts focus at boot then says which
 * nodes are reachable; anything left over is on screen and unreachable.
 * Programmatic focus is only used to EXPLORE (you cannot teleport around a graph
 * otherwise); every edge is a real key event. It is sound because tv.js reads
 * document.activeElement rather than keeping a separate cursor.
 *
 * THE POOL IS DELIBERATELY WIDER THAN THE ENGINE'S. It is what a viewer can SEE
 * and would expect to reach: tv.js's FOCUSABLE rows, PLUS `[role="button"]` and
 * `[onclick]` — things that look and act like controls for a mouse. The engine
 * cannot land on those (no tabindex), so if one is on screen it is a MOUSE-ONLY
 * control, which on a TV means invisible. That asymmetry is the defect class this
 * tool exists for, and it is also the negative control (TV_PLANT=1).
 *
 * It DOES honour tabindex="-1": that is an author's declaration that an element is
 * not keyboard reachable (off-screen carousel slides, say), not an accident of
 * geometry, and counting those would be the tool inventing defects.
 *
 * CONTROLLED. TV_PLANT=1 plants a visible `<div role="button">PLANTED</div>` — in
 * the pool, excluded by the engine — which the run MUST report as UNREACHABLE.
 * Run it planted and unplanted: planted N+1 / 1 unreachable naming the plant,
 * unplanted N / 0. A control that has not been seen to fail proves nothing. Two
 * plants that do NOT work, so they are not retried: a focusable parked outside the
 * viewport (a spatial engine still reaches an off-screen box, so it is not
 * unreachable), and swallowing ArrowDown in a capture listener (tv.js registers its
 * own capture listener on window first).
 *
 * SCOPE. Static surfaces. A route that re-renders on focus cannot be walked
 * without disturbing itself; the run says NOT MEASURABLE rather than guessing.
 *
 *   node tools/tv_reachability.mjs
 *   TV_URL=http://127.0.0.1:8099/?tv=1 TV_ROUTES='#/,#/browse' node tools/tv_reachability.mjs
 *   TV_PLANT=1 node tools/tv_reachability.mjs          # the negative control
 *   TV_CAP=90 (nodes/route)  TV_SETTLE=90 (ms/press)
 */
import { openTv, noteSite, routeUrl, sleep, envList } from "./_tv_cdp.mjs";

const ROUTES = envList("TV_ROUTES", "#/");
/* Each element costs four presses, so a 400-tile grid is 1,600 of them. The cap
 * keeps a run to minutes; the routes worth walking exhaustively are the ones with
 * CONTROLS, not hundreds of identical tiles. */
const CAP = Number(process.env.TV_CAP || 90);
const SETTLE = Number(process.env.TV_SETTLE || 90);
const ARROWS = ["Up", "Down", "Left", "Right"];

/* SELF-CHECK of the walk itself, before any of it is believed. It runs every time
 * so a refactor cannot quietly break the one part that is pure logic. */
{
  const reach = (edges, seed, all) => {
    const seen = new Set([seed]); const q = [seed];
    while (q.length) { const c = q.shift();
      for (const nx of (edges.get(c) || [])) if (!seen.has(nx)) { seen.add(nx); q.push(nx); } }
    return all.filter((k) => !seen.has(k));
  };
  const e = new Map([["a", new Set(["b"])], ["b", new Set(["a"])], ["island", new Set()]]);
  const out = reach(e, "a", ["a", "b", "island"]);
  if (out.length !== 1 || out[0] !== "island") {
    console.log(`FAIL  the walk does not report an isolated node (got ${JSON.stringify(out)})`);
    process.exit(1);
  }
}

/* The pool (see the header for why it is wider than the engine's). */
const SEL = 'a[href]:not([tabindex="-1"])'
  + ',button:not([disabled]):not([tabindex="-1"])'
  + ',input:not([disabled]):not([tabindex="-1"])'
  + ',select:not([disabled]):not([tabindex="-1"])'
  + ',[tabindex]:not([tabindex="-1"])'
  + ',[role="button"]:not([tabindex="-1"])'
  + ',[onclick]:not([tabindex="-1"])';

/* A node is identified by its CONTENT: tag + text + an ordinal for duplicates.
 * Never an index injected into the DOM — a control that selects on focus rebuilds
 * the list under it, every injected tag goes stale mid-walk, and a page a remote
 * walks perfectly reads 15 of 16 unreachable. Never the class either — a class
 * carries STATE ("chip" vs "chip on"), which splits one element into two nodes and
 * invents unreachable ones. Both flaws were found by running the tool against a
 * page known to behave, and disbelieving it. */
const ENUM = `
  const SEL = ${JSON.stringify(SEL)};
  const seen = new Map();
  const list = [];
  for (const el of document.querySelectorAll(SEL)) {
    if (el.closest('[hidden]')) continue;
    const r = el.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) continue;
    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.display === 'none') continue;
    const base = el.tagName + '|'
      + (el.textContent || '').trim().replace(/\\s+/g, ' ').slice(0, 30);
    const n = (seen.get(base) || 0); seen.set(base, n + 1);
    list.push([base + '#' + n, el]);
  }`;
const KEYS_JS = `(() => { ${ENUM} return list.map((x) => x[0]); })()`;
const WHERE = `(() => { ${ENUM}
  const a = document.activeElement;
  const hit = list.find((x) => x[1] === a);
  return hit ? hit[0] : ''; })()`;
const focusKey = (k) => `(() => { ${ENUM}
  const hit = list.find((x) => x[0] === ${JSON.stringify(k)});
  if (!hit) return false;
  hit[1].focus();
  return document.activeElement === hit[1]; })()`;

noteSite();
const tv = await openTv("tv_reachability", { defaultPort: 9232 });
let totalUnreached = 0, totalNodes = 0, problems = 0;
console.log(`reachability: every focusable, four arrows each  @1920x1080  (cap ${CAP}/route)`
          + (process.env.TV_PLANT ? "  [NEGATIVE CONTROL PLANTED]" : "") + "\n");

for (const route of ROUTES) {
  await tv.navigate(routeUrl(route));

  // SETTLE FIRST. An engine may keep claiming focus for a while after a route
  // change (async render, an "arrival" that lands on the primary action), and stop
  // the moment a key arrives. So press one harmless pair to end that, then wait for
  // activeElement to hold still across two reads before tagging anything. Tagging
  // mid-arrival once reported 27 of 28 elements unreachable and 0 on the very next
  // run. An unstable measurement is worse than none: it invents defects.
  await tv.press("Down", SETTLE); await tv.press("Up", SETTLE);
  let last = null, stableFor = 0;
  for (let i = 0; i < 20 && stableFor < 2; i++) {
    const who = await tv.evaluate(`(() => { const a = document.activeElement;
      return a ? a.tagName + '|' + (a.textContent || '').trim().slice(0, 20) : 'none'; })()`);
    stableFor = who === last ? stableFor + 1 : 0;
    last = who;
    await sleep(150);
  }

  if (process.env.TV_PLANT) {
    await tv.evaluate(`(() => {
      const d = document.createElement('div');
      d.setAttribute('role', 'button');
      d.textContent = 'PLANTED';
      d.onclick = () => {};
      d.style.cssText = 'position:fixed;left:140px;top:520px;width:260px;height:60px;'
        + 'background:#c00;color:#fff;z-index:2147483647;';
      document.body.appendChild(d);
      return true;
    })()`);
  }

  const start = await tv.evaluate(WHERE);
  if (process.env.TV_DEBUG) console.log(`    [debug] boot focus = ${start || "(not in the pool)"}`);

  // A TV route always has SOMETHING focusable, so an empty pool is a broken probe,
  // not a clean route. A selector bug that made every evaluate() throw once printed
  // "nothing focusable" for every route and exited 0.
  if (!((await tv.evaluate(KEYS_JS)) || []).length) {
    console.log(`FAIL  ${route}  —  nothing focusable. A TV route always has a control,`);
    console.log("      so this is the probe failing, not a clean page.");
    tv.close(); process.exit(1);
  }

  /* WALK UNTIL THE PAGE STOPS GROWING. A lazy-loading grid appends tiles as focus
   * moves down it (measured: 85 -> 145, removed 0, added 60). That is not churn —
   * nothing walked went away, and appending at the END cannot renumber an earlier
   * key. But the new tiles were never focused, so edges OUT of them were never
   * recorded; the walk repeats, picking up whatever appeared, until nothing new. */
  const edges = new Map();
  let grew = 0;
  for (let round = 0; round < 6 && edges.size < CAP; round++) {
    const present = (await tv.evaluate(KEYS_JS)) || [];
    const todo = present.filter((k) => !edges.has(k)).slice(0, CAP - edges.size);
    if (!todo.length) break;
    if (round) grew += todo.length;
    for (const from of todo) {
      const to = new Set();
      for (const key of ARROWS) {
        if (!(await tv.evaluate(focusKey(from)))) continue;   // cannot hold focus / gone
        await tv.press(key, SETTLE);
        const landed = await tv.evaluate(WHERE);
        if (landed && landed !== from) to.add(landed);
      }
      edges.set(from, to);
    }
  }

  /* DID THE WALK CHANGE THE PAGE UNDER ITSELF? A control that re-renders on focus
   * (a chip that selects when focused, swapping the list below) MUTATES the thing
   * being measured: by the time the walk reaches a node, that node is gone, its
   * edges were never recorded, and everything downstream looks unreachable. REMOVAL
   * is the disqualifying event, not growth. A reader that cannot read SAYS SO —
   * never a confident list of defects that are not there. */
  const present = (await tv.evaluate(KEYS_JS)) || [];
  const now = new Set(present);
  const removed = [...edges.keys()].filter((k) => !now.has(k));
  if (removed.length) {
    problems++;
    console.log(`${route.slice(0, 40).padEnd(42)} ${edges.size} walked — NOT MEASURABLE:`);
    console.log(`      ${removed.length} element(s) already measured are gone, so the page`);
    console.log("      re-renders on focus and the graph is stale.");
    for (const r of removed.slice(0, 4)) console.log(`      gone: ${r}`);
    continue;
  }

  /* REACHABILITY IS ASYMMETRIC. A node the walk FINDS is proven reachable — no
   * unwalked graph can take that back. Only UNreachability needs the complete
   * graph. So an unfinished walk (a page that never stops growing) reports what it
   * PROVED and names what it could not settle, rather than refusing outright. */
  const unwalked = present.filter((k) => !edges.has(k));
  const pool = [...edges.keys()];
  // The seed must be INSIDE the pool, or the walk starts on an island and every
  // node — nav included — reads unreachable (measured: boot focus beyond the cap).
  const seed = start && edges.has(start) ? start : pool[0];
  const seen = new Set([seed]);
  const queue = [seed];
  while (queue.length) {
    const cur = queue.shift();
    for (const nx of (edges.get(cur) || [])) if (!seen.has(nx)) { seen.add(nx); queue.push(nx); }
  }
  const unreached = pool.filter((k) => !seen.has(k));

  if (unwalked.length) {
    console.log(`${route.slice(0, 40).padEnd(42)} ${seen.size} PROVEN reachable — the page kept `
              + `growing (${unwalked.length} unwalked), so`);
    console.log(`      the ${unreached.length} it did not reach are UNSETTLED, not defects.`);
    for (const u of unreached.slice(0, 6)) console.log(`      unsettled: ${u}`);
    continue;
  }

  totalNodes += pool.length; totalUnreached += unreached.length;
  console.log(`${route.slice(0, 40).padEnd(42)} ${pool.length} focusable, ${unreached.length} UNREACHABLE`
            + (grew ? `  (${grew} appeared while walking, all walked too)` : ""));
  for (const u of unreached.slice(0, 6)) console.log(`      ${u}`);
}

console.log(`\n${totalNodes} focusable elements walked, ${totalUnreached} that no arrow key reaches`
          + (problems ? `, ${problems} route(s) NOT MEASURABLE` : ""));
tv.close();
process.exit(totalUnreached || problems ? 1 : 0);
