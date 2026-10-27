import SwiftUI

struct ParentalEmptyView: View {
    @State private var showsSettings = false
    @Environment(AppModel.self) private var app

    var body: some View {
        ContentUnavailableView {
            Label("No allowed channels", systemImage: "lock.shield")
        } description: {
            Text("No available channels match your parental controls. A parent can change the lineup or content restrictions in Settings.")
        } actions: {
            Button("Parental Controls") { showsSettings = true }.buttonStyle(.retroPrimary)
        }
        .screenBackground()
        .sheet(isPresented: $showsSettings, onDismiss: { app.parentalControls.endAuthorization() }) {
            ParentalSettingsGate {
                NavigationStack { ParentalControlsView() }
            }
        }
    }
}
