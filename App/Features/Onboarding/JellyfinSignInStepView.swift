import RetroGuideKit
import SwiftUI

/// Signing in to a Jellyfin server: a Quick Connect code to approve from
/// another Jellyfin app, or a username and password.
struct JellyfinSignInStepView: View {
    private enum Layout {
        static let columnWidth = PlatformMetric.value(tv: CGFloat(1_000), touch: 460)
        static let codeLetterSpacing = PlatformMetric.value(tv: CGFloat(18), touch: 8)
    }

    let signIn: OnboardingModel.JellyfinSignIn
    let onSignIn: (_ username: String, _ password: String) -> Void
    let onUsePassword: () -> Void
    let onUseQuickConnect: () -> Void
    let onCancel: () -> Void

    @Environment(\.theme) private var theme
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("Sign in to \(signIn.server.name)")
                .font(Typography.title)
                .foregroundStyle(theme.textPrimary)
            if signIn.usesPassword {
                passwordForm
            } else {
                quickConnect
            }
            if let message = signIn.message {
                Text(message)
                    .font(Typography.callout)
                    .foregroundStyle(theme.accent)
            }
            Button("Cancel", action: onCancel)
                .buttonStyle(.retro)
        }
        .columnWidth(Layout.columnWidth, alignment: .leading)
        .panel(padding: DesignTokens.Spacing.xl)
    }

    private var quickConnect: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("In Jellyfin on your phone or computer, open your profile, choose Quick Connect and enter this code:")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
            Group {
                if let code = signIn.code {
                    Text(code.code)
                        .kerning(Layout.codeLetterSpacing)
                } else {
                    ProgressView()
                }
            }
            .font(Typography.linkCode)
            .foregroundStyle(theme.accent)
            HStack(spacing: DesignTokens.Spacing.sm) {
                ProgressView()
                Text("Waiting for approval…")
                    .font(Typography.callout)
                    .foregroundStyle(theme.textSecondary)
            }
            Button("Use Password Instead", systemImage: "key", action: onUsePassword)
                .buttonStyle(.retro)
        }
    }

    private var passwordForm: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            TextField("Username", text: $username)
                .textContentType(.username)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
                #endif
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(.password)
                #if os(iOS)
                .textFieldStyle(.roundedBorder)
                #endif
                .onSubmit(submit)
            HStack(spacing: DesignTokens.Spacing.md) {
                Button(action: submit) {
                    if signIn.isSigningIn {
                        ProgressView()
                    } else {
                        Label("Sign In", systemImage: "person.badge.key")
                    }
                }
                .buttonStyle(.retroPrimary)
                .disabled(username.isEmpty || signIn.isSigningIn)
                if signIn.isQuickConnectAvailable {
                    Button("Use Quick Connect", systemImage: "qrcode", action: onUseQuickConnect)
                        .buttonStyle(.retro)
                }
            }
        }
    }

    private func submit() {
        guard !username.isEmpty, !signIn.isSigningIn else { return }
        onSignIn(username, password)
    }
}
