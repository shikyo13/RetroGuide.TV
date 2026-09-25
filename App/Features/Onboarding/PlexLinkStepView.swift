import RetroGuideKit
import SwiftUI

/// Shows the link code and a QR shortcut while waiting for the user to approve.
struct PlexLinkStepView: View {
    private enum Layout {
        static let qrSize: CGFloat = 320
        static let qrPadding: CGFloat = 20
        static let columnWidth: CGFloat = 760
        static let codeLetterSpacing: CGFloat = 18
    }

    let code: PlexLinkCode?
    let onCancel: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.xxl) {
            instructions
            qrCode
        }
        .panel(padding: DesignTokens.Spacing.xl)
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("Link your Plex account")
                .font(Typography.title)
                .foregroundStyle(theme.textPrimary)
            Text("On your phone or computer, go to")
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
            HStack(spacing: DesignTokens.Spacing.sm) {
                ProgressView()
                Text("Waiting for approval…")
                    .font(Typography.callout)
                    .foregroundStyle(theme.textSecondary)
            }
            Button("Cancel", action: onCancel)
                .buttonStyle(.retro)
        }
        .frame(width: Layout.columnWidth, alignment: .leading)
    }

    /// "plex.tv/link" without the scheme.
    private var linkPageDisplay: String {
        (PlexAPI.linkPageURL.host() ?? "") + PlexAPI.linkPageURL.path()
    }

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
}
