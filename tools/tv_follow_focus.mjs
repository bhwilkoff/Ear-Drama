/* tv_follow_focus — does the screen actually follow the selection?
 *
 * Walk each route with the D-pad and assert, after EVERY press, that what the
 * focused element draws is entirely inside the OVERSCAN-SAFE band — the 5% a
 * television cuts off each side. A selection that is on screen in a browser and
 * under the bezel on a TV is exactly "the screen doesn't follow the rectangle",
 * and it is invisible to a screenshot taken at 1920x1080 on a desktop.
 *
 * THE BAND IS FOUR-SIDED, AND IT IS PRINTED. Checking against the VIEWPORT passed
 * footer links at y=1070 — inside 1080, and 44px inside what a TV does not show.
 * And the horizontal half of the band was once 0..1920 from the day the check was
 * written — i.e. not checked at all — so every "0 outside" before that was a
 * statement about top and bottom only. Enforcing it found a logo at left=78 the
 * first time it ran. The band is printed so a reader can see what was measured.
 *
 * JUDGE THE TEXT, NOT THE BOX. What a TV cuts is what the viewer must READ. A
 * box can legitimately run past the screen while everything readable in it sits
 * inside (a programme-guide block sized to a three-hour runtime is wider than 1920
 * by construction, its title at the left end). So the judged rect is the union of
 * the nodes that DRAW TEXT, falling back to the element's own box only when it
 * draws none — then the box IS the thing to see.
 *
 * THE PLAYER, which a focus probe cannot see: a TV player typically has no focused
 * element at all (the engine handles keys globally), and its transport is drawn
 * hard against the bottom edge, exactly where a TV cuts. It is measured by the
 * TEXT its transport draws, only when a <dialog> is open AND the <video> has a
 * source (a <video> element sitting in the markup is not a player — testing for
 * its existence reported "a player opened" on a screen where nothing had been
 * pressed). A player that opened with ZERO transport labels FAILS: a clean reading
 * from an empty probe is worse than no reading.
 *
 *   node tools/tv_follow_focus.mjs
 *   TV_ROUTES='#/,#/browse' TV_URL=http://127.0.0.1:8099/?tv=1 node tools/tv_follow_focus.mjs
 *   TV_PLAY_ROUTE='#/item/x' TV_PLAY_SELECTOR='#view-item .btn-primary' \
 *     TV_TRANSPORT_SELECTOR='[class*="tv-tp"]' node tools/tv_follow_focus.mjs
 */
import { openTv, noteSite, routeUrl, sleep, envList } from "./_tv_cdp.mjs";

const ROUTES = envList("TV_ROUTES", "#/");
/* 5% a side at 1920x1080 — keep in step with the overscan inset in tv.css. */
const SAFE_TOP = 54, SAFE_BOTTOM = 1026, SAFE_LEFT = 96, SAFE_RIGHT = 1824;

/* A walk that changes direction: a one-directional run never exercises the case
 * where the engine has to scroll BACK. Override with TV_KEYS. */
const WALK = envList("TV_KEYS",
  "Down,Down,Right,Right,Right,Down,Right,Down,Down,Right,Up,Left,Down,Down,Down,Right,Down,Down");

const PROBE = `(() => {
  const a = document.activeElement;
  if (!a || a === document.body) return JSON.stringify({ none: true });
  const boxes = [];
  const walk = (el) => {
    let own = '';
    for (const n of el.childNodes) if (n.nodeType === 3) own += n.textContent;
    if (own.trim()) {
      const cs = getComputedStyle(el);
      if (cs.visibility !== 'hidden' && cs.display !== 'none') {
        const b = el.getBoundingClientRect();
        if (b.width > 0 && b.height > 0) boxes.push(b);
      }
    }
    for (const c of el.children) walk(c);
  };
  walk(a);
  const r = boxes.length
    ? { top: Math.min(...boxes.map((b) => b.top)), bottom: Math.max(...boxes.map((b) => b.bottom)),
        left: Math.min(...boxes.map((b) => b.left)), right: Math.max(...boxes.map((b) => b.right)) }
    : a.getBoundingClientRect();
  return JSON.stringify({
    name: a.tagName + '|' + (a.textContent || '').trim().replace(/\\s+/g, ' ').slice(0, 28),
    judged: boxes.length ? 'text' : 'box',
    top: Math.round(r.top), bottom: Math.round(r.bottom),
    left: Math.round(r.left), right: Math.round(r.right),
  });
})()`;

noteSite();
const tv = await openTv("tv_follow_focus", { defaultPort: 9231 });
console.log(`overscan-safe band: x ${SAFE_LEFT}..${SAFE_RIGHT}, y ${SAFE_TOP}..${SAFE_BOTTOM}  @1920x1080\n`);

const outsideBand = (s) => {
  const off = [];
  if (s.top < SAFE_TOP) off.push(`top ${s.top}`);
  if (s.bottom > SAFE_BOTTOM) off.push(`bottom ${s.bottom}`);
  if (s.left < SAFE_LEFT) off.push(`left ${s.left}`);
  if (s.right > SAFE_RIGHT) off.push(`right ${s.right}`);
  return off;
};

let checks = 0, outside = 0, lost = 0;
for (const route of ROUTES) {
  await tv.navigate(routeUrl(route));
  const bad = [];
  let landed = 0, dropped = 0;
  for (const key of WALK) {
    await tv.press(key, 230);          // let a smooth scroll settle
    const s = JSON.parse(await tv.evaluate(PROBE));
    if (s.none) { dropped++; continue; }
    landed++;
    const off = outsideBand(s);
    if (off.length) bad.push(`${key} -> ${s.name} [${s.judged}]  ${off.join(", ")}`);
  }
  checks += landed; outside += bad.length; lost += dropped;
  console.log(`${route.padEnd(16)} ${landed} presses landed, ${dropped} lost focus, `
            + `${bad.length} outside the safe band`);
  bad.slice(0, 5).forEach((b) => console.log("      " + b));
}

const PLAY_ROUTE = process.env.TV_PLAY_ROUTE;
if (!PLAY_ROUTE) {
  console.log("\nplayer          not measured: set TV_PLAY_ROUTE (+ TV_PLAY_SELECTOR, "
            + "TV_TRANSPORT_SELECTOR) to include the player's transport");
} else {
  const PLAY_SEL = process.env.TV_PLAY_SELECTOR || ".btn-primary";
  const TRANSPORT = process.env.TV_TRANSPORT_SELECTOR || "[class*=\"transport\"]";
  await tv.navigate(routeUrl(PLAY_ROUTE), 4000);
  // Open the player DETERMINISTICALLY. This block measures the TRANSPORT, not
  // whether Play is reachable (tv_reachability does that), so a direct click costs
  // it nothing and makes it repeatable. Scope the selector to the view: every view
  // stays in the DOM hidden, and an unscoped match once clicked a different view's
  // button and never opened a player at all.
  const opened = await tv.evaluate(`(() => {
    const play = document.querySelector(${JSON.stringify(PLAY_SEL)});
    if (!play) return 'no element matches TV_PLAY_SELECTOR';
    play.click();
    return '';
  })()`);
  if (opened) {
    console.log(`\nplayer          NOT MEASURED: ${opened}`);
    lost++;
  } else {
    await sleep(5000);
    // A transport usually FADES with the controls; a press brings it back, and Up
    // is the one press that neither seeks nor toggles playback.
    await tv.press("Up", 600);
    const p = JSON.parse(await tv.evaluate(`(() => {
      const v = document.querySelector('video');
      const open = document.querySelector('dialog[open]');
      if (!v || !open || !v.currentSrc) return JSON.stringify({ noPlayer: true });
      const out = [];
      for (const el of document.querySelectorAll(${JSON.stringify(TRANSPORT)} + ', '
                                                + ${JSON.stringify(TRANSPORT)} + ' *')) {
        let own = '';
        for (const n of el.childNodes) if (n.nodeType === 3) own += n.textContent;
        own = own.trim();
        if (!own) continue;
        const cs = getComputedStyle(el);
        if (cs.visibility === 'hidden' || cs.display === 'none' || cs.opacity === '0') continue;
        const r = el.getBoundingClientRect();
        if (r.width <= 0 || r.height <= 0) continue;
        // All four sides travel, or a comparison against undefined is false both
        // ways and passes silently.
        out.push({ t: own.slice(0, 34), top: Math.round(r.top), bottom: Math.round(r.bottom),
                   left: Math.round(r.left), right: Math.round(r.right) });
      }
      return JSON.stringify({ items: out });
    })()`));
    if (p.noPlayer) {
      console.log(`\nplayer          NOT MEASURED: no open dialog with a playing <video> on ${PLAY_ROUTE}`);
      lost++;                            // never report this as a pass
    } else if (!p.items.length) {
      console.log("\nplayer          NOT MEASURED: a player opened but no transport label matched");
      console.log(`      ${TRANSPORT}. A clean reading from an empty probe is worse than none.`);
      lost++;
    } else {
      const bad = p.items.filter((i) => outsideBand(i).length);
      checks += p.items.length; outside += bad.length;
      console.log(`\nplayer          ${p.items.length} transport labels, ${bad.length} outside the safe band`);
      bad.slice(0, 5).forEach((b) =>
        console.log(`      "${b.t}"  top ${b.top} bottom ${b.bottom} left ${b.left} right ${b.right}`));
    }
  }
}

console.log(`\n${checks} checks across ${ROUTES.length} route(s) — ${outside} outside the `
          + `overscan-safe band, ${lost} lost focus / not measured`);
tv.close();
process.exit(outside || lost ? 1 : 0);
