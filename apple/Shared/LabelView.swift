import SwiftUI

// The label drawn (Decision 081, iOS-/macOS-/tvOS-DESIGN "The label is the default art"): LabelSpec
// decides, this paints, with SwiftUI Canvas in a window of any side (crisp from a 40 pt tile to the
// tvOS hero). Colors are the token references the spec names, so light and dark follow the
// environment with no redraw. The same drawing renders to an image for Now Playing and the lock screen.

extension Color {
    /// A label token reference (board.mystery, brand.text, print.ground) as the palette's color.
    static func label(_ ref: String) -> Color {
        let parts = ref.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return .brandText }
        switch parts[0] {
        case "board": return .board(parts[1])
        case "onBoard": return .onBoard(parts[1])
        case "genre": return .genre(parts[1]) ?? .brandTextMuted
        case "print": return .printGround
        default:
            switch parts[1] {
            case "surfaceAlt": return .brandSurfaceAlt
            case "textMuted": return .brandTextMuted
            case "background": return .brandBackground
            default: return .brandText
            }
        }
    }
}

struct LabelView: View {
    let spec: LabelSpec
    /// A play's rules over its own page: no ground, so the opening's text shows through.
    var overlay = false

    /// `tierSide` is the window's size when the drawing sits inside padding that must not demote its tier (a head's round window).
    init(item: LabelItem, side: CGFloat, tierSide: CGFloat? = nil, overlay: Bool = false) {
        spec = LabelSpec.make(item, size: Double(tierSide ?? side))
        self.overlay = overlay
    }

    var body: some View {
        Canvas { context, size in
            Self.paint(spec, in: &context, side: min(size.width, size.height), overlay: overlay)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    // MARK: Painting

    private static func point(_ r: Double, _ deg: Double, _ k: CGFloat) -> CGPoint {
        let a = deg * .pi / 180
        return CGPoint(x: (50 + r * cos(a)) * k, y: (50 - r * sin(a)) * k)
    }

    /// An arc drawn clockwise on screen from `from` to `to` (degrees, from > to).
    private static func arc(_ r: Double, _ from: Double, _ to: Double, _ k: CGFloat) -> Path {
        var p = Path()
        if LabelSpec.isFull(from: from, to: to) {
            p.addEllipse(in: CGRect(x: (50 - r) * k, y: (50 - r) * k, width: 2 * r * k, height: 2 * r * k))
        } else {
            p.addArc(center: CGPoint(x: 50 * k, y: 50 * k), radius: r * k, startAngle: .degrees(-from), endAngle: .degrees(-to), clockwise: false)
        }
        return p
    }

    private static func circle(_ r: Double, _ k: CGFloat) -> Path { arc(r, 0, -360, k) }

    private static func stroke(_ context: inout GraphicsContext, _ path: Path, _ ref: String, _ width: Double, _ opacity: Double = 1,
                               _ k: CGFloat, cap: CGLineCap = .butt) {
        context.stroke(path, with: .color(Color.label(ref).opacity(opacity)), style: StrokeStyle(lineWidth: width * k, lineCap: cap))
    }

    private static func fill(_ context: inout GraphicsContext, _ path: Path, _ ref: String, _ opacity: Double = 1) {
        context.fill(path, with: .color(Color.label(ref).opacity(opacity)))
    }

    private static func font(_ face: String, _ px: CGFloat) -> Font {
        face == "display" ? .custom(TypeRamp.displayFontName, fixedSize: px) : .system(size: px, weight: .bold)
    }

    static func paint(_ s: LabelSpec, in context: inout GraphicsContext, side: CGFloat, overlay: Bool = false) {
        let k = side / CGFloat(s.viewBox)
        let on = s.on
        if !overlay { context.fill(Path(CGRect(x: 0, y: 0, width: side, height: side)), with: .color(Color.label(s.ground))) }
        if let cast = s.cast {
            for b in cast.bars {
                fill(&context, Path(roundedRect: CGRect(x: b.x * k, y: b.y * k, width: b.w * k, height: b.h * k), cornerRadius: b.h * k / 2), on)
            }
        }
        if let d = s.disc { fill(&context, circle(d.r, k), on, d.opacity) }
        if let g = s.grooves { for r in g.radii { stroke(&context, circle(r, k), on, g.width, g.opacity, k) } }
        if let t = s.ticks {
            for deg in t.deg {
                var p = Path()
                p.move(to: point(t.r0, deg, k))
                p.addLine(to: point(t.r1, deg, k))
                stroke(&context, p, on, t.width, t.opacity, k)
            }
        }
        if let r = s.ring { stroke(&context, circle(r.r, k), on, r.width, r.opacity, k) }
        if let a = s.arc {
            stroke(&context, arc(a.r, a.from, LabelSpec.isFull(from: a.from, to: a.to) ? a.from - 360 : a.to, k), on, a.width, 1, k)
            for (deg, cap) in [(a.from, a.capFrom), (a.to, a.capTo)] where cap == "round" {
                let c = point(a.r, deg, k), rad = a.width * k / 2
                fill(&context, Path(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: 2 * rad, height: 2 * rad)), on)
            }
        }
        if let p = s.parts {
            stroke(&context, circle(p.r, k), p.backing.color, p.backing.width, 1, k)
            for g in p.segments {
                stroke(&context, arc(p.r, g.from, LabelSpec.isFull(from: g.from, to: g.to) ? g.from - 360 : g.to, k), g.color, p.width, 1, k)
            }
        }
        if let e = s.evening {
            var p = Path()
            p.move(to: point(e.r0, e.deg, k))
            p.addLine(to: point(e.r1, e.deg, k))
            stroke(&context, p, on, e.width, 1, k, cap: .round)
        }
        if let l = s.label { fill(&context, circle(l.r, k), on) }
        for t in s.text {
            let resolved = context.resolve(Text(verbatim: t.s).font(font(t.face, CGFloat(t.size) * k))
                .foregroundStyle(Color.label(t.fill == "ground" ? s.ground : on)))
            let base = resolved.firstBaseline(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
            context.draw(resolved, at: CGPoint(x: t.x * k, y: t.y * k - base), anchor: t.anchor == "end" ? .topTrailing : .top)
        }
        if let rim = s.rim { paintRim(rim, on: on, in: &context, k) }
        if let rules = s.rules {
            context.fill(Path(CGRect(x: 0, y: rules.foot * k, width: side, height: side - rules.foot * k)), with: .color(Color.label(s.ground)))
            for i in 0..<rules.count {
                let x = rules.x0 + Double(i) * (rules.len + rules.gap)
                fill(&context, Path(CGRect(x: x * k, y: (rules.y - rules.width / 2) * k, width: rules.len * k, height: rules.width * k)), on, rules.opacity)
            }
        }
    }

    /// The rim's words, a glyph at a time along the top of the disc, centered on `centerDeg`.
    private static func paintRim(_ rim: LabelSpec.Rim, on: String, in context: inout GraphicsContext, _ k: CGFloat) {
        let px = rim.size * k, track = rim.tracking * px, rad = rim.r * k
        let color = Color.label(on).opacity(rim.opacity)
        let glyphs = rim.text.map { ch -> (GraphicsContext.ResolvedText, CGFloat) in
            let r = context.resolve(Text(verbatim: String(ch)).font(font("body", px)).foregroundStyle(color))
            return (r, r.measure(in: CGSize(width: 1000, height: 1000)).width + track)
        }
        let total = glyphs.reduce(0) { $0 + $1.1 } - track
        var deg = rim.centerDeg + (total / rad) * 180 / .pi / 2
        for (resolved, advance) in glyphs {
            let mid = deg - ((advance - track) / 2 / rad) * 180 / .pi
            let p = point(rim.r, mid, k)
            var c = context
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: .degrees(90 - mid))
            let base = resolved.firstBaseline(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
            c.draw(resolved, at: CGPoint(x: 0, y: -base), anchor: .top)
            deg -= (advance / rad) * 180 / .pi
        }
    }

    // MARK: The lock screen's image

    /// The label as a square image `px` on a side, for Now Playing's artwork (the lock screen takes a
    /// raster); drawn in the dark palette, the lock screen's own.
    @MainActor static func image(_ item: LabelItem, px: CGFloat = 512) -> CGImage? {
        let renderer = ImageRenderer(content: LabelView(item: item, side: px)
            .frame(width: px, height: px)
            .environment(\.colorScheme, .dark))
        renderer.scale = 1
        return renderer.cgImage
    }
}

extension SeriesRow {
    /// The show's label: its run on the dial and, at the large tier, its network.
    var labelItem: LabelItem { LabelItem(kind: .series, name: name, genre: genre, first: firstDate, last: lastDate, network: networks.first) }
}

extension EpisodeRow {
    /// The episode's own label: its show's disc with this broadcast's date on it (its number when undated).
    func labelItem(series: SeriesRow? = nil) -> LabelItem {
        LabelItem(kind: .episode, name: seriesName, genre: seriesGenre, first: series?.firstDate, last: series?.lastDate,
                  network: network ?? series?.networks.first, date: airDate, num: number.map(String.init))
    }
}
