import Foundation
import TVServices

final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping @Sendable ((any TVTopShelfContent)?) -> Void) {
        guard let snapshot = WhatsOnStore.load() else { completionHandler(nil); return }
        let now = Date.now
        let items = snapshot.channels.compactMap { channel -> TVTopShelfSectionedItem? in
            guard let program = channel.program(at: now),
                  let image = [program.backdropFile, program.stillFile].compactMap({ WhatsOnStore.artworkURL($0) })
                    .first(where: { FileManager.default.fileExists(atPath: $0.path) }),
                  let url = WhatsOnStore.url(forChannel: channel.id) else { return nil }
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
        guard !items.isEmpty else { completionHandler(nil); return }
        let section = TVTopShelfItemCollection(items: items)
        section.title = "On now"
        completionHandler(TVTopShelfSectionedContent(sections: [section]))
    }
}
