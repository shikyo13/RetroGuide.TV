import RetroGuideKit
import SwiftUI

/// What the guide can ask of the watch screen.
struct GuideActions {
    let onTune: (Channel) -> Void
    let onClose: () -> Void
    let onOpenSearch: () -> Void
    let onOpenSettings: () -> Void
}

/// The full-screen program guide: header, preview panel and channel grid,
/// driven by the Siri Remote on Apple TV and by touch on iPhone and iPad.
struct GuideView: View {
    let channels: [Channel]
    let tuner: Tuner
    let actions: GuideActions

    var body: some View {
        #if os(tvOS)
        GuideRemoteView(channels: channels, tuner: tuner, actions: actions)
        #else
        GuideTouchView(channels: channels, tuner: tuner, actions: actions)
        #endif
    }
}
