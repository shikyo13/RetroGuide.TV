import AVFoundation

/// Sound timing for wireless speakers (HomePod, AirPlay) on tvOS 27 and later.
///
/// tvOS 27 times sound sent to these speakers itself, where earlier versions
/// left it to the player. Measured on an Apple TV 4K with a HomePod on
/// tvOS 27.2.1, filming a clip that flashes and beeps at the same instant:
/// - the player's old two-second head start put the sound 1.9 s late (the
///   libmpv patch drops the head start on tvOS 27);
/// - an audio output reused across a channel change stayed silent for about
///   20 s, so each file gets a new one;
/// - without `wirelessDelay` each channel start landed anywhere from in sync
///   to 0.25 s early; with it, starts land 0.01 to 0.15 s late, next to
///   Apple's own player (0.12 s late on the same setup).
///
/// Wired output (HDMI) measured in sync before and after, and stays as it was.
enum MPVAudioRouteTiming {
    /// How much later mpv plays sound on a wireless route (mpv's `audio-delay`, seconds).
    private static let wirelessDelay = "0.10"
    private static let noDelay = "0"

    /// Whether the system times wireless speakers itself.
    static var systemTimesWirelessRoutes: Bool {
        #if os(tvOS)
        if #available(tvOS 27.0, *) { return true }
        #endif
        return false
    }

    /// The `audio-delay` for the speakers sound is going to right now.
    static var audioDelay: String {
        guard systemTimesWirelessRoutes else { return noDelay }
        let isWireless = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .airPlay }
        return isWireless ? wirelessDelay : noDelay
    }
}
