import RetroGuideKit
import SwiftUI

/// Where focus is while watching full screen on Apple TV.
enum PlayerChromeFocus: Hashable {
    /// The full-screen remote input (channel changes, info, guide).
    case remote
    /// The Options button on the info banner.
    case options
}

/// Transient overlays while watching full screen: the channel number, the info
/// banner and, on iPhone and iPad, the on-screen controls. Input comes from the
/// Siri Remote or touch as ``PlayerCommand``s.
///
/// On Apple TV, info the viewer asked for (Left/Right) also offers an Options
/// button, reached with Down; after a channel change Down still
/// changes channel, so surfing is unaffected.
struct PlayerChromeView: View {
    private enum Timing {
        static let osdDuration: Duration = .seconds(3)
        static let bannerDuration: Duration = .seconds(6)
    }

    let tuner: Tuner
    /// False while a panel over the picture (Options) has focus.
    var isActive = true
    let onOpenGuide: () -> Void
    let onOpenOptions: () -> Void

    @State private var isOSDVisible = false
    @State private var isBannerVisible = false
    @State private var showsNext = false
    @State private var bannerRequest = 0
    /// The banner is up because the viewer asked for it (not a channel change).
    @State private var isInfoRequested = false
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
            isInfoRequested = false
            isOSDVisible = true
            isBannerVisible = true
            try? await Task.sleep(for: Timing.osdDuration)
            isOSDVisible = false
        }
        .task(id: BannerTrigger(generation: tuner.tuneGeneration, request: bannerRequest)) {
            try? await Task.sleep(for: DebugLaunchOptions.bannerDuration ?? Timing.bannerDuration)
            // Stays up while the viewer is on its button.
            guard !Task.isCancelled, focus != .options else { return }
            isBannerVisible = false
            isInfoRequested = false
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
        PlayerTouchInput(isInfoVisible: isBannerVisible, onCommand: handle)
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
            #if os(tvOS)
            if offersOptions {
                HStack {
                    Spacer()
                    optionsButton
                }
                .transition(.opacity)
            }
            #endif
            if isBannerVisible, let channel = tuner.channel {
                ChannelBanner(channel: channel, program: bannerProgram, isShowingNext: showsNext, offersOptions: offersOptions)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .padding(PlatformMetric.value(tv: .zero, touch: DesignTokens.Spacing.md))
        .landscapeTopClearance()
        .ignoresSafeArea(.container, edges: isShortLayout ? .bottom : [])
    }

    /// Apple TV: info the viewer asked for offers Options.
    private var offersOptions: Bool {
        #if os(tvOS)
        isBannerVisible && isInfoRequested
        #else
        false
        #endif
    }

    #if os(tvOS)
    private var optionsButton: some View {
        WatchOptionsButton(action: onOpenOptions)
            .disabled(!isActive)
            .focused($focus, equals: .options)
            .onMoveCommand { direction in
                if direction == .up { leaveOptionsButton() }
            }
            .onExitCommand(perform: leaveOptionsButton)
    }

    private func leaveOptionsButton() {
        focus = .remote
        // The banner's timer starts again now that the viewer has moved on.
        bannerRequest += 1
    }
    #endif

    private var bannerProgram: ScheduledProgram? {
        guard let current = tuner.program else { return nil }
        guard showsNext else { return current }
        return tuner.channel?.timeline.program(after: current)
    }

    private func handle(_ command: PlayerCommand) {
        switch command {
        case .channelUp: tuner.channelUp()
        case .channelDown:
            #if os(tvOS)
            if offersOptions {
                focus = .options
                return
            }
            #endif
            tuner.channelDown()
        case .showInfo: presentBanner(next: isBannerVisible)
        case .showNow: presentBanner(next: false)
        case .showNext: presentBanner(next: true)
        case .hideInfo: isBannerVisible = false
        case .openGuide: onOpenGuide()
        case .lastChannel: tuner.recall()
        case .openOptions: onOpenOptions()
        }
    }

    private func presentBanner(next: Bool) {
        showsNext = next
        isBannerVisible = true
        isInfoRequested = true
        bannerRequest += 1
    }
}

/// Restarts the banner auto-hide timer whenever either value changes.
private struct BannerTrigger: Hashable {
    let generation: Int
    let request: Int
}
