import Darwin

/// This device's addresses on local networks: Wi-Fi and Ethernet, which can
/// broadcast. Cellular and VPN interfaces can't, and aren't searched.
enum LocalInterfaces {
    private static let octetMask: UInt32 = 0xFF
    private static let octetShifts: [UInt32] = [24, 16, 8, 0]

    /// Private (RFC 1918) IPv4 addresses of active local-network interfaces,
    /// in host byte order.
    static func privateIPv4Addresses() -> [UInt32] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var addresses: [UInt32] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, flags & IFF_BROADCAST != 0,
                  let raw = interface.ifa_addr, raw.pointee.sa_family == UInt8(AF_INET)
            else { continue }
            let address = raw.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            if NetworkLocation.isPrivateIPv4(address), !addresses.contains(address) {
                addresses.append(address)
            }
        }
        return addresses
    }

    /// "192.168.1.20" for an address in host byte order.
    static func dotted(_ address: UInt32) -> String {
        octetShifts.map { String((address >> $0) & octetMask) }.joined(separator: ".")
    }
}
