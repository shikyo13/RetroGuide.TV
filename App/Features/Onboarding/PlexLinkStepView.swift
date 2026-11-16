import RetroGuideKit
import SwiftUI

/// Links a Plex account while waiting for approval. On iPhone and iPad,
/// Plex's own sign-in page opens in a sheet (nothing to type), with a code as
/// the fallback; on Apple TV, the code with a QR shortcut.
struct PlexLinkStepView: View {
    private enum Layout {
        static let qrSize = PlatformMetric.value(tv: CGFloat(320), touch: 150)
        static let qrPadding = PlatformMetric.value(tv: CGFloat(20), touch: 10)
        static let columnWidth = PlatformMetric.value(tv: CGFloat(760), touch: 420)
        static let codeLetterSpacing = PlatformMetric.value(tv: CGFloat(18), touch: 8)
    }

    private enum Copy {
        static let signInExplanation = "Sign in with the Plex account that has your server, or the one a friend shared their server with."
    }

    let code: PlexLinkCode?
    let signIn: OnboardingModel.PlexSignIn
    let onSwitchSignIn: () -> Void
    let onCancel: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    #if os(iOS)
    @State private var signInSheet = PlexSignInSheet()
    #endif

    var body: some View {
        #if os(tvOS)
        HStack(alignment: .center, spacing: DesignTokens.Spacing.xxl) {
            codeInstructions
            qrCode
        }
        .panel(padding: DesignTokens.Spacing.xl)
        #else
        Group {
            switch signIn {
            case .signInPage: signInPageInstructions
            case .code: codeInstructions
            }
        }
        .panel(padding: DesignTokens.Spacing.xl)
        // Approval moves setup on; close Plex's page with it.
        .onDisappear { signInSheet.close() }
        #endif
    }

    private var title: some View {
        Text("Link your Plex account")
            .font(Typography.title)
            .foregroundStyle(theme.textPrimary)
    }

    private var waiting: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ProgressView()
            Text("Waiting for approval…")
                .font(Typography.callout)
                .foregroundStyle(theme.textSecondary)
        }
    }

    private var codeInstructions: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            title
            Text(PlatformMetric.value(tv: "On your phone or computer, go to", touch: "On this device or any other, go to"))
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
            Text(linkPageDisplay)
                .font(Typography.headline)
                .foregroundStyle(theme.accentSecondary)
            Text("and enter this code:")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
            Group {
                if let code {
                    Text(code.code)
                        .kerning(Layout.codeLetterSpacing)
                } else {
                    ProgressView()
                }
            }
            .font(Typography.linkCode)
            .foregroundStyle(theme.accent)
            waiting
            #if os(iOS)
            Button {
                openURL(PlexAPI.linkPageURL)
            } label: {
                Label("Open \(linkPageDisplay)", systemImage: "safari")
            }
            .buttonStyle(.retroPrimary)
            Button("Sign In on This Device Instead", action: onSwitchSignIn)
                .buttonStyle(.retro)
            #endif
            Button("Cancel", action: onCancel)
                .buttonStyle(.retro)
        }
        .columnWidth(Layout.columnWidth, alignment: .leading)
    }

    #if os(iOS)
    private var signInPageInstructions: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            title
            Text(Copy.signInExplanation)
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if code != nil {
                waiting
            } else {
                ProgressView()
            }
            Button {
                openSignInPage()
            } label: {
                Label("Sign In with Plex", systemImage: "person.crop.circle")
            }
            .buttonStyle(.retroPrimary)
            .disabled(code == nil)
            Button("Use a Code Instead", action: onSwitchSignIn)
                .buttonStyle(.retro)
            Button("Cancel", action: onCancel)
                .buttonStyle(.retro)
        }
        .columnWidth(Layout.columnWidth, alignment: .leading)
    }

    /// The model's polling sees the approval and moves setup on.
    private func openSignInPage() {
        guard let code else { return }
        signInSheet.open(code.linkURL)
    }
    #endif

    /// "plex.tv/link" without the scheme.
    private var linkPageDisplay: String {
        (PlexAPI.linkPageURL.host() ?? "") + PlexAPI.linkPageURL.path()
    }

    #if os(tvOS)
    private var qrCode: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Group {
                if let code {
                    QRCodeView(url: code.linkURL)
                } else {
                    Color.clear
                }
            }
            .frame(width: Layout.qrSize, height: Layout.qrSize)
            .padding(Layout.qrPadding)
            .background(Color.white, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
            Text("Scan to open Plex link")
                .font(Typography.caption)
                .foregroundStyle(theme.textSecondary)
        }
    }
    #endif
}
