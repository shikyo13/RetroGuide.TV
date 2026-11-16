import RetroGuideKit
import SwiftUI

/// How RetroGuide.TV reaches a Jellyfin server. Jellyfin has no relay like
/// Plex, so it gets two addresses: home (used whenever it answers) and away
/// (a VPN such as Tailscale, or an HTTPS internet address).
struct JellyfinConnectionView: View {
    private enum Copy {
        static let home = "Its address on your home network, like 192.168.1.20:8096."
        static let away = "A Tailscale or other VPN address, or an HTTPS internet address. Used when home doesn't answer."
        static let allowTitle = "Allow without encryption"
        static let allowDetail = "Home and VPN addresses only"
        static let confirm = "Your Jellyfin password and video won't be encrypted on your home network or VPN. Internet addresses still need HTTPS."
        static let helpTitle = "Watching away from home"
        static let help = [
            ("bolt.horizontal", "Plex finds its own way. Jellyfin needs an away address."),
            ("network.badge.shield.half.filled", "Easiest: Tailscale on the server and this device. Use the server's Tailscale address."),
            ("globe", "Or publish the server with HTTPS and a domain name."),
        ]
    }

    let serverID: String

    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var homeText = ""
    @State private var awayText = ""
    @State private var allowsUnencrypted = false
    @State private var isSaving = false
    @State private var result: ServerLibrary.JellyfinAddressesResult?
    @State private var isConfirmingUnencrypted = false
    @State private var showsHelp = false

    var body: some View {
        if let account = app.servers.accounts.first(where: { $0.id == serverID }) {
            SettingsPage(title: "Connection") {
                Text(status(account)).secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
                addressSection("At home", text: $homeText, placeholder: "192.168.1.20:8096", note: note(result?.home) ?? Copy.home)
                addressSection("Away from home", text: $awayText, placeholder: "100.x.x.x or https://jellyfin.example.com", note: note(result?.away) ?? Copy.away)
                SettingsSection("Security") {
                    Button {
                        if allowsUnencrypted { allowsUnencrypted = false } else { isConfirmingUnencrypted = true }
                    } label: {
                        SettingsRowLabel(
                            title: Copy.allowTitle,
                            systemImage: allowsUnencrypted ? "lock.open" : "lock",
                            value: allowsUnencrypted ? "On" : "Off",
                            accessory: nil
                        )
                    }
                    Text(Copy.allowDetail)
                        .font(Typography.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                Button(isSaving ? "Checking…" : "Save", systemImage: "checkmark", action: save)
                    .buttonStyle(.retroPrimary)
                    .disabled(isSaving || (homeText.isBlank && awayText.isBlank))
                help
            }
            .onAppear {
                homeText = account.connection.homeAddress.map(JellyfinConnectionText.short) ?? ""
                awayText = account.connection.awayAddress.map(Self.typed) ?? ""
                allowsUnencrypted = account.connection.allowsUnencrypted
            }
            .confirmationDialog(Copy.confirm, isPresented: $isConfirmingUnencrypted, titleVisibility: .visible) {
                Button("Allow Without Encryption") { allowsUnencrypted = true }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func addressSection(_ title: String, text: Binding<String>, placeholder: String, note: String) -> some View {
        SettingsSection(title) {
            TextField(placeholder, text: text)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .onSubmit(save)
            Text(note)
                .font(Typography.caption)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Collapsed until asked for, so the page stays short.
    private var help: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Button {
                withAnimation(DesignTokens.Motion.standardEase) { showsHelp.toggle() }
            } label: {
                SettingsRowLabel(title: Copy.helpTitle, systemImage: "questionmark.circle", value: nil,
                                 accessory: showsHelp ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(.retroRow)
            if showsHelp {
                ForEach(Copy.help, id: \.1) { icon, line in
                    Label {
                        Text(line).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: icon).foregroundStyle(theme.accentSecondary)
                    }
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }

    private func status(_ account: ServerAccount) -> String {
        if isSaving { return "Checking…" }
        if app.servers.status[serverID] == .offline {
            return account.connection.awayAddress == nil
                ? "Can't reach \(account.name) from here. To watch away from home, add an away address."
                : "Can't reach \(account.name) at either address right now."
        }
        let place = account.baseURL == account.connection.homeAddress ? "at home" : "away from home"
        let unencrypted = account.baseURL.scheme?.lowercased() == "http" ? " · not encrypted" : ""
        return "Connected \(place) · \(JellyfinConnectionText.short(account.baseURL))\(unencrypted)"
    }

    /// What a check found, in a few words; `nil` shows the field's explanation.
    private func note(_ check: JellyfinAddressCheck?) -> String? {
        switch check {
        case .none, .reachable: nil
        case let .notSecure(plainAddress):
            plainAddress != nil && !allowsUnencrypted
                ? "Answers only without encryption. Turn on “\(Copy.allowTitle)” to use it."
                : "Answers only without encryption. Over the internet, use HTTPS or a VPN address."
        case .untrusted: "Its certificate isn't trusted by this device. Use one from a trusted authority, such as Let's Encrypt."
        case .noAnswer: "Couldn't reach it from here. It's saved and will be tried when needed."
        case let .differentServer(name): "That's a different server (\(name))."
        case .invalid: "That isn't a valid address."
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            result = await app.setJellyfinAddresses(home: homeText, away: awayText, allowsUnencrypted: allowsUnencrypted, serverID: serverID)
            isSaving = false
        }
    }

    /// An away address as typed: HTTPS internet addresses keep their scheme.
    private static func typed(_ url: URL) -> String {
        NetworkLocation.isLikelyVPN(url) || NetworkLocation.isLikelyLocal(url) ? JellyfinConnectionText.short(url) : url.absoluteString
    }

    /// "Home and away", "Home", "Away", for the server page's row.
    static func summary(_ connection: ServerConnectionSettings) -> String {
        switch (connection.homeAddress, connection.awayAddress) {
        case (.some, .some): "Home and away"
        case (.some, .none): "Home only"
        case (.none, .some): "Away only"
        case (.none, .none): "Not set"
        }
    }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespaces).isEmpty }
}
