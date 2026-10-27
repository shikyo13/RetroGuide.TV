#if os(iOS)
import SwiftUI
import UIKit

/// Stops iPhone and iPad from dimming and locking while live TV is on screen.
private struct KeepsScreenAwake: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        content
            .onChange(of: enabled, initial: true) { UIApplication.shared.isIdleTimerDisabled = enabled }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

extension View {
    func keepsScreenAwake(enabled: Bool = true) -> some View {
        modifier(KeepsScreenAwake(enabled: enabled))
    }
}
#endif
