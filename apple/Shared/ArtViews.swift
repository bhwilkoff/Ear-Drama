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

/// A row's tile: the series' star, else its first letter in its genre hue.
struct ArtTile: View {
    let name: String
    let genre: String?
    let face: Face?
    var size: CGFloat = 40

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
struct NowPlayingArt: View {
    let episode: EpisodeRow
    let face: Face?
    var line: String? = nil
    var side: CGFloat = 200

    var body: some View {
        Group {
            if let face {
                ArtImage(art: face.art, points: side)
                    .frame(width: side, height: side, alignment: .top)
                    .background(Color.brandSurfaceAlt)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            } else {
                TypeCard(name: episode.seriesName, line: line, genre: episode.seriesGenre)
                    .frame(width: side, height: side)
            }
        }
        .accessibilityHidden(true)
    }
}
