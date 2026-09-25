import RetroGuideKit
import SwiftUI

/// The live picture: the engine's video plus signal overlays (static,
/// intermission, no signal), full screen or scaled into the guide preview or
/// picture-in-picture window.
///
/// The video renders into a constant-size surface (``WatchLayout/videoSurfaceSize``)
/// that is only ever *scaled*, so the engine never reconfigures and moving the
/// picture, or rotating the device, is a cheap GPU transform. The overlays are
/// SwiftUI and lay out at screen size so their text stays readable.
struct LiveVideoStack: View {
    let tuner: Tuner
    /// Where the picture should appear, or `nil` for full screen.
    let window: CGRect?
    let screen: CGSize

    @Environment(\.theme) private var theme

    var body: some View {
        let picture = Self.pictureArea(in: screen)
        ZStack(alignment: .topLeading) {
            video(fittingIn: window ?? picture)
            overlays(picture: picture)
            if let window, let channel = tuner.channel {
                channelLabel(channel)
                    .offset(x: window.minX, y: window.minY)
                    .transition(.opacity)
            }
        }
        .frame(width: screen.width, height: screen.height, alignment: .topLeading)
    }

    /// The engine's surface, scaled into `target` (a 16:9 rectangle).
    private func video(fittingIn target: CGRect) -> some View {
        let surface = WatchLayout.videoSurfaceSize
        let scale = target.width / max(surface.width, 1)
        return EngineVideoView(engine: tuner.engine)
            .frame(width: surface.width, height: surface.height)
            // Corner radius is specified before scaling, so divide to get the on-screen radius.
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius / scale, style: .continuous))
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: target.minX, y: target.minY)
    }

    /// Signal overlays: full screen, or their picture area scaled into the window.
    private func overlays(picture: CGRect) -> some View {
        let scale = window.map { $0.width / max(picture.width, 1) } ?? 1
        let origin = window.map { CGPoint(x: $0.minX - picture.minX * scale, y: $0.minY - picture.minY * scale) } ?? .zero
        return SignalOverlay(signal: tuner.signal, channel: tuner.channel, program: tuner.program)
            .frame(width: screen.width, height: screen.height)
            .mask(alignment: .topLeading) {
                if window == nil {
                    Rectangle()
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius / scale, style: .continuous)
                        .frame(width: picture.width, height: picture.height)
                        .offset(x: picture.minX, y: picture.minY)
                }
            }
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: origin.x, y: origin.y)
    }

    private var cornerRadius: CGFloat {
        window == nil ? .zero : DesignTokens.Radius.large
    }

    /// The largest 16:9 rectangle centered in `screen`: where the video appears.
    static func pictureArea(in screen: CGSize) -> CGRect {
        let aspectRatio = WatchLayout.pictureInPictureAspectRatio
        let width = min(screen.width, screen.height * aspectRatio)
        let height = width / aspectRatio
        return CGRect(x: (screen.width - width) / 2, y: (screen.height - height) / 2, width: width, height: height)
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
