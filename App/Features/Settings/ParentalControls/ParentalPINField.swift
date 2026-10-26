import RetroGuideKit
import SwiftUI

struct ParentalPINField: View {
    enum Field: Hashable { case create, confirm, unlock }

    let title: String
    let identifier: String
    @Binding var pin: String
    let field: Field
    var focus: FocusState<Field?>.Binding
    var onComplete: () -> Void = {}
    @State private var isVisible = false
    @Environment(\.scenePhase) private var scenePhase

    private var input: Binding<String> {
        Binding(get: { pin }, set: { pin = ParentalPIN.sanitized($0) })
    }

    private var layout: AnyLayout {
        #if os(tvOS)
        AnyLayout(VStackLayout(alignment: .leading, spacing: DesignTokens.Spacing.sm))
        #else
        AnyLayout(HStackLayout(spacing: DesignTokens.Spacing.sm))
        #endif
    }

    var body: some View {
        layout {
            Group {
                if isVisible {
                    TextField(title, text: input)
                } else {
                    SecureField(title, text: input)
                }
            }
            .focused(focus, equals: field)
            .accessibilityIdentifier(identifier)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
            .privacySensitive()
            Button {
                isVisible.toggle()
                #if os(iOS)
                focus.wrappedValue = field
                #endif
            } label: {
                Label(isVisible ? "Hide \(title)" : "Show \(title)", systemImage: isVisible ? "eye.slash" : "eye")
            }
            #if os(tvOS)
            .buttonStyle(.retro)
            #else
            .buttonStyle(.retroIcon)
            #endif
            .accessibilityLabel(isVisible ? "Hide \(title)" : "Show \(title)")
            .accessibilityIdentifier(identifier + "Visibility")
        }
        .onChange(of: pin) { old, new in
            if old.count < ParentalPIN.length && new.count == ParentalPIN.length { onComplete() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { isVisible = false }
        }
        .onDisappear { isVisible = false }
    }
}
