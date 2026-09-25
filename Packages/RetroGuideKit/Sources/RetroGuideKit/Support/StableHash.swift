import Foundation

/// FNV-1a 64-bit hash. Unlike `Hasher`, the output is stable across launches,
/// which keeps channel schedules identical every time the app starts.
enum StableHash {
    private static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01b3

    static func fnv1a(_ string: String) -> UInt64 {
        var hash = offsetBasis
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}

/// SplitMix64: a tiny, fast, seedable generator with good statistical quality.
struct SeededGenerator: RandomNumberGenerator {
    private static let increment: UInt64 = 0x9e37_79b9_7f4a_7c15
    private static let mixMultiplierA: UInt64 = 0xbf58_476d_1ce4_e5b9
    private static let mixMultiplierB: UInt64 = 0x94d0_49bb_1331_11eb
    private static let shiftA: UInt64 = 30
    private static let shiftB: UInt64 = 27
    private static let shiftC: UInt64 = 31

    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ Self.increment
        var z = state
        z = (z ^ (z >> Self.shiftA)) &* Self.mixMultiplierA
        z = (z ^ (z >> Self.shiftB)) &* Self.mixMultiplierB
        return z ^ (z >> Self.shiftC)
    }
}
