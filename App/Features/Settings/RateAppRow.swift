#if os(iOS)
import SwiftUI

/// Opens the App Store's review sheet. Someone who chooses to rate is never
/// asked automatically again.
struct RateAppRow: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            RatingPrompter.choseToRate()
            openURL(AppIdentity.writeReviewURL)
        } label: {
            SettingsRowLabel(title: "Rate \(AppIdentity.productName)", systemImage: "star.bubble", value: nil, accessory: nil)
        }
    }
}
#endif
