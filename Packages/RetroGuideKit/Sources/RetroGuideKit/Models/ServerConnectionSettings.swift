import Foundation

/// How RetroGuide chooses between a server's addresses (home, VPN, remote).
public enum ConnectionPreference: String, Codable, Sendable, CaseIterable, Hashable {
    /// Home address on the home network or over a VPN, otherwise remote.
    case automatic
    /// Always try the home address first, for VPNs that route to the home network.
    case preferHome
    /// Try a specific address first (for example the server's Tailscale IP).
    case custom

    public var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .preferHome: "Prefer home or VPN address"
        case .custom: "Custom address"
        }
    }

    /// For a settings row's value.
    public var shortName: String {
        switch self {
        case .automatic: "Automatic"
        case .preferHome: "Home first"
        case .custom: "Custom"
        }
    }

    public var explanation: String {
        switch self {
        case .automatic: "Uses the home address at home or over a VPN, and the internet address elsewhere."
        case .preferHome: "Always tries the home address first. Good for Tailscale subnet routes and other VPNs."
        case .custom: "Tries the address you enter first, such as the server's Tailscale IP."
        }
    }
}

/// Per-server connection preferences, set in Settings → Servers.
public struct ServerConnectionSettings: Codable, Sendable, Hashable {
    public var preference: ConnectionPreference
    /// Used with ``ConnectionPreference/custom``.
    public var customAddress: URL?
    /// Jellyfin: the address on the home network, used whenever it answers.
    public var homeAddress: URL?
    /// Jellyfin: the internet or VPN (Tailscale) address, used when the home
    /// address doesn't answer. Plex finds its own through plex.tv.
    public var awayAddress: URL?
    /// Jellyfin: the viewer agreed to plain HTTP for this server's home and
    /// VPN addresses (never internet addresses).
    public var allowsUnencrypted: Bool

    public init(
        preference: ConnectionPreference = .automatic,
        customAddress: URL? = nil,
        homeAddress: URL? = nil,
        awayAddress: URL? = nil,
        allowsUnencrypted: Bool = false
    ) {
        self.preference = preference
        self.customAddress = customAddress
        self.homeAddress = homeAddress
        self.awayAddress = awayAddress
        self.allowsUnencrypted = allowsUnencrypted
    }

    /// Tolerant decoding: settings saved before Jellyfin addresses existed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preference = try container.decodeIfPresent(ConnectionPreference.self, forKey: .preference) ?? .automatic
        customAddress = try container.decodeIfPresent(URL.self, forKey: .customAddress)
        homeAddress = try container.decodeIfPresent(URL.self, forKey: .homeAddress)
        awayAddress = try container.decodeIfPresent(URL.self, forKey: .awayAddress)
        allowsUnencrypted = try container.decodeIfPresent(Bool.self, forKey: .allowsUnencrypted) ?? false
    }

    /// Jellyfin's addresses in the order to try: home first.
    public var jellyfinAddresses: [URL] {
        [homeAddress, awayAddress].compactMap { $0 }
    }

    /// The addresses plain HTTP is allowed for, if the viewer agreed.
    public var plainHTTPAddresses: [URL] {
        allowsUnencrypted ? jellyfinAddresses.filter { $0.scheme?.lowercased() == "http" } : []
    }

    public static let automatic = ServerConnectionSettings()

    /// The custom address when it's the chosen preference.
    public var activeCustomAddress: URL? {
        preference == .custom ? customAddress : nil
    }
}
