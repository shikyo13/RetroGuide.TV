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
        case search
        case settings

        /// Full-screen TV, unless a development launch option asks for a menu.
        static var initial: Overlay {
            switch DebugLaunchOptions.overlay {
            case .guide: .guide
            case .search: .search
            case .settings: .settings
            case nil: .none
            }
        }
    }

    @Environment(AppModel.self) private var app
    @State private var overlay = Overlay.initial
    @State private var previewFrame: CGRect?
    @State private var screenSize = CGSize.zero
    @State private var safeArea = EdgeInsets()
    /// Height of the on-screen keyboard (iPhone and iPad), so the PiP window stays above it.
    @State private var keyboardHeight: CGFloat = .zero

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
            case .search:
                SearchView(onClose: { overlay = .guide }) { channel in
                    tuner.tune(to: channel)
                    overlay = .none
                }
                .transition(.opacity)
            case .none:
                EmptyView()
            }
            liveVideo(tuner: tuner)
            #if os(iOS)
            if isPictureInPicture {
                returnToFullScreenTarget
            }
            #endif
            if overlay == .none {
                PlayerChromeView(tuner: tuner, onOpenGuide: { overlay = .guide })
                    .transition(.opacity)
            }
        }
        .onPreferenceChange(LivePreviewFrameKey.self) { frame in
            previewFrame = frame
        }
        .background {
            // Spans the whole screen, so it reports both the full size and the safe-area insets.
            GeometryReader { _ in
                Color.clear
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { screenSize = $0 }
                    .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { safeArea = $0 }
            }
            .ignoresSafeArea()
        }
        .environment(\.pictureInPictureClearance, WatchLayout.pictureInPictureClearance(in: screenSize))
        #if os(iOS)
        .statusBarHidden(overlay == .none)
        .persistentSystemOverlays(overlay == .none ? .hidden : .automatic)
        .keepsScreenAwake()
        #endif
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
        case .settings, .search: WatchLayout.pictureInPictureFrame(in: screen, safeArea: pictureInPictureSafeArea)
        }
    }

    private var isPictureInPicture: Bool {
        overlay == .settings || overlay == .search
    }

    /// Apple TV's PiP insets already account for overscan.
    private var pictureInPictureSafeArea: EdgeInsets {
        PlatformMetric.value(tv: EdgeInsets(), touch: safeArea)
    }

    #if os(iOS)
    /// Tapping the PiP window goes back to watching full screen.
    private var returnToFullScreenTarget: some View {
        GeometryReader { screen in
            let window = WatchLayout.pictureInPictureFrame(in: screen.size, safeArea: pictureInPictureSafeArea)
            Button {
                overlay = .none
            } label: {
                Color.clear
            }
            .buttonStyle(InvisibleButtonStyle())
            .frame(width: window.width, height: window.height)
            .offset(x: window.minX, y: window.minY)
            .accessibilityLabel("Watch full screen")
        }
        .ignoresSafeArea()
    }
    #endif

    private func guide(tuner: Tuner) -> some View {
        GuideView(
            channels: app.visibleChannels,
            tuner: tuner,
            actions: GuideActions(
                onTune: { channel in
                    tuner.tune(to: channel)
                    overlay = .none
                },
                onClose: { overlay = .none },
                onOpenSearch: { overlay = .search },
                onOpenSettings: { overlay = .settings }
            )
        )
    }
}
