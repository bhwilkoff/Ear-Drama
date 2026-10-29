#if os(watchOS)
import SwiftUI

/// The Apple Watch stub (Decision 056): Continue and, later, downloads only
/// (research 04 §2.7). It shares Core's ListeningHistory and nothing that
/// fetches the catalog; until the phone hands its history over, the list is
/// empty and says what it is waiting for. Its history keeps episode ids, so it
/// forwards them like every other store (contract §3.5), with the forwarding
/// the phone last handed it (`IDForwarding.stored`), on every launch.
@main
struct EarDramaWatchApp: App {
    @State private var history: ListeningHistory

    init() {
        let history = ListeningHistory()
        history.forward(IDForwarding.stored())
        _history = State(initialValue: history)
    }

    var body: some Scene {
        WindowGroup {
            ContinueView_watchOS()
                .environment(history)
        }
    }
}

struct ContinueView_watchOS: View {
    @Environment(ListeningHistory.self) private var history

    var body: some View {
        NavigationStack {
            List {
                if history.inProgressIDs.isEmpty {
                    Text("Waiting on the phone")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(history.inProgressIDs, id: \.self) { id in
                        Text(id)
                    }
                }
            }
            .navigationTitle("Continue")
        }
    }
}
#endif
