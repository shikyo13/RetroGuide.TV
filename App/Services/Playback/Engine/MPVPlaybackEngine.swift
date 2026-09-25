import RetroGuideKit
import UIKit

/// libmpv via MPVKit. Demuxes and decodes nearly any file itself (MKV, AVI,
/// DTS, TrueHD, ASS subtitles…), so the server only has to serve the original file.
@MainActor
final class MPVPlaybackEngine: PlaybackEngine {
    let kind = PlaybackEngineKind.universal
    let capabilities = PlaybackCapabilities.universal
    var onEvent: ((PlaybackEvent) -> Void)?

    private let renderView = MPVRenderView()
    private let core: MPVCore?
    /// Increments per `play` so events from a replaced file are ignored.
    private var generation = 0

    var videoView: UIView {
        renderView
    }

    init() {
        core = MPVCore(layer: renderView.metalLayer)
        core?.onEvent = { [weak self] event, eventGeneration in
            Task { @MainActor in
                guard let self, eventGeneration == self.generation else { return }
                self.onEvent?(event)
            }
        }
    }

    func play(_ request: StreamRequest) {
        guard let core else {
            onEvent?(.failed("The video player could not be started."))
            return
        }
        generation += 1
        core.load(request.url, startPosition: request.startsAtPosition ? nil : request.startPosition, generation: generation)
    }

    func stop() {
        generation += 1
        core?.stop()
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

    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > Self.minimumDrawableDimension, Int(newValue.height) > Self.minimumDrawableDimension {
                super.drawableSize = newValue
            }
        }
    }
}
