import SwiftUI

extension EnvironmentValues {
    /// iPhone in portrait: a single narrow column, so content stacks vertically.
    var isNarrowLayout: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact && verticalSizeClass == .regular
        #else
        false
        #endif
    }

    /// iPhone in landscape: plenty of width but little height.
    var isShortLayout: Bool {
        #if os(iOS)
        verticalSizeClass == .compact
        #else
        false
        #endif
    }
}
