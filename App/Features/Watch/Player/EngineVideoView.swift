import SwiftUI

/// Hosts the active engine's rendering view. Only one instance should be on
/// screen at a time, because a `UIView` can have only one superview.
struct EngineVideoView: UIViewRepresentable {
    let engine: any PlaybackEngine

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        attach(engine.videoView, to: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if engine.videoView.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            attach(engine.videoView, to: container)
        }
    }

    private func attach(_ videoView: UIView, to container: UIView) {
        videoView.removeFromSuperview()
        videoView.frame = container.bounds
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(videoView)
    }
}
