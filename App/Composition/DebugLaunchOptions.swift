import SwiftUI

/// Development-only launch options for testing and screenshots, read from
/// environment variables (set by a launch script, never shipped):
///
/// - `RETROGUIDE_DEV_OVERLAY`: open on `guide`, `search` or `settings`.
/// - `RETROGUIDE_DEV_SEARCH`: text to search for when Search opens.
/// - `RETROGUIDE_DEV_ORIENTATION`: `landscape` to start in landscape (iPhone and iPad).
///
/// Release builds always return the defaults.
enum DebugLaunchOptions {
    enum Overlay: String {
        case guide
        case search
        case settings
    }

    private enum Variable {
        static let overlay = "RETROGUIDE_DEV_OVERLAY"
        static let search = "RETROGUIDE_DEV_SEARCH"
        static let orientation = "RETROGUIDE_DEV_ORIENTATION"
    }

    private static let landscape = "landscape"

    static var overlay: Overlay? {
        value(for: Variable.overlay).flatMap(Overlay.init(rawValue:))
    }

    static var searchText: String {
        value(for: Variable.search) ?? ""
    }

    static var startsInLandscape: Bool {
        value(for: Variable.orientation) == landscape
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
    /// Rotates to landscape once at launch when ``DebugLaunchOptions`` asks for it.
    func debugLaunchOrientation() -> some View {
        onAppear {
            guard DebugLaunchOptions.startsInLandscape,
                  let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            else { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        }
    }
}
#endif
