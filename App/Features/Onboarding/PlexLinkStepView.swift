import RetroGuideKit
import SwiftUI

/// Shows the link code while waiting for the user to approve: with a QR
/// shortcut on Apple TV, and a button that opens the link page on iPhone and iPad.
struct PlexLinkStepView: View {
    private enum Layout {
        static let qrSize = PlatformMetric.value(tv: CGFloat(320), touch: 150)
        static let qrPadding = PlatformMetric.value(tv: CGFloat(20), touch: 10)
        static let columnWidth = PlatformMetric.value(tv: CGFloat(760), touch: 420)
        static let codeLetterSpacing = PlatformMetric.value(tv: CGFloat(18), touch: 8)
    }

    let code: PlexLinkCode?
    let onCancel: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        #if os(tvOS)
        HStack(alignment: .center, spacing: DesignTokens.Spacing.xxl) {
            instructions
            qrCode
        }
        .panel(padding: DesignTokens.Spacing.xl)
        #else
        instructions
            .panel(padding: DesignTokens.Spacing.xl)
        #endif
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("Link your Plex account")
                .font(Typography.title)
                .foregroundStyle(theme.textPrimary)
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
            HStack(spacing: DesignTokens.Spacing.sm) {
                ProgressView()
                Text("Waiting for approval…")
                    .font(Typography.callout)
                    .foregroundStyle(theme.textSecondary)
            }
            #if os(iOS)
            Button {
                openURL(PlexAPI.linkPageURL)
            } label: {
                Label("Open \(linkPageDisplay)", systemImage: "safari")
            }
            .buttonStyle(.retroPrimary)
            #endif
            Button("Cancel", action: onCancel)
                .buttonStyle(.retro)
        }
        .columnWidth(Layout.columnWidth, alignment: .leading)
    }

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
