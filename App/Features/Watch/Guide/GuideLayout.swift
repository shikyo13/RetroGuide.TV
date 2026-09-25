import CoreGraphics
import Foundation
import RetroGuideKit

/// Dimensions and time scale of the program guide.
enum GuideLayout {
    static let channelColumnWidth: CGFloat = 300
    static let rowHeight: CGFloat = 78
    static let rowSpacing: CGFloat = 6
    static let cellSpacing: CGFloat = 4
    static let visibleRows = 6
    static let rulerHeight: CGFloat = 44
    static let previewHeight: CGFloat = 340
    static let previewAspectRatio: CGFloat = 16 / 9
    static let audienceStripeWidth: CGFloat = 5
    static let nowLineWidth: CGFloat = 3
    /// Cells narrower than this show only an ellipsis-free marker.
    static let minimumTitleWidth: CGFloat = 70
    /// Cells wider than this also show the episode line.
    static let minimumSubtitleWidth: CGFloat = 220

    static var gridHeight: CGFloat {
        CGFloat(visibleRows) * rowHeight + CGFloat(visibleRows - 1) * rowSpacing
    }

    enum Time {
        /// One column of the guide (the ruler ticks).
        static let slot: TimeInterval = 30 * ScheduleConstants.secondsPerMinute
        /// How much time is visible across the grid.
        static let window: TimeInterval = 3 * slot
        /// How far into the future the guide can be browsed.
        static let lookahead: TimeInterval = 24 * ScheduleConstants.secondsPerHour
        /// When paging right, keep at least this much of the focused program visible.
        static let minimumVisible: TimeInterval = 15 * ScheduleConstants.secondsPerMinute
        /// Nudges focus anchors inside a program rather than on its boundary.
        static let epsilon: TimeInterval = 1
    }

    /// Floors `date` to the start of its guide slot (e.g. 8:47 → 8:30).
    static func slotStart(containing date: Date) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / Time.slot).rounded(.down) * Time.slot)
    }
}
