import Foundation

/// Builds channels that depend on what is in the library: one per library,
/// network and collection, plus marathons for long-running shows.
enum DynamicChannelFactory {
    static func definitions(for facets: LibraryFacets, options: LineupOptions) -> [ChannelDefinition] {
        libraryChannels(facets.libraries)
            + networkChannels(facets.networks, options: options)
            + collectionChannels(facets.collections, options: options)
            + marathonChannels(facets.series, options: options)
    }

    private static func libraryChannels(_ values: [FacetValue]) -> [ChannelDefinition] {
        numbered(values, in: ChannelNumbering.libraries) { value, number in
            ChannelDefinition(
                id: "library.\(value.id)",
                number: number,
                name: value.name,
                rule: ChannelRule(libraryIDs: [value.id]),
                ordering: .blockShuffle,
                source: .library
            )
        }
    }

    private static func networkChannels(_ values: [FacetValue], options: LineupOptions) -> [ChannelDefinition] {
        let eligible = values.filter {
            $0.runtime >= options.minimumChannelRuntime && $0.seriesCount >= options.networkMinimumShows
        }
        return numbered(eligible, in: ChannelNumbering.networks) { value, number in
            ChannelDefinition(
                id: "network.\(TextNormalizer.key(value.id))",
                number: number,
                name: value.name,
                rule: ChannelRule(networks: [value.name]),
                ordering: .blockShuffle,
                source: .network
            )
        }
    }

    private static func collectionChannels(_ values: [FacetValue], options: LineupOptions) -> [ChannelDefinition] {
        let eligible = values.filter { $0.itemCount >= options.collectionMinimumItems }
        return numbered(eligible, in: ChannelNumbering.collections) { value, number in
            ChannelDefinition(
                id: "collection.\(TextNormalizer.key(value.id))",
                number: number,
                name: value.name,
                rule: ChannelRule(collections: [value.name]),
                ordering: .shuffle,
                source: .collection
            )
        }
    }

    private static func marathonChannels(_ values: [FacetValue], options: LineupOptions) -> [ChannelDefinition] {
        let eligible = values
            .filter { $0.itemCount >= options.marathonMinimumEpisodes }
            .sorted { $0.itemCount > $1.itemCount }
            .prefix(options.maximumMarathonChannels)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return numbered(Array(eligible), in: ChannelNumbering.marathons) { value, number in
            ChannelDefinition(
                id: "series.\(value.id)",
                number: number,
                name: "\(value.name) 24/7",
                callSign: CallSign.make(from: value.name),
                rule: ChannelRule(seriesIDs: [value.id]),
                ordering: .marathon,
                source: .series
            )
        }
    }

    /// Assigns consecutive numbers from `range`, dropping values that do not fit.
    private static func numbered(
        _ values: [FacetValue],
        in range: Range<Int>,
        make: (FacetValue, Int) -> ChannelDefinition
    ) -> [ChannelDefinition] {
        zip(values, range).map(make)
    }
}
