import RetroGuideKit
import SwiftUI

/// The live picture: the engine's video plus signal overlays (static,
/// intermission, no signal).
///
/// It is always laid out at full-screen size and *scaled* into the guide
/// preview or picture-in-picture window. Keeping the rendering surface a
/// constant size means the video engine never has to reconfigure, and moving
/// the picture is a cheap, smooth GPU transform.
struct LiveVideoStack: View {
    let tuner: Tuner
    /// Where the picture should appear, or `nil` for full screen.
    let window: CGRect?
    let screen: CGSize

    @Environment(\.theme) private var theme

    var body: some View {
        let scale = window.map { $0.width / max(screen.width, 1) } ?? 1
        let origin = window?.origin ?? .zero
        ZStack(alignment: .topLeading) {
            ZStack {
                EngineVideoView(engine: tuner.engine)
                SignalOverlay(signal: tuner.signal, channel: tuner.channel, program: tuner.program)
            }
            .frame(width: screen.width, height: screen.height)
            // Corner radius is specified before scaling, so divide to get the on-screen radius.
            .clipShape(RoundedRectangle(cornerRadius: window == nil ? .zero : DesignTokens.Radius.large / scale, style: .continuous))
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: origin.x, y: origin.y)

            if let window, let channel = tuner.channel {
                channelLabel(channel)
                    .offset(x: window.minX, y: window.minY)
                    .transition(.opacity)
            }
        }
        .frame(width: screen.width, height: screen.height, alignment: .topLeading)
    }

    private func channelLabel(_ channel: Channel) -> some View {
        Text("\(channel.number) \(channel.callSign)")
            .font(Typography.callSign)
            .foregroundStyle(theme.osd)
            .padding(DesignTokens.Spacing.xs)
            .background(.black.opacity(DesignTokens.Opacity.muted), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.small))
            .padding(DesignTokens.Spacing.sm)
    }
}

/// Reports where the guide wants the live picture, in global (screen) coordinates.
struct LivePreviewFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}
