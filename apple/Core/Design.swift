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
    nonisolated static let brandPrimary = Color.tokenPair(light: 0xB0152F, dark: 0xE3384B)
    nonisolated static let brandOnPrimary = Color.tokenPair(light: 0xFFFFFF, dark: 0x120708)
    nonisolated static let brandBackground = Color.tokenPair(light: 0xFFFFFF, dark: 0x0F0F11)
    nonisolated static let brandSurface = Color.tokenPair(light: 0xF4F4F5, dark: 0x19191C)
    nonisolated static let brandSurfaceAlt = Color.tokenPair(light: 0xE8E8EB, dark: 0x232327)
    nonisolated static let brandText = Color.tokenPair(light: 0x131316, dark: 0xF2F2F4)
    nonisolated static let brandTextMuted = Color.tokenPair(light: 0x5C5C66, dark: 0xC4C4CC)
    nonisolated static let brandBorder = Color.tokenPair(light: 0xD8D8DD, dark: 0x34343A)
    nonisolated static let brandSecondary = Color.tokenPair(light: 0x0B6E99, dark: 0x5AB4D6)
    nonisolated static let brandOnSecondary = Color.tokenPair(light: 0xFFFFFF, dark: 0x06141B)
    nonisolated static let brandLink = Color.tokenPair(light: 0x0B6E99, dark: 0x6CC0E0)

    // Semantic: content meaning only, never chrome.
    nonisolated static let semanticSuccess = Color.tokenPair(light: 0x1D7A4A, dark: 0x5CC593)
    nonisolated static let semanticWarning = Color.tokenPair(light: 0x8A5300, dark: 0xE8B04B)
    nonisolated static let semanticError = Color.tokenPair(light: 0xC2410C, dark: 0xFF9466)
    nonisolated static let semanticErrorSurface = Color.tokenPair(light: 0xFDEEE8, dark: 0x3A1F16)

    // Genre: content only, never chrome. Keyed by the catalog's genre key.
    nonisolated static let genreDrama = Color.tokenPair(light: 0xB42575, dark: 0xFF91C3)
    nonisolated static let genreMystery = Color.tokenPair(light: 0x3753A2, dark: 0x8DACFA)
    nonisolated static let genreScifi = Color.tokenPair(light: 0x03838C, dark: 0x16E3F2)
    nonisolated static let genreWestern = Color.tokenPair(light: 0xA06841, dark: 0xD97E37)
    nonisolated static let genreComedy = Color.tokenPair(light: 0x8D8300, dark: 0xE2D32B)
    nonisolated static let genreNews = Color.tokenPair(light: 0x44420E, dark: 0xCECEC0)
    nonisolated static let genreDocumentary = Color.tokenPair(light: 0x217500, dark: 0x81CB70)
    nonisolated static let genreSerial = Color.tokenPair(light: 0x5D0087, dark: 0xAE6DDC)

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

    nonisolated private static func tokenPair(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            platformColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
        #else
        Color(nsColor: NSColor(name: nil) { appearance in
            platformColor(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        })
        #endif
    }

    #if canImport(UIKit)
    nonisolated private static func platformColor(_ v: UInt32) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    #else
    nonisolated private static func platformColor(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
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
