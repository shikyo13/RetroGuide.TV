#if os(tvOS)
import AVKit
import CoreMedia
import RetroGuideKit
import UIKit

/// Asks the TV to switch output mode (HDR and refresh rate) to match what's
/// playing, the way Apple's own player does with Match Content.
///
/// The system only switches when Match Content is turned on in the Apple TV's
/// Settings → Video and Audio; ``isSystemMatchingEnabled`` reports that.
@MainActor
final class DisplayModeController {
    /// Describes a 4K HEVC stream; tvOS reads the dynamic range from its color tags.
    private enum Stream {
        static let codec = kCMVideoCodecType_HEVC
        static let width: Int32 = 3840
        static let height: Int32 = 2160
    }

    private var applied: DisplayModeRequest?
    private var hasApplied = false

    /// Whether the Apple TV lets apps switch its output mode.
    static var isSystemMatchingEnabled: Bool {
        displayManager?.isDisplayCriteriaMatchingEnabled ?? false
    }

    /// Requests the mode for `format` under `matching`. Returns whether the TV
    /// is being put in an HDR mode, so the player should output HDR as HDR.
    func update(format: VideoFormat?, matching: DisplayMatching) -> Bool {
        guard let manager = Self.displayManager else { return false }
        let request = manager.isDisplayCriteriaMatchingEnabled ? matching.request(for: format) : nil
        if !hasApplied || request != applied {
            manager.preferredDisplayCriteria = request.flatMap(Self.criteria)
            applied = request
            hasApplied = true
        }
        return request?.dynamicRange.isHDR == true
    }

    /// Returns the TV to its usual mode.
    func reset() {
        Self.displayManager?.preferredDisplayCriteria = nil
        applied = nil
        hasApplied = false
    }

    private static var displayManager: AVDisplayManager? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first,
              window.responds(to: #selector(getter: UIWindow.avDisplayManager))
        else { return nil }
        return window.avDisplayManager
    }

    private static func criteria(for request: DisplayModeRequest) -> AVDisplayCriteria? {
        guard let description = formatDescription(for: request.dynamicRange) else { return nil }
        // Without a frame rate to match, ask for the rate the TV is already using.
        let refreshRate = request.refreshRate ?? Double(UIScreen.main.maximumFramesPerSecond)
        return AVDisplayCriteria(refreshRate: Float(refreshRate), formatDescription: description)
    }

    private static func formatDescription(for dynamicRange: VideoDynamicRange) -> CMFormatDescription? {
        let (transfer, primaries, matrix): (CFString, CFString, CFString) = switch dynamicRange {
        case .sdr:
            (kCMFormatDescriptionTransferFunction_ITU_R_709_2, kCMFormatDescriptionColorPrimaries_ITU_R_709_2, kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2)
        case .hdr10:
            (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ, kCMFormatDescriptionColorPrimaries_ITU_R_2020, kCMFormatDescriptionYCbCrMatrix_ITU_R_2020)
        case .hlg:
            (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG, kCMFormatDescriptionColorPrimaries_ITU_R_2020, kCMFormatDescriptionYCbCrMatrix_ITU_R_2020)
        }
        let extensions = [
            kCMFormatDescriptionExtension_TransferFunction: transfer,
            kCMFormatDescriptionExtension_ColorPrimaries: primaries,
            kCMFormatDescriptionExtension_YCbCrMatrix: matrix,
        ] as CFDictionary
        var description: CMFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: Stream.codec,
            width: Stream.width,
            height: Stream.height,
            extensions: extensions,
            formatDescriptionOut: &description
        )
        return description
    }
}
#endif
