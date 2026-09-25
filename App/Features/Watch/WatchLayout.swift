import CoreGraphics

/// Geometry of the live picture when it shrinks to picture-in-picture over menus.
enum WatchLayout {
    /// PiP width as a fraction of the screen width.
    static let pictureInPictureWidthFraction: CGFloat = 0.25
    static let pictureInPictureAspectRatio: CGFloat = 16 / 9
    /// Distance from the screen edges: the tvOS overscan-safe margins.
    static let pictureInPictureHorizontalInset: CGFloat = 80
    static let pictureInPictureVerticalInset: CGFloat = 60

    static func pictureInPictureFrame(in screen: CGSize) -> CGRect {
        let width = screen.width * pictureInPictureWidthFraction
        let height = width / pictureInPictureAspectRatio
        return CGRect(
            x: screen.width - pictureInPictureHorizontalInset - width,
            y: screen.height - pictureInPictureVerticalInset - height,
            width: width,
            height: height
        )
    }
}
