import Foundation

/// How RetroGuide identifies itself to Jellyfin. The device id must stay
/// stable per installation so the server lists a single device and session.
public struct JellyfinClientIdentity: Sendable, Hashable {
    public let deviceID: String
    public let deviceName: String
    public let client: String
    public let version: String

    public init(deviceID: String, deviceName: String, client: String, version: String) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.client = client
        self.version = version
    }

    /// The `Authorization` header Jellyfin expects, carrying `token` once signed in.
    func authorization(token: String?) -> String {
        var fields = [
            ("Client", client),
            ("Device", deviceName),
            ("DeviceId", deviceID),
            ("Version", version),
        ]
        if let token {
            fields.append(("Token", token))
        }
        return "MediaBrowser " + fields.map { "\($0)=\"\(Self.escaped($1))\"" }.joined(separator: ", ")
    }

    func headers(token: String?) -> [String: String] {
        [
            JellyfinAPI.Header.authorization: authorization(token: token),
            JellyfinAPI.Header.accept: JellyfinAPI.Header.json,
        ]
    }

    /// Header values are quoted, so quotes inside them (a device named
    /// `Adam's "TV"`) would end the value early.
    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "'")
    }
}
