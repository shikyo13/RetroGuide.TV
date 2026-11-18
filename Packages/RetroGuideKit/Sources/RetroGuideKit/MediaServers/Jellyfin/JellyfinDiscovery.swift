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
        /// Jellyfin's plain port first (where nearly every server is, and HTTPS
        /// behind it is rare but tells us a server is there when it isn't),
        /// then its own HTTPS port.
        static let ports = [JellyfinAPI.defaultPort, JellyfinAPI.defaultSecurePort]
    }

    private let service: JellyfinAccountService

    public init(service: JellyfinAccountService) {
        self.service = service
    }

    /// Everything found so far, each time something more answers, ending
    /// with the complete search. Takes a few seconds; cancel to stop early.
    public func scans() -> AsyncStream<JellyfinScan> {
        let targets = Tuning.ports.flatMap { port in Self.localSubnetHosts().map { ($0, port) } }
        let service = service
        return AsyncStream { continuation in
            let task = Task {
                var scan = JellyfinScan()
                var seen = Set<String>()
                await withTaskGroup(of: (String, JellyfinProbe).self) { group in
                    var next = targets.makeIterator()
                    func enqueue() {
                        guard let (host, port) = next.next() else { return }
                        group.addTask {
                            guard let url = URL(string: "\(JellyfinAPI.secureScheme)://\(host):\(port)") else { return (host, .noAnswer) }
                            return (host, await service.probe(url, timeout: Tuning.probeTimeout))
                        }
                    }
                    for _ in 0..<Tuning.concurrentProbes { enqueue() }
                    for await (host, answer) in group {
                        if scan.add(answer, from: host, seen: &seen) {
                            continuation.yield(scan.tidied())
                        }
                        enqueue()
                    }
                }
                continuation.yield(scan.tidied())
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The complete search.
    public func scan() async -> JellyfinScan {
        var last = JellyfinScan()
        for await scan in scans() { last = scan }
        return last
    }

    /// The other addresses in the /24 of each private IPv4 address this device
    /// has on a local network (Wi-Fi or Ethernet, not cellular or VPN).
    static func localSubnetHosts() -> [String] {
        var hosts: [String] = []
        var seenSubnets = Set<UInt32>()
        for address in LocalInterfaces.privateIPv4Addresses() {
            let subnet = address & Tuning.subnetMask
            guard seenSubnets.insert(subnet).inserted else { continue }
            for offset in 1...Tuning.hostsPerSubnet where subnet + offset != address {
                hosts.append(LocalInterfaces.dotted(subnet + offset))
            }
        }
        return hosts
    }
}

private extension JellyfinScan {
    /// Adds what answered at `host`; `true` if that changed the scan.
    mutating func add(_ answer: JellyfinProbe, from host: String, seen: inout Set<String>) -> Bool {
        switch answer {
        case let .server(info) where seen.insert(info.id.lowercased()).inserted:
            servers.append(info)
        case .notSecure where !notSecure.contains(host):
            notSecure.append(host)
        case .untrustedCertificate where !untrusted.contains(host):
            untrusted.append(host)
        default:
            return false
        }
        return true
    }

    /// Servers by name; a host with a working server isn't also a problem.
    func tidied() -> JellyfinScan {
        var scan = self
        scan.servers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let working = Set(scan.servers.compactMap { $0.baseURL.host() })
        scan.notSecure.removeAll(where: working.contains)
        scan.untrusted.removeAll(where: working.contains)
        return scan
    }
}
