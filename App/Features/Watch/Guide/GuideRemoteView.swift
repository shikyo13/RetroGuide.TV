#if os(tvOS)
import RetroGuideKit
import SwiftUI

/// The program guide driven by the Siri Remote: the grid is one focusable
/// element that interprets moves like a cable box. As elsewhere on Apple TV,
/// Back first goes to the top (Search and Settings) and then closes the
/// guide; Play/Pause jumps to the top too.
struct GuideRemoteView: View {
    let tuner: Tuner
    let actions: GuideActions

    @State private var model: GuideModel
    @Binding private var isHeaderFocusable: Bool
    @FocusState private var focus: GuideFocus?

    let channels: [Channel]
    let lineupRevision: Int
    let focusRequest: GuideFocusRequest?

    init(
        channels: [Channel],
        lineupRevision: Int,
        isHeaderFocusable: Binding<Bool>,
        focusRequest: GuideFocusRequest?,
        tuner: Tuner,
        actions: GuideActions
    ) {
        self.channels = channels
        self.focusRequest = focusRequest
        _isHeaderFocusable = isHeaderFocusable
        self.lineupRevision = lineupRevision
        self.tuner = tuner
        self.actions = actions
        _model = State(initialValue: GuideModel(channels: channels, focusedChannelID: tuner.channel?.id))
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            GuideHeader(
                isShowingNow: model.isShowingNow,
                windowStart: model.windowStart,
                focus: $focus,
                actions: actions,
                channel: model.focusedChannel,
                program: model.focusedProgram
            )
            .crtEffect(isFullScreen: false)
            .disabled(!isHeaderFocusable)
            .onMoveCommand { direction in
                switch direction {
                case .down: focusGrid()
                // The picture's controls sit outside the guide, below and left of Favorites.
                case .left where focus == .favorites: actions.onFocusLiveControls()
                default: break
                }
            }

            GuidePreviewPanel(tuner: tuner, channel: model.focusedChannel, program: model.focusedProgram)

            Button {
                if let channel = model.focusedChannel { actions.onTune(channel) }
            } label: {
                GuideGridView(model: model, tunedChannelID: tuner.channel?.id, showsFocus: focus == .grid)
            }
            .buttonStyle(InvisibleButtonStyle())
            .crtEffect(isFullScreen: false)
            .focused($focus, equals: .grid)
            .onMoveCommand(perform: handleGridMove)
            // Play/Pause is the shortcut to Search and Settings from any row.
            .onPlayPauseCommand(perform: focusHeader)
        }
        .screenBackground()
        .onExitCommand(perform: handleBack)
        .onAppear { focus = .grid }
        .onChange(of: lineupRevision) { model.replaceChannels(channels) }
        .onChange(of: channels.map(\.id)) { model.replaceChannels(channels) }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: GuideLayout.Time.followInterval)
                model.followLiveTime()
            }
        }
        .onChange(of: focusRequest) { _, request in
            switch request?.target {
            case .topBar: focusHeader()
            case .grid: focusGrid()
            case nil: break
            }
        }
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

    private func handleBack() {
        if focus == .grid {
            focusHeader()
        } else {
            actions.onClose()
        }
    }

    private func focusHeader() {
        isHeaderFocusable = true
        Task { @MainActor in
            focus = .search
        }
    }

    private func focusGrid() {
        focus = .grid
    }
}
#endif
