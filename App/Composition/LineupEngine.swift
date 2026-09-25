import Foundation
import RetroGuideKit

/// Runs the CPU-heavy parts of lineup generation off the main actor.
struct LineupEngine: Sendable {
    let curated: [ChannelDefinition]

    init() {
        curated = (try? ChannelCatalog.curated()) ?? []
    }

    func makeIndex(from snapshots: [LibrarySnapshot]) async -> LibraryIndex {
        await Task.detached(priority: .userInitiated) {
            LibraryIndex(snapshots: snapshots)
        }.value
    }

    func makeLineup(index: LibraryIndex, customization: LineupCustomization, grid: ScheduleGrid) async -> [Channel] {
        let builder = LineupBuilder(curated: curated, options: LineupOptions.adapted(to: index, grid: grid))
        return await Task.detached(priority: .userInitiated) {
            builder.build(index: index, customization: customization)
        }.value
    }

    func preview(rule: ChannelRule, in index: LibraryIndex) -> [MediaItem] {
        LineupBuilder(curated: []).preview(rule: rule, in: index)
    }
}
