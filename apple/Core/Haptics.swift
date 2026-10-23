import SwiftUI

/// The one haptic taxonomy (AGENTS.md), mapped to the system's feedback here
/// and nowhere else: a view names a `Haptic`, never a `SensoryFeedback`.
/// `error` accompanies an error banner; `selection` a tab or segment change.
nonisolated enum Haptic: CaseIterable, Sendable {
    case selection, light, medium, heavy, success, warning, error

    var feedback: SensoryFeedback {
        switch self {
        case .selection: .selection
        case .light: .impact(weight: .light)
        case .medium: .impact(weight: .medium)
        case .heavy: .impact(weight: .heavy)
        case .success: .success
        case .warning: .warning
        case .error: .error
        }
    }

    #if !os(tvOS)
    /// A download finished (success) or failed, which shows "Download failed"
    /// (error). Only a record that changed state counts: records read from
    /// disk at launch are not news.
    static func forDownloads(from old: [String: DownloadRecord.State],
                             to new: [String: DownloadRecord.State]) -> Haptic? {
        let changed = new.compactMap { id, state in
            old[id].map { $0 != state } == true ? state : nil
        }
        if changed.contains(.failed) { return .error }
        if changed.contains(.downloaded) { return .success }
        return nil
    }
    #endif

    /// An error line appeared where there was none.
    static func forError(from old: String?, to new: String?) -> Haptic? {
        old == nil && new != nil ? .error : nil
    }
}
