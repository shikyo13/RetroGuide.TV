import RetroGuideKit
import SwiftUI

struct ParentalRatingsView: View {
    @Binding var draft: ParentalPolicy
    @Environment(\.theme) private var theme

    var body: some View {
        SettingsPage(title: "Ratings") {
            SettingsSection("U.S. ratings") {
                OptionMenu(title: "Movies", systemImage: "film",
                    choices: ParentalPolicy.MovieRating.allCases.map { .init(id: $0.rawValue, title: $0.rawValue) },
                    selection: Binding(get: { draft.maximumMovieRating.rawValue }, set: { draft.maximumMovieRating = .init(rawValue: $0) ?? .pg }))
                OptionMenu(title: "TV Shows", systemImage: "tv",
                    choices: ParentalPolicy.TVRating.allCases.map { .init(id: $0.rawValue, title: $0.rawValue) },
                    selection: Binding(get: { draft.maximumTVRating.rawValue }, set: { draft.maximumTVRating = .init(rawValue: $0) ?? .pg }))
                Text("Choose the highest rating allowed for each type of content.")
                    .font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
            }
            SettingsSection("Other ratings") {
                CheckmarkRow(title: "Allow unrated or unrecognized content", isSelected: draft.allowsUnrated) {
                    draft.allowsUnrated.toggle()
                }
                Text("Ratings come from your servers. Content without a U.S. rating, including other countries' ratings, is blocked unless you allow it here.")
                    .font(Typography.settingsBody).foregroundStyle(theme.textSecondary)
            }
        }
    }
}
