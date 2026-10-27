import Foundation
import RetroGuideKit

struct RefreshResult: Encodable, Sendable {
    let channelCount: Int
    /// Servers that couldn't be read this time (their previous library is kept).
    let offlineServers: [String]
}

struct ProgressInfo: Encodable, Sendable {
    let fraction: Double
    let message: String
}

struct ChannelInfo: Encodable, Sendable {
    let id: String
    let number: Int
    let name: String
    let callSign: String
    let isHidden: Bool
}

extension CoreState {
    private enum Message {
        static let connecting = "Connecting…"
    }

    /// Reads every server's selected libraries (in parallel), then rebuilds the
    /// lineup. A server that fails keeps its last snapshot and is marked
    /// offline; it throws only when every server failed and nothing is cached.
    func refresh() async throws -> RefreshResult {
        let accounts = accounts
        progress = Dictionary(accounts.map { ($0.id, LibraryLoadProgress(fraction: .zero, message: Message.connecting)) }, uniquingKeysWith: { first, _ in first })
        let results = await withTaskGroup(of: (ServerAccount, Result<LibrarySnapshot, Error>).self) { group in
            for account in accounts {
                guard let client = clients[account.id] else { continue }
                group.addTask {
                    do {
                        let libraries = try await client.fetchLibraries().filter {
                            $0.isSchedulable && (account.selectedLibraryIDs.isEmpty || account.selectedLibraryIDs.contains($0.id))
                        }
                        let items = try await client.fetchItems(in: libraries) { update in
                            Task { await self.report(update, serverID: account.id) }
                        }
                        return (account, .success(LibrarySnapshot(serverID: account.id, serverName: account.name, libraries: libraries, items: items)))
                    } catch {
                        return (account, .failure(error))
                    }
                }
            }
            var collected: [(ServerAccount, Result<LibrarySnapshot, Error>)] = []
            for await result in group { collected.append(result) }
            return collected
        }
        var failures: [Error] = []
        for (account, result) in results {
            switch result {
            case let .success(snapshot):
                snapshots[account.id] = snapshot
                offlineServerIDs.remove(account.id)
                store?.saveSnapshot(snapshot)
            case let .failure(error):
                failures.append(error)
                offlineServerIDs.insert(account.id)
            }
        }
        progress = [:]
        if let failure = failures.first, failures.count == results.count, snapshots.isEmpty {
            throw failure
        }
        await refreshLanguagePreferences()
        rebuildLineup()
        let offline = accounts.filter { offlineServerIDs.contains($0.id) }.map(\.name)
        return RefreshResult(channelCount: visibleChannels.count, offlineServers: offline)
    }

    private func report(_ update: LibraryLoadProgress, serverID: String) {
        guard progress[serverID] != nil else { return }
        progress[serverID] = update
    }

    /// Overall loading progress, with the message of the first server still loading.
    func loadProgress() -> ProgressInfo {
        guard !progress.isEmpty else { return ProgressInfo(fraction: 1, message: "") }
        let fraction = progress.values.map(\.fraction).reduce(0, +) / Double(progress.count)
        let names = Dictionary(accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let loading = progress.sorted { $0.key < $1.key }.first { $0.value.fraction < 1 }
        let message = loading.map { "\(names[$0.key] ?? ""): \($0.value.message)" } ?? ""
        return ProgressInfo(fraction: fraction, message: message)
    }

    func channelList() -> [ChannelInfo] {
        channels.map { channel in
            ChannelInfo(id: channel.id, number: channel.number, name: channel.name, callSign: channel.callSign, isHidden: channel.isHidden)
        }
    }

    /// The account's audio and subtitle settings: Plex's while a Plex server
    /// is connected, otherwise the first Jellyfin user's (as on Apple platforms).
    private func refreshLanguagePreferences() async {
        guard let configuration else { return }
        if accounts.contains(where: { $0.kind == .plex }) {
            guard let accountToken = tokens[Self.plexAccountKey] else { return }
            languagePreferences = try? await PlexAccountService(identity: configuration.plexIdentity).languagePreferences(accountToken: accountToken)
            return
        }
        guard let jellyfin = accounts.first(where: { $0.kind == .jellyfin }), let token = tokens[jellyfin.id],
              var preferences = try? await JellyfinAccountService(identity: configuration.jellyfinIdentity)
                  .languagePreferences(baseURL: jellyfin.baseURL, token: token)
        else { return }
        if preferences.audioLanguage == nil, preferences.subtitleLanguage == nil {
            preferences.subtitleLanguage = Locale.current.language.languageCode?.identifier
        }
        languagePreferences = preferences
    }
}
