import SwiftUI
import UIKit
#if os(iOS)
import WidgetKit
#endif

/// Carries the theme onto the home screen: the app icon in the theme's
/// colors, and the What's On widget's palette.
@MainActor
enum HomeScreenTheme {
    /// Alternate icons are named after their theme (see `Tools/BrandAssets`);
    /// Classic Cable is the primary icon.
    private static let iconPrefix = PlatformMetric.value(tv: "TVAppIcon-", touch: "AppIcon-")

    static func apply(_ theme: Theme) {
        applyIcon(theme.id)
        #if os(iOS)
        if WhatsOnStore.save(palette(for: theme)) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }

    /// Changes the icon only when it differs: the system tells the viewer each time it changes.
    private static func applyIcon(_ id: ThemeID) {
        let application = UIApplication.shared
        let name = id.isIncludedFree ? nil : iconPrefix + id.rawValue
        guard application.supportsAlternateIcons, application.alternateIconName != name else { return }
        application.setAlternateIconName(name)
    }

    #if os(iOS)
    private static func palette(for theme: Theme) -> WidgetPalette {
        let environment = EnvironmentValues()
        func resolved(_ color: Color?) -> Color.Resolved {
            (color ?? .black).resolve(in: environment)
        }
        return WidgetPalette(
            backgroundTop: resolved(theme.backgroundColors.first),
            backgroundBottom: resolved(theme.backgroundColors.last),
            surface: resolved(theme.surface),
            accent: resolved(theme.accent),
            accentSecondary: resolved(theme.accentSecondary),
            textPrimary: resolved(theme.textPrimary),
            textSecondary: resolved(theme.textSecondary),
            osd: resolved(theme.osd)
        )
    }
    #endif
}
