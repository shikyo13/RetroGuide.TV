import Foundation

/// Downloads every film and series with an IMDb id and a genre, and English
/// labels for the types and genres they use, from a public Wikidata SPARQL
/// endpoint (QLever: fast enough to return the whole set in one query).
struct WikidataFetcher {
    private enum Endpoint {
        static let url = URL(string: "https://qlever.dev/api/wikidata")!
        static let userAgent = "RetroGuideTV-title-classifier/1.0 (zero@zeronexus.net)"
        static let timeout: TimeInterval = 900
    }

    /// Types and genres used by fewer titles than this aren't labeled (and
    /// so aren't mapped): together they cover under 1% of genre tags.
    private static let minimumUses = 10
    private static let entityPrefix = "http://www.wikidata.org/entity/"

    private static let titlesQuery = """
        PREFIX wdt: <http://www.wikidata.org/prop/direct/>
        SELECT ?item ?imdb (SAMPLE(?tmdbMovie) AS ?tmdbMovieID) (SAMPLE(?tmdbShow) AS ?tmdbShowID) (SAMPLE(?tvdb) AS ?tvdbID)
          (GROUP_CONCAT(DISTINCT STR(?type); separator=" ") AS ?types) (GROUP_CONCAT(DISTINCT STR(?genre); separator=" ") AS ?genres)
        WHERE {
          ?item wdt:P345 ?imdb . FILTER(STRSTARTS(?imdb, "tt"))
          ?item wdt:P136 ?genre .
          OPTIONAL { ?item wdt:P31 ?type . }
          OPTIONAL { ?item wdt:P4947 ?tmdbMovie . }
          OPTIONAL { ?item wdt:P4983 ?tmdbShow . }
          OPTIONAL { ?item wdt:P4835 ?tvdb . }
        } GROUP BY ?item ?imdb
        """

    let paths: Paths

    func fetch() async throws {
        try FileManager.default.createDirectory(at: paths.data, withIntermediateDirectories: true)
        print("Fetching titles…")
        let titles = clean(try await query(Self.titlesQuery))
        try titles.write(to: paths.titles, atomically: true, encoding: .utf8)
        let rows = TitleRow.parse(titles)
        print("  \(rows.count) titles")

        var uses: [String: Int] = [:]
        for row in rows {
            for id in row.types + row.genres { uses[id, default: 0] += 1 }
        }
        let labeled = uses.filter { $0.value >= Self.minimumUses }.keys.sorted()
        print("Fetching labels for \(labeled.count) types and genres…")
        let labelsQuery = """
            PREFIX wd: <http://www.wikidata.org/entity/>
            PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
            SELECT ?q ?label WHERE { VALUES ?q { \(labeled.map { "wd:\($0)" }.joined(separator: " ")) }
              ?q rdfs:label ?label . FILTER(LANG(?label) = "en") }
            """
        try clean(try await query(labelsQuery)).write(to: paths.labels, atomically: true, encoding: .utf8)
        print("Done. Next: title-classifier build")
    }

    private func query(_ sparql: String) async throws -> String {
        var request = URLRequest(url: Endpoint.url, timeoutInterval: Endpoint.timeout)
        request.httpMethod = "POST"
        request.setValue(Endpoint.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/tab-separated-values", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "query", value: sparql)]
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }
        return text
    }

    /// Bare ids and values: no entity URLs, brackets, quotes or language tags.
    private func clean(_ tsv: String) -> String {
        tsv.replacingOccurrences(of: Self.entityPrefix, with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "@en", with: "")
    }
}
