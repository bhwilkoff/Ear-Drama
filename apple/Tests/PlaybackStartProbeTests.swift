import Foundation
import Testing

/// ED_START_PROBE=1 only (TEST_RUNNER_ED_START_PROBE=1 for xcodebuild): the real AudioPlayer, muted,
/// against real archive.org recordings. Measures tap -> clock moving, pause -> resume, and a
/// relaunch's resume (a new player over the same saved history). Skipped otherwise: it needs the
/// network and takes minutes.
@MainActor
struct PlaybackStartProbeTests {
    nonisolated static let enabled = ProcessInfo.processInfo.environment["ED_START_PROBE"] == "1"

    nonisolated static let samples: [(String, String, Double)] = [
        ("gunsmoke|1960-12-11", "https://archive.org/download/OTRR_Gunsmoke_Singles/Gunsmoke%2060-12-11%20%28453%29%20The%20Cook.mp3", 1422.54),
        ("adventuresofmaisie|1951-11-22", "https://archive.org/download/Maisie/75_511122_The_Efficiency_Expert.mp3", 1682.03),
        ("familytheater|1949-06-08", "https://archive.org/download/OTRR_Family_Theater_Singles/Family%20Theater%201949-06-08%20%28121%29%20Hound%20of%20Heaven.mp3", 1712.61),
        ("beyondteachingseries|1949-03-20", "https://archive.org/download/1306005-128-michael-fisher-acc_20260222_1741/UIUC_Archives_1306005_2650_A.mp3", 878.88),
        ("1024ranch|t1024rt450413driftinwiththecurrent", "https://archive.org/download/10_2_4Ranch/10-2-4RT-450413DriftinWithTheCurrent.mp3", 882.24),
        ("familytheater|tstolensymphony", "https://archive.org/download/15ToledoSmith/03%20Stolen%20Symphony.mp3", 1763.06),
        // A headerless VBR file whose first frame misstates its bitrate (48 kbps first frame, 60 average).
        ("challengeoftheyukon|1949-12-09", "https://archive.org/download/OTRR_Challenge_of_the_Yukon_Singles/COTY%2049-12-09%20%280715%29%20Swindler%27s%20Luck.mp3", 1956.23),
    ]

    private func detail(_ id: String, _ url: String, _ length: Double) -> EpisodeDetail {
        let bust = url + "?probe=\(UUID().uuidString.prefix(6))"
        let episode = EpisodeRow(id: id, seriesKey: String(id.prefix { $0 != "|" }), seriesName: "Probe",
                                 airDate: nil, season: nil, number: nil, title: id, lengthSeconds: length > 0 ? length : nil,
                                 rights: "unclaimed", rightsBasis: nil, network: nil)
        let recording = Recording(rank: 0, archiveID: "probe", url: URL(string: bust)!, format: "VBR MP3", kbps: nil,
                                  lengthSeconds: length > 0 ? length : nil, variant: nil, partial: false)
        return EpisodeDetail(episode: episode, sponsor: nil, credits: [], recordings: [recording], rightsLine: nil)
    }

    private func waitForClock(_ p: AudioPlayer, beyond mark: Double, limit: Double = 90) async -> Double? {
        let t0 = Date()
        while Date().timeIntervalSince(t0) < limit {
            try? await Task.sleep(for: .milliseconds(100))
            if p.elapsed > mark + 0.4 { return Date().timeIntervalSince(t0) }
        }
        return nil
    }

    private func fmt(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "none" }

    @Test(.enabled(if: PlaybackStartProbeTests.enabled), .timeLimit(.minutes(30)))
    func startAndResume() async throws {
        let pauseSeconds = Double(ProcessInfo.processInfo.environment["ED_PROBE_PAUSE"] ?? "20") ?? 20
        for (id, url, length) in Self.samples {
            let defaults = UserDefaults(suiteName: "probe-\(UUID().uuidString)")!
            let history = ListeningHistory(defaults: defaults)
            let p = AudioPlayer(history: history)
            p.isMuted = true
            let d = detail(id, url, length)
            p.play(d, queue: false)
            let start = await waitForClock(p, beyond: 0)
            try? await Task.sleep(for: .seconds(3))
            p.pause()
            let pausedAt = p.elapsed
            try? await Task.sleep(for: .seconds(pauseSeconds))
            p.resume()
            let resumed = await waitForClock(p, beyond: pausedAt)
            let resumedNear = p.elapsed
            // Seek forward a long way, then "relaunch": a new player over the same history.
            p.seek(to: 600)
            _ = await waitForClock(p, beyond: 600)
            p.pause()
            let saved = p.elapsed
            p.stop()
            let again = AudioPlayer(history: ListeningHistory(defaults: defaults))
            again.isMuted = true
            again.play(d, queue: false)
            let relaunch = await waitForClock(again, beyond: saved)
            let relaunchAt = again.elapsed
            print("[probe] \(id) start=\(fmt(start))s pausedAt=\(fmt(pausedAt)) resumeMoving=\(fmt(resumed))s at=\(fmt(resumedNear)) saved=\(fmt(saved)) relaunchMoving=\(fmt(relaunch))s at=\(fmt(relaunchAt)) dur=\(fmt(again.duration))")
            again.stop()
        }
    }
}
