import SwiftUI

/// Makes a view a button when an action is supplied, and leaves it untouched
/// otherwise. Used where content is tappable on iPhone and iPad but reached
/// through focus on Apple TV.
private struct TapAction: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(InvisibleButtonStyle())
        } else {
            content
        }
    }
}

extension View {
    func tapAction(_ action: (() -> Void)?) -> some View {
        modifier(TapAction(action: action))
    }
}
