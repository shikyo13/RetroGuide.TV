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
    @State private var address = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("Enter your server's address")
                .font(Typography.title)
                .foregroundStyle(theme.textPrimary)
            Text("The address you use to open Jellyfin in a browser, like 192.168.1.20 or jellyfin.example.com. Port \(String(JellyfinAPI.defaultPort)) is used unless you add one.")
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
