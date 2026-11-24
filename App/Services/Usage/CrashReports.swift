#if os(iOS)
import MetricKit
import RetroGuideKit

/// Crash and hang counts from MetricKit (iPhone, iPad and Mac; Apple TV has no
/// MetricKit). Only that one happened, on which day and in which build: never the
/// report itself, its call stacks or anything else in it.
final class CrashReports: NSObject, MXMetricManagerSubscriber, Sendable {
    static let shared = CrashReports()

    /// MetricKit delivers the reports gathered since the last launch, once a day at most.
    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let events = payloads.flatMap(Self.events(in:))
        guard !events.isEmpty else { return }
        Task { @MainActor in
            for event in events { PurchaseAttribution.shared.record(event) }
        }
    }

    private static func events(in payload: MXDiagnosticPayload) -> [UsageEvent] {
        let crashes = (payload.crashDiagnostics ?? []).map {
            UsageEvent(.crashed, detail: $0.metaData.applicationBuildVersion, on: payload.timeStampEnd)
        }
        let hangs = (payload.hangDiagnostics ?? []).map {
            UsageEvent(.hung, detail: $0.metaData.applicationBuildVersion, on: payload.timeStampEnd)
        }
        return crashes + hangs
    }
}
#endif
