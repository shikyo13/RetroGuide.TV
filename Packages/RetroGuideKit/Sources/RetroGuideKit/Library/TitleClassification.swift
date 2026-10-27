import Foundation

/// Genre categories for well-known titles, from our own classification of
/// open data (built by `Tools/TitleClassifier` into
/// `Resources/title-classification.bin`), looked up by public database id.
///
/// Servers' genre tags are loose ("Mystery" on a fishing documentary, on
/// Harry Potter); this says what a title is. It's the same table on every
/// device, so lineups built from it still match everywhere.
///
/// The file is memory-mapped and searched in place: nothing is decoded up
/// front, and a lookup is a binary search.
public struct TitleClassification: Sendable {
    /// One table per kind of id, each sorted by id.
    public enum Section: Int, CaseIterable, Sendable {
        case imdb, tmdbMovie, tmdbShow, tvdb
    }

    /// Bit positions of categories in a stored mask. Append only: a
    /// category's bit never changes, so older tables stay readable.
    public static let categoryBits: [GenreCategory] = [
        .action, .adventure, .animation, .anime, .biography, .children, .comedy, .crime,
        .documentary, .drama, .family, .fantasy, .food, .gameShow, .history, .horror,
        .martialArts, .music, .musical, .mystery, .news, .reality, .romance, .sciFi,
        .soap, .sport, .talk, .thriller, .travel, .war, .western,
    ]

    private enum Format {
        static let magic: [UInt8] = Array("RGTC".utf8)
        static let version: UInt16 = 1
        /// Magic, version and section count, then one entry count per section.
        static let fixedHeaderSize = magic.count + MemoryLayout<UInt16>.size * 2
        static let countSize = MemoryLayout<UInt32>.size
        /// An entry is an id and a category mask.
        static let entrySize = MemoryLayout<UInt32>.size * 2
    }

    public enum TableError: Error {
        case missingResource(String)
        case unreadable
    }

    private static let resourceName = "title-classification"
    public static let shared = (try? TitleClassification.bundled()) ?? TitleClassification(data: Data(), sections: [:])

    private let data: Data
    /// Byte offset of each section's first entry, and its entry count.
    private let sections: [Section: (offset: Int, count: Int)]

    private init(data: Data, sections: [Section: (offset: Int, count: Int)]) {
        self.data = data
        self.sections = sections
    }

    static func bundled() throws -> TitleClassification {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "bin") else {
            throw TableError.missingResource(resourceName)
        }
        return try TitleClassification(contentsOf: url)
    }

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    public init(data: Data) throws {
        guard data.count >= Format.fixedHeaderSize, Array(data.prefix(Format.magic.count)) == Format.magic,
              Self.read(UInt16.self, in: data, at: Format.magic.count) == Format.version
        else { throw TableError.unreadable }
        let sectionCount = Int(Self.read(UInt16.self, in: data, at: Format.magic.count + MemoryLayout<UInt16>.size))
        var offset = Format.fixedHeaderSize + sectionCount * Format.countSize
        var sections: [Section: (offset: Int, count: Int)] = [:]
        for index in 0..<sectionCount {
            let count = Int(Self.read(UInt32.self, in: data, at: Format.fixedHeaderSize + index * Format.countSize))
            if let section = Section(rawValue: index) {
                sections[section] = (offset, count)
            }
            offset += count * Format.entrySize
        }
        guard offset <= data.count else { throw TableError.unreadable }
        self.init(data: data, sections: sections)
    }

    /// Whether the table has any titles (it's empty when the resource is missing).
    public var isEmpty: Bool {
        sections.values.allSatisfy { $0.count == .zero }
    }

    /// The title's categories, trying its IMDb id, then TMDB, then TVDB; `nil`
    /// when the table doesn't know it.
    public func categories(for ids: TitleIDs, kind: MediaKind) -> Set<GenreCategory>? {
        let tmdbSection: Section = kind == .movie ? .tmdbMovie : .tmdbShow
        let attempts: [(Section, UInt32?)] = [(.imdb, ids.imdb), (tmdbSection, ids.tmdb), (.tvdb, kind == .movie ? nil : ids.tvdb)]
        for (section, id) in attempts {
            if let id, let mask = mask(for: id, in: section) {
                return Self.categories(in: mask)
            }
        }
        return nil
    }

    private func mask(for id: UInt32, in section: Section) -> UInt32? {
        guard let (start, count) = sections[section] else { return nil }
        return data.withUnsafeBytes { bytes in
            var low = 0
            var high = count - 1
            while low <= high {
                let middle = (low + high) / 2
                let entry = start + middle * Format.entrySize
                let found = UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: entry, as: UInt32.self))
                if found == id {
                    return UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: entry + MemoryLayout<UInt32>.size, as: UInt32.self))
                }
                if found < id {
                    low = middle + 1
                } else {
                    high = middle - 1
                }
            }
            return nil
        }
    }

    // MARK: - Encoding (for the builder)

    /// The table file for `entries`: per section, ids with their categories.
    /// Titles without categories are left out.
    public static func encode(_ entries: [Section: [UInt32: Set<GenreCategory>]]) -> Data {
        var data = Data(Format.magic)
        append(Format.version, to: &data)
        append(UInt16(Section.allCases.count), to: &data)
        let sorted = Section.allCases.map { section in
            (entries[section] ?? [:]).compactMap { id, categories in
                let mask = Self.mask(for: categories)
                return mask == .zero ? nil : (id, mask)
            }
            .sorted { $0.0 < $1.0 }
        }
        sorted.forEach { append(UInt32($0.count), to: &data) }
        for section in sorted {
            for (id, mask) in section {
                append(id, to: &data)
                append(mask, to: &data)
            }
        }
        return data
    }

    static func mask(for categories: Set<GenreCategory>) -> UInt32 {
        categories.reduce(UInt32.zero) { mask, category in
            guard let bit = categoryBits.firstIndex(of: category) else { return mask }
            return mask | (1 << UInt32(bit))
        }
    }

    static func categories(in mask: UInt32) -> Set<GenreCategory> {
        Set(categoryBits.indices.filter { mask & (1 << UInt32($0)) != .zero }.map { categoryBits[$0] })
    }

    // MARK: - Little-endian access

    private static func read<Value: FixedWidthInteger>(_: Value.Type, in data: Data, at offset: Int) -> Value {
        data.withUnsafeBytes { Value(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: Value.self)) }
    }

    private static func append<Value: FixedWidthInteger>(_ value: Value, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
