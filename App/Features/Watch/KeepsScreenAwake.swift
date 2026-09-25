#if os(iOS)
import SwiftUI
import UIKit

/// Stops iPhone and iPad from dimming and locking while live TV is on screen.
private struct KeepsScreenAwake: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

extension View {
    func keepsScreenAwake() -> some View {
        modifier(KeepsScreenAwake())
    }
}
#endif
