import Foundation

/// Shared, bounded catalog. Selection depends on channel and program identity,
/// so loading order, retries and schedule rebuilds cannot change an airing.
public struct CommercialCatalog: Sendable, Hashable {
    public static let empty = CommercialCatalog(items: [], count: .one)
    private let items: [MediaItem]
    private let count: CommercialBreakSettings.Count

    public init(items: [MediaItem], count: CommercialBreakSettings.Count) {
        var seen: Set<String> = []
        self.items = Array(items.filter(CommercialBreakPlan.eligible).sorted { $0.id < $1.id }
            .filter { seen.insert($0.id).inserted }.prefix(CommercialBreakPlan.Limits.maximumCatalogItems))
        self.count = count
    }
    public func selection(channelID: String, program: MediaItem) -> [MediaItem] {
        guard !items.isEmpty else { return [] }
        let offset = Int(StableHash.fnv1a("\(channelID)/\(program.id)") % UInt64(items.count))
        return (0..<min(count.rawValue, items.count)).map { items[(offset + $0) % items.count] }
    }
    public func duration(channelID: String, program: MediaItem) -> TimeInterval {
        selection(channelID: channelID, program: program).reduce(.zero) { $0 + $1.duration }
    }
}
