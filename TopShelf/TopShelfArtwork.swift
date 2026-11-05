import CryptoKit
import ImageIO
import SwiftUI
import UIKit

/// Draws only the current cards, reusing unchanged images without retaining decoded artwork.
@MainActor
enum TopShelfArtwork {
    private enum Limits {
        static let renderingVersion = 2
        static let renderScale: CGFloat = 1.5
        static let sourcePixels = 1260
        static let jpegQuality: CGFloat = 0.9
        static let cachedCards = 16
    }

    private struct Identity: Encodable {
        let version: Int
        let channelID: String
        let number: Int
        let name: String
        let callSign: String
        let title: String
        let episode: String?
        let theme: String
        let source: String?
        let sourceSize: Int?
        let sourceModified: Date?
    }

    static func image(for channel: WhatsOnSnapshot.Channel, program: WhatsOnSnapshot.Program,
                      theme: ThemeID, in directory: URL? = WhatsOnStore.container) -> URL? {
        guard let directory else { return nil }
        return autoreleasepool {
            let source = [program.backdropFile, program.stillFile]
                .compactMap { WhatsOnStore.artworkURL($0, in: directory) }
                .first { FileManager.default.fileExists(atPath: $0.path) }
            let attributes = try? source?.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let identity = Identity(
                version: Limits.renderingVersion, channelID: channel.id, number: channel.number,
                name: channel.name, callSign: channel.callSign, title: program.title, episode: program.episode,
                theme: theme.rawValue, source: source?.lastPathComponent,
                sourceSize: attributes?.fileSize, sourceModified: attributes?.contentModificationDate
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            guard let data = try? encoder.encode(identity) else { return source }
            let name = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + ".jpg"
            let folder = directory.appending(path: WhatsOnStore.topShelfArtworkFolder)
            let destination = folder.appending(path: name)
            if let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > .zero {
                return destination
            }
            let view = TopShelfCard(channel: channel, program: program, artwork: source.flatMap(thumbnail))
                .environment(\.theme, ThemeCatalog.theme(for: theme))
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = Limits.renderScale
            renderer.isOpaque = true
            renderer.proposedSize = ProposedViewSize(width: TopShelfCard.Layout.width, height: TopShelfCard.Layout.height)
            guard let jpeg = render(renderer) else { return source }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try jpeg.write(to: destination, options: .atomic)
                return destination
            } catch {
                return source
            }
        }
    }

    /// An extension may render while inactive. Draw into an explicit bitmap context
    /// instead of using the image property, which depends on the display's render state.
    private static func render<Content: View>(_ renderer: ImageRenderer<Content>) -> Data? {
        var output: Data?
        renderer.render(rasterizationScale: Limits.renderScale) { size, draw in
            guard let context = CGContext(
                data: nil, width: Int(ceil(size.width * Limits.renderScale)),
                height: Int(ceil(size.height * Limits.renderScale)), bitsPerComponent: 8,
                bytesPerRow: .zero, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.scaleBy(x: Limits.renderScale, y: Limits.renderScale)
            draw(context)
            if let image = context.makeImage() {
                output = UIImage(cgImage: image).jpegData(compressionQuality: Limits.jpegQuality)
            }
        }
        return output
    }

    /// Preserve the visible cards and the most recent previous cards, at most two shelves.
    static func prune(keeping images: [URL], in directory: URL? = WhatsOnStore.container) {
        guard let folder = directory?.appending(path: WhatsOnStore.topShelfArtworkFolder),
              let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey]
              ) else { return }
        let current = Set(images.map(\.lastPathComponent))
        let previous = files.filter { !current.contains($0.lastPathComponent) }.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs > rhs
        }
        for file in previous.dropFirst(max(.zero, Limits.cachedCards - current.count)) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func thumbnail(_ url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, .zero, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Limits.sourcePixels,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
