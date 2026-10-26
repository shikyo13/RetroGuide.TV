import CryptoKit
import Foundation
import Observation
import RetroGuideKit

/// Stores restrictions and the PIN verifier together; authorization never survives a relaunch.
@MainActor @Observable
final class ParentalControls {
    enum Limits {
        static let pinLength = ParentalPIN.length
        static let attempts = 5
        static let cooldown: TimeInterval = 60
    }
    private struct Record: Codable {
        var policy: ParentalPolicy
        let salt: String
        let verifier: String
        var failedAttempts = 0
        var retryAfter: Date?
    }
    private enum Storage {
        static let account = "parentalControls.v1"
        static let marker = "parentalControlsConfigured.v1"
    }
    private(set) var policy = ParentalPolicy()
    private(set) var isAuthorized = false
    private(set) var message: String?
    private(set) var isUnavailable = false
    @ObservationIgnored private var record: Record?
    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let defaults: UserDefaults

    var needsAuthorization: Bool { policy.isEnabled && !isAuthorized || isUnavailable }
    var hasPIN: Bool { record != nil }

    init(keychain: KeychainStore = KeychainStore(), defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
        if let text = keychain.token(for: Storage.account), let data = text.data(using: .utf8),
           let saved = try? JSONDecoder().decode(Record.self, from: data) {
            record = saved
            policy = saved.policy
        } else if defaults.bool(forKey: Storage.marker) {
            // Missing or unreadable protected storage cannot turn restrictions off.
            isUnavailable = true
            policy.isEnabled = true
            policy.allLibraries = false
        }
    }

    func authorize(_ pin: String, now: Date = .now) -> Bool {
        guard var saved = record, !isUnavailable else {
            message = "Parental controls could not be read. Try reopening the app after unlocking this device."
            return false
        }
        if let retry = saved.retryAfter, retry > now {
            message = "Too many attempts. Try again in \(Int(ceil(retry.timeIntervalSince(now)))) seconds."
            return false
        }
        guard ParentalPIN.isValid(pin), Self.verifier(pin, salt: saved.salt) == saved.verifier else {
            saved.failedAttempts += 1
            if saved.failedAttempts >= Limits.attempts {
                saved.failedAttempts = 0
                saved.retryAfter = now.addingTimeInterval(Limits.cooldown)
            }
            guard persist(saved) else { return false }
            message = saved.retryAfter.map { $0 > now } == true ? "Too many attempts. Try again in a minute." : "Incorrect PIN."
            return false
        }
        saved.failedAttempts = 0
        saved.retryAfter = nil
        guard persist(saved) else { return false }
        isAuthorized = true
        message = nil
        return true
    }

    func save(_ policy: ParentalPolicy, newPIN: String? = nil) -> Bool {
        guard !needsAuthorization else { message = "Enter your PIN first."; return false }
        if let newPIN {
            guard ParentalPIN.isValid(newPIN) else {
                message = "Use a four-digit PIN."
                return false
            }
            let salt = UUID().uuidString
            guard persist(Record(policy: policy, salt: salt, verifier: Self.verifier(newPIN, salt: salt))) else { return false }
        } else {
            guard var saved = record else { message = "Create a PIN first."; return false }
            saved.policy = policy
            guard persist(saved) else { return false }
        }
        self.policy = policy
        message = nil
        return true
    }

    func endAuthorization() { isAuthorized = false; message = nil }

    /// Learns matching copies without changing the parent's choices or requiring an unlock.
    func refreshTitleMatches(in catalog: ParentalTitleCatalog) {
        guard var saved = record else { return }
        let resolved = policy.resolvingTitles(in: catalog)
        guard resolved != policy else { return }
        saved.policy = resolved
        if persist(saved) { policy = resolved }
    }

    private func persist(_ record: Record) -> Bool {
        guard let data = try? JSONEncoder().encode(record), let text = String(data: data, encoding: .utf8),
              keychain.setToken(text, for: Storage.account) else {
            message = "Couldn't save parental controls. Your previous settings are still in effect."
            return false
        }
        self.record = record
        defaults.set(true, forKey: Storage.marker)
        return true
    }

    private static func verifier(_ pin: String, salt: String) -> String {
        SHA256.hash(data: Data((salt + pin).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
