import SwiftUI

/// A compact value control usable with touch, VoiceOver and the Siri Remote.
struct NumberControl: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Text(title).font(Typography.body).foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: true, vertical: false)
            Spacer()
            Button { value = max(range.lowerBound, value - step) } label: { Image(systemName: "minus") }
                .disabled(value <= range.lowerBound)
                .accessibilityLabel("Decrease \(title)")
            Button { value = min(range.upperBound, value + step) } label: { Image(systemName: "plus") }
                .disabled(value >= range.upperBound)
                .accessibilityLabel("Increase \(title)")
        }.buttonStyle(.retro)
    }
}
