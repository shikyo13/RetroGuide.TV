import Foundation
import RetroGuideKit
import UIKit

/// Static facts about this build of the app.
enum AppIdentity {
    static let productName = "RetroGuide.TV"

    /// The two parts of the logo: the name and the accented suffix.
    enum Wordmark {
        static let name = "RetroGuide"
        static let suffix = ".TV"
    }
    static let bundleIdentifier = "com.adamhunt.retroguide"
    static let keychainService = "com.adamhunt.retroguide.tokens"
    static let cacheFolderName = "RetroGuide"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    @MainActor
    static func plexIdentity(clientIdentifier: String) -> PlexClientIdentity {
        PlexClientIdentity(
            clientIdentifier: clientIdentifier,
            product: productName,
            version: version,
            platform: "tvOS",
            platformVersion: UIDevice.current.systemVersion,
            device: "Apple TV",
            deviceName: UIDevice.current.name
        )
    }

    /// `deviceID` is the same per-install identifier Plex gets, so each
    /// server lists this device once.
    @MainActor
    static func jellyfinIdentity(deviceID: String) -> JellyfinClientIdentity {
        JellyfinClientIdentity(deviceID: deviceID, deviceName: UIDevice.current.name, client: productName, version: version)
    }
}

/// How the app identifies itself to each kind of media server.
struct ServerIdentities: Sendable {
    let plex: PlexClientIdentity
    let jellyfin: JellyfinClientIdentity

    @MainActor
    init(installIdentifier: String) {
        plex = AppIdentity.plexIdentity(clientIdentifier: installIdentifier)
        jellyfin = AppIdentity.jellyfinIdentity(deviceID: installIdentifier)
    }
}
