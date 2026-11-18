import Foundation
import Network

/// Whether this app may reach devices on the local network.
///
/// On iPhone and iPad the system asks the first time the app reaches the
/// local network, and may refuse connections made while it asks, so a search
/// started then finds nothing. The viewer can also turn access off in
/// Settings. Apple TV doesn't ask.
public enum LocalNetworkAccess {
    public enum State: Sendable, Equatable {
        /// The system is asking, or access is off in Settings.
        case blocked
        /// Local network privacy isn't stopping connections (or there's no
        /// local network to reach).
        case allowed
    }

    private enum Tuning {
        /// The discard port: usually refused, which still shows the
        /// connection was allowed to reach the local network.
        static let port: NWEndpoint.Port = 9
        /// How long one check waits for the connection to settle.
        static let checkTimeout: Duration = .seconds(2)
        /// How often to check again while blocked.
        static let recheckInterval: Duration = .seconds(1)
        static let subnetMask: UInt32 = 0xFFFF_FF00
        /// Where routers usually are in a /24.
        static let routerHosts: Set<UInt32> = [1, 254]
        static let lastHost: UInt32 = 254
    }

    /// `.blocked` while access is refused (at most once), then `.allowed`
    /// when it isn't, which ends the sequence. Cancel to stop waiting.
    public static func states() -> AsyncStream<State> {
        AsyncStream { continuation in
            let task = Task {
                var reportedBlocked = false
                while !Task.isCancelled {
                    if await check() == .allowed {
                        continuation.yield(.allowed)
                        break
                    }
                    if !reportedBlocked {
                        reportedBlocked = true
                        continuation.yield(.blocked)
                    }
                    try? await Task.sleep(for: Tuning.recheckInterval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Waits until access isn't blocked, calling `onBlocked` once if it is.
    /// Returns `false` if cancelled first.
    public static func waitUntilAllowed(onBlocked: @Sendable () async -> Void) async -> Bool {
        for await state in states() {
            switch state {
            case .blocked: await onBlocked()
            case .allowed: return true
            }
        }
        return false
    }

    /// One attempt: a TCP connection to another device on this local network.
    /// Without access it stops at once with "network down" (or waits with
    /// `localNetworkDenied`, Apple TN3179); with access it connects, is
    /// refused or times out. (A UDP socket reports ready either way, and the
    /// router answers either way.)
    public static func check() async -> State {
        guard let own = LocalInterfaces.privateIPv4Addresses().first,
              let target = IPv4Address(neighbor(of: own)) else { return .allowed }
        let connection = NWConnection(host: .ipv4(target), port: Tuning.port, using: .tcp)
        let outcome = Outcome()
        defer { connection.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<State, Never>) in
                outcome.set(continuation)
                connection.stateUpdateHandler = { [weak connection] state in
                    switch state {
                    case .ready:
                        outcome.resolve(.allowed)
                    case let .waiting(error), let .failed(error):
                        let denied = connection?.currentPath?.unsatisfiedReason == .localNetworkDenied
                            || error == .posix(.ENETDOWN)
                        outcome.resolve(denied ? .blocked : .allowed)
                    case .cancelled:
                        outcome.resolve(.allowed)
                    default:
                        break
                    }
                }
                connection.pathUpdateHandler = { path in
                    if path.unsatisfiedReason == .localNetworkDenied { outcome.resolve(.blocked) }
                }
                connection.start(queue: .global(qos: .userInitiated))
                Task {
                    try? await Task.sleep(for: Tuning.checkTimeout)
                    outcome.resolve(.allowed)
                }
            }
        } onCancel: {
            outcome.resolve(.allowed)
        }
    }

    /// An address next to `own` that's unlikely to be the router: the
    /// router is reachable even while access is refused.
    private static func neighbor(of own: UInt32) -> String {
        let host = own & ~Tuning.subnetMask
        let next = Tuning.routerHosts.contains(host + 1) || host + 1 > Tuning.lastHost ? own - 1 : own + 1
        return LocalInterfaces.dotted(next)
    }

    /// Resumes the continuation once, whichever answer comes first.
    private final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<State, Never>?
        private var result: State?

        func set(_ continuation: CheckedContinuation<State, Never>) {
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        func resolve(_ state: State) {
            lock.lock()
            guard result == nil else { lock.unlock(); return }
            result = state
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume(returning: state)
        }
    }
}
