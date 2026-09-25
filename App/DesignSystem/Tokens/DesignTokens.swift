import SwiftUI

/// Layout, shape and motion constants shared by every screen.
/// Views must use these instead of literal numbers. Sizes have an Apple TV
/// value and a smaller touch value for iPhone and iPad (see ``PlatformMetric``).
enum DesignTokens {
    enum Spacing {
        static let hairline = PlatformMetric.value(tv: CGFloat(2), touch: 1)
        static let xxs = PlatformMetric.value(tv: CGFloat(4), touch: 2)
        static let xs = PlatformMetric.value(tv: CGFloat(8), touch: 6)
        static let sm = PlatformMetric.value(tv: CGFloat(12), touch: 8)
        static let md = PlatformMetric.value(tv: CGFloat(20), touch: 12)
        static let lg = PlatformMetric.value(tv: CGFloat(32), touch: 20)
        static let xl = PlatformMetric.value(tv: CGFloat(48), touch: 28)
        static let xxl = PlatformMetric.value(tv: CGFloat(72), touch: 40)
    }

    enum Radius {
        static let small = PlatformMetric.value(tv: CGFloat(8), touch: 6)
        static let medium = PlatformMetric.value(tv: CGFloat(14), touch: 10)
        static let large = PlatformMetric.value(tv: CGFloat(24), touch: 16)
        static let pill: CGFloat = 999
    }

    enum Stroke {
        static let thin = PlatformMetric.value(tv: CGFloat(2), touch: 1)
        static let focus = PlatformMetric.value(tv: CGFloat(4), touch: 2)
    }

    enum Opacity {
        static let faint: Double = 0.08
        static let subtle: Double = 0.18
        static let muted: Double = 0.45
        static let strong: Double = 0.75
        static let scrim: Double = 0.85
    }

    enum Shadow {
        static let radius = PlatformMetric.value(tv: CGFloat(18), touch: 10)
        static let offsetY = PlatformMetric.value(tv: CGFloat(8), touch: 4)
        static let opacity: Double = 0.45
    }

    enum Scale {
        static let focused: CGFloat = 1.04
        static let pressed: CGFloat = 0.97
    }

    enum Motion {
        static let quick: Double = 0.15
        static let standard: Double = 0.25
        static let relaxed: Double = 0.45

        /// Spring used when the live picture moves between full screen and a window.
        static let pictureInPictureDuration: Double = 0.5
        static let pictureInPictureBounce: Double = 0.12

        static var quickEase: Animation { .easeOut(duration: quick) }
        static var pictureInPicture: Animation {
            .spring(duration: pictureInPictureDuration, bounce: pictureInPictureBounce)
        }
        static var standardEase: Animation { .easeInOut(duration: standard) }
        static var relaxedEase: Animation { .easeInOut(duration: relaxed) }
    }
}
