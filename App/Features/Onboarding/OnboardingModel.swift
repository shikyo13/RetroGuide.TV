import Foundation
import Observation
import RetroGuideKit

/// Drives server setup, for onboarding and "Add a server": Plex (link the
/// account unless its token is already known → pick a server) or Jellyfin
/// (find or type the server → Quick Connect or password), then libraries.
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Equatable {
        case welcome
        /// "Plex or Jellyfin?" without the welcome text (adding a server).
        case choosingKind
        case linking(PlexLinkCode?)
        case choosingServer([PlexServerCandidate])
        case findingJellyfin(servers: [JellyfinServerInfo], isSearching: Bool)
        case enteringJellyfinAddress(message: String?)
        case jellyfinSignIn(JellyfinSignIn)
        case connecting(serverName: String)
        case choosingLibraries(PendingServer)
        case failed(String)
    }

    /// Signing in to a Jellyfin server that was found.
    struct JellyfinSignIn: Equatable {
        let server: JellyfinServerInfo
        /// The Quick Connect code to approve; `nil` while it's requested or
        /// when the server has Quick Connect turned off.
        var code: JellyfinQuickConnectCode?
        var isQuickConnectAvailable = true
        var usesPassword = false
        var isSigningIn = false
        var message: String?
    }

    /// A server that is connected but not yet saved.
    struct PendingServer: Equatable {
        let account: ServerAccount
        let token: String
        let accountToken: String?
        let libraries: [MediaLibrary]
    }

    private enum Timing {
        /// Plex link codes expire after ~15 minutes; request a fresh one a little earlier.
        static let codeLifetime: Duration = .seconds(14 * 60)
    }

    private enum Flow {
        case plex
        case jellyfin
    }

    private(set) var step: Step

    @ObservationIgnored private let accountService: PlexAccountService
    @ObservationIgnored private let resolver: PlexConnectionResolver
    @ObservationIgnored let identities: ServerIdentities
    @ObservationIgnored let jellyfinService: JellyfinAccountService
    @ObservationIgnored private var accountToken: String?
    @ObservationIgnored let excludedServerIDs: Set<String>
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored private var flow = Flow.plex

    /// - Parameters:
    ///   - accountToken: A saved Plex account token; when present, linking is skipped.
    ///   - excludedServerIDs: Servers already added, hidden from the pickers.
    ///   - showsWelcome: Whether to start with the welcome text (first run)
    ///     rather than just the choice of server.
    init(identities: ServerIdentities, accountToken: String? = nil, excludedServerIDs: Set<String> = [], showsWelcome: Bool = true) {
        self.identities = identities
        self.accountToken = accountToken
        self.excludedServerIDs = excludedServerIDs
        self.accountService = PlexAccountService(identity: identities.plex)
        self.resolver = PlexConnectionResolver(identity: identities.plex)
        self.jellyfinService = JellyfinAccountService(identity: identities.jellyfin)
        self.step = showsWelcome ? .welcome : .choosingKind
    }

    func setStep(_ newStep: Step) {
        step = newStep
    }

    // MARK: - Intents

    /// Starts Plex setup: lists servers straight away with a saved account, otherwise links first.
    func beginPlex() {
        flow = .plex
        task?.cancel()
        if let accountToken {
            step = .connecting(serverName: "your Plex account")
            task = Task { [weak self] in
                await self?.showServers(accountToken: accountToken)
            }
            return
        }
        step = .linking(nil)
        task = Task { [weak self] in
            await self?.runLinkLoop()
        }
    }

    /// Starts Jellyfin setup by looking for servers on the network.
    func beginJellyfin() {
        flow = .jellyfin
        findJellyfinServers()
    }

    /// Starts over with whichever server type was being set up.
    func retry() {
        switch flow {
        case .plex: beginPlex()
        case .jellyfin: beginJellyfin()
        }
    }

    func cancel() {
        task?.cancel()
        step = .welcome
    }

    func choose(_ server: PlexServerCandidate) {
        step = .connecting(serverName: server.name)
        Task { [weak self] in
            await self?.connect(to: server)
        }
    }

    // MARK: - Plex flow

    private func runLinkLoop() async {
        while !Task.isCancelled {
            do {
                let code = try await accountService.createLinkCode()
                step = .linking(code)
                if let token = try await waitForApproval(of: code) {
                    accountToken = token
                    await showServers(accountToken: token)
                    return
                }
            } catch {
                guard !Task.isCancelled else { return }
                step = .failed(error.localizedDescription)
                return
            }
        }
    }

    private func showServers(accountToken: String) async {
        do {
            let servers = try await accountService.servers(accountToken: accountToken)
                .filter { !excludedServerIDs.contains($0.id) }
            step = servers.isEmpty
                ? .failed("There are no more Plex Media Servers on this account to add.")
                : .choosingServer(servers)
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    /// Polls plex.tv until the code is approved (token) or expires (nil).
    private func waitForApproval(of code: PlexLinkCode) async throws -> String? {
        let deadline = ContinuousClock.now + Timing.codeLifetime
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: PlexAPI.Defaults.pinPollInterval)
            if let token = try await accountService.token(for: code) {
                return token
            }
        }
        return nil
    }

    private func connect(to server: PlexServerCandidate) async {
        do {
            let connection = try await resolver.resolveConnection(server, isVPNActive: VPNStatus.isActive)
            let baseURL = connection.url
            let account = ServerAccount(
                id: server.id,
                kind: .plex,
                name: server.name,
                baseURL: baseURL,
                playback: connection.isLocal ? .local : .remote
            )
            let client = PlexServerClient(serverID: server.id, baseURL: baseURL, token: server.accessToken, identity: identities.plex)
            let libraries = try await client.fetchLibraries().filter(\.isSchedulable)
            step = .choosingLibraries(
                PendingServer(account: account, token: server.accessToken, accountToken: accountToken, libraries: libraries)
            )
        } catch {
            step = .failed(error.localizedDescription)
        }
    }
}
