import SwiftUI

/// A content column: a fixed width on Apple TV, where the screen is always the
/// same size, and at most that width on iPhone and iPad so it fits any screen.
private struct ColumnWidth: ViewModifier {
    let width: CGFloat
    let alignment: Alignment

    func body(content: Content) -> some View {
        #if os(tvOS)
        content.frame(width: width, alignment: alignment)
        #else
        content.frame(maxWidth: width, alignment: alignment)
        #endif
    }
}

extension View {
    func columnWidth(_ width: CGFloat, alignment: Alignment = .center) -> some View {
        modifier(ColumnWidth(width: width, alignment: alignment))
    }
}
