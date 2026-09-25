import AVFoundation
import SwiftUI

@main
struct RetroGuideApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
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
            case .active: if model.phase == .ready { model.tuner.resume() }
            default: break
            }
        }
    }
}
