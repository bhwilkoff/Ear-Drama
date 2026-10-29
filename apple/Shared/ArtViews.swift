import SwiftUI

// Art (Decision 069, contract §3.3a): a served portrait, else a card drawn
// from data. No stock, placeholder, or uploader art. A small crop centers on
// the face the pipeline published (R11a), never one found on the device.

/// A small square crop (a row tile, a cast face, R11a): the square `Artwork.cropRect` picks
/// around the published face, the image scaled so that square fills the frame and shifted
/// onto it, at the smallest Commons step covering it on this screen. A wide picture with no
/// face draws nothing, so the view behind it shows (the tile's letter, the empty slot), as it
/// does while loading or on failure; an unknown size keeps the plain top fill crop.
struct CroppedArt: View {
    let art: Artwork
    let points: CGFloat
    @Environment(\.displayScale) private var scale

    var body: some View {
        if let r = art.cropRect() {
            let size = CGSize(width: points / CGFloat(r.w), height: points / CGFloat(r.h))
            AsyncImage(url: art.url(pixels: Double(size.width * scale))) { phase in
                if let image = phase.image {
                    image.resizable()
                        .frame(width: size.width, height: size.height)
                        .offset(x: -CGFloat(r.x) * size.width, y: -CGFloat(r.y) * size.height)
                } else {
                    Color.clear
                }
            }
            .frame(width: points, height: points, alignment: .topLeading)
            .clipped()
        } else if art.aspectRatio == nil {
            AsyncImage(url: art.url(pixels: Double(points * scale))) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                        .frame(width: points, height: points, alignment: .top)
                        .clipped()
                } else {
                    Color.clear
                }
            }
            .frame(width: points, height: points)
        }
    }
}

/// A picture in a box of its own shape (iOS-DESIGN R11a, `artwork-presentation-design`):
/// an archival print's hairline and the control radius, the genre's edge under it, and
/// nothing behind it, no wash, no bars. While it loads the box is the surface at exactly the
/// picture's size; a caller sizes the box from `Artwork.aspectRatio`, so the image fills it,
/// and an unknown size (drawn upright at 4:5) crops top-anchored rather than leaving bars.
struct ShapedArt: View {
    let art: Artwork
    var genre: String? = nil
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.brandSurfaceAlt
                AsyncImage(url: art.url(pixels: Double(geo.size.width * scale))) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.genre(genre) ?? Color.clear).frame(height: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Color.brandBorder, lineWidth: 1)
        }
    }
}

extension Artwork {
    /// The aspect a box is drawn at: the published one, else a portrait's usual 4:5.
    var drawnAspect: CGFloat { CGFloat(aspectRatio ?? 0.8) }

    /// The box for this picture inside a bound: its own aspect, as large as the bound allows.
    func fitted(in bound: CGSize) -> CGSize {
        let a = drawnAspect
        let width = min(bound.width, bound.height * a)
        return CGSize(width: width, height: width / a)
    }
}

/// A page's face (R11a). Upright (a square included): the print, beside its label (whose
/// face, unless the heading already says; the credit its license asks for, a required fact;
/// and the page's facts when given). Wide: the plate, the column's width at its own aspect,
/// at most 320 tall, set at the leading edge, with the label under it.
struct FaceHero: View {
    let face: Face
    var genre: String? = nil
    var showsName = true
    var facts: String? = nil
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var printBound: CGSize { sizeClass == .regular ? CGSize(width: 276, height: 240) : CGSize(width: 150, height: 168) }
    #else
    private let printBound = CGSize(width: 276, height: 240)
    #endif

    var body: some View {
        Group {
            if face.art.isWide {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Color.clear
                        .aspectRatio(face.art.drawnAspect, contentMode: .fit)
                        .frame(maxWidth: 320 * face.art.drawnAspect)
                        .fixedSize(horizontal: false, vertical: true)
                        .overlay { picture }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    label
                }
            } else {
                let box = face.art.fitted(in: printBound)
                HStack(alignment: .bottom, spacing: Spacing.s3) {
                    picture.frame(width: box.width, height: box.height)
                    label
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, Spacing.s4)
    }

    private var picture: some View {
        ShapedArt(art: face.art, genre: genre)
            .accessibilityElement()
            .accessibilityLabel(face.name)
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("face-hero")
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            if showsName {
                Text(face.name)
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
            if let credit = face.art.credit {
                ArtCredit(credit: credit, evidence: face.art.evidence)
            }
            if let facts {
                Text(verbatim: facts)
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
        }
    }
}

/// A row's tile: the series' star, else its first letter in its genre hue.
/// 56 pt on iOS so a face can be known (R11a); the Mac's denser rows keep 40.
struct ArtTile: View {
    let name: String
    let genre: String?
    let face: Face?
    #if os(iOS)
    var size: CGFloat = 56
    #else
    var size: CGFloat = 40
    #endif

    var body: some View {
        let hue = Color.genre(genre)
        ZStack {
            RoundedRectangle(cornerRadius: Radius.control).fill(Color.brandSurfaceAlt)
            Text(verbatim: ArtInitial.of(name))
                .font(TypeRamp.sectionHeader)
                .foregroundStyle(hue ?? Color.brandTextMuted)
            if let face {
                CroppedArt(art: face.art, points: size)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottom) {
            Rectangle().fill(hue ?? Color.brandBorder).frame(height: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
        .accessibilityHidden(true)
    }
}

/// A face beside a heading (tvOS): the print at its own aspect inside a bound `height`
/// tall (a wide one up to 1.5 times as wide), whose it is, and the credit its license asks
/// for (a required fact, so it is on screen).
struct FaceFigure: View {
    let face: Face
    var height: CGFloat = 96

    var body: some View {
        let box = face.art.fitted(in: CGSize(width: height * 1.5, height: height))
        VStack(alignment: .leading, spacing: Spacing.s1) {
            ShapedArt(art: face.art)
                .frame(width: box.width, height: box.height)
                .accessibilityLabel(face.name)
            Text(face.name)
                .font(TypeRamp.caption)
                .foregroundStyle(Color.brandTextMuted)
            if let credit = face.art.credit {
                ArtCredit(credit: credit, evidence: face.art.evidence)
            }
        }
        .frame(width: box.width, alignment: .leading)
    }
}

/// "Author, CC BY-SA 3.0", linked to the Commons file page where links open.
struct ArtCredit: View {
    let credit: String
    let evidence: URL?

    var body: some View {
        #if os(tvOS)
        Text(credit).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
        #else
        if let evidence {
            Link(credit, destination: evidence).font(TypeRamp.caption).foregroundStyle(Color.brandLink)
        } else {
            Text(credit).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
        }
        #endif
    }
}

/// A cast line's round portrait; an empty slot keeps names aligned.
struct CreditFace: View {
    let art: Artwork?
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            if let art, art.cropRect() != nil || art.aspectRatio == nil {
                Circle().fill(Color.brandSurfaceAlt)
                CroppedArt(art: art, points: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// The typographic card (R11): the name and one meta line on the genre. Any
/// titled work with years and a genre draws one, a series or a stage play.
struct TypeCard: View {
    let name: String
    let line: String?
    let genre: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Spacer(minLength: 0)
            Text(name)
                .font(TypeRamp.pageTitle)
                .foregroundStyle(Color.brandText)
                .lineLimit(4)
                .minimumScaleFactor(0.6)
            if let line {
                Text(line).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted).lineLimit(2)
            }
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(Color.brandSurfaceAlt)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.genre(genre) ?? Color.brandBorder).frame(width: 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Now Playing's picture: the episode's face, else the series', else its card.
/// The bound is a square, `side` when given, else as large as the frame it is offered
/// (iOS-DESIGN R11a: full width, bounded so Play stays on the first screen). A portrait is
/// drawn whole at its own aspect and its box shrinks to it, centered; a card fills the square.
struct NowPlayingArt: View {
    let episode: EpisodeRow
    let face: Face?
    var line: String? = nil
    var side: CGFloat? = nil

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let face {
                    GeometryReader { geo in
                        let box = face.art.fitted(in: geo.size)
                        ShapedArt(art: face.art)
                            .frame(width: box.width, height: box.height)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                } else {
                    TypeCard(name: episode.seriesName, line: line, genre: episode.seriesGenre)
                }
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}
