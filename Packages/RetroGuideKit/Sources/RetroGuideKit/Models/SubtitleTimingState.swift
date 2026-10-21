import Foundation

/// Timing corrections for the subtitle tracks in the current copy of a program.
/// Retuning the same copy preserves corrections. Another copy or program starts
/// from its show's last correction (see ``ShowSubtitleOffsets``), or from the
/// original timing for a movie or a show never adjusted.
public struct SubtitleTimingState: Sendable {
    private var itemID: String?
    private var versionIndex: Int?
    private var show: String?
    /// The show's correction when this copy started; tracks not adjusted since use it.
    private var inherited: TimeInterval = .zero
    private var offsets: [SubtitleChoice: TimeInterval] = [:]
    private var selection: SubtitleChoice = .none
    public private(set) var showOffsets: ShowSubtitleOffsets

    public init(showOffsets: ShowSubtitleOffsets = ShowSubtitleOffsets()) {
        self.showOffsets = showOffsets
    }

    /// The show whose episodes share a correction: the same show on any server where possible.
    public static func show(of item: MediaItem) -> String? {
        guard let series = item.series else { return nil }
        return series.externalID ?? "\(item.serverID)/\(series.key)"
    }

    public var delay: TimeInterval {
        guard selection != .none else { return .zero }
        return offsets[selection] ?? inherited
    }

    /// Replaces the remembered show corrections (e.g. with the saved ones at launch).
    public mutating func restore(_ showOffsets: ShowSubtitleOffsets) {
        self.showOffsets = showOffsets
    }

    public mutating func prepare(itemID: String, versionIndex: Int?, show: String? = nil, subtitle: SubtitleChoice) {
        if self.itemID != itemID || self.versionIndex != versionIndex {
            offsets.removeAll(keepingCapacity: true)
            inherited = show.flatMap { showOffsets[$0] } ?? .zero
        }
        self.itemID = itemID
        self.versionIndex = versionIndex
        self.show = show
        select(subtitle)
    }

    public mutating func select(_ subtitle: SubtitleChoice) {
        selection = subtitle
    }

    /// Corrects the selected track, and remembers it for the show's next episodes.
    public mutating func setDelay(_ delay: TimeInterval) {
        guard selection != .none else { return }
        let delay = SubtitleTiming.clamped(delay)
        offsets[selection] = delay
        if let show {
            showOffsets.set(delay, for: show)
        }
    }
}
