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
        case .home: "Home network"
        case .vpn: "VPN"
        case .internet: "Internet"
        }
    }
}
