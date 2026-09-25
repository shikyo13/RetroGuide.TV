import Foundation

/// The dynamic range of a playing video, as the player outputs it.
///
/// Dolby Vision files are rendered by the player using their metadata and
/// output as PQ, so they count as ``hdr10`` here.
public enum VideoDynamicRange: String, Codable, Sendable {
    case sdr
    /// PQ (SMPTE ST 2084): HDR10, HDR10+ and Dolby Vision.
    case hdr10
    /// Hybrid Log-Gamma, mostly broadcast HDR.
    case hlg

    public var isHDR: Bool {
        self != .sdr
    }
}

/// What the player reports about a video once it starts.
public struct VideoFormat: Equatable, Sendable {
    public let dynamicRange: VideoDynamicRange
    /// Frames per second, when known.
    public let frameRate: Double?

    public init(dynamicRange: VideoDynamicRange, frameRate: Double?) {
        self.dynamicRange = dynamicRange
        self.frameRate = frameRate
    }
}

/// An output mode to ask the TV for.
public struct DisplayModeRequest: Equatable, Sendable {
    public let dynamicRange: VideoDynamicRange
    /// The refresh rate to switch to, or `nil` to keep the current one.
    public let refreshRate: Double?

    public init(dynamicRange: VideoDynamicRange, refreshRate: Double?) {
        self.dynamicRange = dynamicRange
        self.refreshRate = refreshRate
    }
}

/// How far the app may switch the TV's output mode to match what's playing
/// (Apple TV; it also needs Match Content turned on in the system settings).
///
/// Each switch blanks the TV for a moment, which matters when channel surfing,
/// so matching frame rates is optional.
public enum DisplayMatching: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    /// Switch to HDR for HDR programs; everything else uses the TV's usual mode.
    case dynamicRange
    /// Also switch the refresh rate to each program's frame rate.
    case dynamicRangeAndFrameRate

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .dynamicRange: "HDR"
        case .dynamicRangeAndFrameRate: "HDR and frame rate"
        }
    }

    public var explanation: String {
        switch self {
        case .off:
            "Always use the Apple TV's usual output. HDR programs are converted to standard range."
        case .dynamicRange:
            "Switch the TV to HDR for HDR programs. Recommended: switches only happen when the dynamic range changes."
        case .dynamicRangeAndFrameRate:
            "Also match each program's frame rate for the smoothest motion. The TV blanks briefly more often while you change channels."
        }
    }

    /// The mode to request for `format`, or `nil` to use the TV's usual mode.
    public func request(for format: VideoFormat?) -> DisplayModeRequest? {
        guard let format else { return nil }
        switch self {
        case .off:
            return nil
        case .dynamicRange:
            guard format.dynamicRange.isHDR else { return nil }
            return DisplayModeRequest(dynamicRange: format.dynamicRange, refreshRate: nil)
        case .dynamicRangeAndFrameRate:
            return DisplayModeRequest(dynamicRange: format.dynamicRange, refreshRate: format.frameRate)
        }
    }
}
