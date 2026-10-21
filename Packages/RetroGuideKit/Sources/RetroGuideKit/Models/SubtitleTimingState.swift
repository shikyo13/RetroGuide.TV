import Foundation

/// Timing corrections for the subtitle tracks in the current copy of a program.
/// Retuning the same copy preserves corrections; another program or copy starts fresh.
public struct SubtitleTimingState: Sendable {
    private var itemID: String?
    private var versionIndex: Int?
    private var offsets: [SubtitleChoice: TimeInterval] = [:]
    private var selection: SubtitleChoice = .none

    public init() {}

    public var delay: TimeInterval {
        offsets[selection] ?? .zero
    }

    public mutating func prepare(itemID: String, versionIndex: Int?, subtitle: SubtitleChoice) {
        if self.itemID != itemID || self.versionIndex != versionIndex {
            offsets.removeAll(keepingCapacity: true)
        }
        self.itemID = itemID
        self.versionIndex = versionIndex
        select(subtitle)
    }

    public mutating func select(_ subtitle: SubtitleChoice) {
        selection = subtitle
    }

    public mutating func setDelay(_ delay: TimeInterval) {
        guard selection != .none else { return }
        let delay = SubtitleTiming.clamped(delay)
        offsets[selection] = delay == .zero ? nil : delay
    }
}
