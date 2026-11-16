import RetroGuideKit
import SwiftUI

/// Typing a Jellyfin server's address.
struct JellyfinAddressStepView: View {
    private enum Layout {
        static let columnWidth = PlatformMetric.value(tv: CGFloat(1_000), touch: 520)
    }

    let message: String?
    let onConnect: (String) -> Void
    let onBack: () -> Void

    @Environment(\.theme) private var theme
    @State private var address: String

    /// `address` starts as what was typed last, so a failed try can be corrected.
    init(address: String, message: String?, onConnect: @escaping (String) -> Void, onBack: @escaping () -> Void) {
        _address = State(initialValue: address)
        self.message = message
        self.onConnect = onConnect
        self.onBack = onBack
    }
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("Enter your server's address")
                .font(Typography.title)
                .foregroundStyle(theme.textPrimary)
            // Verbatim, so the example addresses aren't links to sites that don't exist.
            Text(verbatim: "At home, like 192.168.1.20:8096. Over the internet, an HTTPS address like https://jellyfin.example.com.")
                .secondaryText()
            TextField("Server address", text: $address)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
                #endif
                .autocorrectionDisabled()
                .focused($isFieldFocused)
                .onSubmit(connect)
            if let message {
                Text(message)
                    .font(Typography.callout)
                    .foregroundStyle(theme.accent)
            }
            HStack(spacing: DesignTokens.Spacing.md) {
                Button("Connect", systemImage: "link", action: connect)
                    .buttonStyle(.retroPrimary)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Back", action: onBack)
                    .buttonStyle(.retro)
            }
        }
        .columnWidth(Layout.columnWidth, alignment: .leading)
        .onAppear { isFieldFocused = true }
    }

    private func connect() {
        guard !address.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onConnect(address)
    }
}
