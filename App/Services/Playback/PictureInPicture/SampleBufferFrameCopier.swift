#if os(iOS)
import AVFoundation
import AVKit
import CoreImage
import CoreMedia
import Metal
import UIKit

/// Gives RetroGuide Player a Picture in Picture source without changing how
/// it draws: every frame mpv presents is scaled into a small 8-bit buffer and
/// shown in an `AVSampleBufferDisplayLayer`, which Picture in Picture can use.
/// The copy is direct play like the picture it comes from; nothing is transcoded.
///
/// iOS lets an app use the GPU in the background only while its Picture in
/// Picture window is showing, so copies are skipped in the background otherwise.
final class SampleBufferFrameCopier: @unchecked Sendable {
    private enum Tuning {
        /// The window is small: frames are at most 720p, in even sizes.
        static let maximumSize = CGSize(width: 1_280, height: 720)
        /// Buffers kept in reserve, so a frame the window is still showing isn't reused.
        static let spareBuffers = 6
        /// The source layer must be on screen to start Picture in Picture;
        /// nearly transparent so it doesn't cover mpv's own picture.
        static let layerAlpha: CGFloat = 0.01
    }

    let displayLayer: AVSampleBufferDisplayLayer
    private let displayView: SampleBufferView
    private weak var sourceLayer: MPVMetalLayer?
    private let lock = NSLock()
    private var queue: MTLCommandQueue?
    private var imageContext: CIContext?
    private var textureCache: CVMetalTextureCache?
    private var pool: CVPixelBufferPool?
    private var poolSize = (width: 0, height: 0)
    private var isCopying = false
    /// Frames use the GPU, which iOS allows in the background only while the window shows.
    nonisolated(unsafe) var isPictureInPictureActive = false
    nonisolated(unsafe) private var isInBackground = false
    private var observers: [NSObjectProtocol] = []

    private var isEnabled: Bool {
        !isInBackground || isPictureInPictureActive
    }

    @MainActor
    init(host: MPVRenderView) {
        displayView = SampleBufferView()
        displayLayer = displayView.sampleLayer
        sourceLayer = host.metalLayer
        // Frames are read back from mpv's drawables.
        host.metalLayer.framebufferOnly = false
        displayView.frame = host.bounds
        displayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        displayView.alpha = Tuning.layerAlpha
        displayView.isUserInteractionEnabled = false
        host.addSubview(displayView)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isInBackground = true
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isInBackground = false
        })
        host.metalLayer.drawableObserver = { [weak self] drawable in
            drawable.addPresentedHandler { [weak self] presented in
                guard let self, let drawable = presented as? CAMetalDrawable else { return }
                self.copy(drawable)
            }
        }
    }

    // MARK: - Frames (mpv's render thread, then Metal's completion thread)

    private func copy(_ drawable: CAMetalDrawable) {
        guard isEnabled else { return }
        let texture = drawable.texture
        lock.lock()
        // One copy at a time: drop a frame rather than queue behind a busy GPU.
        guard !isCopying else {
            lock.unlock()
            return
        }
        if queue == nil, let queue = texture.device.makeCommandQueue() {
            self.queue = queue
            imageContext = CIContext(mtlCommandQueue: queue)
            CVMetalTextureCacheCreate(nil, nil, texture.device, nil, &textureCache)
        }
        let scale = min(Tuning.maximumSize.width / CGFloat(texture.width), Tuning.maximumSize.height / CGFloat(texture.height), 1)
        let width = Int(CGFloat(texture.width) * scale) & ~1
        let height = Int(CGFloat(texture.height) * scale) & ~1
        guard width > 0, height > 0,
              let pixelBuffer = makePixelBuffer(width: width, height: height),
              let target = metalTexture(for: pixelBuffer),
              let targetTexture = CVMetalTextureGetTexture(target),
              let commandBuffer = queue?.makeCommandBuffer(),
              let imageContext,
              let image = CIImage(mtlTexture: texture, options: [.colorSpace: sourceLayer?.colorspace ?? CGColorSpace(name: CGColorSpace.sRGB) as Any])
        else {
            lock.unlock()
            return
        }
        isCopying = true
        lock.unlock()
        let destination = CIRenderDestination(mtlTexture: targetTexture, commandBuffer: commandBuffer)
        destination.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        do {
            try imageContext.startTask(toRender: image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)), to: destination)
        } catch {
            finishCopy()
            return
        }
        commandBuffer.addCompletedHandler { [weak self] buffer in
            // The drawable and the texture wrapper stay alive until the copy is done.
            _ = drawable
            _ = target
            self?.finishCopy()
            if buffer.status == .completed {
                self?.show(pixelBuffer)
            }
        }
        commandBuffer.commit()
    }

    private func finishCopy() {
        lock.lock()
        isCopying = false
        lock.unlock()
    }

    private func show(_ pixelBuffer: CVPixelBuffer) {
        var description: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &description)
        guard let description else { return }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescription: description, sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary] {
            attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        let renderer = displayLayer.sampleBufferRenderer
        if renderer.status == .failed {
            renderer.flush()
        }
        renderer.enqueue(sample)
    }

    private func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        if pool == nil || poolSize != (width, height) {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferMetalCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any](),
            ]
            let poolAttributes: [CFString: Any] = [kCVPixelBufferPoolMinimumBufferCountKey: Tuning.spareBuffers]
            pool = nil
            CVPixelBufferPoolCreate(nil, poolAttributes as CFDictionary, attributes as CFDictionary, &pool)
            poolSize = (width, height)
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }

    private func metalTexture(for pixelBuffer: CVPixelBuffer) -> CVMetalTexture? {
        guard let textureCache else { return nil }
        var texture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, pixelBuffer, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer), 0, &texture
        )
        return texture
    }
}

/// A view backed by an `AVSampleBufferDisplayLayer`.
private final class SampleBufferView: UIView {
    override static var layerClass: AnyClass {
        AVSampleBufferDisplayLayer.self
    }

    var sampleLayer: AVSampleBufferDisplayLayer {
        // swiftlint:disable:next force_cast
        layer as! AVSampleBufferDisplayLayer
    }
}
#endif
