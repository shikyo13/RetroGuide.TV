import SwiftUI

/// The built-in themes in picker order.
enum ThemeCatalog {
    static let all: [Theme] = ThemeID.allCases.map(theme(for:))

    static func theme(for id: ThemeID) -> Theme {
        switch id {
        case .classicCable: ThemePalettes.classicCable
        case .localForecast: ThemePalettes.localForecast
        case .saturdayMorning: ThemePalettes.saturdayMorning
        case .payPerView: ThemePalettes.payPerView
        case .woodPanel: ThemePalettes.woodPanel
        case .vhs: ThemePalettes.vhs
        case .synthwave: ThemePalettes.synthwave
        case .midnight: ThemePalettes.midnight
        case .crtGreen: ThemePalettes.crtGreen
        case .amber: ThemePalettes.amber
        case .teletext: ThemePalettes.teletext
        case .mono: ThemePalettes.mono
        }
    }
}
