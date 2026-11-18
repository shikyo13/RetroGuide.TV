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
        /// `accountHasServers` is false when the Plex account has no server,
        /// neither its own nor shared with it.
        case choosingServer([PlexServerCandidate], accountHasServers: Bool)
        case findingJellyfin(JellyfinScan, isSearching: Bool)
        /// Finding a Jellyfin server, or reaching a Plex server at home, waits
        /// for local network access: the system is asking (iPhone and iPad),
        /// or it's off in Settings.
        case waitingForLocalNetwork(ServerKind)
        case enteringJellyfinAddress(message: String?)
        /// A home or VPN Jellyfin server that only offers plain HTTP: ask
        /// before connecting without encryption.
        case offeringPlainHTTP(URL)
        case jellyfinSignIn(JellyfinSignIn)
        /// `nil` while signing in to the saved Plex account, before a server is chosen.
        case connecting(serverName: String?)
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
        /// The users the server shows on its sign-in page, as tiles.
        var users: [JellyfinPublicUser] = []
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

    /// How a Plex account is linked.
    enum PlexSignIn {
        /// Plex's sign-in page in a sheet on this device: nothing to type.
        case signInPage
        /// A four-character code entered at plex.tv/link on any device.
        case code

        /// The sign-in page on iPhone and iPad; Apple TV has no browser.
        static var preferred: Self {
            #if os(tvOS)
            .code
            #else
            .signInPage
            #endif
        }
    }

    private(set) var plexSignIn = PlexSignIn.preferred
    /// The Jellyfin address typed last, shown again after a failed try.
    @ObservationIgnored var lastJellyfinAddress = ""
    /// The last search's results, to return to from a server chosen there.
    @ObservationIgnored var lastJellyfinScan: JellyfinScan?

    private(set) var step: Step {
        didSet {
            if let reached = step.usageStep, reached != oldValue.usageStep {
                PurchaseAttribution.shared.record(UsageEvent(.setup, detail: reached.rawValue))
            }
        }
    }

    @ObservationIgnored private let accountService: PlexAccountService
    @ObservationIgnored private let resolver: PlexConnectionResolver
    @ObservationIgnored let identities: ServerIdentities
    @ObservationIgnored let jellyfinService: JellyfinAccountService
    @ObservationIgnored private var accountToken: String?
    @ObservationIgnored private let onPlexAccountTokenChanged: (String?) -> Void
    @ObservationIgnored let excludedServerIDs: Set<String>
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored private var flow = Flow.plex
    /// The Plex server being connected, for connecting over the internet
    /// instead of waiting for local network access.
    @ObservationIgnored private var pendingPlexServer: PlexServerCandidate?

    /// - Parameters:
    ///   - accountToken: A saved Plex account token; when present, linking is skipped.
    ///   - excludedServerIDs: Servers already added, hidden from the pickers.
    ///   - showsWelcome: Whether to start with the welcome text (first run)
    ///     rather than just the choice of server.
    init(identities: ServerIdentities, accountToken: String? = nil, excludedServerIDs: Set<String> = [], showsWelcome: Bool = true, onPlexAccountTokenChanged: @escaping (String?) -> Void = { _ in }) {
        self.identities = identities
        self.accountToken = accountToken
        self.onPlexAccountTokenChanged = onPlexAccountTokenChanged
        self.excludedServerIDs = excludedServerIDs
        self.accountService = PlexAccountService(identity: identities.plex)
        self.resolver = PlexConnectionResolver(identity: identities.plex)
        self.jellyfinService = JellyfinAccountService(identity: identities.jellyfin)
        self.step = showsWelcome ? .welcome : .choosingKind
        if let reached = step.usageStep {
            PurchaseAttribution.shared.record(UsageEvent(.setup, detail: reached.rawValue))
        }
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
            step = .connecting(serverName: nil)
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

    /// Links the Plex account with the other method (sign-in page or code).
    func switchPlexSignIn() {
        plexSignIn = plexSignIn == .code ? .signInPage : .code
        beginPlex()
    }

    /// Forgets the linked Plex account and links another one.
    func useAnotherPlexAccount() {
        accountToken = nil
        onPlexAccountTokenChanged(nil)
        beginPlex()
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
        PlainHTTPOrigins.clearPending()
        step = .welcome
    }

    /// Connects `server`. One with a home address waits for local network
    /// access first, so the home address can win (and home playback
    /// settings with it) instead of the internet address.
    func choose(_ server: PlexServerCandidate) {
        task?.cancel()
        pendingPlexServer = server
        step = .connecting(serverName: server.name)
        task = Task { [weak self] in
            if server.hasHomeAddress {
                let allowed = await LocalNetworkAccess.waitUntilAllowed { [weak self] in
                    await self?.showLocalNetworkBlocked(for: .plex)
                }
                guard allowed, !Task.isCancelled else { return }
                self?.step = .connecting(serverName: server.name)
            }
            await self?.connect(to: server)
        }
    }

    /// While waiting for local network access: connect through the server's
    /// internet address instead.
    func connectPlexOverInternet() {
        guard let server = pendingPlexServer else { return }
        task?.cancel()
        step = .connecting(serverName: server.name)
        task = Task { [weak self] in
            await self?.connect(to: server)
        }
    }

    /// The viewer opened Plex's sign-in page or plex.tv/link.
    func plexSignInOpened() {
        PurchaseAttribution.shared.record(UsageEvent(.setup, detail: UsageEvent.SetupStep.plexSignInOpened.rawValue))
    }

    /// The viewer closed Plex's sign-in page before linking the account.
    func plexSignInClosed() {
        record(.plexSignInClosed)
    }

    func showLocalNetworkBlocked(for kind: ServerKind) {
        guard !Task.isCancelled else { return }
        record(kind == .plex ? .plexLocalNetworkBlocked : .jellyfinLocalNetworkBlocked)
        setStep(.waitingForLocalNetwork(kind))
    }

    // MARK: - Plex flow

    private func runLinkLoop() async {
        while !Task.isCancelled {
            do {
                let code = try await (plexSignIn == .code ? accountService.createLinkCode() : accountService.createSignIn())
                step = .linking(code)
                if let token = try await waitForApproval(of: code) {
                    accountToken = token
                    onPlexAccountTokenChanged(token)
                    await showServers(accountToken: token)
                    return
                }
                guard !Task.isCancelled else { return }
                record(.plexCodeExpired)
            } catch {
                guard !Task.isCancelled else { return }
                fail(error)
                return
            }
        }
    }

    private func showServers(accountToken: String) async {
        do {
            let all = try await accountService.servers(accountToken: accountToken)
            if all.isEmpty { record(.plexNoServers) }
            step = .choosingServer(all.filter { !excludedServerIDs.contains($0.id) }, accountHasServers: !all.isEmpty)
        } catch HTTPError.unauthorized {
            self.accountToken = nil
            onPlexAccountTokenChanged(nil)
            beginPlex()
        } catch {
            fail(error)
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
            fail(error)
        }
    }

    // MARK: - Measurement

    /// Shows `error` and records why setup stopped.
    func fail(_ error: any Error) {
        fail(error.localizedDescription, reason: UsageEvent.FailureReason(error))
    }

    func fail(_ message: String, reason: UsageEvent.FailureReason) {
        PurchaseAttribution.shared.record(UsageEvent(.setupFailed, detail: reason.rawValue))
        step = .failed(message)
    }

    func record(_ problem: UsageEvent.SetupProblem) {
        PurchaseAttribution.shared.record(UsageEvent(.setupProblem, detail: problem.rawValue))
    }
}

extension OnboardingModel.Step {
    /// The setup step this is, for usage measurement; `nil` for passing states.
    var usageStep: UsageEvent.SetupStep? {
        switch self {
        case .welcome: .welcome
        case .choosingKind, .connecting, .waitingForLocalNetwork: nil
        case .linking: .plexLink
        case .choosingServer: .plexServers
        case .findingJellyfin: .jellyfinFind
        case .enteringJellyfinAddress, .offeringPlainHTTP: .jellyfinAddress
        case .jellyfinSignIn: .jellyfinSignIn
        case .choosingLibraries: .libraries
        case .failed: .failed
        }
    }
}
