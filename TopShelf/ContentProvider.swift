import Foundation
import TVServices

final class ContentProvider: TVTopShelfContentProvider {
    private enum Limits {
        static let channels = 8
    }

    override func loadTopShelfContent(completionHandler: @escaping @Sendable ((any TVTopShelfContent)?) -> Void) {
        Task { @MainActor in
            completionHandler(Self.content())
        }
    }

    @MainActor
    private static func content() -> TVTopShelfSectionedContent? {
        guard let snapshot = WhatsOnStore.load() else { return nil }
        let now = Date.now
        let theme = snapshot.themeID.flatMap(ThemeID.init(rawValue:)) ?? .classicCable
        var images: [URL] = []
        let items = snapshot.channels.prefix(Limits.channels).compactMap { channel -> TVTopShelfSectionedItem? in
            guard let program = channel.program(at: now),
                  let image = TopShelfArtwork.image(for: channel, program: program, theme: theme),
                  let url = WhatsOnStore.url(forChannel: channel.id) else { return nil }
            images.append(image)
            let item = TVTopShelfSectionedItem(identifier: channel.id)
            item.title = "\(channel.number) · \(program.title)"
            item.imageShape = .hdtv
            item.setImageURL(image, for: .screenScale1x)
            item.setImageURL(image, for: .screenScale2x)
            item.playbackProgress = min(max(now.timeIntervalSince(program.start) / program.end.timeIntervalSince(program.start), .zero), 1)
            item.playAction = TVTopShelfAction(url: url)
            item.displayAction = TVTopShelfAction(url: url)
            return item
        }
        TopShelfArtwork.prune(keeping: images)
        guard !items.isEmpty else { return nil }
        let section = TVTopShelfItemCollection(items: items)
        section.title = "On now"
        return TVTopShelfSectionedContent(sections: [section])
    }
}
