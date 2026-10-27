import Foundation
import Network

/// Reports when the device joins a different network (leaving home Wi-Fi,
/// switching to cellular, coming back), so server addresses can be re-checked
/// before playback has a chance to fail.
@MainActor
final class NetworkChangeMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "\(AppIdentity.bundleIdentifier).network")
    private var lastSignature: String?
    private var isStarted = false

    /// Calls `onChange` on the main actor whenever the network changes (not for
    /// the first report at start-up).
    func start(onChange: @escaping @MainActor () -> Void) {
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            let signature = Self.signature(of: path)
            Task { @MainActor in
                guard let self else { return }
                defer { self.lastSignature = signature }
                guard let previous = self.lastSignature, previous != signature else { return }
                onChange()
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }

    /// What identifies "a network" here: whether it's usable and which interfaces carry it.
    private nonisolated static func signature(of path: NWPath) -> String {
        let interfaces = path.availableInterfaces.map { "\($0.type)-\($0.name)" }.joined(separator: ",")
        return "\(path.status)|\(interfaces)"
    }
}
