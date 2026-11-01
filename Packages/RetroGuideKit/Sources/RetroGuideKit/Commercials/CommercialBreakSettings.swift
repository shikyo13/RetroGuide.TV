import Foundation

public struct CommercialBreakSettings: Codable, Equatable, Sendable {
    public enum Count: Int, Codable, CaseIterable, Sendable {
        case one = 1, two = 2, three = 3
        public var displayName: String { rawValue == 1 ? "1 commercial" : "\(rawValue) commercials" }
    }
    public var isEnabled = false
    public var libraryIDs: Set<String> = []
    public var count: Count = .one
    public init() {}
    private enum CodingKeys: String, CodingKey { case isEnabled, libraryIDs, count }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        libraryIDs = try values.decodeIfPresent(Set<String>.self, forKey: .libraryIDs) ?? []
        count = (try? values.decode(Count.self, forKey: .count)) ?? .one
    }
}
