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
            lastJellyfinScan = scan
            // One server and nothing else to choose: straight to signing in.
            if scan.servers.count == 1, scan.notSecure.isEmpty, scan.untrusted.isEmpty, let only = scan.servers.first {
                chooseJellyfin(only)
                return
            }
            setStep(.findingJellyfin(scan, isSearching: false))
        }
    }

    func enterJellyfinAddress() {
        task?.cancel()
        lastJellyfinScan = nil
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
                if let plain = JellyfinAddress.plainHTTP(from: address) {
                    setStep(.offeringPlainHTTP(plain))
                } else {
                    setStep(.enteringJellyfinAddress(message: JellyfinSetupText.notSecureOnInternet))
                }
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

    /// Back from "Connect without encryption?": to the search results when
    /// that's where it was chosen, otherwise to typing an address.
    func backFromPlainHTTPOffer() {
        if let scan = lastJellyfinScan {
            task?.cancel()
            setStep(.findingJellyfin(scan, isSearching: false))
        } else {
            enterJellyfinAddress()
        }
    }

    /// A server the search found that only offers plain HTTP.
    func offerPlainHTTP(host: String) {
        guard let plain = JellyfinAddress.plainHTTP(from: host) else { return }
        task?.cancel()
        setStep(.offeringPlainHTTP(plain))
    }

    /// The viewer agreed: connects to `address` without encryption. Allowed
    /// only for home-network and VPN addresses.
    func connectWithoutEncryption(_ address: URL) {
        task?.cancel()
        PlainHTTPOrigins.allowPending(address)
        record(.jellyfinUnencryptedChosen)
        setStep(.connecting(serverName: JellyfinConnectionText.short(address)))
        task = Task { [weak self] in
            guard let self else { return }
            let answer = await jellyfinService.probe(address)
            guard !Task.isCancelled else { return }
            guard case let .server(server) = answer else {
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

    /// Signs in to `server`. On iPhone and iPad, a server that lists its users
    /// starts with them as tiles (tap your name; saved passwords fill in);
    /// otherwise, and on Apple TV, Quick Connect when it's turned on.
    func chooseJellyfin(_ server: JellyfinServerInfo) {
        chooseJellyfin(server, preferQuickConnect: false)
    }

    private func chooseJellyfin(_ server: JellyfinServerInfo, preferQuickConnect: Bool) {
        task?.cancel()
        setStep(.jellyfinSignIn(JellyfinSignIn(server: server)))
        task = Task { [weak self] in
            guard let self else { return }
            let users = await jellyfinService.publicUsers(on: server)
            guard !Task.isCancelled else { return }
            #if os(iOS)
            if !preferQuickConnect, !users.isEmpty {
                var signIn = JellyfinSignIn(server: server)
                signIn.users = users
                signIn.usesPassword = true
                signIn.isQuickConnectAvailable = await jellyfinService.isQuickConnectEnabled(on: server)
                guard !Task.isCancelled else { return }
                setStep(.jellyfinSignIn(signIn))
                return
            }
            #endif
            await runQuickConnect(on: server, users: users)
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
        chooseJellyfin(signIn.server, preferQuickConnect: true)
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

    private func runQuickConnect(on server: JellyfinServerInfo, users: [JellyfinPublicUser]) async {
        guard await jellyfinService.isQuickConnectEnabled(on: server) else {
            var signIn = JellyfinSignIn(server: server)
            signIn.users = users
            signIn.isQuickConnectAvailable = false
            signIn.usesPassword = true
            setStep(.jellyfinSignIn(signIn))
            return
        }
        do {
            let code = try await jellyfinService.startQuickConnect(on: server)
            guard !Task.isCancelled else { return }
            var waiting = JellyfinSignIn(server: server, code: code)
            waiting.users = users
            setStep(.jellyfinSignIn(waiting))
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
            signIn.users = users
            signIn.usesPassword = true
            signIn.message = "Quick Connect isn't working right now (\(error.localizedDescription)). Sign in with your password instead."
            setStep(.jellyfinSignIn(signIn))
        }
    }

    private func finishJellyfin(_ server: JellyfinServerInfo, session: JellyfinSession) async {
        setStep(.connecting(serverName: server.name))
        let isHome = NetworkLocation.isLikelyLocal(server.baseURL)
        let account = ServerAccount(
            id: server.id,
            kind: .jellyfin,
            name: server.name,
            baseURL: server.baseURL,
            playback: isHome ? .local : .remote,
            connection: ServerConnectionSettings(
                homeAddress: isHome ? server.baseURL : nil,
                awayAddress: isHome ? nil : server.baseURL,
                allowsUnencrypted: server.baseURL.scheme?.lowercased() == "http"
            ),
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
    static let notSecureOnInternet = "A server answered, but only without encryption (plain HTTP). Over the internet, RetroGuide.TV needs HTTPS with a trusted certificate. At home or over a VPN like Tailscale, use the server's home or VPN address instead."
    static let untrusted = "A server answered, but this device doesn't trust its certificate. A self-signed certificate won't work: use one from a trusted authority, such as Let's Encrypt."
    static let noAnswer = "No Jellyfin server answered at that address. Check the address and port, and that the server uses HTTPS with a trusted certificate."
}

/// Jellyfin addresses as people type them.
enum JellyfinConnectionText {
    /// "10.10.1.25:8096" or "jellyfin.example.com".
    static func short(_ url: URL) -> String {
        (url.host() ?? url.absoluteString) + (url.port.map { ":\($0)" } ?? "")
    }
}
