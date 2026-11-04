import SwiftUI

/// The website's credits, privacy, and take-down pages (iOS-DESIGN §4.10a,
/// tvOS-DESIGN §4.9a). Names only. iOS opens the system browser; a TV has none,
/// so it shows the address. The Mac keeps these in its Help menu.
struct SiteLinkRows: View {
    var body: some View {
        #if os(tvOS)
        ForEach([("Credits", "eardrama.org/credits"), ("Privacy", "eardrama.org/privacy"),
                 ("Take-down requests", "eardrama.org/takedown")], id: \.0) { name, address in
            VStack(alignment: .leading, spacing: 2) {
                Text(name).foregroundStyle(Color.brandText)
                Text(verbatim: address).foregroundStyle(Color.brandTextMuted)
            }
            .lineLimit(1)
            .fixedSize()
        }
        #elseif os(iOS)
        Link("Credits", destination: SiteLinks.credits)
        Link("Privacy", destination: SiteLinks.privacy)
        Link("Take-down requests", destination: SiteLinks.takedown)
        #endif
    }
}
