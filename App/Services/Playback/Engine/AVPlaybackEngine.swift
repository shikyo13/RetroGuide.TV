import AVFoundation
import Combine
import RetroGuideKit
import UIKit

/// Apple's AVPlayer. Plays MP4/MOV directly and HLS from the server otherwise.
@MainActor
final class AVPlaybackEngine: PlaybackEngine {
    private enum Tuning {
        static let forwardBufferSeconds: TimeInterval = 6
        static let seekTimescale: CMTimeScale = 600
    }

    let kind = PlaybackEngineKind.appleNative
    let capabilities = PlaybackCapabilities.appleNative
    var onEvent: ((PlaybackEvent) -> Void)?

    private let player = AVPlayer()
    private let layerView = PlayerLayerView()
    private var statusCancellable: AnyCancellable?
    private var itemCancellables = Set<AnyCancellable>()

    var videoView: UIView {
        layerView
    }

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
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
        let item = AVPlayerItem(url: request.url)
        item.preferredForwardBufferDuration = Tuning.forwardBufferSeconds
        observe(item)
        player.replaceCurrentItem(with: item)
        if !request.startsAtPosition {
            player.seek(to: CMTime(seconds: request.startPosition, preferredTimescale: Tuning.seekTimescale))
        }
        player.play()
    }

    func stop() {
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
