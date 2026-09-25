import RetroGuideKit
import SwiftUI

/// Transient overlays while watching full screen: the channel number, the info
/// banner and, on iPhone and iPad, the on-screen controls. Input comes from the
/// Siri Remote or touch as ``PlayerCommand``s.
struct PlayerChromeView: View {
    private enum Timing {
        static let osdDuration: Duration = .seconds(3)
        static let bannerDuration: Duration = .seconds(6)
    }

    let tuner: Tuner
    let onOpenGuide: () -> Void

    @State private var isOSDVisible = false
    @State private var isBannerVisible = false
    @State private var showsNext = false
    @State private var bannerRequest = 0

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
            try? await Task.sleep(for: Timing.bannerDuration)
            guard !Task.isCancelled else { return }
            isBannerVisible = false
        }
    }

    @ViewBuilder
    private var input: some View {
        #if os(tvOS)
        PlayerRemoteInput(onCommand: handle)
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
            if isBannerVisible, let channel = tuner.channel {
                ChannelBanner(channel: channel, program: bannerProgram, isShowingNext: showsNext)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .padding(PlatformMetric.value(tv: .zero, touch: DesignTokens.Spacing.md))
    }

    private var bannerProgram: ScheduledProgram? {
        guard let current = tuner.program else { return nil }
        guard showsNext else { return current }
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
        case .lastChannel: tuner.recall()
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
