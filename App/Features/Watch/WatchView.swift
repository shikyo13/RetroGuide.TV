import RetroGuideKit
import SwiftUI

/// The main experience: live TV with the guide and settings layered on top.
///
/// The live picture is a single view that sits full screen behind the player
/// chrome, or animates into the guide's preview window when the guide opens.
struct WatchView: View {
    @Environment(AppModel.self) private var app
    @State private var isGuideVisible = false
    @State private var isSettingsPresented = false
    @State private var previewFrame: CGRect?

    var body: some View {
        let tuner = app.tuner
        ZStack {
            Color.black.ignoresSafeArea()
            if isGuideVisible {
                guide(tuner: tuner)
                    .transition(.opacity)
            }
            liveVideo(tuner: tuner)
            if !isGuideVisible {
                PlayerChromeView(tuner: tuner, onOpenGuide: { isGuideVisible = true })
                    .transition(.opacity)
            }
        }
        .onPreferenceChange(LivePreviewFrameKey.self) { frame in
            previewFrame = frame
        }
        .animation(DesignTokens.Motion.standardEase, value: isGuideVisible)
        .animation(DesignTokens.Motion.standardEase, value: previewFrame)
        .fullScreenCover(isPresented: $isSettingsPresented) {
            SettingsView()
        }
    }

    /// Full screen, or the guide's preview window (reported in global coordinates).
    private func liveVideo(tuner: Tuner) -> some View {
        GeometryReader { screen in
            let compactFrame = isGuideVisible ? previewFrame : nil
            let frame = compactFrame ?? CGRect(origin: .zero, size: screen.size)
            LiveVideoStack(tuner: tuner, isCompact: compactFrame != nil)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func guide(tuner: Tuner) -> some View {
        GuideView(
            channels: app.visibleChannels,
            tuner: tuner,
            onTune: { channel in
                tuner.tune(to: channel)
                isGuideVisible = false
            },
            onClose: { isGuideVisible = false },
            onOpenSettings: { isSettingsPresented = true }
        )
    }
}
