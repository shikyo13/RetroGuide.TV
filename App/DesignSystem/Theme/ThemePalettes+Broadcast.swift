import RetroGuideKit
import SwiftUI

// Themes inspired by cable and broadcast TV.
extension ThemePalettes {
    /// Late-90s cable preview channel: deep blue grid, golden text.
    static let classicCable = Theme(
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

    /// Early-90s weather channel: teal panels, orange highlights.
    static let localForecast = Theme(
        id: .localForecast,
        name: "Local Forecast",
        backgroundColors: [Color(hex: "#0B4F6C"), Color(hex: "#042536")],
        surface: Color(hex: "#106887"),
        surfaceRaised: Color(hex: "#1580A3"),
        focusFill: Color(hex: "#FFA62B"),
        textPrimary: Color(hex: "#FFFFFF"),
        textSecondary: Color(hex: "#B3E0F0"),
        textOnFocus: Color(hex: "#042536"),
        accent: Color(hex: "#FFA62B"),
        accentSecondary: Color(hex: "#5CE1E6"),
        nowLine: Color(hex: "#FF5A5F"),
        osd: Color(hex: "#FFFFFF"),
        audienceColors: standardAudienceColors
    )

    /// Cartoon-block purple with sunny yellow and orange.
    static let saturdayMorning = Theme(
        id: .saturdayMorning,
        name: "Saturday Morning",
        backgroundColors: [Color(hex: "#4B1FA8"), Color(hex: "#22094F")],
        surface: Color(hex: "#5E2BC4"),
        surfaceRaised: Color(hex: "#7038D6"),
        focusFill: Color(hex: "#FFC93C"),
        textPrimary: Color(hex: "#FFFFFF"),
        textSecondary: Color(hex: "#D8C8FF"),
        textOnFocus: Color(hex: "#2A0B5E"),
        accent: Color(hex: "#FF7A30"),
        accentSecondary: Color(hex: "#3DDC97"),
        nowLine: Color(hex: "#FF3D7F"),
        osd: Color(hex: "#FFC93C"),
        audienceColors: standardAudienceColors
    )

    /// Hotel-room movie menu: velvet maroon and gold.
    static let payPerView = Theme(
        id: .payPerView,
        name: "Pay-Per-View",
        backgroundColors: [Color(hex: "#4A0E24"), Color(hex: "#1E0510")],
        surface: Color(hex: "#62142F"),
        surfaceRaised: Color(hex: "#781B3B"),
        focusFill: Color(hex: "#E9C46A"),
        textPrimary: Color(hex: "#FFF6F0"),
        textSecondary: Color(hex: "#E6B3C2"),
        textOnFocus: Color(hex: "#2A0714"),
        accent: Color(hex: "#E9C46A"),
        accentSecondary: Color(hex: "#F4A6B8"),
        nowLine: Color(hex: "#FFFFFF"),
        osd: Color(hex: "#E9C46A"),
        audienceColors: standardAudienceColors
    )
}
