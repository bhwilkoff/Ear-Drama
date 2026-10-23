import SwiftUI

/// Starts an episode from anywhere: the catalog resolves it, the player plays
/// it. Views never touch AVFoundation or the database themselves.
struct PlayEpisodeAction {
    let catalog: CatalogStore
    let player: AudioPlayer
    let store: AppStore

    func callAsFunction(_ id: String, recording: Recording? = nil, presentPlayer: Bool = false) {
        Task {
            await catalog.whenReady()
            guard let detail = await catalog.episodeDetail(id) else { return }
            player.isMuted = store.isMuted
            player.play(detail, recording: recording)
            if presentPlayer { store.isPlayerPresented = true }
        }
    }
}
