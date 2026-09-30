import Foundation

/// How far a viewer's audio or subtitle choice reaches.
public enum TrackScope: String, Codable, Sendable, CaseIterable, Hashable {
    case episode
    case season
    case show
    case library

    /// Most specific first: the order choices are looked up in.
    static let mostSpecificFirst: [TrackScope] = [.episode, .season, .show, .library]
}

/// A remembered audio choice: a language, and the track's name, to tell apart
/// several in one language (the main track and a commentary).
public struct AudioRule: Codable, Sendable, Hashable {
    public let language: String?
    public let title: String

    public init(_ option: TrackOption) {
        language = option.language
        title = option.title
    }

    init(language: String?, title: String) {
        self.language = language
        self.title = title
    }

    /// The track on another item that best matches this choice.
    func pick(from options: [TrackOption]) -> TrackOption? {
        TrackMatcher.best(in: options, language: language, title: title, isForced: nil)
    }
}

/// A remembered subtitle choice: off, or a language and kind of track.
public enum SubtitleRule: Codable, Sendable, Hashable {
    case off
    case track(language: String?, isForced: Bool, title: String)

    /// `nil` means subtitles off.
    public init(_ option: TrackOption?) {
        guard let option else {
            self = .off
            return
        }
        self = .track(language: option.language, isForced: option.isForced, title: option.title)
    }

    func choice(from options: [TrackOption]) -> SubtitleChoice {
        guard case let .track(language, isForced, title) = self,
              let match = TrackMatcher.best(in: options, language: language, title: title, isForced: isForced)
        else { return .none }
        return match.subtitleChoice
    }
}

/// The viewer's audio and subtitle choices, each remembered at its own scope
/// (like PASTA): one episode, a season, a whole show or a whole library. The
/// most specific choice covering an item wins; audio and subtitles are looked
/// up separately.
public struct TrackRules: Codable, Sendable, Hashable {
    private var audio: [String: AudioRule]
    private var subtitles: [String: SubtitleRule]

    public init() {
        audio = [:]
        subtitles = [:]
    }

    public var isEmpty: Bool {
        audio.isEmpty && subtitles.isEmpty
    }

    // MARK: - Looking up

    /// The tracks to play for `item`: its audio and subtitle choices, or the
    /// server's (`tracks.selection`) where it has none.
    public func selection(for item: MediaItem, tracks: ItemTracks) -> TrackSelection {
        let audioIndex = audioRule(for: item).flatMap { $0.rule.pick(from: tracks.audio)?.streamIndex }
        let subtitle = subtitleRule(for: item).map { $0.rule.choice(from: tracks.subtitles) }
        return TrackSelection(
            audioStreamIndex: audioIndex ?? tracks.selection.audioStreamIndex,
            subtitle: subtitle ?? tracks.selection.subtitle
        )
    }

    public func audioRule(for item: MediaItem) -> (rule: AudioRule, scope: TrackScope)? {
        Self.mostSpecific(in: audio, for: item)
    }

    public func subtitleRule(for item: MediaItem) -> (rule: SubtitleRule, scope: TrackScope)? {
        Self.mostSpecific(in: subtitles, for: item)
    }

    // MARK: - Choosing

    /// Remembers `rule` for everything `scope` covers around `item`, replacing
    /// narrower choices inside it (choosing for a show overrides its episodes).
    public mutating func setAudio(_ rule: AudioRule, scope: TrackScope, for item: MediaItem) {
        guard let key = Self.key(scope, for: item) else { return }
        Self.removeNarrower(than: scope, around: item, in: &audio)
        audio[key] = rule
    }

    public mutating func setSubtitles(_ rule: SubtitleRule, scope: TrackScope, for item: MediaItem) {
        guard let key = Self.key(scope, for: item) else { return }
        Self.removeNarrower(than: scope, around: item, in: &subtitles)
        subtitles[key] = rule
    }

    /// Forgets the episode, season and show choices covering `item` (a library
    /// choice stays: it's the default for everything else too).
    public mutating func reset(for item: MediaItem) {
        resetAudio(for: item)
        resetSubtitles(for: item)
    }

    public mutating func resetAudio(for item: MediaItem) {
        Self.removeShowChoices(around: item, in: &audio)
    }

    public mutating func resetSubtitles(for item: MediaItem) {
        Self.removeShowChoices(around: item, in: &subtitles)
    }

    private static func removeShowChoices<Rule>(around item: MediaItem, in rules: inout [String: Rule]) {
        if let key = key(.show, for: item) {
            rules[key] = nil
        }
        removeNarrower(than: .show, around: item, in: &rules)
    }

    // MARK: - Keys

    /// Whether `scope` means anything for `item` (movies have no seasons).
    public static func applies(_ scope: TrackScope, to item: MediaItem) -> Bool {
        key(scope, for: item) != nil
    }

    /// Items `scope` reaches from `item` among `items`.
    public static func items(in scope: TrackScope, around item: MediaItem, among items: [MediaItem]) -> [MediaItem] {
        guard let key = key(scope, for: item) else { return [] }
        return items.filter { self.key(scope, for: $0) == key }
    }

    /// Episode keys carry the show and season, and season keys the show, so a
    /// broader choice can find the narrower ones it replaces.
    static func key(_ scope: TrackScope, for item: MediaItem) -> String? {
        switch scope {
        case .episode:
            "\(scope.rawValue):\(showPrefix(for: item))\(seasonPart(for: item))/\(item.id)"
        case .season:
            item.series?.seasonNumber.map { "\(scope.rawValue):\(showPrefix(for: item))#\($0)" }
        case .show:
            "\(scope.rawValue):\(item.showID)"
        case .library:
            "\(scope.rawValue):\(item.libraryID)"
        }
    }

    private static func showPrefix(for item: MediaItem) -> String {
        item.showID
    }

    private static func seasonPart(for item: MediaItem) -> String {
        item.series?.seasonNumber.map { "#\($0)" } ?? ""
    }

    private static func mostSpecific<Rule>(in rules: [String: Rule], for item: MediaItem) -> (rule: Rule, scope: TrackScope)? {
        for scope in TrackScope.mostSpecificFirst {
            if let key = key(scope, for: item), let rule = rules[key] {
                return (rule, scope)
            }
        }
        return nil
    }

    private static func removeNarrower<Rule>(than scope: TrackScope, around item: MediaItem, in rules: inout [String: Rule]) {
        let prefixes: [String]
        switch scope {
        case .episode, .library:
            // Nothing is narrower than an episode; a library choice is only a default.
            return
        case .season:
            guard let season = key(.season, for: item) else { return }
            prefixes = [TrackScope.episode.rawValue + ":" + season.dropFirst(TrackScope.season.rawValue.count + 1) + "/"]
        case .show:
            let show = showPrefix(for: item)
            prefixes = ["\(TrackScope.episode.rawValue):\(show)#", "\(TrackScope.episode.rawValue):\(show)/", "\(TrackScope.season.rawValue):\(show)#"]
        }
        rules = rules.filter { key, _ in !prefixes.contains { key.hasPrefix($0) } }
    }
}

/// Finds the track on another episode that matches a remembered one: same
/// language, then the words that tell tracks apart ("Dialogue", "Signs",
/// "Commentary", "SDH"…), so a commentary never wins over the main track and
/// a signs-only track never over the full dialogue.
enum TrackMatcher {
    private static let distinguishingWords: Set<String> = [
        "commentary", "signs", "songs", "forced", "sdh", "cc", "dialogue", "dialog", "full", "karaoke", "director", "descriptive", "description",
    ]
    private enum Weight {
        static let distinguishingMatch = 3
        static let distinguishingMismatch = -3
        static let forcedMatch = 2
        static let otherMatch = 1
    }

    static func best(in options: [TrackOption], language: String?, title: String, isForced: Bool?) -> TrackOption? {
        let wanted = LanguageCode.normalized(language)
        let candidates = options.filter { wanted == nil || LanguageCode.normalized($0.language) == wanted }
        let words = self.words(in: title)
        var best: (option: TrackOption, score: Int)?
        for option in candidates {
            let score = self.score(words, against: self.words(in: option.title), isForced: isForced, candidateIsForced: option.isForced)
            if best.map({ score > $0.score }) ?? true {
                best = (option, score)
            }
        }
        return best?.option
    }

    private static func score(_ wanted: Set<String>, against candidate: Set<String>, isForced: Bool?, candidateIsForced: Bool) -> Int {
        let wantedKinds = wanted.intersection(distinguishingWords)
        let candidateKinds = candidate.intersection(distinguishingWords)
        var score = wantedKinds.intersection(candidateKinds).count * Weight.distinguishingMatch
        score += wantedKinds.symmetricDifference(candidateKinds).count * Weight.distinguishingMismatch
        score += wanted.subtracting(distinguishingWords).intersection(candidate).count * Weight.otherMatch
        if let isForced, isForced == candidateIsForced {
            score += Weight.forcedMatch
        }
        return score
    }

    /// Lowercased words, without release-group tags in brackets ("[SubsPlease]").
    static func words(in title: String) -> Set<String> {
        let withoutTags = title.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
        return Set(withoutTags.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }
}
