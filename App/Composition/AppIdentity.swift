import Foundation
import RetroTVKit
import UIKit

/// Static facts about this build of the app.
enum AppIdentity {
    static let productName = "RetroTV"
    static let keychainService = "io.github.retrotv.tokens"
    static let cacheFolderName = "RetroTV"

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
