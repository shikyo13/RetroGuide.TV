import SwiftUI
import WidgetKit

struct AppIconWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AppIconWidget", provider: AppIconProvider()) { entry in
            TVGlyph()
                .brandFill(entry.colors.accent)
                .padding(WidgetStyle.Spacing.lg)
                .containerBackground(entry.colors.background, for: .widget)
                .widgetURL(URL(string: "retroguide://open"))
                .accessibilityLabel("Open RetroGuide.TV")
        }
        .configurationDisplayName("App Icon")
        .description("A larger RetroGuide icon. Choose What's On for live listings and channel controls.")
        .supportedFamilies([.systemSmall])
    }
}

struct AppIconProvider: TimelineProvider {
    func placeholder(in context: Context) -> WhatsOnEntry { WhatsOnEntry(date: .now, channels: []) }
    func getSnapshot(in context: Context, completion: @escaping (WhatsOnEntry) -> Void) { completion(placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WhatsOnEntry>) -> Void) {
        completion(Timeline(entries: [placeholder(in: context)], policy: .never))
    }
}
