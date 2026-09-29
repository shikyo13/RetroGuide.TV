import RetroGuideKit
import SwiftUI

/// What the guide can ask of the watch screen.
struct GuideActions {
    let onTune: (Channel) -> Void
    let onClose: () -> Void
    let onOpenSearch: () -> Void
    let onOpenSettings: () -> Void
    /// Apple TV: move focus to the controls on the live picture (drawn outside the guide).
    var onFocusLiveControls: () -> Void = {}
}

/// Apple TV: asks the guide to move focus somewhere, from outside it (the
/// live picture's controls). Each request is new, so repeating one works.
struct GuideFocusRequest: Equatable {
    enum Target {
        case topBar
        case grid
    }

    let target: Target
    let serial: Int
}

/// The full-screen program guide: header, preview panel and channel grid,
/// driven by the Siri Remote on Apple TV and by touch on iPhone and iPad.
struct GuideView: View {
    let channels: [Channel]
    /// Changes whenever the lineup is rebuilt (schedules can change even when
    /// the channels don't), so an open guide picks up the new one.
    let lineupRevision: Int
    /// Apple TV: whether the top row can take focus (the grid has it otherwise).
    @Binding var isTopBarActive: Bool
    var focusRequest: GuideFocusRequest?
    let tuner: Tuner
    let actions: GuideActions

    var body: some View {
        #if os(tvOS)
        GuideRemoteView(
            channels: channels,
            lineupRevision: lineupRevision,
            isHeaderFocusable: $isTopBarActive,
            focusRequest: focusRequest,
            tuner: tuner,
            actions: actions
        )
        #else
        GuideTouchView(channels: channels, lineupRevision: lineupRevision, tuner: tuner, actions: actions)
        #endif
    }
}
