import Foundation
import Testing

/// DECISIONS 061, the same cases as js/api.test.js `playbackVolume`.
struct LoudnessLevelTests {
    private func near(_ a: Float, _ b: Double) -> Bool { abs(Double(a) - b) < 1e-6 }

    @Test func reachesTheTargetByCuttingClampedAtTheTruePeak() {
        #expect(near(LoudnessLevel.volume(i: -15, tp: -6), pow(10, -6.0 / 20)), "a loud episode is cut 6 dB")
        #expect(near(LoudnessLevel.volume(i: -18, tp: -1.3), pow(10, -3.0 / 20)), "-18 LUFS is cut 3 dB")
        #expect(LoudnessLevel.volume(i: -25, tp: -10) == 1, "a quiet episode is never boosted")
        #expect(near(LoudnessLevel.volume(i: -20, tp: 1.0), pow(10, -2.0 / 20)),
                "a hot peak pulls the gain below the loudness target (clamp)")
        #expect(LoudnessLevel.volume(i: nil, tp: nil) == 1, "unmeasured plays at unity")
        #expect(LoudnessLevel.volume(i: nil, tp: -3) == 1, "no loudness, no change")
    }

    /// Negative control: a version without the true-peak clamp gets the clamp
    /// case wrong, so that case is what holds the clamp.
    @Test func theClampCaseRejectsAnUnclampedVersion() {
        func unclamped(_ i: Double) -> Double { pow(10, min(LoudnessLevel.target - i, 0) / 20) }
        #expect(abs(unclamped(-20) - pow(10, -2.0 / 20)) > 1e-3)
        #expect(abs(unclamped(-15) - pow(10, -6.0 / 20)) < 1e-6)
    }

    @Test func onlyTheDefaultCopyCarriesTheMeasurement() throws {
        var episode = EpisodeRow(id: "x|1950-01-01", seriesKey: "x", seriesName: "X", airDate: "1950-01-01",
                                 season: nil, number: nil, title: nil, lengthSeconds: nil, rights: "unclaimed",
                                 rightsBasis: nil, network: nil)
        episode.loudnessI = -15
        episode.loudnessTP = -6
        let url = try #require(URL(string: "https://archive.org/download/x/a.mp3"))
        func copy(_ rank: Int) -> Recording {
            Recording(rank: rank, archiveID: "x", url: url, format: nil, kbps: nil, lengthSeconds: nil,
                      variant: nil, partial: false)
        }
        #expect(near(LoudnessLevel.volume(for: episode, recording: copy(0)), pow(10, -6.0 / 20)))
        #expect(LoudnessLevel.volume(for: episode, recording: copy(1)) == 1)
    }
}
