import Foundation

/// One show on one channel, in broadcast order, as arithmetic: which episode
/// its nth airing is and how long its first n airings take, for any n,
/// without replaying anything.
struct ShowReel: Sendable {
    /// The channel's item indices for this show, in broadcast order.
    let items: [Int]
    /// `prefix[k]`: slot time (milliseconds) of `items[0..<k]`; `prefix[count]` is one full pass.
    let prefix: [Int]
    /// Where in the show its first airing is.
    let start: Int

    init(items: [Int], slotLengths: [Int], start: Int) {
        self.init(items: items, prefix: Self.prefix(of: items, slotLengths: slotLengths), start: start)
    }

    /// A reel reusing another reel's items and prefix sums with a new start.
    init(items: [Int], prefix: [Int], start: Int) {
        self.items = items
        self.prefix = prefix
        self.start = items.isEmpty ? .zero : start % items.count
    }

    static func prefix(of items: [Int], slotLengths: [Int]) -> [Int] {
        var prefix = [0]
        prefix.reserveCapacity(items.count + 1)
        for item in items {
            prefix.append(prefix[prefix.count - 1] + slotLengths[item])
        }
        return prefix
    }

    /// Airing number (from this reel's start) of the item at `index` in ``items``.
    func airing(ofIndex index: Int) -> Int {
        (index - start + count) % count
    }

    var count: Int { items.count }

    var passLength: Int { prefix[count] }

    /// The item of the show's `airing`th airing (0-based), episodes in order, wrapping.
    func item(ofAiring airing: Int) -> Int {
        items[(start + airing) % count]
    }

    /// The item aired just before the show's `airing`th airing (for the
    /// first, the one before where the reel starts).
    func item(beforeAiring airing: Int) -> Int {
        items[((start + airing - 1) % count + count) % count]
    }

    /// Slot time of the show's first `airings` airings.
    func airtime(_ airings: Int) -> Int {
        guard airings > .zero else { return .zero }
        let end = start + airings
        return end / count * passLength + prefix[end % count] - prefix[start]
    }
}
