import Foundation

/// The media server backends RetroTV can talk to.
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

    public init(id: String, kind: ServerKind, name: String, baseURL: URL, selectedLibraryIDs: Set<String> = []) {
        self.id = id
        self.kind = kind
        self.name = name
        self.baseURL = baseURL
        self.selectedLibraryIDs = selectedLibraryIDs
    }
}
