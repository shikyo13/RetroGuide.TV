import SwiftUI

/// The colors of the theme in use, saved by the app so the widget matches
/// it. Without one saved, the widget uses Classic Cable.
struct WidgetPalette: Codable, Sendable, Equatable {
    let backgroundTop: Color.Resolved
    let backgroundBottom: Color.Resolved
    let surface: Color.Resolved
    let accent: Color.Resolved
    let accentSecondary: Color.Resolved
    let textPrimary: Color.Resolved
    let textSecondary: Color.Resolved
    /// The on-screen channel number display.
    let osd: Color.Resolved
}

extension WhatsOnStore {
    private static let paletteKey = "whatsOnPalette"

    static var palette: WidgetPalette? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: paletteKey) else { return nil }
        return try? JSONDecoder().decode(WidgetPalette.self, from: data)
    }

    /// Saves `palette`; false when it's the one already saved.
    @discardableResult
    static func save(_ palette: WidgetPalette) -> Bool {
        guard palette != self.palette, let data = try? JSONEncoder().encode(palette) else { return false }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: paletteKey)
        return true
    }
}
