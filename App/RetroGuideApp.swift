import AVFoundation
import SwiftUI

@main
struct RetroGuideApp: App {
    @State private var model = AppModel()
    #if os(iOS)
    @State private var ads = AdsController()
    #endif
    @Environment(\.scenePhase) private var scenePhase

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        #if DEBUG && os(iOS)
        DebugSnapshot.install()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                #if os(iOS)
                .debugLaunchOrientation()
                #endif
                .environment(model)
                #if os(iOS)
                .environment(ads)
                #endif
                .environment(\.theme, model.theme)
                .environment(\.artworkResolver, model.artworkResolver)
                .environment(\.showsScanlines, model.preferences.showsScanlines)
                .tint(model.theme.accent)
                .preferredColorScheme(.dark)
                .task { await model.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: model.tuner.suspend()
            case .active:
                if model.phase == .ready {
                    model.tuner.resume()
                    Task { await model.refreshConnections() }
                }
            default: break
            }
        }
    }
}
