import Foundation

/// "This installation did `name` (`detail`) on `day`": setup and usage
/// steps, so it's known where people stop and why. Sent with the random installation
/// identifier that purchase measurement also uses. Details come from fixed
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
        /// Detail: its ``FailureReason`` (empty before 1.9.1).
        case libraryFailed
        /// Server setup stopped on an error screen. Detail: its ``FailureReason``.
        case setupFailed
        /// Server setup hit a known obstacle. Detail: ``SetupProblem``.
        case setupProblem
        /// Channels are on the guide. Detail: ``ChannelCount``.
        case lineupReady
        /// A program started playing. Detail: its ``ServerKind``.
        case watched
        /// The screen showed No Signal: a program couldn't be played after
        /// the quick retries. Detail: its ``FailureReason``.
        case playbackFailed
        /// A playing program stopped to buffer for a while. Detail: the
        /// playback ``Location``.
        case playbackStalled
        /// The Pro page was opened. Detail: where from, a ``ProEntry`` (empty before 1.11.4).
        case proViewed
        /// A program started playing. Detail: the ``Player``.
        case played
        /// No Signal, by player. Detail: `player.reason` (``detail(_:_:)``).
        case playerFailed
        /// Buffering, by player. Detail: `player.location`.
        case playerStalled
        /// How long a channel change took to show a picture. Detail: `player.time` (``TuneTime``).
        case tuneTime
        /// Programs played for at least this long today. Detail: ``WatchTime``.
        case watchTime
        /// A step of buying Pro. Detail: ``PurchaseStep``.
        case proPurchase
        /// The app crashed (MetricKit, iPhone and iPad). Detail: the build it crashed in.
        case crashed
        /// The app stopped responding for a while (MetricKit). Detail: the build.
        case hung
    }

    /// The video player, for the `player…` events.
    public enum Player: String, Sendable, CaseIterable {
        /// RetroGuide Player (libmpv).
        case retroguide
        /// Apple Player (AVFoundation).
        case apple
    }

    /// `player.value`, the detail of the per-player events.
    public static func detail(_ player: Player, _ value: some RawRepresentable<String>) -> String {
        "\(player.rawValue).\(value.rawValue)"
    }

    /// Channel change to picture, in coarse buckets.
    public enum TuneTime: String, Sendable, CaseIterable {
        case underOne = "0-1s"
        case underThree = "1-3s"
        case underTen = "3-10s"
        case longer = "10s+"

        public init(seconds: Double) {
            switch seconds {
            case ..<1: self = .underOne
            case ..<3: self = .underThree
            case ..<10: self = .underTen
            default: self = .longer
            }
        }
    }

    /// Daily playing time thresholds, each reported once a day when crossed.
    public enum WatchTime: String, Sendable, CaseIterable {
        case quarterHour = "15m"
        case hour = "1h"
        case threeHours = "3h"
        case sixHours = "6h"

        public var seconds: Double {
            switch self {
            case .quarterHour: 15 * 60
            case .hour: 60 * 60
            case .threeHours: 3 * 60 * 60
            case .sixHours: 6 * 60 * 60
            }
        }
    }

    /// Where the Pro page was opened from.
    public enum ProEntry: String, Sendable, CaseIterable {
        case settings
        case theme
        case channels
        case favorites
        case guide
        case reminders
        case setup
        case servers
        case schedule
        case topShelf
        case widgets
        case other
    }

    /// The steps of buying Pro.
    public enum PurchaseStep: String, Sendable, CaseIterable {
        case started
        case completed
        case pending
        case cancelled
        case failed
        /// Paid, but the App Store's signature didn't check out.
        case unverified
    }

    /// Server setup steps, in the order they're reached.
    public enum SetupStep: String, Sendable, CaseIterable {
        case welcome
        case plexLink
        /// Plex's sign-in page or plex.tv/link was opened from setup.
        case plexSignInOpened
        case plexServers
        case jellyfinFind
        /// The Jellyfin search found at least one server it can connect to.
        case jellyfinFound
        case jellyfinAddress
        case jellyfinSignIn
        case libraries
        case failed
    }

    /// Obstacles in server setup that explain where people stop.
    public enum SetupProblem: String, Sendable, CaseIterable {
        /// The Plex account has no server of its own and none shared with it.
        case plexNoServers
        /// The Jellyfin search found nothing on this network.
        case jellyfinFoundNone
        /// The Jellyfin search found only servers that don't offer HTTPS.
        case jellyfinFoundNotSecure
        /// The Jellyfin search found only servers whose certificate isn't trusted.
        case jellyfinFoundUntrusted
        /// A typed Jellyfin address answered, but not over HTTPS.
        case jellyfinNotSecure
        /// ...and it's an internet address, so connecting anyway wasn't
        /// offered (the viewer was told to use the home or VPN address).
        case jellyfinNotSecureInternet
        /// Finding a Jellyfin server waited on local network access: the
        /// system was asking (as it does the first time on iPhone and iPad),
        /// or it's turned off in Settings.
        case jellyfinLocalNetworkBlocked
        /// Connecting a Plex server with a home address waited on local
        /// network access.
        case plexLocalNetworkBlocked
        /// Local network access was still off a while after the Jellyfin
        /// search asked for it: refused, or the question left unanswered.
        case jellyfinLocalNetworkRefused
        /// The same, while connecting a Plex server at home.
        case plexLocalNetworkRefused
        /// Plex's sign-in page was closed before the account was linked.
        case plexSignInClosed
        /// A Plex link code expired without being approved (a new one is shown).
        case plexCodeExpired
        /// A typed Jellyfin address has a certificate this device doesn't trust.
        case jellyfinUntrusted
        /// Nothing answered at a typed Jellyfin address.
        case jellyfinNoAnswer
        /// The viewer chose to connect to a home or VPN Jellyfin server without
        /// encryption (not an obstacle, but where those setups go next).
        case jellyfinUnencryptedChosen
    }

    /// Why something failed, in coarse categories (never the message itself).
    public enum FailureReason: String, Sendable, CaseIterable {
        case timeout
        case offline
        case unreachable
        /// The server only offers plain HTTP.
        case notSecure
        case certificate
        case unauthorized
        case serverError
        case rejected
        case unreadable
        case badAddress
        case cancelled
        /// The previous startup didn't finish.
        case interrupted
        /// The server has no movie or TV show libraries the account can see.
        case noLibraries
        /// The video player couldn't play the file it was given.
        case player
        /// The stream opened but no picture arrived in time.
        case didNotStart
        case other

        public init(_ error: any Error) {
            self = Self.classify(error, depth: .zero)
        }

        private static let maximumDepth = 3

        private static func classify(_ error: any Error, depth: Int) -> Self {
            if error is CancellationError { return .cancelled }
            if let http = error as? HTTPError {
                switch http {
                case .secureConnectionRequired: return .notSecure
                case .invalidURL: return .badAddress
                case .invalidResponse, .decoding: return .unreadable
                case .unauthorized: return .unauthorized
                case let .status(code): return (500..<600).contains(code) ? .serverError : .rejected
                }
            }
            if let url = error as? URLError, let reason = reason(for: url.code) { return reason }
            if depth < maximumDepth, let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? any Error {
                return classify(underlying, depth: depth + 1)
            }
            return .other
        }

        private static func reason(for code: URLError.Code) -> Self? {
            switch code {
            case .cancelled: .cancelled
            case .timedOut: .timeout
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
                .offline
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .resourceUnavailable:
                .unreachable
            case .secureConnectionFailed, .appTransportSecurityRequiresSecureConnection:
                .notSecure
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired:
                .certificate
            case .userAuthenticationRequired, .userCancelledAuthentication: .unauthorized
            case .badServerResponse, .cannotParseResponse, .cannotDecodeRawData, .cannotDecodeContentData, .zeroByteResource:
                .unreadable
            case .badURL, .unsupportedURL: .badAddress
            default: nil
            }
        }
    }

    /// Where a stream came from, for ``Name/playbackStalled``: buffering at
    /// home and away from home have different fixes.
    public enum Location: String, Sendable, CaseIterable {
        case home
        case away
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
