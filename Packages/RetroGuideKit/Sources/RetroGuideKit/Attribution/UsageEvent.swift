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
        /// A typed Jellyfin address has a certificate this device doesn't trust.
        case jellyfinUntrusted
        /// Nothing answered at a typed Jellyfin address.
        case jellyfinNoAnswer
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
