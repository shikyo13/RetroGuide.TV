import SwiftUI

/// Development-only launch options for testing and screenshots, read from
/// environment variables (set by a launch script, never shipped):
///
/// - `RETROGUIDE_DEV_OVERLAY`: open on `guide`, `search`, `settings` or `options`.
/// - `RETROGUIDE_DEV_SEARCH`: text to search for when Search opens.
/// - `RETROGUIDE_DEV_ORIENTATION`: `landscape` or `portrait` to start that way (iPhone).
/// - `RETROGUIDE_DEV_PRO`: `1` to act as if RetroGuide Pro were purchased.
/// - `RETROGUIDE_DEV_SETTINGS_PAGE`: `theme` or `pro` to open that page when
///   Settings opens (with `RETROGUIDE_DEV_OVERLAY=settings`).
/// - `RETROGUIDE_DEV_BANNER_SECONDS`: how long the info banner stays up after
///   tuning (for screenshots, so it's still showing once video starts).
/// - `RETROGUIDE_DEV_AUTOTUNE`: seconds after launch to tune the next channel
///   from the guide, as if it had been picked (for testing that path).
/// - `RETROGUIDE_DEV_PLAY_URL`: plays this URL whenever a channel is tuned,
///   to test specific files on a device.
/// - `RETROGUIDE_DEV_PLAY_START`: seconds into that file to start (default 60;
///   RetroGuide Player only, Apple Player starts at the beginning).
/// - `RETROGUIDE_DEV_AUDIO_PROBE`: `1` to record the audio route at launch and
///   write libmpv's log to Library/Caches (see ``AudioRouteProbe``).
///
/// - `RETROGUIDE_DEV_ATTRIBUTION_URL`: an HTTPS measurement service to use
///   instead of the real one (a local test server).
/// - `RETROGUIDE_DEV_RELINK_PLEX`: `1` to make Settings › Add a server › Plex
///   link the Plex account again instead of using the saved one, to test
///   sign-in on a set-up device without removing anything.
///
/// Release builds always return the defaults.
enum DebugLaunchOptions {
    enum Overlay: String {
        case guide
        case search
        case settings
        /// The Options panel over full-screen TV.
        case options
    }

    enum SettingsPage: String {
        case theme
        case pro
        case connection
        case channel
        case order
        case repeats
        case commercials
        case cloudSync
    }

    private enum Variable {
        static let overlay = "RETROGUIDE_DEV_OVERLAY"
        static let search = "RETROGUIDE_DEV_SEARCH"
        static let orientation = "RETROGUIDE_DEV_ORIENTATION"
        static let pro = "RETROGUIDE_DEV_PRO"
        static let autoTune = "RETROGUIDE_DEV_AUTOTUNE"
        static let settingsPage = "RETROGUIDE_DEV_SETTINGS_PAGE"
        static let bannerSeconds = "RETROGUIDE_DEV_BANNER_SECONDS"
        static let audioProbe = "RETROGUIDE_DEV_AUDIO_PROBE"
        static let playURL = "RETROGUIDE_DEV_PLAY_URL"
        static let playStart = "RETROGUIDE_DEV_PLAY_START"
        static let mute = "RETROGUIDE_DEV_MUTE"
        static let attributionURL = "RETROGUIDE_DEV_ATTRIBUTION_URL"
        static let relinkPlex = "RETROGUIDE_DEV_RELINK_PLEX"
        static let audioDelay = "RETROGUIDE_DEV_AUDIO_DELAY"
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

    /// Silent playback, so simulator runs don't fill the room with dialogue.
    static var isMuted: Bool {
        value(for: Variable.mute) == enabled
    }

    static var settingsPage: SettingsPage? {
        value(for: Variable.settingsPage).flatMap(SettingsPage.init(rawValue:))
    }

    static var autoTuneDelay: Duration? {
        value(for: Variable.autoTune).flatMap(Double.init).map { .seconds($0) }
    }

    static var playURLOverride: URL? {
        value(for: Variable.playURL).flatMap(URL.init(string:))
    }

    static var playStartOverride: String? {
        value(for: Variable.playStart).flatMap(Double.init).map { String($0) }
    }

    static var probesAudio: Bool {
        value(for: Variable.audioProbe) == enabled
    }

    static var forcesPro: Bool {
        value(for: Variable.pro) == enabled
    }

    static var attributionURL: String? {
        value(for: Variable.attributionURL)
    }

    /// Shifts the player's sound by this many seconds, to measure audio timing on a device.
    static var audioDelay: String? {
        value(for: Variable.audioDelay).flatMap(Double.init).map { String($0) }
    }

    static var relinksPlex: Bool {
        value(for: Variable.relinkPlex) == enabled
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
