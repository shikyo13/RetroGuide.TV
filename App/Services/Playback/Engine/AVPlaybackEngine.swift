import AVFoundation
import AVKit
import Combine
import RetroGuideKit
import UIKit

/// Apple's AVPlayer. Plays MP4/MOV directly and HLS from the server otherwise.
@MainActor
final class AVPlaybackEngine: PlaybackEngine {
    private enum Tuning {
        static let forwardBufferSeconds: TimeInterval = 6
        static let extendedForwardBufferSeconds: TimeInterval = 60
        static let seekTimescale: CMTimeScale = 600
    }

    let kind = PlaybackEngineKind.appleNative
    let capabilities = PlaybackCapabilities.appleNative
    var onEvent: ((PlaybackEvent) -> Void)?
    private var positionOffset: TimeInterval = .zero
    var position: TimeInterval? {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds + positionOffset : nil
    }

    private let player = AVPlayer()
    private var relay: LoopbackPlaybackRelay?
    private var opening: Task<Void, Never>?
    private var wantsPaused = false
    private let layerView = PlayerLayerView()
    private var statusCancellable: AnyCancellable?
    private var itemCancellables = Set<AnyCancellable>()

    var videoView: UIView {
        layerView
    }

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        // The relay address belongs to this device and must never be handed to a remote player.
        player.allowsExternalPlayback = false
        #if DEBUG
        player.isMuted = DebugLaunchOptions.isMuted
        #endif
        layerView.backgroundColor = .black
        layerView.playerLayer.player = player
        layerView.playerLayer.videoGravity = .resizeAspect
        statusCancellable = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated {
                    if status == .playing { self?.onEvent?(.playing) }
                }
            }
    }

    /// `tracks` is not needed here: when the server repackages a stream it applies
    /// its own track selection, and direct-play MP4s use the file's defaults.
    func play(_ request: StreamRequest, tracks: TrackSelection?) {
        guard SecureTransport.permits(request.url) else {
            stop()
            onEvent?(.failed(HTTPError.secureConnectionRequired.localizedDescription))
            return
        }
        stop()
        wantsPaused = false
        positionOffset = request.startsAtPosition ? request.startPosition : .zero
        opening = Task { [weak self] in
            guard let self else { return }
            do {
                let relay = try LoopbackPlaybackRelay(origin: request.url)
                self.relay = relay
                let localURL = try await relay.start()
                try Task.checkCancellation()
                let asset = AVURLAsset(url: localURL, options: [
                    AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue
                ])
                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = request.buffer == .extended
                    ? Tuning.extendedForwardBufferSeconds : Tuning.forwardBufferSeconds
                self.observe(item)
                self.player.replaceCurrentItem(with: item)
                if !request.startsAtPosition {
                    await self.player.seek(to: CMTime(seconds: request.startPosition, preferredTimescale: Tuning.seekTimescale))
                    try Task.checkCancellation()
                }
                if !self.wantsPaused { self.player.play() }
            } catch {
                guard !Task.isCancelled else { return }
                self.relay?.stop()
                self.relay = nil
                self.onEvent?(.failed("A secure connection to this stream could not be established."))
            }
        }
    }

    #if os(iOS)
    func pictureInPictureSource(playbackDelegate: any AVPictureInPictureSampleBufferPlaybackDelegate) -> AVPictureInPictureController.ContentSource? {
        AVPictureInPictureController.ContentSource(playerLayer: layerView.playerLayer)
    }
    #endif

    func setPaused(_ paused: Bool) {
        wantsPaused = paused
        if paused {
            player.pause()
        } else {
            player.play()
        }
    }

    func stop() {
        opening?.cancel()
        opening = nil
        relay?.stop()
        relay = nil
        itemCancellables.removeAll()
        player.replaceCurrentItem(with: nil)
    }

    private func observe(_ item: AVPlayerItem) {
        itemCancellables.removeAll()
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] status in
                MainActor.assumeIsolated {
                    guard status == .failed else { return }
                    self?.onEvent?(.failed(item?.error?.localizedDescription ?? "The stream could not be played."))
                }
            }
            .store(in: &itemCancellables)
        NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.onEvent?(.ended) }
            }
            .store(in: &itemCancellables)
    }
}

/// A view backed by `AVPlayerLayer`.
final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        // swiftlint:disable:next force_cast
        layer as! AVPlayerLayer
    }
}
