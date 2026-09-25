import Foundation

/// How RetroGuide identifies itself to Plex. The client identifier must stay
/// stable per installation so Plex shows a single authorized device.
public struct PlexClientIdentity: Sendable, Hashable {
    public let clientIdentifier: String
    public let product: String
    public let version: String
    public let platform: String
    public let platformVersion: String
    public let device: String
    public let deviceName: String

    public init(
        clientIdentifier: String,
        product: String,
        version: String,
        platform: String,
        platformVersion: String,
        device: String,
        deviceName: String
    ) {
        self.clientIdentifier = clientIdentifier
        self.product = product
        self.version = version
        self.platform = platform
        self.platformVersion = platformVersion
        self.device = device
        self.deviceName = deviceName
    }

    var headers: [String: String] {
        [
            PlexAPI.Header.accept: PlexAPI.Header.json,
            PlexAPI.Header.product: product,
            PlexAPI.Header.version: version,
            PlexAPI.Header.clientIdentifier: clientIdentifier,
            PlexAPI.Header.platform: platform,
            PlexAPI.Header.platformVersion: platformVersion,
            PlexAPI.Header.device: device,
            PlexAPI.Header.deviceName: deviceName,
        ]
    }

    var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: PlexAPI.Header.product, value: product),
            URLQueryItem(name: PlexAPI.Header.version, value: version),
            URLQueryItem(name: PlexAPI.Header.clientIdentifier, value: clientIdentifier),
            URLQueryItem(name: PlexAPI.Header.platform, value: platform),
            URLQueryItem(name: PlexAPI.Header.device, value: device),
        ]
    }
}
