import SwiftUI
import UIKit

/// Geometry of the live picture when it shrinks to picture-in-picture over menus.
enum WatchLayout {
    /// PiP width as a fraction of the screen width: a quarter on landscape
    /// screens (always the case on Apple TV), more on a phone held upright.
    static let pictureInPictureWidthFraction: CGFloat = 0.25
    static let portraitPictureInPictureWidthFraction: CGFloat = 0.34
    static let pictureInPictureAspectRatio: CGFloat = 16 / 9

    /// The video engine's rendering surface: 16:9 at the display's long side.
    ///
    /// It depends only on the display, never on rotation or window size, so the
    /// engine never has to resize (libmpv's Metal context only picks up a new
    /// size when a file loads). The surface is scaled to fit instead. On Apple
    /// TV this is exactly the screen.
    @MainActor
    static var videoSurfaceSize: CGSize {
        let bounds = UIScreen.main.bounds
        let longSide = max(bounds.width, bounds.height)
        return CGSize(width: longSide, height: longSide / pictureInPictureAspectRatio)
    }
    /// Distance from the screen edges: the tvOS overscan-safe margins, or a
    /// small gap inside the safe area on iPhone and iPad.
    static let pictureInPictureHorizontalInset = PlatformMetric.value(tv: CGFloat(80), touch: 16)
    static let pictureInPictureVerticalInset = PlatformMetric.value(tv: CGFloat(60), touch: 16)

    /// The PiP window in the bottom-right corner of `screen`, kept inside `safeArea`
    /// (the notch and home indicator on iPhone; Apple TV passes none, as its
    /// insets already cover overscan).
    static func pictureInPictureFrame(in screen: CGSize, safeArea: EdgeInsets = EdgeInsets()) -> CGRect {
        let width = pictureInPictureWidth(in: screen)
        let height = width / pictureInPictureAspectRatio
        return CGRect(
            x: screen.width - safeArea.trailing - pictureInPictureHorizontalInset - width,
            y: screen.height - safeArea.bottom - pictureInPictureVerticalInset - height,
            width: width,
            height: height
        )
    }

    /// Scrolling content under the PiP window needs this much room at the
    /// bottom on iPhone and iPad so its last rows can be scrolled clear of it.
    static func pictureInPictureClearance(in screen: CGSize) -> CGFloat {
        #if os(tvOS)
        // Apple TV menus are laid out beside the PiP window instead.
        .zero
        #else
        pictureInPictureWidth(in: screen) / pictureInPictureAspectRatio + pictureInPictureVerticalInset * 2
        #endif
    }

    private static func pictureInPictureWidth(in screen: CGSize) -> CGFloat {
        let isPortrait = screen.height > screen.width
        return screen.width * (isPortrait ? portraitPictureInPictureWidthFraction : pictureInPictureWidthFraction)
    }
}

extension EnvironmentValues {
    /// Bottom room scrolling menus should leave for the picture-in-picture window.
    @Entry var pictureInPictureClearance: CGFloat = .zero
}
