import Foundation

/// Projects the cached guide onto only the channels a widget actually displays.
enum WidgetTimeline {
    enum Tuning {
        static let rotation: TimeInterval = 3 * 60
        static let horizon: TimeInterval = 2 * 60 * 60
        static let upcomingPrograms = 4
    }

    static func channels(at date: Date, in snapshot: WhatsOnSnapshot, offset: Int, limit: Int) -> [WhatsOnSnapshot.Channel] {
        let live = snapshot.channels.filter { $0.program(at: date) != nil }
        guard !live.isEmpty else { return [] }
        let turn = snapshot.pinned == true ? 0 : Int((date.timeIntervalSince1970 / Tuning.rotation).rounded(.down)) + offset
        let start = ((turn % live.count) + live.count) % live.count
        let programs = live.count == 1 && limit > 1 ? Tuning.upcomingPrograms : 1
        return (live[start...] + live[..<start]).prefix(limit).map { channel in
            WhatsOnSnapshot.Channel(id: channel.id, number: channel.number, name: channel.name, callSign: channel.callSign,
                                    programs: Array(channel.programs.filter { $0.end > date }.prefix(programs)))
        }
    }

    static func dates(from now: Date, until end: Date, in snapshot: WhatsOnSnapshot, offset: Int, visibleChannels: Int) -> [Date] {
        var dates: Set<Date> = [now]
        var slot = (now.timeIntervalSince1970 / Tuning.rotation).rounded(.down) + 1
        while case let date = Date(timeIntervalSince1970: slot * Tuning.rotation), date < end {
            dates.insert(date)
            slot += 1
        }
        // A program changing on an off-screen channel cannot change the rendered widget.
        for channel in snapshot.channels {
            for program in channel.programs where program.end > now && program.end < end {
                if !channel.programs.contains(where: { $0.start == program.end }) {
                    dates.insert(program.end)
                }
            }
            for program in channel.programs where program.start > now && program.start < end {
                // A channel joining after a gap also changes the rotation's live set.
                let joinsRotation = !channel.programs.contains { $0.end == program.start }
                if joinsRotation || channels(at: program.start, in: snapshot, offset: offset, limit: visibleChannels).contains(where: { $0.id == channel.id }) {
                    dates.insert(program.start)
                }
            }
        }
        return dates.sorted()
    }
}
