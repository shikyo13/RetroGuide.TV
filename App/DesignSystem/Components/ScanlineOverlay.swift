import SwiftUI

/// Subtle CRT scanlines (and optionally a vignette) drawn over menus.
/// Never applied to video: the TV picture stays clean.
struct ScanlineOverlay: View {
    private enum Spec {
        static let lineSpacing: CGFloat = 4
        static let lineThickness: CGFloat = 1.5
        static let lineOpacity: Double = 0.16
        static let vignetteOpacity: Double = 0.55
        static let vignetteStartRadius: CGFloat = 500
        static let vignetteEndRadius: CGFloat = 1_300
    }

    var includesVignette = true

    var body: some View {
        ZStack {
            Canvas { context, size in
                var path = Path()
                var y: CGFloat = .zero
                while y < size.height {
                    path.addRect(CGRect(x: .zero, y: y, width: size.width, height: Spec.lineThickness))
                    y += Spec.lineSpacing
                }
                context.fill(path, with: .color(.black.opacity(Spec.lineOpacity)))
            }
            if includesVignette {
                RadialGradient(
                    colors: [.clear, .black.opacity(Spec.vignetteOpacity)],
                    center: .center,
                    startRadius: Spec.vignetteStartRadius,
                    endRadius: Spec.vignetteEndRadius
                )
                .ignoresSafeArea()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Applies ``ScanlineOverlay`` when the user has the menu CRT effect turned on.
struct CRTEffect: ViewModifier {
    let isFullScreen: Bool

    @Environment(\.showsScanlines) private var showsScanlines

    func body(content: Content) -> some View {
        content.overlay {
            if showsScanlines {
                ScanlineOverlay(includesVignette: isFullScreen)
                    .ignoresSafeArea(edges: isFullScreen ? .all : [])
            }
        }
    }
}

private struct ShowsScanlinesKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var showsScanlines: Bool {
        get { self[ShowsScanlinesKey.self] }
        set { self[ShowsScanlinesKey.self] = newValue }
    }
}

extension View {
    /// CRT scanlines for menu surfaces. `isFullScreen` adds the edge vignette.
    func crtEffect(isFullScreen: Bool = true) -> some View {
        modifier(CRTEffect(isFullScreen: isFullScreen))
    }
}
