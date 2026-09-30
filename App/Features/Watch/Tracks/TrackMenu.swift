import SwiftUI

/// A settings-style row that opens a menu of choices ("Subtitles  English ⌃⌄").
struct TrackMenu: View {
    struct Choice: Identifiable, Hashable {
        let id: String
        let title: String
    }

    let title: String
    let systemImage: String
    let choices: [Choice]
    @Binding var selection: String

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(choices) { choice in
                    Text(choice.title).tag(choice.id)
                }
            }
            .pickerStyle(.inline)
        } label: {
            SettingsRowLabel(
                title: title,
                systemImage: systemImage,
                value: choices.first { $0.id == selection }?.title,
                accessory: "chevron.up.chevron.down"
            )
        }
        .menuStyle(.button)
        .buttonStyle(.retroRow)
    }
}
