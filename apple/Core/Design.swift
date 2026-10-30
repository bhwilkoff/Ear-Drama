// Design tokens, generated from design-tokens.json by tools/design_tokens.mjs. Do not edit by hand:
// change design-tokens.json at the repository root and run `node tools/design_tokens.mjs`.
// Every Apple platform reads this one file (it lives in Core/).

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    // Brand: UI chrome only, never content meaning.
    nonisolated static let brandPrimary = Color.tokenPair(light: 0x131316, dark: 0xF2F2F4)
    nonisolated static let brandOnPrimary = Color.tokenPair(light: 0xFFFFFF, dark: 0x0F0F11)
    nonisolated static let brandBackground = Color.tokenPair(light: 0xFFFFFF, dark: 0x0F0F11)
    nonisolated static let brandSurface = Color.tokenPair(light: 0xF4F4F5, dark: 0x19191C)
    nonisolated static let brandSurfaceAlt = Color.tokenPair(light: 0xE8E8EB, dark: 0x232327)
    nonisolated static let brandText = Color.tokenPair(light: 0x131316, dark: 0xF2F2F4)
    nonisolated static let brandTextMuted = Color.tokenPair(light: 0x5C5C66, dark: 0xC4C4CC)
    nonisolated static let brandBorder = Color.tokenPair(light: 0xD8D8DD, dark: 0x34343A)
    nonisolated static let brandSecondary = Color.tokenPair(light: 0x0B6E99, dark: 0x6CC0E0)
    nonisolated static let brandOnSecondary = Color.tokenPair(light: 0xFFFFFF, dark: 0x06141B)
    nonisolated static let brandLink = Color.tokenPair(light: 0x0B6E99, dark: 0x6CC0E0)
    nonisolated static let brandRecord = Color.tokenPair(light: 0xB0152F, dark: 0xE3384B)
    nonisolated static let brandOnRecord = Color.tokenPair(light: 0xFFFFFF, dark: 0x120708)

    // Semantic: content meaning only, never chrome.
    nonisolated static let semanticSuccess = Color.tokenPair(light: 0x1D7A4A, dark: 0x5CC593)
    nonisolated static let semanticWarning = Color.tokenPair(light: 0x8A5300, dark: 0xE8B04B)
    nonisolated static let semanticError = Color.tokenPair(light: 0xC2410C, dark: 0xFF9466)
    nonisolated static let semanticErrorSurface = Color.tokenPair(light: 0xFDEEE8, dark: 0x3A1F16)

    // Genre: content only, never chrome. Keyed by the catalog's genre key.
    nonisolated static let genreDrama = Color.tokenPair(light: 0x9D547C, dark: 0xF89DC9)
    nonisolated static let genreMystery = Color.tokenPair(light: 0x2459A5, dark: 0x8EBBFF)
    nonisolated static let genreScifi = Color.tokenPair(light: 0x007C88, dark: 0x44D5D7)
    nonisolated static let genreWestern = Color.tokenPair(light: 0x864E37, dark: 0xC99580)
    nonisolated static let genreComedy = Color.tokenPair(light: 0x816B01, dark: 0xD4C27E)
    nonisolated static let genreNews = Color.tokenPair(light: 0x504C3E, dark: 0xB4B3B3)
    nonisolated static let genreDocumentary = Color.tokenPair(light: 0x2F6100, dark: 0x7CB45A)
    nonisolated static let genreSerial = Color.tokenPair(light: 0x5A3983, dark: 0xAA87DE)

    /// The mark for a catalog genre key; nil for a key the palette does not name.
    nonisolated static func genre(_ key: String?) -> Color? {
        switch key {
        case "drama": genreDrama
        case "mystery": genreMystery
        case "scifi": genreScifi
        case "western": genreWestern
        case "comedy": genreComedy
        case "news": genreNews
        case "documentary": genreDocumentary
        case "serial": genreSerial
        default: nil
        }
    }

    nonisolated static let onGenreDrama = Color.tokenPair(light: 0xFFFFFF, dark: 0x0F0F11)
    nonisolated static let onGenreMystery = Color.tokenPair(light: 0xFFFFFF, dark: 0x0F0F11)
    nonisolated static let onGenreScifi = Color.tokenPair(light: 0xFFFFFF, dark: 0x0F0F11)
    nonisolated static let onGenreWestern = Color.tokenPair(light: 0xFFFFFF, dark: 0x0F0F11)
    nonisolated static let onGenreComedy = Color.tokenPair(light: 0xFFFFFF, dark: 0x0F0F11)
    nonisolated static let onGenreNews = Color.tokenPair(light: 0xFFFFFF, dark: 0x0F0F11)
    nonisolated static let onGenreDocumentary = Color.tokenPair(light: 0xFFFFFF, dark: 0x0F0F11)
    nonisolated static let onGenreSerial = Color.tokenPair(light: 0xFFFFFF, dark: 0x0F0F11)
    /// Text on a genre mark used as a fill (a part's initial); the page text for a key the palette does not name.
    nonisolated static func onGenre(_ key: String?) -> Color {
        switch key {
        case "drama": onGenreDrama
        case "mystery": onGenreMystery
        case "scifi": onGenreScifi
        case "western": onGenreWestern
        case "comedy": onGenreComedy
        case "news": onGenreNews
        case "documentary": onGenreDocumentary
        case "serial": onGenreSerial
        default: brandText
        }
    }

    nonisolated static let boardDrama = Color.tokenPair(light: 0x86426F, dark: 0x5F2A4D)
    nonisolated static let boardMystery = Color.tokenPair(light: 0x375C9B, dark: 0x223F6F)
    nonisolated static let boardScifi = Color.tokenPair(light: 0x006A79, dark: 0x004854)
    nonisolated static let boardWestern = Color.tokenPair(light: 0x8B492A, dark: 0x623018)
    nonisolated static let boardComedy = Color.tokenPair(light: 0x795700, dark: 0x543B00)
    nonisolated static let boardNews = Color.tokenPair(light: 0x615D53, dark: 0x424038)
    nonisolated static let boardDocumentary = Color.tokenPair(light: 0x296E38, dark: 0x154C22)
    nonisolated static let boardSerial = Color.tokenPair(light: 0x684D92, dark: 0x473368)
    /// A genre's board, the block a tile or head stands on; the neutral surfaceAlt for a show with no genre.
    nonisolated static func board(_ key: String?) -> Color {
        switch key {
        case "drama": boardDrama
        case "mystery": boardMystery
        case "scifi": boardScifi
        case "western": boardWestern
        case "comedy": boardComedy
        case "news": boardNews
        case "documentary": boardDocumentary
        case "serial": boardSerial
        default: brandSurfaceAlt
        }
    }

    nonisolated static let onBoardDrama = Color.tokenPair(light: 0xFFFFFF, dark: 0xF2F2F4)
    nonisolated static let onBoardMystery = Color.tokenPair(light: 0xFFFFFF, dark: 0xF2F2F4)
    nonisolated static let onBoardScifi = Color.tokenPair(light: 0xFFFFFF, dark: 0xF2F2F4)
    nonisolated static let onBoardWestern = Color.tokenPair(light: 0xFFFFFF, dark: 0xF2F2F4)
    nonisolated static let onBoardComedy = Color.tokenPair(light: 0xFFFFFF, dark: 0xF2F2F4)
    nonisolated static let onBoardNews = Color.tokenPair(light: 0xFFFFFF, dark: 0xF2F2F4)
    nonisolated static let onBoardDocumentary = Color.tokenPair(light: 0xFFFFFF, dark: 0xF2F2F4)
    nonisolated static let onBoardSerial = Color.tokenPair(light: 0xFFFFFF, dark: 0xF2F2F4)
    /// The one color everything on a board takes; the page text on the neutral board.
    nonisolated static func onBoard(_ key: String?) -> Color {
        switch key {
        case "drama": onBoardDrama
        case "mystery": onBoardMystery
        case "scifi": onBoardScifi
        case "western": onBoardWestern
        case "comedy": onBoardComedy
        case "news": onBoardNews
        case "documentary": onBoardDocumentary
        case "serial": onBoardSerial
        default: brandText
        }
    }

    // The print mount: the ground a contained picture sits on, and the hairline edge around every window.
    nonisolated static let printGround = Color.tokenPair(light: 0xEDEDED, dark: 0x2A2A2E)
    nonisolated static let printEdge = Color.tokenPair(light: 0x131316, dark: 0xF2F2F4, lightAlpha: 0.18, darkAlpha: 0.16)

    nonisolated private static func tokenPair(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? platformColor(dark, darkAlpha) : platformColor(light, lightAlpha)
        })
        #else
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? platformColor(dark, darkAlpha) : platformColor(light, lightAlpha)
        })
        #endif
    }

    #if canImport(UIKit)
    nonisolated private static func platformColor(_ v: UInt32, _ alpha: CGFloat) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
    }
    #else
    nonisolated private static func platformColor(_ v: UInt32, _ alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
    }
    #endif
}

/// The six-level type ramp. Apple platforms use the system text styles, so
/// Dynamic Type keeps working; tvOS maps to its own larger ten-foot styles.
/// The display levels set the bundled BigShoulders-Bold (Decision 060) at the
/// system style's default size, scaled with Dynamic Type relative to that style.
enum TypeRamp {
    #if os(tvOS)
    nonisolated static let pageTitle = displayFont(.title)  // L1
    #else
    nonisolated static let pageTitle = displayFont(.largeTitle)  // L1
    #endif
    #if os(tvOS)
    nonisolated static let sectionHeader = displayFont(.title3)  // L2
    #else
    nonisolated static let sectionHeader = displayFont(.title2)  // L2
    #endif
    #if os(tvOS)
    nonisolated static let bodyStrong = Font.headline.weight(.semibold)  // L3
    #else
    nonisolated static let bodyStrong = Font.headline.weight(.semibold)  // L3
    #endif
    #if os(tvOS)
    nonisolated static let body = Font.body.weight(.regular)  // L4
    #else
    nonisolated static let body = Font.body.weight(.regular)  // L4
    #endif
    #if os(tvOS)
    nonisolated static let caption = Font.body.weight(.regular)  // L5
    #else
    nonisolated static let caption = Font.caption.weight(.regular)  // L5
    #endif
    #if os(tvOS)
    nonisolated static let tabular = Font.body.monospacedDigit().weight(.regular)  // L6
    #else
    nonisolated static let tabular = Font.body.monospacedDigit().weight(.regular)  // L6
    #endif

    nonisolated static let displayFontName = "BigShoulders-Bold"

    nonisolated private static func displayFont(_ style: Font.TextStyle) -> Font {
        Font.custom(displayFontName, size: defaultSize(style), relativeTo: style)
    }

    /// The style's size at the default text size, so relativeTo: does the scaling.
    nonisolated static func defaultSize(_ style: Font.TextStyle) -> CGFloat {
        #if canImport(UIKit)
        let ui: UIFont.TextStyle
        #else
        let ui: NSFont.TextStyle
        #endif
        switch style {
        #if !os(tvOS)
        case .largeTitle: ui = .largeTitle
        #endif
        case .title: ui = .title1
        case .title2: ui = .title2
        case .title3: ui = .title3
        default: ui = .body
        }
        #if canImport(UIKit)
        return UIFont.preferredFont(forTextStyle: ui, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize
        #else
        return NSFont.preferredFont(forTextStyle: ui).pointSize
        #endif
    }
}

enum Spacing {
    nonisolated static let s1: CGFloat = 4
    nonisolated static let s2: CGFloat = 8
    nonisolated static let s3: CGFloat = 12
    nonisolated static let s4: CGFloat = 16
    nonisolated static let s6: CGFloat = 24
    nonisolated static let s8: CGFloat = 32
}

enum Radius {
    nonisolated static let control: CGFloat = 8
    nonisolated static let card: CGFloat = 12
}
