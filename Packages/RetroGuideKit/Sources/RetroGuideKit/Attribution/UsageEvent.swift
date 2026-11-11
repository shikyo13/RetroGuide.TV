import Foundation

/// "This installation did `name` (`detail`) on `day`": anonymous setup and
/// usage steps, so it's known where people stop. Details come from fixed
/// lists. Never titles, server addresses, library contents or viewing history.
public struct UsageEvent: Codable, Hashable, Sendable {
    public enum Name: String, Codable, Sendable, CaseIterable {
        /// The app was in the foreground. Detail: the kinds of server it has.
        case active
        /// Server setup reached a step. Detail: ``SetupStep``.
        case setup
        /// A server was saved. Detail: its ``ServerKind``.
        case serverConnected
        /// Startup or a library refresh failed with no channels to show.
        case libraryFailed
        /// Channels are on the guide. Detail: ``ChannelCount``.
        case lineupReady
        /// A program started playing. Detail: its ``ServerKind``.
        case watched
        /// The Pro page was opened.
        case proViewed
    }

    /// Server setup steps, in the order they're reached.
    public enum SetupStep: String, Sendable, CaseIterable {
        case welcome
        case plexLink
        case plexServers
        case jellyfinFind
        case jellyfinAddress
        case jellyfinSignIn
        case libraries
        case failed
    }

    /// How many channels a lineup has, in coarse buckets.
    public enum ChannelCount: String, Sendable, CaseIterable {
        case none = "0"
        case few = "1-9"
        case some = "10-49"
        case many = "50+"

        public init(_ count: Int) {
            switch count {
            case ..<1: self = .none
            case ..<10: self = .few
            case ..<50: self = .some
            default: self = .many
            }
        }
    }

    public static let noDetail = ""

    public let name: Name
    public let detail: String
    /// The UTC calendar day, `yyyy-MM-dd`.
    public let day: String

    public init(_ name: Name, detail: String = UsageEvent.noDetail, on date: Date = .now) {
        self.name = name
        self.detail = detail
        self.day = Self.day(of: date)
    }

    /// The servers an installation has, for ``Name/active``: `none`, `plex`,
    /// `jellyfin` or `jellyfin+plex`.
    public static func serverKinds(_ kinds: some Sequence<ServerKind>) -> String {
        let names = Set(kinds.map(\.rawValue)).sorted()
        return names.isEmpty ? "none" : names.joined(separator: "+")
    }

    static func day(of date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
