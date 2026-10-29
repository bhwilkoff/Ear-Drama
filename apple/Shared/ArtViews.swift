import SwiftUI

// Art (Decision 069, contract §3.3a): a served portrait, else a card drawn
// from data. No stock, placeholder, or uploader art. A portrait is the
// person's own Wikidata image, so a top-anchored crop keeps the face.

/// A served image at the smallest Commons step covering its frame on this
/// screen. While it loads, or when it fails, the view behind it shows.
struct ArtImage: View {
    let art: Artwork
    let points: CGFloat
    @Environment(\.displayScale) private var scale

    var body: some View {
        AsyncImage(url: art.url(pixels: Double(points * scale))) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.clear
            }
        }
    }
}

/// The whole portrait at its own aspect over a wash of the same image,
/// blurred and dimmed (iOS-DESIGN R11a): never reshaped, and never an empty
/// box while the sharp copy loads, since the wash is the 120 step a row's
/// tile has usually cached already. A failed sharp copy leaves the wash.
struct PortraitFrame: View {
    let art: Artwork
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { geo in
            let drawn = min(geo.size.width, geo.size.height * art.aspect)
            Color.brandSurfaceAlt
                .overlay {
                    AsyncImage(url: art.url(pixels: 120)) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                                .blur(radius: 20).brightness(-0.3).saturation(0.8).scaleEffect(1.2)
                        } else {
                            Color.clear
                        }
                    }
                }
                .overlay {
                    AsyncImage(url: art.url(pixels: Double(drawn * scale))) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Color.clear
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .clipped()
    }
}

extension Artwork {
    /// Width over height when the original's size is known; a portrait's usual shape otherwise.
    var aspect: CGFloat {
        guard let width, let height, width > 0, height > 0 else { return 0.8 }
        return min(CGFloat(width) / CGFloat(height), 1.6)
    }
}

/// A page's face (R11a): a full-width band, the genre's edge under it, then
/// whose it is (unless the heading already says) and the credit its license
/// asks for, a required fact, so it is on screen with the picture.
struct FaceHero: View {
    let face: Face
    var genre: String? = nil
    var showsName = true
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var height: CGFloat { sizeClass == .regular ? 320 : 240 }
    #else
    private let height: CGFloat = 320
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            PortraitFrame(art: face.art)
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.genre(genre) ?? Color.clear).frame(height: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .accessibilityElement()
                .accessibilityLabel(face.name)
                .accessibilityAddTraits(.isImage)
                .accessibilityIdentifier("face-hero")
            Group {
                if showsName {
                    Text(face.name)
                        .font(TypeRamp.caption)
                        .foregroundStyle(Color.brandTextMuted)
                }
                if let credit = face.art.credit {
                    ArtCredit(credit: credit, evidence: face.art.evidence)
                }
            }
            .padding(.horizontal, Spacing.s4)
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
                ArtImage(art: face.art, points: size)
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

/// A face beside a heading: the portrait, whose it is, and the credit its
/// license asks for (a required fact, so it is on screen).
struct FaceFigure: View {
    let face: Face
    var width: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            ArtImage(art: face.art, points: width)
                .frame(width: width, height: width * 1.25, alignment: .top)
                .background(Color.brandSurfaceAlt)
                .clipShape(RoundedRectangle(cornerRadius: Radius.control))
                .accessibilityLabel(face.name)
            Text(face.name)
                .font(TypeRamp.caption)
                .foregroundStyle(Color.brandTextMuted)
            if let credit = face.art.credit {
                ArtCredit(credit: credit, evidence: face.art.evidence)
            }
        }
        .frame(width: width, alignment: .leading)
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
            if let art {
                Circle().fill(Color.brandSurfaceAlt)
                ArtImage(art: art, points: size)
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
/// Square: at `side` when given, else as large as the frame it is offered
/// (iOS-DESIGN R11a: full width, bounded so Play stays on the first screen).
/// A portrait sits whole in it over its wash.
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
                    PortraitFrame(art: face.art)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                } else {
                    TypeCard(name: episode.seriesName, line: line, genre: episode.seriesGenre)
                }
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}
