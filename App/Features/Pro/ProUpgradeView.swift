import SwiftUI

/// What RetroGuide Pro includes, with the purchase and restore buttons.
struct ProUpgradeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        let pro = app.pro
        SettingsPage(title: "RetroGuide Pro") {
            Text(pro.isPro ? "You have RetroGuide Pro. Thank you for supporting the app!" : "One purchase, no subscription. It unlocks Pro on your iPhone, iPad and Apple TV.")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
            SettingsSection("Included") {
                ForEach(ProBenefit.all) { benefit in
                    ProBenefitRow(benefit: benefit)
                }
            }
            if !pro.isPro {
                purchaseControls(pro)
            }
        }
    }

    @ViewBuilder
    private func purchaseControls(_ pro: ProStore) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Button {
                Task { await pro.purchase() }
            } label: {
                Label(buyTitle(pro), systemImage: "star.fill")
            }
            .buttonStyle(.retroPrimary)
            .disabled(pro.product == nil || pro.purchaseState == .purchasing)

            Button {
                Task { await pro.restore() }
            } label: {
                Label("Restore Purchase", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.retro)

            if let status = statusMessage(pro) {
                Text(status)
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private func buyTitle(_ pro: ProStore) -> String {
        guard let product = pro.product else { return "Not available right now" }
        return "Upgrade for \(product.displayPrice)"
    }

    private func statusMessage(_ pro: ProStore) -> String? {
        switch pro.purchaseState {
        case .idle: nil
        case .purchasing: "Contacting the App Store…"
        case .pending: "Waiting for approval. Pro unlocks as soon as the purchase goes through."
        case .failed(let message): "The purchase didn't go through: \(message)"
        }
    }
}

/// One line of the Pro feature list.
private struct ProBenefitRow: View {
    let benefit: ProBenefit
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
            Image(systemName: benefit.systemImage)
                .foregroundStyle(theme.accent)
                .frame(width: DesignTokens.Spacing.xl)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.hairline) {
                Text(benefit.title)
                    .font(Typography.bodyEmphasis)
                    .foregroundStyle(theme.textPrimary)
                Text(benefit.detail)
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
