#if os(iOS)
import RetroGuideKit
import SwiftUI

/// The program guide on iPhone and iPad: tap to preview, tap again or press
/// Watch to tune, scroll through channels and page through time.
struct GuideTouchView: View {
    let tuner: Tuner
    let actions: GuideActions

    @State private var model: GuideModel
    @FocusState private var focus: GuideFocus?
    @Environment(\.isNarrowLayout) private var isNarrowLayout

    init(channels: [Channel], tuner: Tuner, actions: GuideActions) {
        self.tuner = tuner
        self.actions = actions
        _model = State(initialValue: GuideModel(channels: channels, focusedChannelID: tuner.channel?.id))
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            GuideHeader(
                isShowingNow: model.isShowingNow,
                windowStart: model.windowStart,
                focus: $focus,
                actions: actions
            )
            .crtEffect(isFullScreen: false)

            GuidePreviewPanel(
                tuner: tuner,
                channel: model.focusedChannel,
                program: model.focusedProgram,
                onWatch: watchFocusedChannel
            )

            GuideTouchGrid(model: model, tunedChannelID: tuner.channel?.id, onTune: actions.onTune)
                .crtEffect(isFullScreen: false)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.top, DesignTokens.Spacing.xs)
        .screenBackground()
        .onAppear(perform: fitWindowToWidth)
        .onChange(of: isNarrowLayout) { fitWindowToWidth() }
        .animation(DesignTokens.Motion.quickEase, value: model.windowStart)
        .animation(DesignTokens.Motion.quickEase, value: model.focusAnchor)
    }

    private func watchFocusedChannel() {
        if let channel = model.focusedChannel { actions.onTune(channel) }
    }

    private func fitWindowToWidth() {
        model.setVisibleSlots(isNarrowLayout ? GuideLayout.Time.compactVisibleSlots : GuideLayout.Time.visibleSlots)
    }
}
#endif
