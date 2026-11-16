import Foundation

/// Which way a server address is reached, for showing in Settings.
public enum ConnectionRoute: Sendable, Hashable {
    case home
    case vpn
    case internet

    public init(_ url: URL) {
        if NetworkLocation.isLikelyLocal(url) {
            self = .home
        } else if NetworkLocation.isLikelyVPN(url) {
            self = .vpn
        } else {
            self = .internet
        }
    }

    public var displayName: String {
        switch self {
        case .home: String(localized: "Home network", bundle: .module)
        case .vpn: String(localized: "VPN", bundle: .module)
        case .internet: String(localized: "Internet", bundle: .module, comment: "How a server address is reached: over the internet.")
        }
    }
}
