import RetroGuideKit
import SwiftUI

/// The built-in themes. Hex values here are the single source of truth for color.
enum ThemeCatalog {
    static let all: [Theme] = ThemeID.allCases.map(theme(for:))

    static func theme(for id: ThemeID) -> Theme {
        switch id {
        case .classicCable: classicCable
        case .midnight: midnight
        case .crtGreen: crtGreen
        case .amber: amber
        case .synthwave: synthwave
        case .mono: mono
        }
    }

    private static let standardAudienceColors: [Audience: Color] = [
        .kids: Color(hex: "#4CD964"),
        .family: Color(hex: "#5AC8FA"),
        .teen: Color(hex: "#FFCC00"),
        .mature: Color(hex: "#FF3B30"),
        .unrated: Color(hex: "#8E8E93"),
    ]

    /// Late-90s cable preview channel: deep blue grid, golden text.
    private static let classicCable = Theme(
        id: .classicCable,
        name: "Classic Cable",
        backgroundColors: [Color(hex: "#0A1A5C"), Color(hex: "#050D33")],
        surface: Color(hex: "#15287A"),
        surfaceRaised: Color(hex: "#1D3494"),
        focusFill: Color(hex: "#FFD23F"),
        textPrimary: Color(hex: "#FFFFFF"),
        textSecondary: Color(hex: "#B8C4F0"),
        textOnFocus: Color(hex: "#0A1A5C"),
        accent: Color(hex: "#FFD23F"),
        accentSecondary: Color(hex: "#6EC6FF"),
        nowLine: Color(hex: "#FF4D4D"),
        osd: Color(hex: "#7CFC00"),
        audienceColors: standardAudienceColors
    )

    private static let midnight = Theme(
        id: .midnight,
        name: "Midnight",
        backgroundColors: [Color(hex: "#10141F"), Color(hex: "#05070C")],
        surface: Color(hex: "#1B2130"),
        surfaceRaised: Color(hex: "#242C3F"),
        focusFill: Color(hex: "#3DD6F5"),
        textPrimary: Color(hex: "#F2F5FA"),
        textSecondary: Color(hex: "#8D98B0"),
        textOnFocus: Color(hex: "#05070C"),
        accent: Color(hex: "#3DD6F5"),
        accentSecondary: Color(hex: "#A78BFA"),
        nowLine: Color(hex: "#F472B6"),
        osd: Color(hex: "#3DD6F5"),
        audienceColors: standardAudienceColors
    )

    private static let crtGreen = Theme(
        id: .crtGreen,
        name: "CRT Green",
        backgroundColors: [Color(hex: "#031A08"), Color(hex: "#000A02")],
        surface: Color(hex: "#062B10"),
        surfaceRaised: Color(hex: "#0A3A17"),
        focusFill: Color(hex: "#39FF6A"),
        textPrimary: Color(hex: "#B6FFC6"),
        textSecondary: Color(hex: "#4FB76A"),
        textOnFocus: Color(hex: "#001A06"),
        accent: Color(hex: "#39FF6A"),
        accentSecondary: Color(hex: "#9CFFB3"),
        nowLine: Color(hex: "#FFFFFF"),
        osd: Color(hex: "#39FF6A"),
        audienceColors: [
            .kids: Color(hex: "#9CFFB3"), .family: Color(hex: "#6BFF8E"), .teen: Color(hex: "#39FF6A"),
            .mature: Color(hex: "#1FCC4D"), .unrated: Color(hex: "#4FB76A"),
        ]
    )

    private static let amber = Theme(
        id: .amber,
        name: "Amber Terminal",
        backgroundColors: [Color(hex: "#1A0F00"), Color(hex: "#0A0600")],
        surface: Color(hex: "#2B1A02"),
        surfaceRaised: Color(hex: "#3A2405"),
        focusFill: Color(hex: "#FFB000"),
        textPrimary: Color(hex: "#FFD27A"),
        textSecondary: Color(hex: "#C08A2E"),
        textOnFocus: Color(hex: "#1A0F00"),
        accent: Color(hex: "#FFB000"),
        accentSecondary: Color(hex: "#FFD27A"),
        nowLine: Color(hex: "#FFF3D6"),
        osd: Color(hex: "#FFB000"),
        audienceColors: [
            .kids: Color(hex: "#FFE3A3"), .family: Color(hex: "#FFD27A"), .teen: Color(hex: "#FFB000"),
            .mature: Color(hex: "#FF7A00"), .unrated: Color(hex: "#C08A2E"),
        ]
    )

    private static let synthwave = Theme(
        id: .synthwave,
        name: "Synthwave",
        backgroundColors: [Color(hex: "#2B0A4A"), Color(hex: "#12021F")],
        surface: Color(hex: "#3A1363"),
        surfaceRaised: Color(hex: "#4A1B7D"),
        focusFill: Color(hex: "#FF4FD8"),
        textPrimary: Color(hex: "#FFF0FF"),
        textSecondary: Color(hex: "#C9A3E8"),
        textOnFocus: Color(hex: "#12021F"),
        accent: Color(hex: "#FF4FD8"),
        accentSecondary: Color(hex: "#3DF5F5"),
        nowLine: Color(hex: "#3DF5F5"),
        osd: Color(hex: "#3DF5F5"),
        audienceColors: standardAudienceColors
    )

    private static let mono = Theme(
        id: .mono,
        name: "Mono",
        backgroundColors: [Color(hex: "#1C1C1E"), Color(hex: "#000000")],
        surface: Color(hex: "#2C2C2E"),
        surfaceRaised: Color(hex: "#3A3A3C"),
        focusFill: Color(hex: "#F2F2F7"),
        textPrimary: Color(hex: "#FFFFFF"),
        textSecondary: Color(hex: "#98989F"),
        textOnFocus: Color(hex: "#000000"),
        accent: Color(hex: "#FFFFFF"),
        accentSecondary: Color(hex: "#C7C7CC"),
        nowLine: Color(hex: "#FF453A"),
        osd: Color(hex: "#FFFFFF"),
        audienceColors: [
            .kids: Color(hex: "#E5E5EA"), .family: Color(hex: "#C7C7CC"), .teen: Color(hex: "#AEAEB2"),
            .mature: Color(hex: "#8E8E93"), .unrated: Color(hex: "#636366"),
        ]
    )
}
