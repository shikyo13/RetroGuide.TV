import SwiftUI

/// Open-source notices for software bundled in the app (required by the LGPL).
struct AcknowledgementsView: View {
    private enum Resource {
        static let licenseName = "LGPL-3.0"
        static let licenseExtension = "txt"
    }

    private struct Component: Identifiable {
        let name: String
        let license: String
        let source: String

        var id: String { name }
    }

    private static let components = [
        Component(name: "MPVKit", license: "GNU LGPL v3.0", source: "github.com/mpvkit/MPVKit"),
        Component(name: "mpv", license: "GNU LGPL (via MPVKit)", source: "mpv.io"),
        Component(name: "FFmpeg", license: "GNU LGPL (via MPVKit)", source: "ffmpeg.org"),
    ]

    @Environment(\.theme) private var theme
    @State private var licenseParagraphs: [String] = []

    var body: some View {
        SettingsPage(title: "Acknowledgements") {
            Text("\(AppIdentity.productName) is open-source software under the MIT License. Video playback uses the following libraries. You can rebuild the app with modified versions of them from the public source code.")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
            // Rows are focusable (no-op buttons) so the Siri Remote can scroll the page.
            SettingsSection("Libraries") {
                ForEach(Self.components) { component in
                    Button {} label: {
                        SettingsRowLabel(title: component.name, systemImage: "shippingbox", value: "\(component.license) · \(component.source)", accessory: nil)
                    }
                }
            }
            SettingsSection("GNU Lesser General Public License v3.0") {
                ForEach(licenseParagraphs.indices, id: \.self) { index in
                    Button {} label: {
                        Text(licenseParagraphs[index])
                            .font(Typography.micro)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .task {
            licenseParagraphs = Self.loadLicenseParagraphs()
        }
    }

    private static func loadLicenseParagraphs() -> [String] {
        guard let url = Bundle.main.url(forResource: Resource.licenseName, withExtension: Resource.licenseExtension),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
