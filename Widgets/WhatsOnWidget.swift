import AppIntents
import SwiftUI
import WidgetKit

@main
struct RetroGuideWidgets: WidgetBundle {
    var body: some Widget {
        WhatsOnWidget()
        AppIconWidget()
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
    var canFlip = false
    /// The app's theme colors, read once per timeline.
    var colors: WidgetStyle.Colors = .classicCable
}

/// One entry every few minutes, each showing the next channel in the
/// rotation (moved on by however many times the viewer flipped it), from
/// the schedule the app saved, without the app running.
struct WhatsOnProvider: TimelineProvider {
    private enum Tuning {
        /// When nothing is saved, or the saved schedule runs out, look again after this.
        static let retry: TimeInterval = 60 * 60
    }

    func placeholder(in context: Context) -> WhatsOnEntry {
        WhatsOnEntry(date: .now, channels: WhatsOnSnapshot.sample.channels, canFlip: true, colors: palette)
    }

    func getSnapshot(in context: Context, completion: @escaping (WhatsOnEntry) -> Void) {
        let snapshot = WhatsOnStore.load() ?? (context.isPreview ? .sample : WhatsOnSnapshot(channels: []))
        completion(entry(at: .now, snapshot, family: context.family, offset: WhatsOnStore.offset, colors: palette))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WhatsOnEntry>) -> Void) {
        let now = Date.now
        guard let snapshot = WhatsOnStore.load(), let coveredUntil = snapshot.coveredUntil, coveredUntil > now else {
            completion(Timeline(entries: [WhatsOnEntry(date: now, channels: [], colors: palette)], policy: .after(now.addingTimeInterval(Tuning.retry))))
            return
        }
        let end = min(coveredUntil, now.addingTimeInterval(WidgetTimeline.Tuning.horizon))
        let offset = WhatsOnStore.offset
        let colors = palette
        let dates = WidgetTimeline.dates(from: now, until: end, in: snapshot, offset: offset, visibleChannels: channelLimit(context.family))
        completion(Timeline(entries: dates.map { entry(at: $0, snapshot, family: context.family, offset: offset, colors: colors) }, policy: .after(end)))
    }

    private var palette: WidgetStyle.Colors {
        WhatsOnStore.palette.map(WidgetStyle.Colors.init) ?? .classicCable
    }

    private func channelLimit(_ family: WidgetFamily) -> Int {
        family == .systemLarge ? WidgetStyle.Size.otherChannels + 1 : 1
    }

    private func entry(at date: Date, _ snapshot: WhatsOnSnapshot, family: WidgetFamily, offset: Int, colors: WidgetStyle.Colors) -> WhatsOnEntry {
        let channels = WidgetTimeline.channels(at: date, in: snapshot, offset: offset, limit: channelLimit(family))
        let canFlip = snapshot.channels.filter { $0.program(at: date) != nil }.count > 1
        return WhatsOnEntry(date: date, channels: channels, canFlip: canFlip, colors: colors)
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
