import CoreGraphics
import SwiftUI

/// Animated analog "snow", shown while a channel is tuning.
///
/// A handful of small grayscale frames are generated once and cycled with
/// nearest-neighbor scaling, which is far cheaper than drawing noise per frame.
struct StaticNoiseView: View {
    private enum Timing {
        static let framesPerSecond: Double = 24
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1 / Timing.framesPerSecond)) { context in
            let frames = StaticNoiseFrames.frames
            let index = Int(context.date.timeIntervalSinceReferenceDate * Timing.framesPerSecond) % max(frames.count, 1)
            if frames.indices.contains(index) {
                Image(decorative: frames[index], scale: 1)
                    .resizable()
                    .interpolation(.none)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

@MainActor
private enum StaticNoiseFrames {
    private enum Spec {
        static let width = 240
        static let height = 135
        static let frameCount = 6
        static let bitsPerComponent = 8
        static let minimumBrightness: UInt8 = 20
    }

    static let frames: [CGImage] = (0..<Spec.frameCount).compactMap { _ in makeFrame() }

    private static func makeFrame() -> CGImage? {
        var generator = SystemRandomNumberGenerator()
        var pixels = [UInt8](repeating: .zero, count: Spec.width * Spec.height)
        for index in pixels.indices {
            pixels[index] = UInt8.random(in: Spec.minimumBrightness...UInt8.max, using: &generator)
        }
        return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(
                data: buffer.baseAddress,
                width: Spec.width,
                height: Spec.height,
                bitsPerComponent: Spec.bitsPerComponent,
                bytesPerRow: Spec.width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )?.makeImage()
        }
    }
}
