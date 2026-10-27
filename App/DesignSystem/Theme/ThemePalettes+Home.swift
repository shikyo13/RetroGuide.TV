import RetroGuideKit
import SwiftUI

// Themes inspired by TV sets and tapes at home.
extension ThemePalettes {
    /// A 70s console set in the den: walnut, harvest gold and rust.
    static let woodPanel = Theme(
        id: .woodPanel,
        name: "Wood Paneling",
        backgroundColors: [Color(hex: "#4A2C17"), Color(hex: "#22130A")],
        surface: Color(hex: "#5E3A1F"),
        surfaceRaised: Color(hex: "#704627"),
        focusFill: Color(hex: "#F2A541"),
        textPrimary: Color(hex: "#FFF4E2"),
        textSecondary: Color(hex: "#D8B48F"),
        textOnFocus: Color(hex: "#2B170A"),
        accent: Color(hex: "#F2A541"),
        accentSecondary: Color(hex: "#E4572E"),
        nowLine: Color(hex: "#F7E07A"),
        osd: Color(hex: "#F7E07A"),
        audienceColors: [
            .kids: Color(hex: "#9BC53D"), .family: Color(hex: "#F7E07A"), .teen: Color(hex: "#F2A541"),
            .mature: Color(hex: "#E4572E"), .unrated: Color(hex: "#B08968"),
        ]
    )

    /// Late-night tape: near-black with tracking-error red and cyan.
    static let vhs = Theme(
        id: .vhs,
        name: "VHS",
        backgroundColors: [Color(hex: "#15131F"), Color(hex: "#07060B")],
        surface: Color(hex: "#221F31"),
        surfaceRaised: Color(hex: "#2D2941"),
        focusFill: Color(hex: "#FF3B5C"),
        textPrimary: Color(hex: "#F4F1FF"),
        textSecondary: Color(hex: "#A39DC2"),
        textOnFocus: Color(hex: "#0B0A12"),
        accent: Color(hex: "#FF3B5C"),
        accentSecondary: Color(hex: "#3BE8FF"),
        nowLine: Color(hex: "#3BE8FF"),
        osd: Color(hex: "#FFFFFF"),
        audienceColors: standardAudienceColors
    )

    static let synthwave = Theme(
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

    static let midnight = Theme(
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
}
