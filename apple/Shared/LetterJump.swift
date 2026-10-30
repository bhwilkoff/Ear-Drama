import SwiftUI

// Browse's A to Z jump (iOS-/macOS-/tvOS-DESIGN R11c). The letters are `Grammar.azLetters`: only a
// letter that has shows, "#" first. Each platform draws its own idiom: iOS and iPadOS the system's
// section index (a drag-along rail below iOS 26), the Mac a row of letter buttons, the Apple TV a
// row focus can reach.

#if os(iOS)
/// The index rail for iOS 18 to 25, where the List's own section index does not exist: letters down
/// the trailing edge; a touch or a drag along them jumps, with the selection haptic per letter.
struct LetterRail: View {
    let letters: [String]
    let jump: (String) -> Void
    @State private var last: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(letters, id: \.self) { l in
                Text(verbatim: l)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.brandSecondary)
                    .frame(width: 20, height: 20)
            }
        }
        .padding(.vertical, Spacing.s1)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local).onChanged { value in
            guard !letters.isEmpty else { return }
            let i = min(letters.count - 1, max(0, Int((value.location.y - Spacing.s1) / 20)))
            if letters[i] != last { last = letters[i]; jump(letters[i]) }
        }.onEnded { _ in last = nil })
        .sensoryFeedback(Haptic.selection.feedback, trigger: last)
        .accessibilityElement()
        .accessibilityLabel("Jump to a letter")
        .accessibilityAdjustableAction { direction in
            let current = last.flatMap(letters.firstIndex(of:)) ?? 0
            let next = direction == .increment ? min(letters.count - 1, current + 1) : max(0, current - 1)
            last = letters[next]; jump(letters[next])
        }
    }
}
#endif

#if !os(iOS)
/// A row of letter buttons: the Mac's pointer clicks one; the Apple TV's focus moves along them.
struct LetterRow: View {
    let letters: [String]
    let jump: (String) -> Void

    var body: some View {
        #if os(tvOS)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s3) { buttons }
                .padding(.vertical, Spacing.s2)
        }
        .focusSection()
        #else
        FlowLayout(spacing: 2) { buttons }
        #endif
    }

    @ViewBuilder private var buttons: some View {
        ForEach(letters, id: \.self) { l in
            Button { jump(l) } label: {
                Text(verbatim: l)
                    .font(TypeRamp.bodyStrong)
                    .frame(minWidth: 28)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(l == "#" ? "Numbers and symbols" : "Shows starting with \(l)")
        }
    }
}
#endif
