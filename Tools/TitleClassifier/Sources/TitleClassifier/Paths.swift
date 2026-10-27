import Foundation

/// Where the tool reads and writes, relative to `Tools/TitleClassifier`.
struct Paths {
    let root: URL

    var data: URL { root.appending(path: "data") }
    var titles: URL { data.appending(path: "titles.tsv") }
    var labels: URL { data.appending(path: "labels.tsv") }
    var overrides: URL { root.appending(path: "wikidata-overrides.json") }
    var output: URL {
        root.appending(path: "../../Packages/RetroGuideKit/Sources/RetroGuideKit/Resources/title-classification.bin").standardizedFileURL
    }
}
