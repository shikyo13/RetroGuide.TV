import Foundation
import RetroGuideKit

/// The Jellyfin steps of server setup: find the server (on the network or by
/// address), sign in with Quick Connect or a password, then pick libraries.
extension OnboardingModel {
    /// Searches the local network; servers already added are left out.
    func findJellyfinServers() {
        task?.cancel()
        setStep(.findingJellyfin(JellyfinScan(), isSearching: true))
        let discovery = JellyfinDiscovery(service: jellyfinService)
        let excluded = excludedServerIDs
        task = Task { [weak self] in
            var scan = await discovery.scan()
            guard !Task.isCancelled, let self else { return }
            if let problem = scan.problem { record(problem) }
            scan.servers.removeAll { excluded.contains($0.id) }
            setStep(.findingJellyfin(scan, isSearching: false))
        }
    }

    func enterJellyfinAddress() {
        task?.cancel()
        setStep(.enteringJellyfinAddress(message: nil))
    }

    /// Looks for a Jellyfin server at what the viewer typed. An `http://`
    /// address is tried over HTTPS at the same place.
    func connectToJellyfin(address: String) {
        task?.cancel()
        lastJellyfinAddress = address
        guard !JellyfinAddress.candidates(from: JellyfinAddress.upgradingInsecureScheme(address)).isEmpty else {
            setStep(.enteringJellyfinAddress(message: HTTPError.invalidURL.localizedDescription))
            return
        }
        setStep(.connecting(serverName: address.trimmingCharacters(in: .whitespaces)))
        task = Task { [weak self] in
            guard let self else { return }
            let answer = await jellyfinService.lookUp(address)
            guard !Task.isCancelled else { return }
            let server: JellyfinServerInfo
            switch answer {
            case let .server(found):
                server = found
            case .notSecure:
                record(.jellyfinNotSecure)
                setStep(.enteringJellyfinAddress(message: JellyfinSetupText.notSecure))
                return
            case .untrustedCertificate:
                record(.jellyfinUntrusted)
                setStep(.enteringJellyfinAddress(message: JellyfinSetupText.untrusted))
                return
            case .noAnswer:
                record(.jellyfinNoAnswer)
                setStep(.enteringJellyfinAddress(message: JellyfinSetupText.noAnswer))
                return
            }
            guard !excludedServerIDs.contains(server.id) else {
                setStep(.enteringJellyfinAddress(message: "\(server.name) is already added."))
                return
            }
            chooseJellyfin(server)
        }
    }

    /// Signs in to `server`, starting with Quick Connect when it's turned on.
    func chooseJellyfin(_ server: JellyfinServerInfo) {
        task?.cancel()
        setStep(.jellyfinSignIn(JellyfinSignIn(server: server)))
        task = Task { [weak self] in
            await self?.runQuickConnect(on: server)
        }
    }

    func useJellyfinPassword() {
        guard case var .jellyfinSignIn(signIn) = step else { return }
        task?.cancel()
        signIn.usesPassword = true
        signIn.message = nil
        setStep(.jellyfinSignIn(signIn))
    }

    func useJellyfinQuickConnect() {
        guard case let .jellyfinSignIn(signIn) = step else { return }
        chooseJellyfin(signIn.server)
    }

    func signInToJellyfin(username: String, password: String) {
        guard case var .jellyfinSignIn(signIn) = step else { return }
        signIn.isSigningIn = true
        signIn.message = nil
        setStep(.jellyfinSignIn(signIn))
        let server = signIn.server
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await jellyfinService.signIn(on: server, username: username, password: password)
                await finishJellyfin(server, session: session)
            } catch {
                signIn.isSigningIn = false
                signIn.message = (error as? HTTPError) == .unauthorized
                    ? "That username and password didn't work."
                    : error.localizedDescription
                setStep(.jellyfinSignIn(signIn))
            }
        }
    }

    // MARK: - Flow

    private func runQuickConnect(on server: JellyfinServerInfo) async {
        guard await jellyfinService.isQuickConnectEnabled(on: server) else {
            var signIn = JellyfinSignIn(server: server)
            signIn.isQuickConnectAvailable = false
            signIn.usesPassword = true
            setStep(.jellyfinSignIn(signIn))
            return
        }
        do {
            let code = try await jellyfinService.startQuickConnect(on: server)
            guard !Task.isCancelled else { return }
            setStep(.jellyfinSignIn(JellyfinSignIn(server: server, code: code)))
            while !Task.isCancelled {
                try await Task.sleep(for: JellyfinAPI.Defaults.quickConnectPollInterval)
                if let session = try await jellyfinService.session(for: code, on: server) {
                    await finishJellyfin(server, session: session)
                    return
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            var signIn = JellyfinSignIn(server: server)
            signIn.usesPassword = true
            signIn.message = "Quick Connect isn't working right now (\(error.localizedDescription)). Sign in with your password instead."
            setStep(.jellyfinSignIn(signIn))
        }
    }

    private func finishJellyfin(_ server: JellyfinServerInfo, session: JellyfinSession) async {
        setStep(.connecting(serverName: server.name))
        let account = ServerAccount(
            id: server.id,
            kind: .jellyfin,
            name: server.name,
            baseURL: server.baseURL,
            playback: NetworkLocation.isLikelyLocal(server.baseURL) ? .local : .remote,
            userID: session.userID
        )
        let client = JellyfinServerClient(
            serverID: server.id,
            baseURL: server.baseURL,
            token: session.accessToken,
            userID: session.userID,
            identity: identities.jellyfin
        )
        do {
            let libraries = try await client.fetchLibraries().filter(\.isSchedulable)
            if libraries.isEmpty {
                fail("\(server.name) has no movie or TV show libraries this account can see.", reason: .noLibraries)
            } else {
                setStep(.choosingLibraries(PendingServer(account: account, token: session.accessToken, accountToken: nil, libraries: libraries)))
            }
        } catch {
            fail(error)
        }
    }
}

/// What Jellyfin setup says when a server can't be used, and why.
enum JellyfinSetupText {
    static let notSecure = "A server answered, but only without encryption (plain HTTP). RetroGuide.TV needs HTTPS with a trusted certificate. See HTTPS setup at retroguide.tv/support."
    static let untrusted = "A server answered, but this device doesn't trust its certificate. A self-signed certificate won't work: use one from a trusted authority, such as Let's Encrypt."
    static let noAnswer = "No Jellyfin server answered at that address. Check the address and port, and that the server uses HTTPS with a trusted certificate."
}
