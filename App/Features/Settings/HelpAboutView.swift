import SwiftUI

/// Support, the privacy policy, what's new, rating and credits. Apple TV has
/// no browser, so it shows the addresses instead of opening them.
struct HelpAboutView: View {
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsPage(title: String(localized: "Help and About")) {
            SettingsSection(String(localized: "Help")) {
                link(String(localized: "Support"), systemImage: "questionmark.circle", url: AppIdentity.supportURL)
                link(String(localized: "What's new"), systemImage: "sparkles", url: AppIdentity.changelogURL)
                link(String(localized: "Privacy policy"), systemImage: "hand.raised", url: AppIdentity.privacyURL)
            }
            SettingsSection(String(localized: "About")) {
                #if os(iOS)
                RateAppRow()
                PrivacyChoicesRow()
                #endif
                NavigationLink { AcknowledgementsView() } label: {
                    SettingsRowLabel(title: String(localized: "Acknowledgements"), systemImage: "doc.text", value: nil)
                }
            }
            Text("\(AppIdentity.productName) \(AppIdentity.version) (\(AppIdentity.build)) · Open source under the MIT License")
                .font(Typography.caption)
                .foregroundStyle(theme.textSecondary)
        }
    }

    @ViewBuilder
    private func link(_ title: String, systemImage: String, url: URL) -> some View {
        #if os(tvOS)
        SettingsRowLabel(title: title, systemImage: systemImage, value: Self.shortAddress(url), accessory: nil)
        #else
        Button { openURL(url) } label: {
            SettingsRowLabel(title: title, systemImage: systemImage, value: nil, accessory: "arrow.up.right")
        }
        #endif
    }

    /// "retroguide.tv/support".
    private static func shortAddress(_ url: URL) -> String {
        let host = (url.host() ?? "").replacingOccurrences(of: "www.", with: "")
        return host + url.path()
    }
}
