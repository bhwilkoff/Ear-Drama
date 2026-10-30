#if os(iOS) || os(macOS)
import SwiftUI

// The parts of a play in direction D (D3-6): the face a part wears, where it speaks, the card that
// holds both, and the buttons of the recorder. Color follows Decision 064: ink acts, blue finds
// the way, red is recording only. A part's mark is a face, a strip and the box of its own line, never
// a stripe on a card's edge.

// MARK: - Buttons

/// The recorder's and the part cards' buttons: 44 pt, one style per meaning.
struct PlayButtonStyle: ButtonStyle {
    enum Kind {
        /// The action: ink.
        case ink
        /// Wayfinding: blue on the surface.
        case way
        /// The recording control: red.
        case record
        /// Again: red on the surface, with its dot.
        case again
    }

    let kind: Kind
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        return configuration.label
            .font(TypeRamp.bodyStrong)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.s4)
            .frame(minWidth: 44, minHeight: 44)
            .background(background, in: shape)
            .overlay { if let edge { shape.strokeBorder(edge, lineWidth: 1) } }
            .contentShape(shape)
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }

    private var foreground: Color {
        switch kind {
        case .ink: Color.brandOnPrimary
        case .way: Color.brandSecondary
        case .record: Color.brandOnRecord
        case .again: Color.brandRecord
        }
    }

    private var background: Color {
        switch kind {
        case .ink: Color.brandPrimary
        case .way, .again: Color.brandBackground
        case .record: Color.brandRecord
        }
    }

    private var edge: Color? {
        switch kind {
        case .way: Color.brandBorder
        case .again: Color.brandRecord
        default: nil
        }
    }
}

extension ButtonStyle where Self == PlayButtonStyle {
    static func play(_ kind: PlayButtonStyle.Kind) -> PlayButtonStyle { PlayButtonStyle(kind: kind) }
}

// MARK: - The face

/// Who holds a part.
enum PartHolder: Equatable {
    /// A person, by the name they gave; nil when they gave none.
    case person(String?)
    /// The device voice, never a person.
    case deviceVoice
    /// Left silent.
    case silent
}

/// A part's face: a filled circle in its mark, the performer's initial in it; the device voice is the
/// same circle in outline with a waveform, so a stand-in never passes as a person. A check badge says
/// the part is recorded.
struct PartFace: View {
    let hue: String?
    let holder: PartHolder
    var recorded = false
    var side: CGFloat = 36

    var body: some View {
        let mark = Color.genre(hue) ?? Color.brandTextMuted
        ZStack {
            switch holder {
            case let .person(name):
                Circle().fill(Color.genre(hue) ?? Color.brandSurfaceAlt)
                if let initial = name?.trimmingCharacters(in: .whitespaces).first {
                    Text(verbatim: String(initial).uppercased())
                        .font(TypeRamp.sectionHeader)
                        .foregroundStyle(hue == nil ? Color.brandTextMuted : Color.onGenre(hue))
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: side * 0.42))
                        .foregroundStyle(hue == nil ? Color.brandTextMuted : Color.onGenre(hue))
                }
            case .deviceVoice:
                Circle().strokeBorder(mark, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                Image(systemName: "waveform").font(.system(size: side * 0.42)).foregroundStyle(mark)
            case .silent:
                Circle().fill(Color.brandSurfaceAlt)
                Image(systemName: "speaker.slash").font(.system(size: side * 0.4)).foregroundStyle(Color.brandTextMuted)
            }
        }
        .frame(width: side, height: side)
        .overlay(alignment: .bottomTrailing) {
            if recorded {
                Image(systemName: "checkmark")
                    .font(.system(size: side * 0.24, weight: .bold))
                    .foregroundStyle(Color.brandOnPrimary)
                    .frame(width: side * 0.4, height: side * 0.4)
                    .background(Circle().fill(Color.brandPrimary))
                    .overlay { Circle().strokeBorder(Color.brandBackground, lineWidth: 1.5) }
                    .offset(x: side * 0.08, y: side * 0.08)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Where a part speaks

/// 24 bars across the script, each the share of its run of lines the part speaks, in the part's mark.
struct PresenceStrip: View {
    let script: PlayScript
    let part: PartID
    var height: CGFloat = 24

    var body: some View {
        let bars = script.presence(of: part)
        let peak = max(bars.max() ?? 0, 0.0001)
        let mark = Color.genre(script.partHue(part)) ?? Color.brandTextMuted
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, share in
                RoundedRectangle(cornerRadius: 1)
                    .fill(share > 0 ? mark : Color.brandBorder)
                    .frame(height: share > 0 ? max(3, height * CGFloat(share / peak)) : 2)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

// MARK: - The part card

/// A part as a card: its face, its name in the display face, who holds it, its lines, where it speaks,
/// and the verbs that apply. The card is one element for VoiceOver; its buttons are their own.
struct PartCard<Actions: View>: View {
    let script: PlayScript
    let part: CastPart
    var holder: PartHolder = .deviceVoice
    var recorded = false
    /// "You · 5 of 76", "Pat · recorded", "Open"; nil on a play's own page, where no one holds a part.
    var who: String? = nil
    /// The part being recorded now stands out with an ink outline.
    var current = false
    /// Makes the card's face, name and strip one button, for a part that opens its lines.
    var onOpen: (() -> Void)? = nil
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            if let onOpen {
                Button(action: onOpen) { info }.buttonStyle(.plain)
            } else {
                info
            }
            actions()
        }
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.brandSurface, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay {
            if current { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.brandPrimary, lineWidth: 2) }
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                HStack(spacing: Spacing.s2) {
                    PartFace(hue: script.partHue(part.id), holder: holder, recorded: recorded)
                    Text(verbatim: part.title)
                        .font(TypeRamp.sectionHeader)
                        .foregroundStyle(Color.brandText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 0) {
                    if let who {
                        Text(verbatim: who).font(TypeRamp.caption.weight(.semibold)).foregroundStyle(Color.brandText)
                    }
                    Text(part.lineCount == 1 ? "1 line" : "\(part.lineCount) lines")
                        .font(TypeRamp.caption)
                        .foregroundStyle(Color.brandTextMuted)
                }
                PresenceStrip(script: script, part: part.id)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([part.title, who, part.lineCount == 1 ? "1 line" : "\(part.lineCount) lines"]
                .compactMap { $0 }.joined(separator: ", "))
        }
    }
}

extension PartCard where Actions == EmptyView {
    init(script: PlayScript, part: CastPart, holder: PartHolder = .deviceVoice, recorded: Bool = false,
         who: String? = nil, current: Bool = false) {
        self.init(script: script, part: part, holder: holder, recorded: recorded, who: who, current: current) { EmptyView() }
    }
}

/// The parts, two or more to a row as the width allows.
struct PartGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: Spacing.s3, alignment: .top)],
                  alignment: .leading, spacing: Spacing.s3) {
            content()
        }
    }
}

/// What a play's head board says about it: the kind from the record, then the facts the record holds.
enum PlayHead {
    static func kicker(_ script: PlayScript) -> String { script.kind == "radio" ? "Radio play" : "Stage play" }

    static func facts(_ script: PlayScript) -> [String?] {
        let parts = script.castParts.filter { $0.id.isSpeaking }.count
        return [script.year.map(String.init),
                parts == 1 ? "1 part" : "\(parts) parts",
                script.lines.count == 1 ? "1 line" : "\(script.lines.count.formatted()) lines"]
    }
}
#endif
