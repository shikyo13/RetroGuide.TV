import RetroGuideKit
import SwiftUI

/// Where a Jellyfin server is reached. Jellyfin servers have one address,
/// so changing it (a new IP, a Tailscale address) is the whole setting.
struct JellyfinAddressView: View {
    let serverID: String

    @Environment(AppModel.self) private var app
    @State private var addressText = ""
    @State private var isApplying = false
    @State private var message: String?

    var body: some View {
        if let account = app.servers.accounts.first(where: { $0.id == serverID }) {
            SettingsPage(title: "Server address") {
                Text(status(account)).secondaryText()
                SettingsSection("Address") {
                    TextField("192.168.1.20 or jellyfin.example.com", text: $addressText)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .onSubmit(apply)
                    Button("Use this address", action: apply)
                        .buttonStyle(.retro)
                        .disabled(isApplying || addressText.trimmingCharacters(in: .whitespaces).isEmpty)
                    Text("Enter the address the server answers on, such as its new IP or its Tailscale address. Port 8096 is used unless you add one.")
                        .secondaryText()
                }
                if let message {
                    Text(message).secondaryText()
                }
            }
            .onAppear {
                addressText = Self.displayAddress(account.baseURL)
            }
        }
    }

    private func status(_ account: ServerAccount) -> String {
        if isApplying { return "Connecting…" }
        if app.servers.status[serverID] == .offline { return "Can't reach \(account.name) right now." }
        return "Connected at \(Self.displayAddress(account.baseURL))."
    }

    private func apply() {
        let text = addressText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isApplying else { return }
        isApplying = true
        message = nil
        Task {
            switch await app.changeJellyfinAddress(text, serverID: serverID) {
            case .moved:
                message = nil
            case .notFound:
                message = "No Jellyfin server answered at that address."
            case let .differentServer(name):
                message = "That address is a different Jellyfin server (\(name)). To use it too, add it as a new server."
            }
            isApplying = false
        }
    }

    /// "10.10.1.25:8096", the way it would be typed.
    static func displayAddress(_ url: URL) -> String {
        ServerAddressText.short(url) + (url.port.map { ":\($0)" } ?? "")
    }
}
