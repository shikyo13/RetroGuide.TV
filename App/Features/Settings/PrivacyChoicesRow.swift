#if os(iOS)
import SwiftUI

/// Lets viewers in regions that require it (EEA, UK, Switzerland) change
/// their ad consent choice.
struct PrivacyChoicesRow: View {
    @Environment(AdsController.self) private var ads

    var body: some View {
        if ads.isPrivacyChoiceRequired {
            Button {
                Task { await ads.presentPrivacyChoices() }
            } label: {
                SettingsRowLabel(title: "Privacy choices", systemImage: "hand.raised", value: nil, accessory: nil)
            }
        }
    }
}
#endif
