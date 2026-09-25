import SwiftUI

/// A focusable button with no visual treatment, used to capture remote input.
struct InvisibleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
    }
}
