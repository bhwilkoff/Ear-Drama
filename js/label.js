/**
 * Draws the label (WEB-DESIGN §6.4r): js/label-core.js decides, this paints, as inline SVG in a window
 * (crisp from 32 px to a 1920 px hero) or onto a canvas for the lock screen's PNG (Media Session takes a
 * raster). Colors are the token references the spec names, as the page's CSS variables, so light and
 * dark follow the theme with no redraw.
 */
const Label = (() => {
  'use strict';
  const NS = 'http://www.w3.org/2000/svg';
  let seq = 0;

  const kebab = (s) => s.replace(/[A-Z]/g, (c) => '-' + c.toLowerCase());
  /** A token reference as its CSS variable: board.mystery is --color-board-mystery, brand.text --color-text. */
  function cssVar(ref) {
    const [group, name] = String(ref).split('.');
    return group === 'brand' || group === 'semantic' ? `--color-${kebab(name)}` : `--color-${kebab(group)}-${kebab(name)}`;
  }
  const col = (ref) => `var(${cssVar(ref)})`;
  const pol = (r, deg) => { const a = (deg * Math.PI) / 180; return [50 + r * Math.cos(a), 50 - r * Math.sin(a)]; };
  const f2 = (v) => +v.toFixed(2);
  /** An arc drawn clockwise on screen from `from` to `to` (degrees, from > to). */
  function arcPath(r, from, to) {
    const [x0, y0] = pol(r, from), [x1, y1] = pol(r, to);
    return `M${f2(x0)} ${f2(y0)} A${r} ${r} 0 ${from - to > 180 ? 1 : 0} 1 ${f2(x1)} ${f2(y1)}`;
  }
  const full = (a) => a.from - a.to >= 359.99;

  function node(tag, attrs, ...kids) {
    const n = document.createElementNS(NS, tag);
    for (const [k, v] of Object.entries(attrs)) if (v !== null && v !== undefined) n.setAttribute(k, String(v));
    n.append(...kids);
    return n;
  }
  const fillOn = (ref, opacity) => ({ style: `fill: ${col(ref)}`, ...(opacity !== undefined && opacity < 1 ? { 'fill-opacity': opacity } : {}) });
  const strokeOn = (ref, width, opacity, cap = 'butt') => ({ fill: 'none', style: `stroke: ${col(ref)}`, 'stroke-width': width, 'stroke-linecap': cap,
                                                            ...(opacity !== undefined && opacity < 1 ? { 'stroke-opacity': opacity } : {}) });

  /** An arc with a round end drawn as a dot, so each end keeps its own cap (a clamped end stays square). */
  function arcNodes(a, ref) {
    if (full(a)) return [node('circle', { cx: 50, cy: 50, r: a.r, ...strokeOn(ref, a.width) })];
    const out = [node('path', { d: arcPath(a.r, a.from, a.to), ...strokeOn(ref, a.width) })];
    for (const [deg, cap] of [[a.from, a.capFrom], [a.to, a.capTo]]) {
      if (cap !== 'round') continue;
      const [x, y] = pol(a.r, deg);
      out.push(node('circle', { cx: f2(x), cy: f2(y), r: a.width / 2, ...fillOn(ref) }));
    }
    return out;
  }

  /** The spec as an inline SVG. `overlay` leaves the ground out (a play's rules over its page). */
  function svg(spec, { overlay = false } = {}) {
    const s = spec, on = s.on, kids = [];
    if (!overlay) kids.push(node('rect', { width: 100, height: 100, ...fillOn(s.ground) }));
    if (s.cast) s.cast.bars.forEach((b) => kids.push(node('rect', { x: b.x, y: b.y, width: b.w, height: b.h, rx: b.h / 2, ...fillOn(on) })));
    if (s.ruler) {
      const R = s.ruler, ticks = [];
      for (let i = 0; i <= 7; i++) { const x = f2(R.x0 + i * R.cell); ticks.push(node('line', { x1: x, y1: f2(R.y - R.tick), x2: x, y2: f2(R.y + R.tick) })); }
      kids.push(node('g', strokeOn(on, R.width, R.opacity), node('line', { x1: R.x0, y1: R.y, x2: f2(R.x0 + R.span), y2: R.y }), ...ticks));
      if (R.lit >= 0) kids.push(node('rect', { x: f2(R.x0 + R.lit * R.cell + R.inset), y: f2(R.y - R.h / 2), width: f2(R.cell - 2 * R.inset), height: R.h, rx: R.h / 2, ...fillOn(on) }));
    }
    if (s.disc) kids.push(node('circle', { cx: 50, cy: 50, r: s.disc.r, ...fillOn(on, s.disc.opacity) }));
    if (s.grooves) kids.push(node('g', strokeOn(on, s.grooves.width, s.grooves.opacity), ...s.grooves.radii.map((r) => node('circle', { cx: 50, cy: 50, r }))));
    if (s.ticks) {
      kids.push(node('g', strokeOn(on, s.ticks.width, s.ticks.opacity), ...s.ticks.deg.map((d) => {
        const [x0, y0] = pol(s.ticks.r0, d), [x1, y1] = pol(s.ticks.r1, d);
        return node('line', { x1: f2(x0), y1: f2(y0), x2: f2(x1), y2: f2(y1) });
      })));
    }
    if (s.ring) kids.push(node('circle', { cx: 50, cy: 50, r: s.ring.r, ...strokeOn(on, s.ring.width, s.ring.opacity) }));
    if (s.arc) kids.push(...arcNodes(s.arc, on));
    if (s.parts) {
      kids.push(node('circle', { cx: 50, cy: 50, r: s.parts.r, ...strokeOn(s.parts.backing.color, s.parts.backing.width) }));
      for (const g of s.parts.segments) {
        kids.push(full(g) ? node('circle', { cx: 50, cy: 50, r: s.parts.r, ...strokeOn(g.color, s.parts.width) })
          : node('path', { d: arcPath(s.parts.r, g.from, g.to), ...strokeOn(g.color, s.parts.width) }));
      }
    }
    if (s.evening) {
      const [x0, y0] = pol(s.evening.r0, s.evening.deg), [x1, y1] = pol(s.evening.r1, s.evening.deg);
      kids.push(node('line', { x1: f2(x0), y1: f2(y0), x2: f2(x1), y2: f2(y1), ...strokeOn(on, s.evening.width, 1, 'round') }));
    }
    if (s.label) kids.push(node('circle', { cx: 50, cy: 50, r: s.label.r, ...fillOn(on) }));
    for (const t of s.text) {
      kids.push(node('text', { x: t.x, y: t.y, 'text-anchor': t.anchor, 'font-size': t.size, class: `lb-${t.face}`,
                               'letter-spacing': t.tracking ? f2(t.tracking * t.size) : null,
                               ...fillOn(t.fill === 'ground' ? s.ground : on, t.opacity) }, t.s));
    }
    if (s.cols) s.cols.bars.forEach((b) => kids.push(node('rect', { x: b.x, y: b.y, width: b.w, height: b.h, ...fillOn(on, b.rest ? s.cols.restOpacity : 1) })));
    if (s.rim) {
      const id = `lb-rim-${++seq}`, half = 180 - 30;
      kids.push(node('path', { id, d: arcPath(s.rim.r, s.rim.centerDeg + half, s.rim.centerDeg - half), fill: 'none' }));
      kids.push(node('text', { 'font-size': s.rim.size, 'letter-spacing': f2(s.rim.tracking * s.rim.size), class: 'lb-body', ...fillOn(on, s.rim.opacity) },
        node('textPath', { href: `#${id}`, startOffset: '50%', 'text-anchor': 'middle' }, s.rim.text)));
    }
    if (s.rules) {
      // The page's foot, in the page's own ground, so the opening's last line never runs under the rules.
      kids.push(node('rect', { x: 0, y: s.rules.foot, width: 100, height: 100 - s.rules.foot, ...fillOn(s.ground) }));
      for (let i = 0; i < s.rules.count; i++) {
        kids.push(node('rect', { x: s.rules.x0 + i * (s.rules.len + s.rules.gap), y: s.rules.y - s.rules.width / 2, width: s.rules.len, height: s.rules.width,
                                 ...fillOn(on, s.rules.opacity) }));
      }
    }
    return node('svg', { class: `lb lb-${s.kind}${overlay ? ' lb-overlay' : ''}`, viewBox: `0 0 ${s.viewBox} ${s.viewBox}`, 'aria-hidden': 'true',
                         focusable: 'false', 'data-tier': s.tier,
                         'data-r': s.label ? s.label.r : s.ring ? s.ring.r : null }, ...kids);
  }

  /** The spec painted on a canvas `px` square (the lock screen's art), its colors read from `el`'s CSS. */
  function paint(ctx, spec, px, el = document.documentElement) {
    const s = spec, k = px / s.viewBox, cs = getComputedStyle(el);
    const c = (ref) => cs.getPropertyValue(cssVar(ref)).trim() || '#888';
    const face = (f) => cs.getPropertyValue(f === 'display' ? '--font-display' : '--font-body').trim() || 'sans-serif';
    const P = (r, deg) => pol(r, deg).map((v) => v * k);
    const ring = (r, from, to) => { ctx.beginPath(); ctx.arc(50 * k, 50 * k, r * k, (-from * Math.PI) / 180, (-to * Math.PI) / 180, false); };
    const stroke = (ref, w, a = 1, cap = 'butt') => { ctx.globalAlpha = a; ctx.strokeStyle = c(ref); ctx.lineWidth = w * k; ctx.lineCap = cap; ctx.stroke(); ctx.globalAlpha = 1; };
    const fill = (ref, a = 1) => { ctx.globalAlpha = a; ctx.fillStyle = c(ref); ctx.fill(); ctx.globalAlpha = 1; };
    const dot = (r, deg, rad, ref) => { const [x, y] = P(r, deg); ctx.beginPath(); ctx.arc(x, y, rad * k, 0, 2 * Math.PI); fill(ref); };
    ctx.fillStyle = c(s.ground); ctx.fillRect(0, 0, px, px);
    if (s.cast) s.cast.bars.forEach((b) => { ctx.beginPath(); ctx.rect(b.x * k, b.y * k, b.w * k, b.h * k); fill(s.on); });
    if (s.ruler) {
      const R = s.ruler;
      ctx.beginPath(); ctx.moveTo(R.x0 * k, R.y * k); ctx.lineTo((R.x0 + R.span) * k, R.y * k);
      for (let i = 0; i <= 7; i++) { const x = (R.x0 + i * R.cell) * k; ctx.moveTo(x, (R.y - R.tick) * k); ctx.lineTo(x, (R.y + R.tick) * k); }
      stroke(s.on, R.width, R.opacity);
      if (R.lit >= 0) { ctx.beginPath(); ctx.rect((R.x0 + R.lit * R.cell + R.inset) * k, (R.y - R.h / 2) * k, (R.cell - 2 * R.inset) * k, R.h * k); fill(s.on); }
    }
    if (s.disc) { ring(s.disc.r, 0, -360); fill(s.on, s.disc.opacity); }
    if (s.grooves) s.grooves.radii.forEach((r) => { ring(r, 0, -360); stroke(s.on, s.grooves.width, s.grooves.opacity); });
    if (s.ticks) s.ticks.deg.forEach((d) => { const [x0, y0] = P(s.ticks.r0, d), [x1, y1] = P(s.ticks.r1, d); ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); stroke(s.on, s.ticks.width, s.ticks.opacity); });
    if (s.ring) { ring(s.ring.r, 0, -360); stroke(s.on, s.ring.width, s.ring.opacity); }
    if (s.arc) {
      ring(s.arc.r, s.arc.from, full(s.arc) ? s.arc.from - 360 : s.arc.to); stroke(s.on, s.arc.width);
      if (s.arc.capFrom === 'round') dot(s.arc.r, s.arc.from, s.arc.width / 2, s.on);
      if (s.arc.capTo === 'round') dot(s.arc.r, s.arc.to, s.arc.width / 2, s.on);
    }
    if (s.parts) {
      ring(s.parts.r, 0, -360); stroke(s.parts.backing.color, s.parts.backing.width);
      s.parts.segments.forEach((g) => { ring(s.parts.r, g.from, full(g) ? g.from - 360 : g.to); stroke(g.color, s.parts.width); });
    }
    if (s.evening) { const [x0, y0] = P(s.evening.r0, s.evening.deg), [x1, y1] = P(s.evening.r1, s.evening.deg); ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); stroke(s.on, s.evening.width, 1, 'round'); }
    if (s.label) { ring(s.label.r, 0, -360); fill(s.on); }
    ctx.textBaseline = 'alphabetic';
    for (const t of s.text) {
      ctx.textAlign = t.anchor === 'end' ? 'right' : t.anchor === 'start' ? 'left' : 'center';
      ctx.font = `700 ${t.size * k}px ${face(t.face)}`; ctx.fillStyle = c(t.fill === 'ground' ? s.ground : s.on);
      ctx.letterSpacing = t.tracking ? `${t.tracking * t.size * k}px` : '0px';
      ctx.globalAlpha = t.opacity ?? 1; ctx.fillText(t.s, t.x * k, t.y * k); ctx.globalAlpha = 1;
    }
    ctx.letterSpacing = '0px';
    if (s.cols) s.cols.bars.forEach((b) => { ctx.beginPath(); ctx.rect(b.x * k, b.y * k, b.w * k, b.h * k); fill(s.on, b.rest ? s.cols.restOpacity : 1); });
    ctx.textAlign = 'center';
    if (s.rim) {
      ctx.font = `700 ${s.rim.size * k}px ${face('body')}`;
      ctx.fillStyle = c(s.on); ctx.globalAlpha = s.rim.opacity;
      const track = s.rim.tracking * s.rim.size * k, chars = [...s.rim.text];
      const widths = chars.map((ch) => ctx.measureText(ch).width + track);
      const total = widths.reduce((a, b) => a + b, 0) - track, rad = s.rim.r * k;
      let deg = s.rim.centerDeg + ((total / rad) * 180) / Math.PI / 2;
      chars.forEach((ch, i) => {
        const mid = deg - ((widths[i] - track) / 2 / rad) * 180 / Math.PI;
        const [x, y] = P(s.rim.r, mid);
        ctx.save(); ctx.translate(x, y); ctx.rotate(((90 - mid) * Math.PI) / 180); ctx.fillText(ch, 0, 0); ctx.restore();
        deg -= (widths[i] / rad) * 180 / Math.PI;
      });
      ctx.globalAlpha = 1;
    }
    if (s.rules) { ctx.fillStyle = c(s.ground); ctx.fillRect(0, s.rules.foot * k, px, (100 - s.rules.foot) * k); }
    if (s.rules) for (let i = 0; i < s.rules.count; i++) { ctx.beginPath(); ctx.rect((s.rules.x0 + i * (s.rules.len + s.rules.gap)) * k, (s.rules.y - s.rules.width / 2) * k, s.rules.len * k, s.rules.width * k); fill(s.on, s.rules.opacity); }
  }

  /** A PNG object URL of the spec at `px` (the lock screen), or null where a canvas cannot. */
  function png(spec, px = 512, el) {
    const cv = document.createElement('canvas');
    cv.width = cv.height = px;
    const ctx = cv.getContext && cv.getContext('2d');
    if (!ctx || !cv.toBlob) return null;
    paint(ctx, spec, px, el);
    return new Promise((res) => cv.toBlob((b) => res(b ? URL.createObjectURL(b) : null), 'image/png'));
  }

  return { svg, paint, png, cssVar };
})();
