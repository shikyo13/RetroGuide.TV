import RetroGuideKit
import SwiftUI

/// Identifiers for the built-in themes, persisted in preferences.
enum ThemeID: String, Codable, CaseIterable, Identifiable, Sendable {
    case classicCable
    case localForecast
    case saturdayMorning
    case payPerView
    case woodPanel
    case vhs
    case synthwave
    case midnight
    case crtGreen
    case amber
    case teletext
    case mono

    var id: String { rawValue }

    /// The free version includes Classic Cable; every other theme is RetroGuide Pro.
    var isIncludedFree: Bool {
        self == .classicCable
    }
}

/// A complete color palette. Every color in the UI comes from the active theme.
struct Theme: Identifiable, Equatable {
    let id: ThemeID
    let name: String
    /// Top-to-bottom screen background gradient.
    let backgroundColors: [Color]
    /// Panels, list rows and guide cells.
    let surface: Color
    /// Alternate surface for zebra striping and headers.
    let surfaceRaised: Color
    /// Fill of the focused guide cell or button.
    let focusFill: Color
    let textPrimary: Color
    let textSecondary: Color
    /// Text on top of `focusFill`.
    let textOnFocus: Color
    /// Brand highlight: logo, channel numbers, progress.
    let accent: Color
    /// Secondary highlight: call signs, chips.
    let accentSecondary: Color
    /// The vertical "now" line in the guide.
    let nowLine: Color
    /// Color of the on-screen channel number overlay.
    let osd: Color
    let audienceColors: [Audience: Color]

    var backgroundGradient: LinearGradient {
        LinearGradient(colors: backgroundColors, startPoint: .top, endPoint: .bottom)
    }

    /// Dark backing for overlays drawn on top of video.
    var scrim: Color {
        (backgroundColors.last ?? .black).opacity(DesignTokens.Opacity.scrim)
    }

    func color(for audience: Audience) -> Color {
        audienceColors[audience] ?? textSecondary
    }

    static func == (lhs: Theme, rhs: Theme) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = ThemeCatalog.theme(for: .classicCable)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
