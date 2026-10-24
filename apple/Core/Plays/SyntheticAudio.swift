#if os(iOS) || os(macOS)
import Foundation
import os

/// Every buffer a device voice makes is marked here when it is made
/// (`StandInAudio.init`), and every audio writer asks before it writes: a take,
/// room tone, the mix, an export (PLAYS-DESIGN §5 rule 3). The type system
/// already keeps `StandInAudio` out of the writers; this catches its samples
/// copied into anything else. Marks live in memory only, for this run.
nonisolated enum SyntheticAudio {
    enum Refusal: Error, Equatable { case synthetic }

    private static let marks = OSAllocatedUnfairLock<Set<Int>>(initialState: [])

    /// Samples are marked in aligned blocks, so a copy cut short or run on
    /// (a file read back a few frames short, say) is still known. A block that
    /// holds one value throughout (digital silence) is never marked.
    static let block = 1_024

    static func mark(_ samples: [Float]) {
        let keys = fingerprints(samples)
        marks.withLock { $0.formUnion(keys) }
    }

    static func isSynthetic(_ samples: [Float]) -> Bool {
        let keys = fingerprints(samples)
        guard !keys.isEmpty else { return false }
        return marks.withLock { !$0.isDisjoint(with: keys) }
    }

    static func refuse(_ samples: [Float]) throws(Refusal) {
        if isSynthetic(samples) { throw .synthetic }
    }

    private static func fingerprints(_ samples: [Float]) -> Set<Int> {
        var keys: Set<Int> = []
        samples.withUnsafeBufferPointer { all in
            for start in stride(from: 0, to: all.count, by: block) {
                let slice = UnsafeBufferPointer(rebasing: all[start..<min(start + block, all.count)])
                guard let first = slice.first, slice.contains(where: { $0 != first }) else { continue }
                var hasher = Hasher()
                hasher.combine(bytes: UnsafeRawBufferPointer(slice))
                keys.insert(hasher.finalize())
            }
        }
        return keys
    }
}
#endif
