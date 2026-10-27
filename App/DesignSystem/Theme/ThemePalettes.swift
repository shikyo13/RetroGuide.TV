import RetroGuideKit
import SwiftUI

/// Color definitions for the built-in themes, grouped by inspiration in
/// extension files. Hex values here are the single source of truth for color.
enum ThemePalettes {
    static let standardAudienceColors: [Audience: Color] = [
        .kids: Color(hex: "#4CD964"),
        .family: Color(hex: "#5AC8FA"),
        .teen: Color(hex: "#FFCC00"),
        .mature: Color(hex: "#FF3B30"),
        .unrated: Color(hex: "#8E8E93"),
    ]
}
