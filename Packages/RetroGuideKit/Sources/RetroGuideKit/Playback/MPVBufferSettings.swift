import Foundation

/// Network cache sizes per ``BufferProfile``. Extended buffering reads far
/// ahead to ride out slow or uneven connections to remote servers.
public struct MPVBufferSettings: Sendable {
    public let maxBytes: String
    public let readaheadSeconds: String

    public init(_ profile: BufferProfile) {
        switch profile {
        case .standard:
            maxBytes = "64MiB"
            readaheadSeconds = "20"
        case .extended:
            maxBytes = "192MiB"
            readaheadSeconds = "120"
        }
    }
}
