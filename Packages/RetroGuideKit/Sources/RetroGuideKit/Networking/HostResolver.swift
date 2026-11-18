import Darwin
import Foundation

/// Looks up the addresses a host name means on this network.
enum HostResolver {
    /// The first IPv4 address `host` resolves to, dotted, or `nil`.
    static func firstIPv4(of host: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: lookUp(host))
            }
        }
    }

    private static func lookUp(_ host: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var results: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &results) == 0, let first = results else { return nil }
        defer { freeaddrinfo(results) }
        guard let raw = first.pointee.ai_addr, raw.pointee.sa_family == UInt8(AF_INET) else { return nil }
        let address = raw.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
        return LocalInterfaces.dotted(address)
    }
}
