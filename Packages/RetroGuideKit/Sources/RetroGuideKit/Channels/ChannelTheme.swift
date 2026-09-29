import Foundation

/// A curated channel template plus the part it plays in lineup generation.
public struct ChannelTheme: Sendable, Hashable {
    public enum Role: String, Codable, Sendable {
        /// A genre titles live on; every title gets exactly one home.
        case home
        /// A cross-cut (decade, holiday, heroes…) where titles may appear again.
        case spotlight
        /// Airs (nearly) everything of a kind: Everything, All Shows, The Movie Channel.
        case catchAll
    }

    /// Broader channel that thin home channels merge into.
    public enum Family: String, Codable, Sendable, CaseIterable {
        case scripted, unscripted, cartoons, anime, movies

        var definition: ChannelDefinition {
            switch self {
            case .scripted: Self.make("scripted", "Prime Time", "PRIME", kinds: [.episode])
            case .unscripted: Self.make("unscripted", "Real TV", "REAL", kinds: [.episode])
            case .cartoons: Self.make("cartoons", "Cartoon Corner", "TOON", kinds: [.episode])
            case .anime: Self.make("anime", "Anime Mix", "ANIM", kinds: [.episode])
            case .movies: Self.make("movies", "Feature Presentation", "FEAT", kinds: [.movie])
            }
        }

        private static func make(_ id: String, _ name: String, _ callSign: String, kinds: Set<MediaKind>) -> ChannelDefinition {
            ChannelDefinition(id: "family.\(id)", number: .zero, name: name, callSign: callSign, rule: ChannelRule(kinds: kinds), ordering: .syndication, source: .curated)
        }
    }

    public let definition: ChannelDefinition
    public let role: Role
    public let family: Family?
}

extension ChannelCatalog {
    private struct ThemeMetadata: Decodable {
        let id: String
        let role: ChannelTheme.Role
        let family: ChannelTheme.Family?
    }

    /// Every curated template with its role and family.
    public static func themes() throws -> [ChannelTheme] {
        let definitions = try curated()
        guard let url = Bundle.module.url(forResource: "curated-channels", withExtension: "json") else {
            throw CatalogError.missingResource("curated-channels")
        }
        let metadata = try JSONDecoder().decode([ThemeMetadata].self, from: Data(contentsOf: url))
        let byID = Dictionary(uniqueKeysWithValues: metadata.map { ($0.id, $0) })
        return definitions.map { definition in
            let info = byID[definition.id]
            return ChannelTheme(definition: definition, role: info?.role ?? .spotlight, family: info?.family)
        }
    }
}
