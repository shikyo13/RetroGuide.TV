import Foundation
import Observation
import RetroGuideKit

/// Focus and scroll state of the program guide.
///
/// The grid is one focusable element; this model interprets remote moves the
/// way a cable box does: up/down change channel rows, left/right step between
/// programs, and the visible time window follows the focus.
@MainActor
@Observable
final class GuideModel {
    private(set) var channels: [Channel]
    private(set) var focusedRow: Int
    private(set) var firstVisibleRow: Int
    private(set) var windowStart: Date
    /// The instant used to pick the focused program within the focused row.
    private(set) var focusAnchor: Date

    init(channels: [Channel], focusedChannelID: String?, now: Date = .now) {
        self.channels = channels
        let row = channels.firstIndex { $0.id == focusedChannelID } ?? .zero
        focusedRow = row
        firstVisibleRow = Self.centeredFirstRow(for: row, count: channels.count)
        windowStart = GuideLayout.slotStart(containing: now)
        focusAnchor = now
    }

    // MARK: - Derived

    var windowEnd: Date {
        windowStart.addingTimeInterval(GuideLayout.Time.window)
    }

    var window: DateInterval {
        DateInterval(start: windowStart, end: windowEnd)
    }

    var visibleRows: Range<Int> {
        firstVisibleRow..<min(firstVisibleRow + GuideLayout.visibleRows, channels.count)
    }

    var focusedChannel: Channel? {
        channels.indices.contains(focusedRow) ? channels[focusedRow] : nil
    }

    var focusedProgram: ScheduledProgram? {
        focusedChannel?.timeline.program(at: focusAnchor)
    }

    var isShowingNow: Bool {
        windowStart <= .now
    }

    // MARK: - Navigation

    func moveDown() {
        guard focusedRow + 1 < channels.count else { return }
        setRow(focusedRow + 1)
    }

    /// Returns `false` when already on the first row so the caller can move focus to the header.
    @discardableResult
    func moveUp() -> Bool {
        guard focusedRow > .zero else { return false }
        setRow(focusedRow - 1)
        return true
    }

    /// Jumps a full page of channels, wrapping back to the top at the end.
    func pageDown() {
        let next = focusedRow + GuideLayout.visibleRows
        setRow(next < channels.count ? next : .zero)
    }

    func moveRight() {
        guard let timeline = focusedChannel?.timeline,
              let current = focusedProgram,
              let next = timeline.program(after: current),
              next.start < Date.now.addingTimeInterval(GuideLayout.Time.lookahead)
        else { return }
        let visibleSpan = min(GuideLayout.Time.minimumVisible, next.slotEnd.timeIntervalSince(next.start))
        while next.start.addingTimeInterval(visibleSpan) > windowEnd {
            windowStart = windowStart.addingTimeInterval(GuideLayout.Time.slot)
        }
        focusAnchor = next.start.addingTimeInterval(GuideLayout.Time.epsilon)
    }

    func moveLeft() {
        guard let timeline = focusedChannel?.timeline, let current = focusedProgram else { return }
        let earliest = GuideLayout.slotStart(containing: .now)
        if current.start <= windowStart {
            // The focused program is clipped on the left: reveal more of it first.
            guard windowStart > earliest else { return }
            windowStart = windowStart.addingTimeInterval(-GuideLayout.Time.slot)
            return
        }
        guard let previous = timeline.program(at: current.start.addingTimeInterval(-GuideLayout.Time.epsilon)),
              previous.slotEnd > Date.now
        else { return }
        while previous.start < windowStart, windowStart > earliest {
            windowStart = windowStart.addingTimeInterval(-GuideLayout.Time.slot)
        }
        focusAnchor = anchor(for: previous)
    }

    /// Returns the grid to the current time.
    func jumpToNow() {
        windowStart = GuideLayout.slotStart(containing: .now)
        focusAnchor = .now
    }

    // MARK: - Helpers

    private func setRow(_ row: Int) {
        focusedRow = row
        if row < firstVisibleRow {
            firstVisibleRow = row
        } else if row >= firstVisibleRow + GuideLayout.visibleRows {
            firstVisibleRow = row - GuideLayout.visibleRows + 1
        }
        // The anchor time is kept as-is so moving through rows stays in the
        // same time slot, like a cable box guide; it never falls behind "now".
        focusAnchor = max(focusAnchor, .now)
    }

    /// The anchor for a program is the latest of its start and now, so focus
    /// never lands on something that has already finished.
    private func anchor(for program: ScheduledProgram) -> Date {
        max(program.start, .now).addingTimeInterval(GuideLayout.Time.epsilon)
    }

    private static func centeredFirstRow(for row: Int, count: Int) -> Int {
        let half = GuideLayout.visibleRows / 2
        let maxFirst = max(count - GuideLayout.visibleRows, .zero)
        return min(max(row - half, .zero), maxFirst)
    }
}
