import SwiftUI

/// The widget's look: the Classic Cable theme's colors and the guide's type.
enum WidgetStyle {
    /// The widget's colors: the app's theme, or Classic Cable until one is saved.
    struct Colors {
        var backgroundTop = Color(hex: "#0A1A5C")
        var backgroundBottom = Color(hex: "#050D33")
        var surface = Color(hex: "#15287A")
        var accent = Color(hex: "#FFD23F")
        var accentSecondary = Color(hex: "#6EC6FF")
        var textPrimary = Color(hex: "#FFFFFF")
        var textSecondary = Color(hex: "#B8C4F0")
        /// The guide's channel-number display.
        var osd = Color(hex: "#7CFC00")

        static let classicCable = Colors()

        var background: LinearGradient {
            LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
        }
    }

    enum Motion {
        static let channelChange: TimeInterval = 0.18
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
    }

    enum Size {
        static let glyph: CGFloat = 26
        static let corner: CGFloat = 12
        static let smallLogoHeight: CGFloat = 34
        static let mediumLogoHeight: CGFloat = 40
        static let largeLogoHeight: CGFloat = 48
        static let largeHeroHeight: CGFloat = 150
        /// The episode still where the guide shows live video.
        static let stillAspect: CGFloat = 16.0 / 10.0
        static let stillOpacity: Double = 0.75
        static let backdropOpacity: Double = 0.6
        static let glowOpacity: Double = 0.6
        static let glowRadius: CGFloat = 4
        static let button: CGFloat = 44
        static let osdColumn: CGFloat = 74
        static let otherChannels = 3
        static let minimumScale: CGFloat = 0.7
    }

    enum Font {
        static let osd = SwiftUI.Font.system(size: 15, weight: .heavy, design: .monospaced)
        static let title = SwiftUI.Font.system(size: 18, weight: .bold, design: .rounded)
        static let episode = SwiftUI.Font.system(size: 14, weight: .bold)
        static let clock = SwiftUI.Font.system(size: 13, weight: .semibold, design: .monospaced)
        static let clockSmall = SwiftUI.Font.system(size: 12, weight: .semibold, design: .monospaced)
        static let detail = SwiftUI.Font.system(size: 12, weight: .medium)
        static let detailEmphasis = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let section = SwiftUI.Font.system(size: 11, weight: .heavy, design: .rounded)
        static let button = SwiftUI.Font.system(size: 13, weight: .bold)
        static let wordmark = SwiftUI.Font.system(size: 17, weight: .semibold, design: .rounded)
    }

}

extension WidgetStyle.Colors {
    init(_ palette: WidgetPalette) {
        self.init(
            backgroundTop: Color(palette.backgroundTop),
            backgroundBottom: Color(palette.backgroundBottom),
            surface: Color(palette.surface),
            accent: Color(palette.accent),
            accentSecondary: Color(palette.accentSecondary),
            textPrimary: Color(palette.textPrimary),
            textSecondary: Color(palette.textSecondary),
            osd: Color(palette.osd)
        )
    }
}
