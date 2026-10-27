#if os(iOS)
import OSLog
import UserMessagingPlatform

/// Google's consent flow (required for the EEA, UK and Switzerland): asks
/// once where needed and offers a way to change the choice later.
@MainActor
enum AdConsent {
    private static let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "Ads")

    /// Updates consent status, shows the form if one is required, and reports
    /// whether ads may be requested.
    static func gather() async -> Bool {
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: PresentingViewController.current)
        } catch {
            logger.error("Consent flow failed: \(error.localizedDescription, privacy: .public)")
        }
        return ConsentInformation.shared.canRequestAds
    }

    /// Whether Settings must offer a way to change the consent choice.
    static var isPrivacyChoiceRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    static func presentPrivacyChoices() async {
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: PresentingViewController.current)
        } catch {
            logger.error("Privacy options failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
