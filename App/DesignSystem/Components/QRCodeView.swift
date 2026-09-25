import CoreImage.CIFilterBuiltins
import SwiftUI

/// Renders a URL as a crisp QR code.
struct QRCodeView: View {
    let url: URL

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            image = QRCodeRenderer.image(for: url.absoluteString)
        }
        .accessibilityLabel("QR code")
    }
}

enum QRCodeRenderer {
    private static let errorCorrection = "M"

    static func image(for string: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = errorCorrection
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
