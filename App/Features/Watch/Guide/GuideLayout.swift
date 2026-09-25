import Foundation
import RetroGuideKit
import SwiftUI

/// Dimensions and time scale of the program guide.
enum GuideLayout {
    static let channelColumnWidth = PlatformMetric.value(tv: CGFloat(300), touch: 132)
    /// iPhone in portrait: the channel column shows only the number badge.
    static let narrowChannelColumnWidth: CGFloat = 96
    static let rowHeight = PlatformMetric.value(tv: CGFloat(78), touch: 54)
    static let rowSpacing = PlatformMetric.value(tv: CGFloat(6), touch: 4)
    static let cellSpacing = PlatformMetric.value(tv: CGFloat(4), touch: 2)
    static let visibleRows = 6
    static let rulerHeight = PlatformMetric.value(tv: CGFloat(44), touch: 36)
    static let previewHeight = PlatformMetric.value(tv: CGFloat(340), touch: 190)
    /// Preview height on phones in landscape, where vertical space is scarce.
    static let compactPreviewHeight: CGFloat = 120
    static let previewAspectRatio: CGFloat = 16 / 9
    static let audienceStripeWidth = PlatformMetric.value(tv: CGFloat(5), touch: 3)
    static let nowLineWidth = PlatformMetric.value(tv: CGFloat(3), touch: 2)
    /// Cells narrower than this show only an ellipsis-free marker.
    static let minimumTitleWidth = PlatformMetric.value(tv: CGFloat(70), touch: 64)
    /// Cells wider than this also show the episode line.
    static let minimumSubtitleWidth = PlatformMetric.value(tv: CGFloat(220), touch: 120)

    static var gridHeight: CGFloat {
        CGFloat(visibleRows) * rowHeight + CGFloat(visibleRows - 1) * rowSpacing
    }

    enum Time {
        /// One column of the guide (the ruler ticks).
        static let slot: TimeInterval = 30 * ScheduleConstants.secondsPerMinute
        /// How many slots are visible across the grid.
        static let visibleSlots = 3
        /// Fewer slots on narrow screens (iPhone in portrait) so titles stay readable.
        static let compactVisibleSlots = 2
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

extension EnvironmentValues {
    /// Width of the guide's channel column for the current screen.
    var guideChannelColumnWidth: CGFloat {
        isNarrowLayout ? GuideLayout.narrowChannelColumnWidth : GuideLayout.channelColumnWidth
    }
}
