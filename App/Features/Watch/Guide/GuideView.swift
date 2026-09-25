import RetroTVKit
import SwiftUI

/// The full-screen program guide: header, preview panel and channel grid.
struct GuideView: View {
    private enum FocusTarget: Hashable {
        case grid
        case header
    }

    let tuner: Tuner
    let onTune: (Channel) -> Void
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    @State private var model: GuideModel
    @State private var isHeaderFocusable = false
    @FocusState private var focus: FocusTarget?

    init(
        channels: [Channel],
        tuner: Tuner,
        onTune: @escaping (Channel) -> Void,
        onClose: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.tuner = tuner
        self.onTune = onTune
        self.onClose = onClose
        self.onOpenSettings = onOpenSettings
        _model = State(initialValue: GuideModel(channels: channels, focusedChannelID: tuner.channel?.id))
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            GuideHeader(
                isShowingNow: model.isShowingNow,
                windowStart: model.windowStart,
                onOpenSettings: onOpenSettings
            )
            .crtEffect(isFullScreen: false)
            .focused($focus, equals: .header)
            .disabled(!isHeaderFocusable)
            .onMoveCommand { direction in
                if direction == .down { focusGrid() }
            }

            GuidePreviewPanel(tuner: tuner, channel: model.focusedChannel, program: model.focusedProgram)

            Button {
                if let channel = model.focusedChannel { onTune(channel) }
            } label: {
                GuideGridView(model: model, tunedChannelID: tuner.channel?.id, showsFocus: focus == .grid)
            }
            .buttonStyle(InvisibleButtonStyle())
            .crtEffect(isFullScreen: false)
            .focused($focus, equals: .grid)
            .onMoveCommand(perform: handleGridMove)
            .onPlayPauseCommand(perform: model.pageDown)
        }
        .screenBackground()
        .onExitCommand(perform: onClose)
        .onAppear { focus = .grid }
        .onChange(of: focus) { _, newFocus in
            if newFocus == .grid { isHeaderFocusable = false }
        }
        .animation(DesignTokens.Motion.quickEase, value: model.focusedRow)
        .animation(DesignTokens.Motion.quickEase, value: model.windowStart)
    }

    private func handleGridMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .up:
            if !model.moveUp() { focusHeader() }
        case .down: model.moveDown()
        case .left: model.moveLeft()
        case .right: model.moveRight()
        @unknown default: break
        }
    }

    private func focusHeader() {
        isHeaderFocusable = true
        Task { @MainActor in
            focus = .header
        }
    }

    private func focusGrid() {
        focus = .grid
    }
}
