import RetroGuideKit
import SwiftUI

// Themes inspired by text displays and monochrome screens.
extension ThemePalettes {
    static let crtGreen = Theme(
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

    static let amber = Theme(
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

    /// Broadcast text pages: pure black with primary-color blocks.
    static let teletext = Theme(
        id: .teletext,
        name: "Teletext",
        backgroundColors: [Color(hex: "#050505"), Color(hex: "#000000")],
        surface: Color(hex: "#0018A8"),
        surfaceRaised: Color(hex: "#0022CC"),
        focusFill: Color(hex: "#FFFF00"),
        textPrimary: Color(hex: "#FFFFFF"),
        textSecondary: Color(hex: "#00FFFF"),
        textOnFocus: Color(hex: "#000000"),
        accent: Color(hex: "#FFFF00"),
        accentSecondary: Color(hex: "#00FF00"),
        nowLine: Color(hex: "#FF0000"),
        osd: Color(hex: "#FFFF00"),
        audienceColors: [
            .kids: Color(hex: "#00FF00"), .family: Color(hex: "#00FFFF"), .teen: Color(hex: "#FFFF00"),
            .mature: Color(hex: "#FF0000"), .unrated: Color(hex: "#FF00FF"),
        ]
    )

    static let mono = Theme(
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
