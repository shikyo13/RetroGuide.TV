import AVFoundation
import SwiftUI

@main
struct RetroGuideApp: App {
    @State private var model = AppModel()
    #if os(iOS)
    @State private var ads = AdsController()
    #endif
    @Environment(\.scenePhase) private var scenePhase

    /// The localization the app is shown in (e.g. "ja", "pt-BR"), for typesetting.
    private static let appLanguage: Locale.Language = {
        let shown = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale.Language(identifier: TypesettingOverride.languages[shown] ?? shown)
    }()

    private enum TypesettingOverride {
        /// Odia's system font draws Latin digits with Odia-looking shapes, so
        /// "$9.99" reads like "$2.22". Typeset as English: Odia letters keep
        /// the Odia font, digits get the standard one. Odia separates words with
        /// spaces, so line breaking is unaffected.
        static let languages = ["or": "en"]
    }

    init() {
        #if os(iOS)
        // Follow the output other video apps use (AirPlay, HomePod) when the system routes there.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
        #else
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        #endif
        #if os(iOS)
        NavigationTitleFit.install()
        #endif
        #if DEBUG && os(iOS)
        DebugSnapshot.install()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                #if os(iOS)
                .debugLaunchOrientation()
                .modifier(AppEnvironment(model: model, ads: ads))
                #else
                .modifier(AppEnvironment(model: model))
                #endif
                // Typeset in the language the app is showing, not the device's:
                // Japanese and Chinese then break lines between words, and each
                // script gets its own fonts.
                .typesettingLanguage(Self.appLanguage)
                .preferredColorScheme(.dark)
                .onChange(of: model.pro.hasLoaded ? model.pro.isPro : nil) { model.proAccessChanged() }
                .task { await model.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: model.enteredBackground()
            case .active:
                #if os(iOS)
                model.becameActive(resumePlayback: !ads.isPresentingInterstitial)
                #else
                model.becameActive()
                #endif
                PurchaseAttribution.shared.start()
            default: break
            }
        }
    }
}
