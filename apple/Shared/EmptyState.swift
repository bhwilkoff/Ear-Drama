import SwiftUI

/// The one empty state on every Apple platform (iOS-DESIGN §7.4, macOS-DESIGN
/// §7.4, tvOS-DESIGN §7.3a): a title that states the fact and, when one
/// exists, one productive action. Never a description. An empty state sits
/// beside the navigation the screen carries; it never replaces it. On the TV
/// the action takes the focus.
struct EmptyState: View {
    struct Action {
        let title: String
        let perform: () -> Void
    }

    let title: String
    let systemImage: String
    var action: Action?

    init(_ title: String, systemImage: String, action: Action? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    #if os(tvOS)
    @FocusState private var actionFocused: Bool
    #endif

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } actions: {
            if let action {
                Button(action.title, action: action.perform)
                    .accessibilityIdentifier("empty-action")
                    #if os(tvOS)
                    .focused($actionFocused)
                    #endif
            }
        }
        #if os(tvOS)
        .defaultFocus($actionFocused, true)
        #endif
    }
}
