import SwiftUI

/// The "Audio & Subtitles" button pinned to the guide's live picture.
struct LiveTracksButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Audio & Subtitles", systemImage: "captions.bubble")
                .font(Typography.caption)
        }
        #if os(tvOS)
        .buttonStyle(.retro)
        #else
        .buttonStyle(.retroIcon)
        .accessibilityLabel("Audio and subtitles")
        #endif
    }
}
