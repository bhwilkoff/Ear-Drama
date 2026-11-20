#if os(iOS) || os(macOS)
import SwiftUI

/// One take waiting for the teacher on the class page (PLAYS-DESIGN §12.4 Review, §12.11): the seat, the part, the play, the
/// line's words, then Play (when the take passed through to this device), Approve and Again. The note is optional and goes
/// with Again only. Stateless but for the note, so a render can draw it.
struct ClassReviewRow: View {
    let item: ClassReviewItem
    let seatLabel: String
    let partTitle: String
    let words: String
    let canPlay: Bool
    var play: () -> Void = {}
    var decide: (String, String?) -> Void = { _, _ in }
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(verbatim: "\(seatLabel) \u{00B7} \(partTitle) \u{00B7} \(item.playTitle)")
                .font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
            Text(verbatim: words).font(TypeRamp.body).lineLimit(3)
            HStack(spacing: Spacing.s2) {
                if canPlay {
                    Button("Play") { play() }
                } else {
                    Text("On another device").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                }
                Button("Approve") { decide("approved", nil) }
                Button("Again") { decide("again", ClassReview.note(note)) }
            }
            .buttonStyle(.bordered)
            .font(TypeRamp.caption)
            TextField("Note to \(seatLabel)", text: $note, axis: .vertical)
                .lineLimit(1...3)
                .font(TypeRamp.caption)
                .accessibilityLabel("Note to \(seatLabel)")
        }
        .padding(.vertical, Spacing.s1)
    }
}
#endif
