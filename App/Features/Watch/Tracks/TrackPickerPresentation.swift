import SwiftUI

/// Shows ``TrackPickerPanel`` over whatever is on screen (the guide or the
/// full-screen picture): beside it on Apple TV, where Back closes it, and as a
/// sheet on iPhone and iPad.
struct TrackPickerPresentation: ViewModifier {
    private enum Layout {
        static let panelWidth: CGFloat = 760
    }

    let tuner: Tuner
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        #if os(tvOS)
        content.overlay {
            if isPresented {
                panel
            }
        }
        #else
        content.sheet(isPresented: $isPresented) {
            TrackPickerPanel(tuner: tuner)
                .screenBackground()
                .presentationDetents([.medium, .large])
        }
        #endif
    }

    #if os(tvOS)
    private var panel: some View {
        HStack {
            Spacer()
            TrackPickerPanel(tuner: tuner)
                .frame(width: Layout.panelWidth)
                .panel()
                .padding(DesignTokens.Spacing.xl)
        }
        .background(Color.black.opacity(DesignTokens.Opacity.muted))
        .focusSection()
        .onExitCommand { isPresented = false }
    }
    #endif
}

extension View {
    func trackPicker(isPresented: Binding<Bool>, tuner: Tuner) -> some View {
        modifier(TrackPickerPresentation(tuner: tuner, isPresented: isPresented))
    }
}
