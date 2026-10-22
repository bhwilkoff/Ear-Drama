/* tv_audit_sizes — is anything on the TV still built for a mouse?
 *
 * "Nothing should be optimized for a web interface" is a real instruction and it
 * deserves a real measurement rather than a designer's eye, because the failure
 * is specific and countable: type too small to read across a room, and targets too
 * small to land on with four arrows. Thresholds are the platform vendors' own:
 *   * Google's TV guidance: body text 24sp at 1080p, nothing legible below 18.
 *   * TV platforms ask for focusable targets ~48-64px tall; a D-pad lands on a
 *     whole element and a viewer cannot aim.
 *
 * Render at a true 1920x1080, walk the routes, and report every FOCUSABLE whose
 * text or box fails the floors, plus two independent questions a size floor can
 * never answer: do two text boxes OVERLAP, and is any text SQUEEZED (given less
 * height than the lines it may draw). It REPORTS a worklist (exit 0) unless
 * TV_STRICT=1 — a legitimately small thing is a judgement, not a bug.
 *
 * EXEMPTIONS: TV_EXEMPT is a comma list of class-name regexes. A floor with no
 * exceptions gets ignored, so an exception is NAMED and REASONED here rather than
 * the floor quietly lowered. Every entry in DEFAULT_EXEMPT must carry its reason:
 *   (none yet) — e.g. a third-party sign-in button whose size and type are fixed
 *   by the vendor's branding terms: /\bgsi-btn\b/ — "Google's guidelines fix it at
 *   40px / 14px; restyling it breaches them".
 *
 *   node tools/tv_audit_sizes.mjs
 *   TV_ROUTES='#/,#/browse' TV_KEYS=Down,Enter node tools/tv_audit_sizes.mjs
 */
import { openTv, noteSite, routeUrl, sleep, envList } from "./_tv_cdp.mjs";

const ROUTES = envList("TV_ROUTES", "#/");
/* TV_KEYS presses a sequence on each route BEFORE measuring — the only way to
 * reach an OVERLAY (a player is not a route; it opens on Enter). */
const KEYS = envList("TV_KEYS", "");
const MIN_FONT = 18;      // below this is not readable at ten feet
const MIN_TARGET = 44;    // below this is hard to land on with a D-pad
const DEFAULT_EXEMPT = [];
const EXEMPT = DEFAULT_EXEMPT.concat(envList("TV_EXEMPT", "").map((s) => new RegExp(s)));

const PROBE = `(() => {
  const SEL = 'a[href]:not([tabindex="-1"]),button:not([disabled]):not([tabindex="-1"]),'
    + 'input:not([disabled]):not([tabindex="-1"]),select:not([disabled]):not([tabindex="-1"]),'
    + '[tabindex]:not([tabindex="-1"])';
  const ownText = (el) => { let s = ''; for (const n of el.childNodes) if (n.nodeType === 3) s += n.textContent; return s.trim(); };
  const out = [];
  for (const el of document.querySelectorAll(SEL)) {
    if (el.closest('[hidden]')) continue;
    const r = el.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) continue;
    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.display === 'none') continue;
    // The floor applies to the node that DRAWS the text, which is not always the
    // focusable. A 24px card can hold a 15px span (that is how a placeholder card
    // shipped at 15px on a TV), and a button whose words all live in child spans
    // was once reported at 13px from its own inherited size while its labels were
    // 20-28px. So: the element's OWN direct text, then every descendant's.
    const own = ownText(el);
    let minFont = own ? Math.round(parseFloat(cs.fontSize) || 0) : Infinity;
    let minText = own.replace(/\\s+/g, ' ').slice(0, 34);
    let minCls = (el.className || '').toString().split(/\\s+/)[0] || '';
    const boxes = [];
    let squeezed = '';
    for (const d of el.querySelectorAll('*')) {
      const t = ownText(d);
      if (!t) continue;
      const dr = d.getBoundingClientRect();
      if (dr.width <= 0 || dr.height <= 0) continue;
      const dcs = getComputedStyle(d);
      if (dcs.visibility === 'hidden' || dcs.display === 'none') continue;
      const f = Math.round(parseFloat(dcs.fontSize) || 0);
      if (f > 0 && f < minFont) {
        minFont = f; minText = t.replace(/\\s+/g, ' ').slice(0, 34);
        minCls = (d.className || '').toString().split(/\\s+/)[0] || minCls;
      }
      boxes.push({ el: d, r: dr, t: t.slice(0, 24) });
      // SQUEEZED vs deliberately CLAMPED. A flex column shrinks its children, so a
      // text box can get less height than its lines and overflow:hidden cuts a line
      // in half — 390 guide titles once, while every other signal here read zero.
      // A -webkit-line-clamp box is MEANT to stop at N lines; the question is
      // whether the box is shorter than the lines the design allots it.
      if (!squeezed && dcs.overflow !== 'visible') {
        const lh = parseFloat(dcs.lineHeight) || 0;
        if (lh) {
          const clamp = parseInt(dcs.webkitLineClamp, 10);
          const allowed = Number.isFinite(clamp) && clamp > 0 ? Math.round(lh * clamp) : d.scrollHeight;
          const want = Math.min(d.scrollHeight, allowed);
          if (d.clientHeight > 0 && d.clientHeight < want - 1) {
            squeezed = JSON.stringify(t.slice(0, 24)) + ' got ' + d.clientHeight + 'px, needs ' + want;
          }
        }
      }
    }
    // OVERLAPPING TEXT: a size floor proves type is big enough, never that it
    // FITS — and enlarging type for TV is what makes it stop fitting. Never an
    // ancestor against its own descendant: a caption holding a role <span>
    // contains it by definition (the false positive the first real page produced).
    let overlap = '';
    for (let i = 0; i < boxes.length && !overlap; i++) {
      for (let j = i + 1; j < boxes.length; j++) {
        if (boxes[i].el.contains(boxes[j].el) || boxes[j].el.contains(boxes[i].el)) continue;
        const a = boxes[i].r, b = boxes[j].r;
        const ox = Math.min(a.right, b.right) - Math.max(a.left, b.left);
        const oy = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
        if (ox > 2 && oy > 2) { overlap = JSON.stringify(boxes[i].t) + ' over ' + JSON.stringify(boxes[j].t); break; }
      }
    }
    out.push({ tag: el.tagName.toLowerCase(), cls: minCls, text: minText,
               font: Number.isFinite(minFont) ? minFont : 0, overlap, squeezed,
               h: Math.round(r.height), w: Math.round(r.width) });
  }
  return out;
})()`;

noteSite();
const tv = await openTv("tv_audit_sizes", { defaultPort: 9224 });
let findings = 0, checked = 0;
console.log(`thresholds: font >= ${MIN_FONT}px, focusable height >= ${MIN_TARGET}px, `
          + "no overlapping or squeezed text  @1920x1080\n");

for (const route of ROUTES) {
  await tv.navigate(routeUrl(route), 2600);
  for (const k of KEYS) await tv.press(k, 900);
  const els = (await tv.evaluate(PROBE)) || [];
  checked += els.length;
  // The font floor applies only to elements that HAVE text: a carousel dot is an
  // empty button, and a checker that cries about unreadable nothing gets ignored.
  const bad = els.filter((e) => ((e.text && e.font < MIN_FONT) || e.h < MIN_TARGET
                                 || e.overlap || e.squeezed)
                             && !EXEMPT.some((re) => re.test(e.cls)));
  console.log(`${route}  —  ${els.length} focusable, ${bad.length} below the floor`);
  const seen = new Set();
  for (const b of bad) {
    const key = `${b.tag}.${b.cls}:${b.font}:${b.h}:${b.overlap ? "ov" : ""}:${b.squeezed ? "sq" : ""}`;
    if (seen.has(key)) continue;            // one line per KIND, not per instance
    seen.add(key);
    findings++;
    const why = [b.text && b.font < MIN_FONT ? `font ${b.font}px` : null,
                 b.h < MIN_TARGET ? `height ${b.h}px` : null,
                 b.overlap ? `TEXT OVERLAP: ${b.overlap}` : null,
                 b.squeezed ? `TEXT SQUEEZED: ${b.squeezed}` : null].filter(Boolean).join(", ");
    console.log(`    ${b.tag}.${b.cls || "—"}  ${why}   "${b.text}"`);
  }
}
// Zero focusables across every route is a broken probe, not a perfect TV UI.
if (!checked) {
  console.log("\nFAIL  no focusable elements found on any route — the probe is not seeing the app");
  tv.close(); process.exit(1);
}
console.log(`\n${checked} focusable elements checked, ${findings} distinct kinds below the TV floor`);
tv.close();
await sleep(0);
process.exit(process.env.TV_STRICT && findings ? 1 : 0);
