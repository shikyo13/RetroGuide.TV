import SwiftUI

/// The "Options" button (audio, subtitles, schedule order) on the live picture.
struct WatchOptionsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Options", systemImage: "slider.horizontal.3")
                .font(Typography.caption)
        }
        #if os(tvOS)
        .buttonStyle(.retro)
        #else
        .buttonStyle(.retroIcon)
        .accessibilityLabel("Audio, subtitles and schedule order")
        #endif
    }
}
