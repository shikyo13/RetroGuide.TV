import Foundation
import Observation
import RetroGuideKit

/// Drives first-run setup: link Plex → pick a server → pick libraries.
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Equatable {
        case welcome
        case linking(PlexLinkCode?)
        case choosingServer([PlexServerCandidate])
        case connecting(serverName: String)
        case choosingLibraries(PendingServer)
        case failed(String)
    }

    /// A server that is connected but not yet saved.
    struct PendingServer: Equatable {
        let account: ServerAccount
        let token: String
        let libraries: [MediaLibrary]
    }

    private enum Timing {
        /// Plex link codes expire after ~15 minutes; request a fresh one a little earlier.
        static let codeLifetime: Duration = .seconds(14 * 60)
    }

    private(set) var step: Step = .welcome

    @ObservationIgnored private let accountService: PlexAccountService
    @ObservationIgnored private let resolver: PlexConnectionResolver
    @ObservationIgnored private let identity: PlexClientIdentity
    @ObservationIgnored private var accountToken: String?
    @ObservationIgnored private var linkTask: Task<Void, Never>?

    init(identity: PlexClientIdentity) {
        self.identity = identity
        self.accountService = PlexAccountService(identity: identity)
        self.resolver = PlexConnectionResolver(identity: identity)
    }

    // MARK: - Intents

    func beginPlexLink() {
        linkTask?.cancel()
        step = .linking(nil)
        linkTask = Task { [weak self] in
            await self?.runLinkLoop()
        }
    }

    func cancel() {
        linkTask?.cancel()
        step = .welcome
    }

    func choose(_ server: PlexServerCandidate) {
        step = .connecting(serverName: server.name)
        Task { [weak self] in
            await self?.connect(to: server)
        }
    }

    // MARK: - Flow

    private func runLinkLoop() async {
        while !Task.isCancelled {
            do {
                let code = try await accountService.createLinkCode()
                step = .linking(code)
                if let token = try await waitForApproval(of: code) {
                    accountToken = token
                    let servers = try await accountService.servers(accountToken: token)
                    step = servers.isEmpty
                        ? .failed("No Plex Media Servers were found on this account.")
                        : .choosingServer(servers)
                    return
                }
            } catch {
                guard !Task.isCancelled else { return }
                step = .failed(error.localizedDescription)
                return
            }
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
            let baseURL = try await resolver.resolve(server)
            let account = ServerAccount(id: server.id, kind: .plex, name: server.name, baseURL: baseURL)
            let client = PlexServerClient(serverID: server.id, baseURL: baseURL, token: server.accessToken, identity: identity)
            let libraries = try await client.fetchLibraries().filter(\.isSchedulable)
            step = .choosingLibraries(PendingServer(account: account, token: server.accessToken, libraries: libraries))
        } catch {
            step = .failed(error.localizedDescription)
        }
    }
}
