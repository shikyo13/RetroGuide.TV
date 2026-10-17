#if os(iOS)
import RetroGuideKit
import UIKit
import WidgetKit

/// Keeps the "What's On" widget current: saves a few channels' programs
/// for the next hours, with artwork for what's on now and next, whenever
/// the channel or the lineup changes, then asks the widget to reload.
@MainActor
final class WhatsOnWidgetWriter {
    private enum Tuning {
        /// Channels the widget rotates through: the one watched last, then the next in the guide.
        static let channels = 8
        static let horizon: TimeInterval = 3 * ScheduleConstants.secondsPerHour
        static let programsPerChannel = 8
        /// Programs per channel with artwork: now and next.
        static let programsWithArtwork = 2
        static let backdropPixels = 640
        static let logoPixels = 400
        static let stillPixels = 320
        static let jpegQuality: CGFloat = 0.7
    }

    private enum Kind: String {
        case backdrop, logo, still
    }

    private var task: Task<Void, Never>?
    /// What was saved last, so an unchanged schedule isn't saved again.
    private var savedKey: String?

    /// Saves `channels` (in rotation order) for the widget.
    func update(channels: [Channel], artworkResolver: ArtworkResolver) {
        let now = Date.now
        let window = DateInterval(start: now, duration: Tuning.horizon)
        let schedules = channels.prefix(Tuning.channels).map { channel in
            (channel, Array(channel.timeline.programs(overlapping: window).prefix(Tuning.programsPerChannel)))
        }.filter { !$0.1.isEmpty }
        guard !schedules.isEmpty else { return }
        let key = schedules.map { "\($0.0.id)|\($0.1.first?.id ?? "")" }.joined(separator: ",")
        guard key != savedKey else { return }
        task?.cancel()
        task = Task { [weak self] in
            var artwork: [String: Data] = [:]
            var saved: [WhatsOnSnapshot.Channel] = []
            for (channelIndex, (channel, programs)) in schedules.enumerated() {
                var entries: [WhatsOnSnapshot.Program] = []
                for (programIndex, program) in programs.enumerated() {
                    var files: [Kind: String] = [:]
                    if programIndex < Tuning.programsWithArtwork {
                        for (kind, data) in await Self.artwork(for: program.item, resolver: artworkResolver) {
                            let name = "\(channelIndex)-\(programIndex)-\(kind.rawValue)"
                            artwork[name] = data
                            files[kind] = name
                        }
                    }
                    entries.append(WhatsOnSnapshot.Program(
                        title: program.item.headline,
                        episode: program.item.subheadline,
                        start: program.start,
                        end: program.slotEnd,
                        backdropFile: files[.backdrop],
                        logoFile: files[.logo],
                        stillFile: files[.still]
                    ))
                }
                saved.append(WhatsOnSnapshot.Channel(id: channel.id, number: channel.number, name: channel.name, callSign: channel.callSign, programs: entries))
            }
            guard !Task.isCancelled else { return }
            let snapshot = WhatsOnSnapshot(channels: saved)
            await Task.detached(priority: .utility) {
                WhatsOnStore.save(snapshot, artwork: artwork)
            }.value
            WidgetCenter.shared.reloadTimelines(ofKind: WhatsOnStore.widgetKind)
            self?.savedKey = key
        }
    }

    /// The program's backdrop and episode still (JPEG) and title logo (PNG, keeping its transparency).
    private static func artwork(for item: MediaItem, resolver: ArtworkResolver) async -> [Kind: Data] {
        async let backdrop = image(item, item.artwork.backdrop, ArtworkSize.backdrop, pixels: Tuning.backdropPixels, resolver: resolver)
        async let logo = image(item, item.artwork.logo, ArtworkSize.logo, pixels: Tuning.logoPixels, resolver: resolver)
        async let still = image(item, item.artwork.thumbnail, ArtworkSize.thumbnail, pixels: Tuning.stillPixels, resolver: resolver)
        var result: [Kind: Data] = [:]
        result[.backdrop] = await backdrop?.jpegData(compressionQuality: Tuning.jpegQuality)
        result[.logo] = await logo?.pngData()
        result[.still] = await still?.jpegData(compressionQuality: Tuning.jpegQuality)
        return result
    }

    private static func image(_ item: MediaItem, _ reference: String?, _ size: ImageSize, pixels: Int, resolver: ArtworkResolver) async -> UIImage? {
        guard let url = resolver.url(serverID: item.serverID, reference: reference, size: size) else { return nil }
        return await ImagePipeline.shared.image(for: url, maxPixelSize: pixels)
    }
}
#endif
