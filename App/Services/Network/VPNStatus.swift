import Darwin
import Foundation

/// Whether a VPN (Tailscale, WireGuard, IPsec…) is currently up, judged by a
/// tunnel interface carrying an IPv4 address. The system's own tunnels only
/// carry IPv6 link-local addresses, so they don't count.
enum VPNStatus {
    private static let tunnelInterfacePrefixes = ["utun", "ipsec", "ppp", "tun", "tap", "wg"]

    static var isActive: Bool {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == .zero, let first = addresses else { return false }
        defer { freeifaddrs(addresses) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  interface.ifa_flags & UInt32(IFF_UP) != .zero
            else { continue }
            let name = String(cString: interface.ifa_name)
            if tunnelInterfacePrefixes.contains(where: name.hasPrefix) {
                return true
            }
        }
        return false
    }
}
