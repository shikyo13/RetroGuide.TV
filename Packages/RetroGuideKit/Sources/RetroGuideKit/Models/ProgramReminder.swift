import Foundation

public struct ProgramReminder: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let channelID: String
    public let itemID: String
    public let title: String
    public let channelName: String
    public let start: Date

    public init(channel: Channel, program: ScheduledProgram) {
        id = "reminder.\(channel.id).\(Int(program.start.timeIntervalSince1970))"
        channelID = channel.id
        itemID = program.item.id
        title = program.item.headline
        channelName = "\(channel.number) · \(channel.name)"
        start = program.start
    }

    public enum Limits {
        public static let pending = 60
        public static let staleAfter: TimeInterval = 5 * 60
    }
}
