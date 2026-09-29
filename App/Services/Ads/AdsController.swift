#if os(iOS)
import Foundation
import GoogleMobileAds
import Observation
import OSLog
import RetroGuideKit

/// Ads in the free version on iPhone and iPad: a banner under the menus and,
/// at most once per 90 minutes of watching, a full-screen ad at a natural
/// break. Nothing is requested until the viewer's consent choice allows it.
@MainActor
@Observable
final class AdsController {
    private enum Key {
        static let pacing = "ads.pacing.v1"
    }

    /// Consent allows ads and the SDK has started.
    private(set) var isReady = false
    /// Settings must offer "Privacy choices" (EEA, UK, Switzerland).
    private(set) var isPrivacyChoiceRequired = false

    @ObservationIgnored private var pacing: AdPacing
    @ObservationIgnored private var interstitial: InterstitialAd?
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private let presenter = InterstitialPresenter()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "Ads")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Key.pacing).flatMap { try? JSONDecoder().decode(AdPacing.self, from: $0) }
        self.pacing = stored ?? AdPacing()
    }

    /// Runs the consent flow, then starts the ads SDK and preloads a full-screen ad.
    func start() async {
        guard !isReady, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        let canRequestAds = await AdConsent.gather()
        isPrivacyChoiceRequired = AdConsent.isPrivacyChoiceRequired
        guard canRequestAds else { return }
        // Match the app's 4+ age rating: only ads suitable for general audiences.
        MobileAds.shared.requestConfiguration.maxAdContentRating = .general
        _ = await MobileAds.shared.start()
        isReady = true
        await loadInterstitial()
    }

    func recordWatching(_ duration: TimeInterval) {
        pacing.recordWatching(duration)
        savePacing()
    }

    /// At a natural break, shows a full-screen ad if one is due. `onPresent`
    /// runs just before it appears and `onFinish` once it's gone.
    func presentInterstitialIfDue(onPresent: () -> Void, onFinish: @escaping () -> Void) {
        guard isReady, pacing.isInterstitialDue, let ad = interstitial else { return }
        interstitial = nil
        presenter.onFinish = { [weak self] in
            onFinish()
            Task { await self?.loadInterstitial() }
        }
        ad.fullScreenContentDelegate = presenter
        onPresent()
        ad.present(from: PresentingViewController.current)
        pacing.interstitialShown()
        savePacing()
    }

    func presentPrivacyChoices() async {
        await AdConsent.presentPrivacyChoices()
        isPrivacyChoiceRequired = AdConsent.isPrivacyChoiceRequired
    }

    private func loadInterstitial() async {
        guard let unit = AdUnits.interstitial else { return }
        do {
            interstitial = try await InterstitialAd.load(with: unit, request: AdRequestFactory.make())
        } catch {
            logger.error("Full-screen ad failed to load: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func savePacing() {
        defaults.set(try? JSONEncoder().encode(pacing), forKey: Key.pacing)
    }
}
#endif
