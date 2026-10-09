import RetroGuideKit
import SwiftUI

/// Asynchronously loaded server artwork with a fade-in and a caller-provided placeholder.
struct RemoteImage<Placeholder: View>: View {
    let serverID: String
    let reference: String?
    let size: ImageSize
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(\.artworkResolver) private var resolver
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .animation(DesignTokens.Motion.standardEase, value: image != nil)
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            let maxPixelSize = max(size.width, size.height)
            // Already in memory: show it at once, with no placeholder or fade.
            if let cached = ImagePipeline.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { image = cached }
                return
            }
            image = nil
            let loaded = await ImagePipeline.shared.image(for: url, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }

    private var url: URL? {
        resolver.url(serverID: serverID, reference: reference, size: size)
    }
}

extension RemoteImage where Placeholder == Color {
    init(serverID: String, reference: String?, size: ImageSize, contentMode: ContentMode = .fill) {
        self.init(serverID: serverID, reference: reference, size: size, contentMode: contentMode) { Color.clear }
    }
}
