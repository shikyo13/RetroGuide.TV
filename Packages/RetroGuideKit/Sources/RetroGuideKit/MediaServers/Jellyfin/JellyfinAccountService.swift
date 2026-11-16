import Foundation

/// A Jellyfin server found at an address, before signing in.
public struct JellyfinServerInfo: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let version: String?
    /// The address that answered.
    public let baseURL: URL
    /// The address the server reports for its own network, if any.
    public let localAddress: URL?

    /// Whether this is the server with `serverID`, however the id is written.
    public func isServer(_ serverID: String) -> Bool {
        Self.sameServer(id, serverID)
    }

    /// Server ids appear with and without dashes and in either case.
    static func sameServer(_ lhs: String, _ rhs: String) -> Bool {
        canonical(lhs) == canonical(rhs)
    }

    private static func canonical(_ id: String) -> String {
        id.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

/// What answered when looking for a Jellyfin server at an address.
public enum JellyfinProbe: Sendable, Hashable {
    case server(JellyfinServerInfo)
    /// Something answered, but not over HTTPS (usually Jellyfin's plain-HTTP port).
    case notSecure
    /// HTTPS answered with a certificate this device doesn't trust.
    case untrustedCertificate
    case noAnswer

    /// Lower explains more.
    fileprivate var rank: Int {
        switch self {
        case .server: 0
        case .notSecure: 1
        case .untrustedCertificate: 2
        case .noAnswer: 3
        }
    }
}

/// A signed-in Jellyfin user.
public struct JellyfinSession: Sendable, Hashable {
    public let accessToken: String
    public let userID: String
    public let userName: String?
}

/// A code the viewer approves in another Jellyfin app to sign this device in.
public struct JellyfinQuickConnectCode: Sendable, Hashable {
    public let code: String
    let secret: String
}

/// Finding a Jellyfin server and signing in to it.
public struct JellyfinAccountService: Sendable {
    private let identity: JellyfinClientIdentity
    private let http: HTTPClient

    public init(identity: JellyfinClientIdentity, http: HTTPClient = HTTPClient()) {
        self.identity = identity
        self.http = http.jellyfin
    }

    /// The server answering at `baseURL`, or `nil` if nothing Jellyfin does.
    public func serverInfo(at baseURL: URL, timeout: TimeInterval = JellyfinAPI.Defaults.probeTimeout) async -> JellyfinServerInfo? {
        if case let .server(info) = await probe(baseURL, timeout: timeout) { return info }
        return nil
    }

    /// What answers at `baseURL` over HTTPS: a Jellyfin server, a server
    /// that doesn't offer HTTPS or has an untrusted certificate, or nothing.
    public func probe(_ baseURL: URL, timeout: TimeInterval = JellyfinAPI.Defaults.probeTimeout) async -> JellyfinProbe {
        do {
            let request = try builder(baseURL, timeout: timeout).request(path: JellyfinAPI.Path.publicInfo)
            let info = try await http.decode(JellyfinPublicInfo.self, for: request)
            return .server(JellyfinServerInfo(
                id: info.id,
                name: info.serverName ?? baseURL.host() ?? info.id,
                version: info.version,
                baseURL: baseURL,
                localAddress: info.localAddress.flatMap(URL.init(string:))
            ))
        } catch {
            switch UsageEvent.FailureReason(error) {
            case .notSecure: return .notSecure
            case .certificate: return .untrustedCertificate
            default: return .noAnswer
            }
        }
    }

    /// The first address `text` could mean that a Jellyfin server answers on,
    /// or `nil` if none does.
    public func findServer(at text: String) async -> JellyfinServerInfo? {
        if case let .server(info) = await lookUp(text) { return info }
        return nil
    }

    /// Tries each address `text` could mean. An `http://` address is tried
    /// over HTTPS at the same place, since many people type it out of habit.
    /// Without a server, the most telling answer: a server that isn't secure,
    /// then an untrusted certificate, then nothing.
    public func lookUp(_ text: String) async -> JellyfinProbe {
        let candidates = JellyfinAddress.candidates(from: JellyfinAddress.upgradingInsecureScheme(text))
        // All at once, so an address that doesn't answer costs one timeout, not several.
        let answers = await withTaskGroup(of: (Int, JellyfinProbe).self) { group in
            for (index, url) in candidates.enumerated() {
                group.addTask { (index, await probe(url)) }
            }
            var answers: [(Int, JellyfinProbe)] = []
            for await answer in group { answers.append(answer) }
            return answers
        }
        // The earliest candidate wins among servers, as if tried in order.
        return answers.min { ($0.1.rank, $0.0) < ($1.1.rank, $1.0) }?.1 ?? .noAnswer
    }

    public func isQuickConnectEnabled(on server: JellyfinServerInfo) async -> Bool {
        guard let request = try? builder(server.baseURL).request(path: JellyfinAPI.Path.quickConnectEnabled),
              let data = try? await http.data(for: request)
        else { return false }
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
    }

    public func startQuickConnect(on server: JellyfinServerInfo) async throws -> JellyfinQuickConnectCode {
        let request = try builder(server.baseURL).request(path: JellyfinAPI.Path.quickConnectInitiate, method: "POST")
        let state = try await http.decode(JellyfinQuickConnectState.self, for: request)
        return JellyfinQuickConnectCode(code: state.code, secret: state.secret)
    }

    /// The session once the code has been approved, otherwise `nil`.
    public func session(for code: JellyfinQuickConnectCode, on server: JellyfinServerInfo) async throws -> JellyfinSession? {
        let check = try builder(server.baseURL).request(
            path: JellyfinAPI.Path.quickConnectConnect,
            query: [URLQueryItem(name: "secret", value: code.secret)]
        )
        guard try await http.decode(JellyfinQuickConnectState.self, for: check).authenticated == true else { return nil }
        return try await authenticate(on: server, path: JellyfinAPI.Path.authenticateWithQuickConnect, body: JellyfinQuickConnectSignIn(secret: code.secret))
    }

    public func signIn(on server: JellyfinServerInfo, username: String, password: String) async throws -> JellyfinSession {
        try await authenticate(on: server, path: JellyfinAPI.Path.authenticateByName, body: JellyfinPasswordSignIn(username: username, pw: password))
    }

    /// The user's audio and subtitle language settings.
    public func languagePreferences(baseURL: URL, token: String) async throws -> LanguagePreferences {
        let request = try builder(baseURL, token: token).request(path: JellyfinAPI.Path.currentUser)
        let configuration = try await http.decode(JellyfinUser.self, for: request).configuration
        return LanguagePreferences(
            audioLanguage: Self.nonEmpty(configuration?.audioLanguagePreference),
            subtitleLanguage: Self.nonEmpty(configuration?.subtitleLanguagePreference),
            subtitleMode: Self.subtitleMode(configuration?.subtitleMode)
        )
    }

    /// "Default" and "Smart" use the foreign-audio rule; "Only forced"
    /// never enables ordinary subtitles, even for foreign audio.
    private static func subtitleMode(_ mode: String?) -> SubtitleMode {
        switch mode {
        case JellyfinAPI.SubtitleMode.always: .always
        case JellyfinAPI.SubtitleMode.none: .manual
        case JellyfinAPI.SubtitleMode.onlyForced: .forcedOnly
        default: .foreignAudio
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func authenticate(on server: JellyfinServerInfo, path: String, body: some Encodable) async throws -> JellyfinSession {
        var request = try builder(server.baseURL).request(
            path: path,
            method: "POST",
            extraHeaders: [JellyfinAPI.Header.contentType: JellyfinAPI.Header.json]
        )
        request.httpBody = try JellyfinCoding.encoder.encode(body)
        let result = try await http.decode(JellyfinAuthenticationResult.self, for: request)
        return JellyfinSession(accessToken: result.accessToken, userID: result.user.id, userName: result.user.name)
    }

    private func builder(_ baseURL: URL, token: String? = nil, timeout: TimeInterval = JellyfinAPI.Defaults.requestTimeout) -> RequestBuilder {
        RequestBuilder(baseURL: baseURL, headers: identity.headers(token: token), timeout: timeout)
    }
}
