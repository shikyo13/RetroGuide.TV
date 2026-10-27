import RetroGuideKit
import SwiftUI

struct ParentalPINView: View {
    var onCancel: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var pin = ""
    @FocusState private var focusedField: ParentalPINField.Field?

    var body: some View {
        SettingsPage(title: "Parental Lock") {
            Text("Enter your PIN to change settings. Content restrictions stay active while you make changes.")
                .font(Typography.settingsBody)
            ParentalPINField(title: "Four-digit PIN", identifier: "parentalPIN", pin: $pin,
                field: .unlock, focus: $focusedField)
                .onSubmit(unlock)
            Button("Unlock Settings", action: unlock)
                .buttonStyle(.retroPrimary)
                .accessibilityIdentifier("unlockParentalSettings")
                .disabled(!ParentalPIN.isValid(pin))
            Button("Cancel") {
                if let onCancel { onCancel() } else { dismiss() }
            }.buttonStyle(.retro)
            if let message = app.parentalControls.message {
                Text(message).font(Typography.settingsBody)
            }
        }
        .onDisappear { pin = "" }
    }

    private func unlock() {
        guard ParentalPIN.isValid(pin) else { return }
        _ = app.parentalControls.authorize(pin)
        pin = ""
    }
}

/// Replaces the entire protected navigation tree when authorization expires.
struct ParentalSettingsGate<Content: View>: View {
    @Environment(AppModel.self) private var app
    var onCancel: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        if app.parentalControls.needsAuthorization {
            NavigationStack { ParentalPINView(onCancel: onCancel) }
        } else {
            content()
        }
    }
}
