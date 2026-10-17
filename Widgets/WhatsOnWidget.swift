import AppIntents
import SwiftUI
import WidgetKit

@main
struct RetroGuideWidgets: WidgetBundle {
    var body: some Widget {
        WhatsOnWidget()
    }
}

/// What's on now, like the guide's preview: the show's backdrop and title
/// logo, the episode, its times and the channel. It rotates through the
/// channel watched last and the ones after it, sliding to the next every
/// few minutes; the arrows flip channels, and a tap opens the one shown.
struct WhatsOnWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WhatsOnStore.widgetKind, provider: WhatsOnProvider()) { entry in
            WhatsOnView(entry: entry)
                .containerBackground(entry.colors.background, for: .widget)
        }
        .configurationDisplayName("What's On")
        .description("What's on your channels right now.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct WhatsOnEntry: TimelineEntry {
    let date: Date
    /// The channel shown, and the rest of the rotation after it (for the large size).
    let channels: [WhatsOnSnapshot.Channel]
    /// The app's theme colors.
    var colors = WhatsOnStore.palette.map(WidgetStyle.Colors.init) ?? .classicCable
}

/// One entry every few minutes, each showing the next channel in the
/// rotation (moved on by however many times the viewer flipped it), from
/// the schedule the app saved, without the app running.
struct WhatsOnProvider: TimelineProvider {
    private enum Tuning {
        static let rotation: TimeInterval = 3 * 60
        /// When nothing is saved, or the saved schedule runs out, look again after this.
        static let retry: TimeInterval = 60 * 60
    }

    func placeholder(in context: Context) -> WhatsOnEntry {
        WhatsOnEntry(date: .now, channels: WhatsOnSnapshot.sample.channels)
    }

    func getSnapshot(in context: Context, completion: @escaping (WhatsOnEntry) -> Void) {
        let snapshot = WhatsOnStore.load() ?? .sample
        completion(entry(at: .now, snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WhatsOnEntry>) -> Void) {
        let now = Date.now
        guard let snapshot = WhatsOnStore.load(), let end = snapshot.coveredUntil, end > now else {
            completion(Timeline(entries: [WhatsOnEntry(date: now, channels: [])], policy: .after(now.addingTimeInterval(Tuning.retry))))
            return
        }
        let firstSlot = (now.timeIntervalSince1970 / Tuning.rotation).rounded(.down) + 1
        var dates = [now]
        var slot = firstSlot
        while case let date = Date(timeIntervalSince1970: slot * Tuning.rotation), date < end {
            dates.append(date)
            slot += 1
        }
        completion(Timeline(entries: dates.map { entry(at: $0, snapshot) }, policy: .after(end)))
    }

    /// The rotation at `date`: which channel's turn it is, then the others in order.
    private func entry(at date: Date, _ snapshot: WhatsOnSnapshot) -> WhatsOnEntry {
        let live = snapshot.channels.filter { $0.program(at: date) != nil }
        guard !live.isEmpty else { return WhatsOnEntry(date: date, channels: []) }
        let turn = Int((date.timeIntervalSince1970 / Tuning.rotation).rounded(.down)) + WhatsOnStore.offset
        let start = ((turn % live.count) + live.count) % live.count
        return WhatsOnEntry(date: date, channels: Array(live[start...] + live[..<start]))
    }
}

/// The widget's arrows: show the next or previous channel in the rotation.
struct FlipChannelIntent: AppIntent {
    static let title: LocalizedStringResource = "Flip Channel"
    static let isDiscoverable = false

    @Parameter(title: "Step")
    var step: Int

    init() {
        step = 1
    }

    init(step: Int) {
        self.step = step
    }

    func perform() async throws -> some IntentResult {
        WhatsOnStore.flip(by: step)
        return .result()
    }
}

extension WhatsOnSnapshot {
    private enum Sample {
        static let elapsed: TimeInterval = 10 * 60
        static let length: TimeInterval = 30 * 60
    }

    /// Shown in the widget gallery before anything has been watched.
    static let sample: WhatsOnSnapshot = {
        let start = Date.now.addingTimeInterval(-Sample.elapsed)
        let shows = [(3, "ALL", "Everything", "Classic Sitcom", "S2 E5 · The Big Day"), (5, "TOON", "Cartoons", "Saturday Cartoons", "S1 E3 · Rocket Race")]
        return WhatsOnSnapshot(channels: shows.map { show in
            Channel(id: show.1, number: show.0, name: show.2, callSign: show.1, programs: [
                Program(title: show.3, episode: show.4, start: start, end: start.addingTimeInterval(Sample.length), backdropFile: nil, logoFile: nil, stillFile: nil),
            ])
        })
    }()
}
