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
}
