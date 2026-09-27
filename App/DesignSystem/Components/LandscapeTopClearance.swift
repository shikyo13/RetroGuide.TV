import SwiftUI

/// iPhone in landscape has no top safe-area inset, so controls placed at the
/// top would sit against the screen's rounded edge while the bottom keeps the
/// home indicator's clearance. This adds matching room at the top.
private struct LandscapeTopClearance: ViewModifier {
    /// About the home indicator's inset, so top and bottom margins match.
    static let clearance = DesignTokens.Spacing.lg

    @Environment(\.isShortLayout) private var isShortLayout

    func body(content: Content) -> some View {
        content.padding(.top, isShortLayout ? Self.clearance : .zero)
    }
}

extension View {
    /// Extra top margin on iPhone in landscape (see ``LandscapeTopClearance``).
    func landscapeTopClearance() -> some View {
        modifier(LandscapeTopClearance())
    }
}
