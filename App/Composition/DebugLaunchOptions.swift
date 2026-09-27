import SwiftUI

/// Development-only launch options for testing and screenshots, read from
/// environment variables (set by a launch script, never shipped):
///
/// - `RETROGUIDE_DEV_OVERLAY`: open on `guide`, `search` or `settings`.
/// - `RETROGUIDE_DEV_SEARCH`: text to search for when Search opens.
/// - `RETROGUIDE_DEV_ORIENTATION`: `landscape` or `portrait` to start that way (iPhone).
/// - `RETROGUIDE_DEV_PRO`: `1` to act as if RetroGuide Pro were purchased.
/// - `RETROGUIDE_DEV_SETTINGS_PAGE`: `theme` or `pro` to open that page when
///   Settings opens (with `RETROGUIDE_DEV_OVERLAY=settings`).
/// - `RETROGUIDE_DEV_BANNER_SECONDS`: how long the info banner stays up after
///   tuning (for screenshots, so it's still showing once video starts).
/// - `RETROGUIDE_DEV_AUTOTUNE`: seconds after launch to tune the next channel
///   from the guide, as if it had been picked (for testing that path).
///
/// Release builds always return the defaults.
enum DebugLaunchOptions {
    enum Overlay: String {
        case guide
        case search
        case settings
    }

    enum SettingsPage: String {
        case theme
        case pro
    }

    private enum Variable {
        static let overlay = "RETROGUIDE_DEV_OVERLAY"
        static let search = "RETROGUIDE_DEV_SEARCH"
        static let orientation = "RETROGUIDE_DEV_ORIENTATION"
        static let pro = "RETROGUIDE_DEV_PRO"
        static let autoTune = "RETROGUIDE_DEV_AUTOTUNE"
        static let settingsPage = "RETROGUIDE_DEV_SETTINGS_PAGE"
        static let bannerSeconds = "RETROGUIDE_DEV_BANNER_SECONDS"
    }

    private static let landscape = "landscape"
    private static let portrait = "portrait"
    private static let enabled = "1"

    static var overlay: Overlay? {
        value(for: Variable.overlay).flatMap(Overlay.init(rawValue:))
    }

    static var searchText: String {
        value(for: Variable.search) ?? ""
    }

    static var startsInLandscape: Bool {
        value(for: Variable.orientation) == landscape
    }

    static var startsInPortrait: Bool {
        value(for: Variable.orientation) == portrait
    }

    static var bannerDuration: Duration? {
        value(for: Variable.bannerSeconds).flatMap(Double.init).map { .seconds($0) }
    }

    static var settingsPage: SettingsPage? {
        value(for: Variable.settingsPage).flatMap(SettingsPage.init(rawValue:))
    }

    static var autoTuneDelay: Duration? {
        value(for: Variable.autoTune).flatMap(Double.init).map { .seconds($0) }
    }

    static var forcesPro: Bool {
        value(for: Variable.pro) == enabled
    }

    private static func value(for variable: String) -> String? {
        #if DEBUG
        ProcessInfo.processInfo.environment[variable]
        #else
        nil
        #endif
    }
}

#if os(iOS)
extension View {
    /// Rotates once at launch when ``DebugLaunchOptions`` asks for an orientation.
    func debugLaunchOrientation() -> some View {
        onAppear {
            let orientations: UIInterfaceOrientationMask? =
                DebugLaunchOptions.startsInLandscape ? .landscapeRight :
                DebugLaunchOptions.startsInPortrait ? .portrait : nil
            guard let orientations, let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
        }
    }
}
#endif
