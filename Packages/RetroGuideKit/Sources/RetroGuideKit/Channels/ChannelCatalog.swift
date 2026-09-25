import Foundation

/// The bundled, curated channel templates (`Resources/curated-channels.json`).
///
/// Adding a channel is a data change: append an entry to the JSON file with a
/// unique `id` and `number` below ``ChannelNumbering/libraries``.
public enum ChannelCatalog {
    private static let resourceName = "curated-channels"

    public static func curated() throws -> [ChannelDefinition] {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw CatalogError.missingResource(resourceName)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ChannelDefinition].self, from: data)
    }

    public enum CatalogError: Error, Equatable {
        case missingResource(String)
    }
}
