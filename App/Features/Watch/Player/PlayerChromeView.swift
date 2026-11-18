import RetroGuideKit
import SwiftUI

/// Where focus is while watching full screen on Apple TV.
enum PlayerChromeFocus: Hashable {
    /// The full-screen remote input (channel changes, info, guide, Options).
    case remote
}

/// Transient overlays while watching full screen: the channel number, the info
/// banner and, on iPhone and iPad, the on-screen controls. Input comes from the
/// Siri Remote or touch as ``PlayerCommand``s.
///
/// On Apple TV, Up and Down always change channel; Options opens with a
/// click and hold (Watch from Beginning is at its top).
struct PlayerChromeView: View {
    private enum Timing {
        static let osdDuration: Duration = .seconds(3)
        static let bannerDuration: Duration = .seconds(6)
    }

    let tuner: Tuner
    /// False while a panel over the picture (Options) has focus.
    var isActive = true
    let onOpenGuide: () -> Void
    var onGoBack: () -> Void = {}
    let onOpenOptions: () -> Void

    @State private var isOSDVisible = false
    @State private var isBannerVisible = false
    @State private var showsNext = false
    @State private var bannerRequest = 0
    @FocusState private var focus: PlayerChromeFocus?
    /// iPhone in landscape: the banner can't be tapped, so it may sit over the
    /// home indicator's area, close to the bottom edge.
    @Environment(\.isShortLayout) private var isShortLayout

    var body: some View {
        ZStack {
            input
            overlays
        }
        .animation(DesignTokens.Motion.standardEase, value: isBannerVisible)
        .animation(DesignTokens.Motion.quickEase, value: isOSDVisible)
        .task(id: tuner.tuneGeneration) {
            showsNext = false
            isOSDVisible = true
            isBannerVisible = true
            try? await Task.sleep(for: Timing.osdDuration)
            isOSDVisible = false
        }
        .task(id: BannerTrigger(generation: tuner.tuneGeneration, request: bannerRequest)) {
            try? await Task.sleep(for: DebugLaunchOptions.bannerDuration ?? Timing.bannerDuration)
            guard !Task.isCancelled else { return }
            isBannerVisible = false
        }
        .onAppear { focus = .remote }
        .onChange(of: isActive) { _, isActive in
            if isActive { focus = .remote }
        }
    }

    @ViewBuilder
    private var input: some View {
        #if os(tvOS)
        PlayerRemoteInput(focus: $focus, onCommand: handle)
            .disabled(!isActive)
        #else
        PlayerTouchInput(isInfoVisible: isBannerVisible, isIndependent: tuner.isWatchingFromBeginning, onCommand: handle)
        #endif
    }

    private var overlays: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            #if os(iOS)
            if isBannerVisible {
                PlayerTouchControls(onCommand: handle)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            #endif
            HStack {
                Spacer()
                if isOSDVisible, let channel = tuner.channel {
                    ChannelNumberOSD(number: channel.number, callSign: channel.callSign)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            Spacer()
            #if os(iOS)
            // With the program it restarts, not among the controls.
            if isBannerVisible, tuner.program != nil {
                HStack {
                    Spacer()
                    playbackActionButton
                }
                .transition(.opacity)
            }
            #endif
            if isBannerVisible, let channel = tuner.channel {
                ChannelBanner(channel: channel, program: bannerProgram, isShowingNext: showsNext, isIndependent: tuner.isWatchingFromBeginning, isCommercial: tuner.isPlayingCommercial && !showsNext)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .padding(PlatformMetric.value(tv: .zero, touch: DesignTokens.Spacing.md))
        .landscapeTopClearance()
        .ignoresSafeArea(.container, edges: isShortLayout ? .bottom : [])
    }

    #if os(iOS)
    private var playbackActionButton: some View {
        Button {
            if tuner.isWatchingFromBeginning {
                tuner.returnToLive()
            } else if let program = tuner.program, let channel = tuner.channel {
                tuner.watchFromBeginning(program, on: channel)
            }
        } label: {
            Label(tuner.isWatchingFromBeginning ? "Return to Live" : "Watch from Beginning",
                  systemImage: tuner.isWatchingFromBeginning ? "dot.radiowaves.left.and.right" : "backward.end.fill")
        }
        .buttonStyle(.retro)
        .disabled(!isActive)
    }
    #endif

    private var bannerProgram: ScheduledProgram? {
        guard let current = tuner.program else { return nil }
        guard showsNext, !tuner.isWatchingFromBeginning else { return current }
        return tuner.channel?.timeline.program(after: current)
    }

    private func handle(_ command: PlayerCommand) {
        switch command {
        case .channelUp: tuner.channelUp()
        case .channelDown: tuner.channelDown()
        case .showInfo: presentBanner(next: isBannerVisible)
        case .showNow: presentBanner(next: false)
        case .showNext: presentBanner(next: true)
        case .hideInfo: isBannerVisible = false
        case .openGuide: onOpenGuide()
        case .goBack: onGoBack()
        case .lastChannel: tuner.recall()
        case .openOptions: onOpenOptions()
        }
    }

    private func presentBanner(next: Bool) {
        showsNext = next
        isBannerVisible = true
        bannerRequest += 1
    }
}

/// Restarts the banner auto-hide timer whenever either value changes.
private struct BannerTrigger: Hashable {
    let generation: Int
    let request: Int
}
