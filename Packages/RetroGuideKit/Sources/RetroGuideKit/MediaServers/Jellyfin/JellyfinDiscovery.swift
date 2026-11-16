import Darwin
import Foundation

/// What a search of the local network found.
public struct JellyfinScan: Sendable, Hashable {
    /// Servers that answered over HTTPS with a trusted certificate, by name.
    public var servers: [JellyfinServerInfo] = []
    /// Addresses where a server answered on a Jellyfin port, but not over HTTPS.
    public var notSecure: [String] = []
    /// Addresses where HTTPS answered with a certificate this device doesn't trust.
    public var untrusted: [String] = []

    public init(servers: [JellyfinServerInfo] = [], notSecure: [String] = [], untrusted: [String] = []) {
        self.servers = servers
        self.notSecure = notSecure
        self.untrusted = untrusted
    }

    /// Why nothing usable was found, if so.
    public var problem: UsageEvent.SetupProblem? {
        guard servers.isEmpty else { return nil }
        if !notSecure.isEmpty { return .jellyfinFoundNotSecure }
        if !untrusted.isEmpty { return .jellyfinFoundUntrusted }
        return .jellyfinFoundNone
    }
}

/// Finds Jellyfin servers on the local network by asking every address of
/// this device's subnet, on Jellyfin's ports and over HTTPS, who it is.
///
/// Jellyfin also answers UDP broadcasts, but receiving broadcast replies
/// needs Apple's multicast entitlement; HTTPS probes don't.
public struct JellyfinDiscovery: Sendable {
    private enum Tuning {
        /// Simultaneous probes; most addresses never answer, so this bounds the wait.
        static let concurrentProbes = 128
        static let probeTimeout: TimeInterval = 1.5
        /// Only the device's own /24 is searched, even on larger networks.
        static let hostsPerSubnet: UInt32 = 254
        static let subnetMask: UInt32 = 0xFFFF_FF00
        /// Jellyfin's plain port (HTTPS behind it is rare but tells us a server is
        /// there when it isn't) and its own HTTPS port.
        static let ports = [JellyfinAPI.defaultPort, JellyfinAPI.defaultSecurePort]
    }

    private let service: JellyfinAccountService

    public init(service: JellyfinAccountService) {
        self.service = service
    }

    /// Every server that answered. Takes a few seconds.
    public func scan() async -> JellyfinScan {
        let targets = Self.localSubnetHosts().flatMap { host in Tuning.ports.map { (host, $0) } }
        let answers = (try? await targets.concurrentMap(limit: Tuning.concurrentProbes) { host, port -> (String, JellyfinProbe) in
            guard let url = URL(string: "\(JellyfinAPI.secureScheme)://\(host):\(port)") else { return (host, .noAnswer) }
            return (host, await service.probe(url, timeout: Tuning.probeTimeout))
        }) ?? []
        var scan = JellyfinScan()
        var seen = Set<String>()
        for (host, answer) in answers {
            switch answer {
            case let .server(info) where seen.insert(info.id.lowercased()).inserted:
                scan.servers.append(info)
            case .notSecure where !scan.notSecure.contains(host):
                scan.notSecure.append(host)
            case .untrustedCertificate where !scan.untrusted.contains(host):
                scan.untrusted.append(host)
            default:
                break
            }
        }
        scan.servers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        // A host with a working server isn't also reported as a problem.
        let working = Set(scan.servers.compactMap { $0.baseURL.host() })
        scan.notSecure.removeAll(where: working.contains)
        scan.untrusted.removeAll(where: working.contains)
        return scan
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
