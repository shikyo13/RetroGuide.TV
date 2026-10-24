import Darwin
import Foundation

/// Finds Jellyfin servers on the local network by asking every address of
/// this device's subnet, on Jellyfin's port, who it is.
///
/// Jellyfin also answers UDP broadcasts, but receiving broadcast replies
/// needs Apple's multicast entitlement; plain HTTP probes don't.
public struct JellyfinDiscovery: Sendable {
    private enum Tuning {
        /// Simultaneous probes; most addresses never answer, so this bounds the wait.
        static let concurrentProbes = 64
        static let probeTimeout: TimeInterval = 1.5
        /// Only the device's own /24 is searched, even on larger networks.
        static let hostsPerSubnet: UInt32 = 254
        static let subnetMask: UInt32 = 0xFFFF_FF00
    }

    private let service: JellyfinAccountService

    public init(service: JellyfinAccountService) {
        self.service = service
    }

    /// Every server that answered, sorted by name. Takes a few seconds.
    public func scan() async -> [JellyfinServerInfo] {
        let hosts = Self.localSubnetHosts()
        let found = (try? await hosts.concurrentMap(limit: Tuning.concurrentProbes) { host -> JellyfinServerInfo? in
            guard let url = URL(string: "\(JellyfinAPI.defaultScheme)://\(host):\(JellyfinAPI.defaultPort)") else { return nil }
            return await service.serverInfo(at: url, timeout: Tuning.probeTimeout)
        }) ?? []
        var seen = Set<String>()
        return found.compactMap { $0 }
            .filter { seen.insert($0.id.lowercased()).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The other addresses in the /24 of each private IPv4 address this device has.
    static func localSubnetHosts() -> [String] {
        var hosts: [String] = []
        var seenSubnets = Set<UInt32>()
        for address in privateIPv4Addresses() {
            let subnet = address & Tuning.subnetMask
            guard seenSubnets.insert(subnet).inserted else { continue }
            for offset in 1...Tuning.hostsPerSubnet where subnet + offset != address {
                hosts.append(dotted(subnet + offset))
            }
        }
        return hosts
    }

    /// Private (RFC 1918) IPv4 addresses of active interfaces, host byte order.
    private static func privateIPv4Addresses() -> [UInt32] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var addresses: [UInt32] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let raw = interface.ifa_addr, raw.pointee.sa_family == UInt8(AF_INET)
            else { continue }
            let address = raw.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            if NetworkLocation.isPrivateIPv4(address) {
                addresses.append(address)
            }
        }
        return addresses
    }

    private static func dotted(_ address: UInt32) -> String {
        [24, 16, 8, 0].map { String((address >> $0) & 0xFF) }.joined(separator: ".")
    }
}
