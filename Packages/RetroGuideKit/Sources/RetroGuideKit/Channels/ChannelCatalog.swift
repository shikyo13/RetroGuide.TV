import Foundation

/// The bundled, curated channel templates (`Resources/curated-channels.json`).
///
/// Adding a channel is a data change: append an entry to the JSON file with a
/// unique `id` and `number` below ``ChannelNumbering/libraries``, and an entry
/// for its name in `Resources/Channels.xcstrings` keyed by that `id`.
public enum ChannelCatalog {
    private static let resourceName = "curated-channels"
    /// String table with each channel's translated name, keyed by channel id.
    static let namesTable = "Channels"

    /// The curated channels, named in the viewer's language (English when a
    /// name has no translation). Names are display text only: settings refer
    /// to channels by id.
    public static func curated() throws -> [ChannelDefinition] {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw CatalogError.missingResource(resourceName)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ChannelDefinition].self, from: data).map { definition in
            var definition = definition
            definition.name = Bundle.module.localizedString(forKey: definition.id, value: definition.name, table: namesTable)
            return definition
        }
    }

    public enum CatalogError: Error, Equatable {
        case missingResource(String)
    }
}
