import RetroGuideKit
import UIKit
#if os(iOS)
import WidgetKit
#else
import TVServices
#endif

/// Keeps the "What's On" widget current: saves a few channels' programs
/// for the next hours, with artwork for the whole saved guide, whenever
/// the channel or the lineup changes, then asks the widget to reload.
@MainActor
final class WhatsOnWidgetWriter {
    private enum Tuning {
        /// Channels the widget rotates through: the one watched last, then the next in the guide.
        static let channels = 8
        static let horizon: TimeInterval = 12 * ScheduleConstants.secondsPerHour
        static let programsPerChannel = 64
        static let artworkBatchSize = 3
        static let artworkRetry: TimeInterval = 5 * 60
        static let backdropPixels = 640
        static let logoPixels = 400
        static let stillPixels = 320
        static let jpegQuality: CGFloat = 0.7
    }

    private var task: Task<Void, Never>?
    private var generation = 0
    private let files = SnapshotFileWriter()
    /// What was saved last, so an unchanged schedule isn't saved again.
    private var savedKey: String?
    private var retryArtworkAfter = Date.distantFuture
    private var pendingKey: String?
    private var needsHomeScreenReload = false

    /// Give changes made while browsing the app one final reload as the widget becomes visible.
    func reloadForHomeScreen() {
        guard needsHomeScreenReload else { return }
        needsHomeScreenReload = false
        Self.reload()
    }

    /// Saves `channels` (in rotation order) for the widget.
    func update(channels: [Channel], artworkResolver: ArtworkResolver, pinned: Bool = false) {
        guard WhatsOnStore.container != nil else { return }
        let now = Date.now
        let window = DateInterval(start: now, duration: Tuning.horizon)
        let schedules = channels.prefix(Tuning.channels).map { channel in
            (channel, Array(channel.timeline.programs(overlapping: window).prefix(Tuning.programsPerChannel)))
        }.filter { !$0.1.isEmpty }
        guard !schedules.isEmpty else {
            clear()
            return
        }
        let key = String(pinned) + schedules.map { channel, programs in
            channel.id + "|" + programs.map { "\($0.id):\($0.slotEnd.timeIntervalSince1970)" }.joined(separator: ";")
        }.joined(separator: ",")
        guard key != pendingKey, key != savedKey || now >= retryArtworkAfter else { return }
        needsHomeScreenReload = true
        task?.cancel()
        pendingKey = key
        generation += 1
        let generation = generation
        let files = files
        task = Task { [weak self] in
            let activity = WidgetArtworkActivity { [weak self] in
                guard self?.generation == generation else { return }
                self?.task?.cancel()
            }
            defer {
                activity.end()
                if self?.pendingKey == key { self?.pendingKey = nil }
            }
            // References cover the entire saved guide from the first publication. Existing
            // files stay visible while new artwork arrives, including after cancellation.
            let snapshot = WhatsOnSnapshot(channels: schedules.map { channel, programs in
                WhatsOnSnapshot.Channel(
                    id: channel.id, number: channel.number, name: channel.name,
                    callSign: channel.callSign, programs: programs.map { Self.entry($0) }
                )
            }, pinned: pinned, updatedAt: now)
            guard !Task.isCancelled else { return }
            let published = await files.save(snapshot, artwork: [:], generation: generation)
            guard published, !Task.isCancelled else { return }
            Self.reload()

            // Current programs on every channel come first; then prefetch the rest in
            // airing order. Shared show backdrops/logos are downloaded just once.
            let current = schedules.compactMap { $0.1.first }
            let upcoming = schedules.flatMap { $0.1.dropFirst() }.sorted { $0.start < $1.start }
            var seen = Set<WidgetArtworkPlan.Asset>()
            var complete = true
            for programs in [current, upcoming] {
                let assets = programs.flatMap { WidgetArtworkPlan($0.item).assets }
                    .filter { seen.insert($0).inserted }
                let missing = await files.missingArtwork(assets.map(\.file))
                let requests = assets.filter { missing.contains($0.file) }
                for start in stride(from: 0, to: requests.count, by: Tuning.artworkBatchSize) {
                    guard !Task.isCancelled else { return }
                    let batch = Array(requests[start..<min(start + Tuning.artworkBatchSize, requests.count)])
                    let artwork = await withTaskGroup(of: (String, Data?).self) { group in
                        for asset in batch {
                            group.addTask { (asset.file, await Self.image(asset, resolver: artworkResolver)) }
                        }
                        var downloaded: [String: Data] = [:]
                        for await (file, data) in group { downloaded[file] = data }
                        return downloaded
                    }
                    guard !Task.isCancelled else { return }
                    let stored = await files.saveArtwork(artwork, generation: generation)
                    complete = complete && stored && artwork.count == batch.count
                }
                guard !Task.isCancelled else { return }
                Self.reload()
                self?.needsHomeScreenReload = true
            }
            self?.savedKey = key
            self?.retryArtworkAfter = complete ? .distantFuture : Date.now.addingTimeInterval(Tuning.artworkRetry)
        }
    }

    func clear() {
        needsHomeScreenReload = true
        task?.cancel()
        pendingKey = nil
        savedKey = nil
        generation += 1
        let generation = generation
        let files = files
        task = Task {
            await files.clear(generation: generation)
            guard !Task.isCancelled else { return }
            Self.reload()
        }
    }

    func clearAndWait() async {
        clear()
        await task?.value
    }

    private static func reload() {
        #if os(iOS)
        WidgetCenter.shared.reloadTimelines(ofKind: WhatsOnStore.widgetKind)
        #else
        TVTopShelfContentProvider.topShelfContentDidChange()
        #endif
    }

    private static func entry(_ program: ScheduledProgram) -> WhatsOnSnapshot.Program {
        let artwork = WidgetArtworkPlan(program.item)
        return WhatsOnSnapshot.Program(
            title: program.item.headline, episode: program.item.subheadline,
            start: program.start, end: program.slotEnd,
            backdropFile: artwork.file(for: .backdrop), logoFile: artwork.file(for: .logo), stillFile: artwork.file(for: .still)
        )
    }

    private static func image(_ asset: WidgetArtworkPlan.Asset, resolver: ArtworkResolver) async -> Data? {
        let size: ImageSize
        let pixels: Int
        switch asset.kind {
        case .backdrop: (size, pixels) = (ArtworkSize.backdrop, Tuning.backdropPixels)
        case .logo: (size, pixels) = (ArtworkSize.logo, Tuning.logoPixels)
        case .still: (size, pixels) = (ArtworkSize.thumbnail, Tuning.stillPixels)
        }
        guard let url = resolver.url(serverID: asset.serverID, reference: asset.reference, size: size),
              let image = await ImagePipeline.shared.image(for: url, maxPixelSize: pixels),
              !Task.isCancelled else { return nil }
        return asset.kind == .logo ? image.pngData() : image.jpegData(compressionQuality: Tuning.jpegQuality)
    }
}
