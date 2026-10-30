import SwiftUI

/// An empty Library section's one line: what it would hold, a fact the person
/// cannot discover by looking (iOS-DESIGN §4.6). Never an invitation.
struct SectionCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(verbatim: text)
            .font(TypeRamp.caption)
            .foregroundStyle(Color.brandTextMuted)
    }
}

/// Library's Following: the followed series as the grammar's show tiles in one
/// shelf, names sharing a height so every strip and fact line sits on one line.
/// The context menu is the unfollow verb (a series page's Follow button is the other).
struct FollowingShelf: View {
    let series: [SeriesRow]
    @Environment(FollowedSeries.self) private var follows

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                ForEach(series) { row in
                    NavigationLink(value: Route.series(row.key)) { ShowTile(series: row) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { follows.setFollowing(row.key, false) } label: {
                                Label("Unfollow", systemImage: "heart.slash")
                            }
                        }
                }
            }
            .sharesNameHeight()
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s2)
        }
        .scrollIndicators(.hidden)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}
