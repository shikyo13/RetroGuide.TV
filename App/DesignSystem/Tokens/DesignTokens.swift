import SwiftUI

/// Layout, shape and motion constants shared by every screen.
/// Views must use these instead of literal numbers.
enum DesignTokens {
    enum Spacing {
        static let hairline: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 20
        static let lg: CGFloat = 32
        static let xl: CGFloat = 48
        static let xxl: CGFloat = 72
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 14
        static let large: CGFloat = 24
        static let pill: CGFloat = 999
    }

    enum Stroke {
        static let thin: CGFloat = 2
        static let focus: CGFloat = 4
    }

    enum Opacity {
        static let faint: Double = 0.08
        static let subtle: Double = 0.18
        static let muted: Double = 0.45
        static let strong: Double = 0.75
        static let scrim: Double = 0.85
    }

    enum Shadow {
        static let radius: CGFloat = 18
        static let offsetY: CGFloat = 8
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

        static var quickEase: Animation { .easeOut(duration: quick) }
        static var standardEase: Animation { .easeInOut(duration: standard) }
        static var relaxedEase: Animation { .easeInOut(duration: relaxed) }
    }
}
