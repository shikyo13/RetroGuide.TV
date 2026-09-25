import Foundation
import Libmpv
import RetroGuideKit

/// Reads the playing video's dynamic range and frame rate from libmpv.
enum MPVVideoFormat {
    private enum Property {
        /// Transfer characteristic of the decoded video ("pq", "hlg", "bt.1886", …).
        static let gamma = "video-params/gamma"
        /// Frame rate from the container, then as measured by the decoder.
        static let frameRates = ["container-fps", "estimated-vf-fps"]
    }

    private enum Gamma {
        static let perceptualQuantizer = "pq"
        static let hybridLogGamma = "hlg"
    }

    /// The format of the current video, or `nil` if no video is loaded yet.
    static func read(from handle: OpaquePointer) -> VideoFormat? {
        guard let gamma = string(Property.gamma, handle) else { return nil }
        let frameRate = Property.frameRates.lazy
            .compactMap { string($0, handle).flatMap(Double.init) }
            .first { $0 > .zero }
        return VideoFormat(dynamicRange: dynamicRange(forGamma: gamma), frameRate: frameRate)
    }

    static func dynamicRange(forGamma gamma: String) -> VideoDynamicRange {
        switch gamma {
        case Gamma.perceptualQuantizer: .hdr10
        case Gamma.hybridLogGamma: .hlg
        default: .sdr
        }
    }

    private static func string(_ property: String, _ handle: OpaquePointer) -> String? {
        guard let raw = mpv_get_property_string(handle, property) else { return nil }
        defer { mpv_free(raw) }
        return String(cString: raw)
    }
}
