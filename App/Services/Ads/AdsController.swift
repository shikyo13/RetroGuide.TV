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
    private(set) var isPresentingInterstitial = false

    @ObservationIgnored private var pacing: AdPacing
    @ObservationIgnored private let interstitials: InterstitialAdCache?
    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private let presenter = InterstitialPresenter()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "Ads")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Key.pacing).flatMap { try? JSONDecoder().decode(AdPacing.self, from: $0) }
        self.pacing = stored ?? AdPacing()
        interstitials = AdUnits.interstitial.map { unit in
            InterstitialAdCache {
                try await InterstitialAd.load(with: unit, request: AdRequestFactory.make())
            }
        }
    }

    /// Runs the consent flow, then starts the ads SDK.
    func start() async {
        guard !isReady, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        let canRequestAds = await AdConsent.gather()
        isPrivacyChoiceRequired = AdConsent.isPrivacyChoiceRequired
        guard canRequestAds, !Task.isCancelled else { return }
        // Match the app's 4+ age rating: only ads suitable for general audiences.
        MobileAds.shared.requestConfiguration.maxAdContentRating = .general
        _ = await MobileAds.shared.start()
        guard !Task.isCancelled else { return }
        isReady = true
    }

    /// The view owns this task, cancelling it in the background or when Pro is granted.
    func maintainInterstitial() async {
        while isReady, !Task.isCancelled {
            if !presenter.isPresenting { await interstitials?.refreshIfNeeded() }
            do {
                try await Task.sleep(for: .seconds(InterstitialLoadPolicy.maintenanceInterval))
            } catch { return }
        }
    }

    func discardPreloadedAd() {
        interstitials?.discard()
    }

    func recordWatching(_ duration: TimeInterval) {
        pacing.recordWatching(duration)
        savePacing()
    }

    /// At a natural break, shows a full-screen ad if one is due. `onPresent`
    /// runs just before it appears and `onFinish` once it's gone.
    func presentInterstitialIfDue(onPresent: () -> Void, onFinish: @escaping () -> Void) {
        guard isReady, pacing.isInterstitialDue, !presenter.isPresenting,
              let controller = PresentingViewController.current,
              controller.viewIfLoaded?.window != nil,
              let ad = interstitials?.takeFreshAd() else { return }
        do {
            try presenter.present(ad, from: controller, onPresent: {
                isPresentingInterstitial = true
                onPresent()
            }, onImpression: { [weak self] in
                self?.pacing.interstitialShown()
                self?.savePacing()
            }, onFinish: { [weak self] displayed in
                self?.isPresentingInterstitial = false
                if !displayed { self?.interstitials?.presentationFailed() }
                onFinish()
            })
        } catch {
            interstitials?.presentationFailed()
            logger.error("Full-screen ad could not be presented: \(error.localizedDescription, privacy: .public)")
        }
    }

    func presentPrivacyChoices() async {
        await AdConsent.presentPrivacyChoices()
        isPrivacyChoiceRequired = AdConsent.isPrivacyChoiceRequired
        discardPreloadedAd()
        if AdConsent.canRequestAds {
            await start()
        } else {
            isReady = false
        }
    }

    private func savePacing() {
        defaults.set(try? JSONEncoder().encode(pacing), forKey: Key.pacing)
    }
}
#endif
