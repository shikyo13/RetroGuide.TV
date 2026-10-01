import Foundation

/// `fetch` downloads titles and labels from Wikidata into `data/`; `build`
/// turns them into the kit's classification table.
enum Command: String {
    case fetch
    case build
}

let arguments = CommandLine.arguments.dropFirst()
guard let command = arguments.first.flatMap(Command.init(rawValue:)) else {
    print("usage: title-classifier fetch | build")
    exit(EXIT_FAILURE)
}
let paths = Paths(root: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
do {
    switch command {
    case .fetch: try await WikidataFetcher(paths: paths).fetch()
    case .build: try ClassificationBuilder(paths: paths).build()
    }
} catch {
    print("error: \(error)")
    exit(EXIT_FAILURE)
}
