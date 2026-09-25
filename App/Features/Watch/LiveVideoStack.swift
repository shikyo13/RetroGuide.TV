import RetroTVKit
import SwiftUI

/// The live picture: the engine's video plus signal overlays (static,
/// intermission, no signal). Rendered once and moved between full screen and
/// the guide's preview window.
struct LiveVideoStack: View {
    let tuner: Tuner
    let isCompact: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            EngineVideoView(engine: tuner.engine)
            SignalOverlay(signal: tuner.signal, channel: tuner.channel, program: tuner.program)
            if isCompact, let channel = tuner.channel {
                Text("\(channel.number) \(channel.callSign)")
                    .font(Typography.callSign)
                    .foregroundStyle(theme.osd)
                    .padding(DesignTokens.Spacing.xs)
                    .background(.black.opacity(DesignTokens.Opacity.muted), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.small))
                    .padding(DesignTokens.Spacing.sm)
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isCompact ? DesignTokens.Radius.large : .zero, style: .continuous))
    }
}

/// Reports where the guide wants the live picture, in global (screen) coordinates.
struct LivePreviewFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}
