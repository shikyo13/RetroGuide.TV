import Foundation
import RetroGuideKit

/// User-facing settings. Small and Codable so it fits comfortably in UserDefaults
/// (tvOS offers no guaranteed persistent file storage beyond that).
struct UserPreferences: Codable, Equatable, Sendable {
    var themeID: ThemeID = .classicCable
    var scheduleGrid: ScheduleGrid = .continuous
    var showsScanlines = true
    var playerEngine: PlaybackEngineKind = .universal
    var displayMatching: DisplayMatching = .dynamicRange
    var lastChannelID: String?

    init() {}

    /// Tolerant decoding: settings added in later versions fall back to defaults
    /// instead of discarding everything the user already chose.
    init(from decoder: Decoder) throws {
        let defaults = UserPreferences()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        themeID = (try? container.decode(ThemeID.self, forKey: .themeID)) ?? defaults.themeID
        scheduleGrid = (try? container.decode(ScheduleGrid.self, forKey: .scheduleGrid)) ?? defaults.scheduleGrid
        showsScanlines = (try? container.decode(Bool.self, forKey: .showsScanlines)) ?? defaults.showsScanlines
        playerEngine = (try? container.decode(PlaybackEngineKind.self, forKey: .playerEngine)) ?? defaults.playerEngine
        displayMatching = (try? container.decode(DisplayMatching.self, forKey: .displayMatching)) ?? defaults.displayMatching
        lastChannelID = try? container.decode(String.self, forKey: .lastChannelID)
    }
}

/// Typed, Codable access to `UserDefaults` for everything except secrets.
@MainActor
struct PreferencesStore {
    private enum Key {
        static let preferences = "preferences.v1"
        static let accounts = "accounts.v1"
        static let customization = "lineupCustomization.v1"
        static let languagePreferences = "languagePreferences.v1"
        static let plexClientIdentifier = "plexClientIdentifier"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var preferences: UserPreferences {
        get { decode(UserPreferences.self, forKey: Key.preferences) ?? UserPreferences() }
        nonmutating set { encode(newValue, forKey: Key.preferences) }
    }

    var accounts: [ServerAccount] {
        get { decode([ServerAccount].self, forKey: Key.accounts) ?? [] }
        nonmutating set { encode(newValue, forKey: Key.accounts) }
    }

    /// The account's language settings as last fetched, so tracks are right
    /// from the first channel after launch.
    var languagePreferences: LanguagePreferences? {
        get { decode(LanguagePreferences.self, forKey: Key.languagePreferences) }
        nonmutating set {
            if let newValue {
                encode(newValue, forKey: Key.languagePreferences)
            } else {
                defaults.removeObject(forKey: Key.languagePreferences)
            }
        }
    }

    var customization: LineupCustomization {
        get { decode(LineupCustomization.self, forKey: Key.customization) ?? LineupCustomization() }
        nonmutating set { encode(newValue, forKey: Key.customization) }
    }

    /// A stable per-install identifier so Plex lists this Apple TV as one device.
    var plexClientIdentifier: String {
        if let existing = defaults.string(forKey: Key.plexClientIdentifier) {
            return existing
        }
        let created = UUID().uuidString.lowercased()
        defaults.set(created, forKey: Key.plexClientIdentifier)
        return created
    }

    func resetAll() {
        [Key.preferences, Key.accounts, Key.customization, Key.languagePreferences].forEach(defaults.removeObject(forKey:))
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
