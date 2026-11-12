import Foundation

/// Usage events waiting to be sent, and the recent ones already sent, so each
/// event goes once a day at most. Bounded and durable; losing it costs only
/// measurement.
public actor UsageLedger {
    public enum Limits {
        /// Events kept while offline; the oldest go first.
        public static let pending = 200
        /// Events sent in one request.
        public static let batch = 50
        /// Days a sent event is remembered so it isn't sent again.
        static let rememberedDays = 3
        static let fileBytes = 256 * 1024
    }

    /// Thrown by a delivery the service refused for good (a malformed or
    /// unknown request): that batch is dropped rather than retried forever.
    public struct Rejected: Error {
        public init() {}
    }

    private struct State: Codable {
        var pending: [UsageEvent] = []
        var sent: Set<UsageEvent> = []
    }

    private let file: URL
    private var state: State
    private var draining = false

    public init(file: URL) {
        self.file = file
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size <= Limits.fileBytes,
           let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        } else {
            state = State()
        }
    }

    /// Queues `event` unless it is already queued or was sent.
    /// Returns whether it was queued.
    @discardableResult
    public func record(_ event: UsageEvent) -> Bool {
        guard !state.sent.contains(event), !state.pending.contains(event) else { return false }
        state.pending.append(event)
        while state.pending.count > Limits.pending {
            // Daily marks go first: the steps of someone's first day matter most.
            state.pending.remove(at: state.pending.firstIndex { $0.name == .active } ?? state.pending.startIndex)
        }
        persist()
        return true
    }

    public var pendingCount: Int { state.pending.count }

    /// Sends everything queued, a batch at a time. Returns false on failure;
    /// the failed batch stays queued.
    @discardableResult
    public func drain(now: Date = .now, deliver: @Sendable ([UsageEvent]) async throws -> Void) async -> Bool {
        guard !draining else { return true }
        draining = true
        defer { draining = false }
        while !state.pending.isEmpty {
            let batch = Array(state.pending.prefix(Limits.batch))
            var accepted = true
            do { try await deliver(batch) } catch is Rejected { accepted = false } catch { return false }
            state.pending.removeAll(where: batch.contains)
            if accepted { state.sent.formUnion(batch) }
            forgetOldSent(now: now)
            persist()
        }
        return true
    }

    private func forgetOldSent(now: Date) {
        let oldest = UsageEvent.day(of: now.addingTimeInterval(-Double(Limits.rememberedDays) * 86_400))
        state.sent = state.sent.filter { $0.day >= oldest }
    }

    private func persist() {
        do {
            let directory = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(state)
            try data.write(to: file, options: .atomic)
        } catch {
            // Measurement only: nothing depends on it.
        }
    }
}
