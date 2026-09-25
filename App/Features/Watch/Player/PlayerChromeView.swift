import RetroGuideKit
import SwiftUI

/// Remote-control handling and transient overlays while watching full screen.
///
/// Siri Remote mapping:
/// - Swipe/press up and down: channel up / down
/// - Swipe/press left and right: show what's on now / next
/// - Click: open the guide
/// - Play/Pause: jump back to the last channel
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
    @FocusState private var hasRemoteFocus: Bool

    var body: some View {
        ZStack {
            Button(action: onOpenGuide) {
                Color.clear
            }
            .buttonStyle(InvisibleButtonStyle())
            .focused($hasRemoteFocus)
            .onMoveCommand(perform: handleMove)
            .onPlayPauseCommand(perform: tuner.recall)
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    if isOSDVisible, let channel = tuner.channel {
                        ChannelNumberOSD(number: channel.number, callSign: channel.callSign)
                            .transition(.opacity)
                    }
                }
                Spacer()
                if isBannerVisible, let channel = tuner.channel {
                    ChannelBanner(channel: channel, program: bannerProgram, isShowingNext: showsNext)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .allowsHitTesting(false)
        }
        .animation(DesignTokens.Motion.standardEase, value: isBannerVisible)
        .animation(DesignTokens.Motion.quickEase, value: isOSDVisible)
        .onAppear { hasRemoteFocus = true }
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

    private var bannerProgram: ScheduledProgram? {
        guard let current = tuner.program else { return nil }
        guard showsNext else { return current }
        return tuner.channel?.timeline.program(after: current)
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .up: tuner.channelUp()
        case .down: tuner.channelDown()
        case .left: presentBanner(next: false)
        case .right: presentBanner(next: isBannerVisible)
        @unknown default: break
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

/// A focusable button with no visual treatment, used to capture remote input.
struct InvisibleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
    }
}
