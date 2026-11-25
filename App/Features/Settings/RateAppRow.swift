#if os(iOS)
import SwiftUI

/// Opens the App Store's review sheet. Someone who chooses to rate is never
/// asked automatically again.
struct RateAppRow: View {
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            RatingPrompter.choseToRate()
            app.recordUsage(.rateTapped)
            openURL(AppIdentity.writeReviewURL)
        } label: {
            SettingsRowLabel(title: String(localized: "Rate \(AppIdentity.productName)"), systemImage: "star.bubble", value: nil, accessory: nil)
        }
    }
}
#endif
