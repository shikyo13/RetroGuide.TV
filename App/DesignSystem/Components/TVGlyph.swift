import SwiftUI

/// The RetroGuide.TV brand glyph: a TV with an inset screen and a stand.
///
/// Drawn as a shape (rather than an SF Symbol) so the exact same artwork can
/// be used in the app icon. Keep `Geometry` in sync with
/// `Tools/BrandAssets/generate-brand-assets.swift`.
struct TVGlyph: Shape {
    /// Proportions relative to the glyph's width.
    enum Geometry {
        static let aspectRatio: CGFloat = 1.18
        static let bodyHeight: CGFloat = 0.72
        static let bodyCornerRadius: CGFloat = 0.16
        static let frameThickness: CGFloat = 0.085
        static let screenGap: CGFloat = 0.05
        static let screenCornerRadius: CGFloat = 0.07
        static let standWidth: CGFloat = 0.44
        static let standHeight: CGFloat = 0.075
        static let standGap: CGFloat = 0.05
    }

    func path(in rect: CGRect) -> Path {
        let unit = rect.width
        var path = Path()
        let body = CGRect(x: rect.minX, y: rect.minY, width: unit, height: Geometry.bodyHeight * unit)
        let frameInner = body.insetBy(dx: Geometry.frameThickness * unit, dy: Geometry.frameThickness * unit)
        let screen = frameInner.insetBy(dx: Geometry.screenGap * unit, dy: Geometry.screenGap * unit)
        path.addRoundedRect(in: body, cornerSize: square(Geometry.bodyCornerRadius * unit))
        path.addRoundedRect(in: frameInner, cornerSize: square((Geometry.bodyCornerRadius - Geometry.frameThickness) * unit))
        path.addRoundedRect(in: screen, cornerSize: square(Geometry.screenCornerRadius * unit))
        let standHeight = Geometry.standHeight * unit
        let stand = CGRect(
            x: rect.midX - Geometry.standWidth * unit / 2,
            y: body.maxY + Geometry.standGap * unit,
            width: Geometry.standWidth * unit,
            height: standHeight
        )
        path.addRoundedRect(in: stand, cornerSize: square(standHeight / 2))
        return path
    }

    private func square(_ side: CGFloat) -> CGSize {
        CGSize(width: side, height: side)
    }
}

extension TVGlyph {
    /// Fills the frame ring, screen and stand, leaving the gap between frame and screen empty.
    func brandFill(_ color: Color) -> some View {
        fill(color, style: FillStyle(eoFill: true))
            .aspectRatio(Geometry.aspectRatio, contentMode: .fit)
    }
}
