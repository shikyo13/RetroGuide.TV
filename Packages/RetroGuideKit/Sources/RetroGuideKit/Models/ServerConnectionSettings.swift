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

    public init(preference: ConnectionPreference = .automatic, customAddress: URL? = nil) {
        self.preference = preference
        self.customAddress = customAddress
    }

    public static let automatic = ServerConnectionSettings()

    /// The custom address when it's the chosen preference.
    public var activeCustomAddress: URL? {
        preference == .custom ? customAddress : nil
    }
}
