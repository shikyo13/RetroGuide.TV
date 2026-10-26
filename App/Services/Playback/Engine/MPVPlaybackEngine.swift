import AVKit
import RetroGuideKit
import UIKit

/// libmpv via MPVKit. Demuxes and decodes nearly any file itself (MKV, AVI,
/// DTS, TrueHD, ASS subtitles…), so the server only has to serve the original file.
@MainActor
final class MPVPlaybackEngine: PlaybackEngine {
    let kind = PlaybackEngineKind.universal
    let capabilities = PlaybackCapabilities.universal
    var onEvent: ((PlaybackEvent) -> Void)?
    var position: TimeInterval? { core?.position }

    private let renderView = MPVRenderView()
    private let core: MPVCore?
    #if os(iOS)
    private let frameCopier: SampleBufferFrameCopier
    #endif
    /// Increments per `play` so events from a replaced file are ignored.
    private var generation = 0

    var videoView: UIView {
        renderView
    }

    init() {
        core = MPVCore(layer: renderView.metalLayer)
        #if os(iOS)
        frameCopier = SampleBufferFrameCopier(host: renderView)
        #endif
        core?.onEvent = { [weak self] event, eventGeneration in
            Task { @MainActor in
                guard let self, eventGeneration == self.generation else { return }
                self.onEvent?(event)
            }
        }
    }

    func play(_ request: StreamRequest, tracks: TrackSelection?) {
        guard SecureTransport.permits(request.url) else {
            stop()
            onEvent?(.failed(HTTPError.secureConnectionRequired.localizedDescription))
            return
        }
        guard let core else {
            onEvent?(.failed("The video player could not be started."))
            return
        }
        generation += 1
        core.load(
            request.url,
            startPosition: request.startsAtPosition ? nil : request.startPosition,
            tracks: tracks,
            buffer: request.buffer,
            generation: generation
        )
    }

    func stop() {
        generation += 1
        core?.stop()
    }

    func setPaused(_ paused: Bool) {
        core?.setPaused(paused)
    }

    #if os(iOS)
    func pictureInPictureSource(playbackDelegate: any AVPictureInPictureSampleBufferPlaybackDelegate) -> AVPictureInPictureController.ContentSource? {
        AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: frameCopier.displayLayer, playbackDelegate: playbackDelegate)
    }

    func setPictureInPictureActive(_ active: Bool) {
        frameCopier.isPictureInPictureActive = active
    }
    #endif

    let switchesTracksLive = true

    func selectTracks(_ tracks: TrackSelection) {
        core?.selectTracks(tracks)
    }

    let adjustsSubtitleTiming = true

    func setSubtitleDelay(_ seconds: TimeInterval) {
        core?.setSubtitleDelay(seconds)
    }

    func setPrefersHDROutput(_ prefersHDROutput: Bool) {
        core?.setHDROutput(prefersHDROutput)
    }
}

/// A view whose backing layer is the Metal layer mpv renders into.
final class MPVRenderView: UIView {
    override static var layerClass: AnyClass {
        MPVMetalLayer.self
    }

    var metalLayer: MPVMetalLayer {
        // swiftlint:disable:next force_cast
        layer as! MPVMetalLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = UIScreen.main.nativeScale
        #if os(iOS)
        // Lets HDR video use the display's extra brightness (EDR).
        metalLayer.wantsExtendedDynamicRangeContent = true
        #endif
    }

    /// CAMetalLayer does not track its view's size by itself; keep the drawable
    /// matching the view so mpv renders at full resolution.
    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = metalLayer.contentsScale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// Works around MoltenVK briefly forcing a 1×1 drawable, which causes flicker
/// (see mpv-player/mpv#13651).
final class MPVMetalLayer: CAMetalLayer {
    private static let minimumDrawableDimension = 1

    /// Told about every drawable mpv takes, on mpv's render thread (Picture in Picture copies frames from them).
    nonisolated(unsafe) var drawableObserver: ((CAMetalDrawable) -> Void)?

    override func nextDrawable() -> CAMetalDrawable? {
        let drawable = super.nextDrawable()
        if let drawable {
            drawableObserver?(drawable)
        }
        return drawable
    }

    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > Self.minimumDrawableDimension, Int(newValue.height) > Self.minimumDrawableDimension {
                super.drawableSize = newValue
            }
        }
    }
}
