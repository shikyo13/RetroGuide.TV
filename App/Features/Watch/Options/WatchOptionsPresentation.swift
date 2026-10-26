import SwiftUI

/// Shows ``WatchOptionsPanel`` over whatever is on screen (the guide or the
/// full-screen picture): beside it on Apple TV, where Back closes it, and as a
/// sheet on iPhone and iPad.
struct WatchOptionsPresentation: ViewModifier {
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
            WatchOptionsPanel(tuner: tuner)
                .screenBackground()
                .presentationDetents([.medium, .large])
        }
        #endif
    }

    #if os(tvOS)
    private var panel: some View {
        HStack {
            Spacer()
            WatchOptionsPanel(tuner: tuner, onPlaybackAction: { isPresented = false })
                .frame(width: Layout.panelWidth)
                .panel()
                // Long content scrolls inside the panel rather than past its edge.
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.large, style: .continuous))
                .padding(DesignTokens.Spacing.xl)
        }
        .background(Color.black.opacity(DesignTokens.Opacity.muted))
        .focusSection()
        .remoteExitCommand { isPresented = false }
    }
    #endif
}

extension View {
    func watchOptions(isPresented: Binding<Bool>, tuner: Tuner) -> some View {
        modifier(WatchOptionsPresentation(tuner: tuner, isPresented: isPresented))
    }
}
