import RetroGuideKit
import SwiftUI

/// The main experience: live TV with the guide and settings layered on top.
///
/// The live picture is a single view: full screen behind the player chrome,
/// inside the guide's preview window, or picture-in-picture over Settings.
struct WatchView: View {
    private enum Overlay: Equatable {
        case none
        case guide
        case settings
    }

    @Environment(AppModel.self) private var app
    @State private var overlay = Overlay.none
    @State private var previewFrame: CGRect?

    var body: some View {
        let tuner = app.tuner
        ZStack {
            Color.black.ignoresSafeArea()
            switch overlay {
            case .guide:
                guide(tuner: tuner)
                    .transition(.opacity)
            case .settings:
                SettingsView(onClose: { overlay = .guide })
                    .transition(.opacity)
            case .none:
                EmptyView()
            }
            liveVideo(tuner: tuner)
            if overlay == .none {
                PlayerChromeView(tuner: tuner, onOpenGuide: { overlay = .guide })
                    .transition(.opacity)
            }
        }
        .onPreferenceChange(LivePreviewFrameKey.self) { frame in
            previewFrame = frame
        }
        .animation(DesignTokens.Motion.pictureInPicture, value: overlay)
        .animation(DesignTokens.Motion.pictureInPicture, value: previewFrame)
    }

    /// Full screen, the guide's preview window, or PiP in the bottom-right corner over Settings.
    private func liveVideo(tuner: Tuner) -> some View {
        GeometryReader { screen in
            LiveVideoStack(tuner: tuner, window: frame(in: screen.size), screen: screen.size)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func frame(in screen: CGSize) -> CGRect? {
        switch overlay {
        case .none: nil
        case .guide: previewFrame
        case .settings: WatchLayout.pictureInPictureFrame(in: screen)
        }
    }

    private func guide(tuner: Tuner) -> some View {
        GuideView(
            channels: app.visibleChannels,
            tuner: tuner,
            onTune: { channel in
                tuner.tune(to: channel)
                overlay = .none
            },
            onClose: { overlay = .none },
            onOpenSettings: { overlay = .settings }
        )
    }
}
