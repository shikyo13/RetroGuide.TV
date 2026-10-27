import Foundation

/// Airs a channel's ``NominalOrder`` program by program, stepping around
/// clashes. When the due program may not air now (its show is on enough
/// other channels, or the episode is on elsewhere), the nearest later
/// program that may air goes early, and the due one airs as soon as it can.
/// A show's own episodes never change order.
///
/// Once everything aired early has been reached, the channel is exactly
/// back on its order, at the order's own times: wherever it started, it
/// ends up in the same place, which is what lets ``SimulcastCoordinator``
/// start from any point without replaying the past.
struct TrackingPicker: Sendable {
    enum Tuning {
        /// How many programs past the due one a channel may air early.
        static let window = 64
    }

    private let order: any NominalOrder
    /// The lowest position not yet aired: every earlier one has.
    private var due: Int
    /// Positions after `due` already aired, ascending.
    private var early: [Int] = []
    /// Show and item of positions `due..<due + upcoming.count`.
    private var upcoming: [(show: Int, item: Int)] = []

    init(order: any NominalOrder, at position: Int) {
        self.order = order
        due = position
        fill()
    }

    /// The item to air next. `isAllowed` says whether an item may air now;
    /// when nothing in reach is allowed, one that `isAcceptable` airs
    /// (breaking only the rules that may bend), and failing that the due one.
    mutating func next(isAllowed: (Int) -> Bool, isAcceptable: (Int) -> Bool) -> Int {
        let step = firstStep(passing: isAllowed) ?? firstStep(passing: isAcceptable) ?? 0
        return air(step: step)
    }

    /// The nearest program not yet aired whose show has nothing earlier
    /// still waiting, and whose item passes.
    private func firstStep(passing passes: (Int) -> Bool) -> Int? {
        // Usually a handful of shows: a list beats hashing.
        var waiting: [Int] = []
        var earlyIndex = 0
        for step in upcoming.indices {
            if earlyIndex < early.count, early[earlyIndex] == due + step {
                earlyIndex += 1
                continue
            }
            let (show, item) = upcoming[step]
            guard !waiting.contains(show) else { continue }
            waiting.append(show)
            if passes(item) {
                return step
            }
        }
        return nil
    }

    private mutating func air(step: Int) -> Int {
        let item = upcoming[step].item
        guard step == 0 else {
            let position = due + step
            early.insert(position, at: early.firstIndex { $0 > position } ?? early.count)
            return item
        }
        // The due program airs: move past it and everything after it that already aired.
        var advance = 1
        while advance <= early.count, early[advance - 1] == due + advance {
            advance += 1
        }
        early.removeFirst(advance - 1)
        due += advance
        upcoming.removeFirst(advance)
        fill()
        return item
    }

    private mutating func fill() {
        while upcoming.count < Tuning.window {
            upcoming.append(order.program(at: due + upcoming.count))
        }
    }
}
