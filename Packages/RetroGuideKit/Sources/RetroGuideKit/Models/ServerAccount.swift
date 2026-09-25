import Foundation

/// The media server backends RetroGuide can talk to.
public enum ServerKind: String, Codable, Sendable, CaseIterable {
    case plex

    public var displayName: String {
        switch self {
        case .plex: "Plex"
        }
    }
}

/// A connected media server. Secrets (access tokens) are stored separately in
/// the keychain, keyed by ``id``, and are never part of this value.
public struct ServerAccount: Codable, Sendable, Hashable, Identifiable {
    /// The server's stable machine identifier.
    public let id: String
    public let kind: ServerKind
    public var name: String
    public var baseURL: URL
    /// Library ids (``MediaLibrary/id``) the user chose to build channels from.
    public var selectedLibraryIDs: Set<String>
    public var playback: ServerPlaybackSettings

    public init(
        id: String,
        kind: ServerKind,
        name: String,
        baseURL: URL,
        selectedLibraryIDs: Set<String> = [],
        playback: ServerPlaybackSettings = .local
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.baseURL = baseURL
        self.selectedLibraryIDs = selectedLibraryIDs
        self.playback = playback
    }

    /// Tolerant decoding so servers saved by older versions keep working.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(ServerKind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decode(URL.self, forKey: .baseURL)
        selectedLibraryIDs = try container.decodeIfPresent(Set<String>.self, forKey: .selectedLibraryIDs) ?? []
        // Servers saved before playback settings existed get defaults for where they are.
        playback = try container.decodeIfPresent(ServerPlaybackSettings.self, forKey: .playback)
            ?? (NetworkLocation.isLikelyLocal(baseURL) ? .local : .remote)
    }
}
