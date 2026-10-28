import SwiftUI

/// The website's credits, privacy, and take-down pages (iOS-DESIGN §4.10a,
/// tvOS-DESIGN §4.9a). Names only. iOS opens the system browser; a TV has none,
/// so it shows the address. The Mac keeps these in its Help menu.
struct SiteLinkRows: View {
    var body: some View {
        #if os(tvOS)
        LabeledContent("Credits", value: "eardrama.org/credits")
        LabeledContent("Privacy", value: "eardrama.org/privacy")
        LabeledContent("Take-down requests", value: "eardrama.org/takedown")
        #elseif os(iOS)
        Link("Credits", destination: SiteLinks.credits)
        Link("Privacy", destination: SiteLinks.privacy)
        Link("Take-down requests", destination: SiteLinks.takedown)
        #endif
    }
}
