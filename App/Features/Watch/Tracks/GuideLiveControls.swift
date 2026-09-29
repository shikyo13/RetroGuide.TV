import SwiftUI

/// Controls on the guide's live picture, drawn above the video layer (which
/// sits over the guide): the "Audio & Subtitles" button and, on Apple TV, the
/// panel it opens beside the guide.
///
/// On Apple TV the button belongs to the guide's top row: it can take focus
/// only while Search and Settings can (reach it with Left from Search), and
/// Back from it closes the guide like Back from the top row.
struct GuideLiveControls: View {
    private enum Layout {
        static let panelWidth = PlatformMetric.value(tv: CGFloat(760), touch: 420)
    }

    let tuner: Tuner
    /// Where the live picture is, in screen coordinates.
    let pictureFrame: CGRect
    let isTopBarActive: Bool
    @Binding var isChoosingTracks: Bool
    /// Changes whenever the guide hands focus to the button.
    let focusSerial: Int
    let onCloseGuide: () -> Void
    #if os(tvOS)
    /// A move off the button, for the guide to take focus back.
    var onMoveOut: (MoveCommandDirection) -> Void = { _ in }
    #endif

    @FocusState private var isButtonFocused: Bool

    var body: some View {
        GeometryReader { _ in
            button
                .padding(DesignTokens.Spacing.sm)
                .frame(width: pictureFrame.width, height: pictureFrame.height, alignment: .bottomLeading)
                .offset(x: pictureFrame.minX, y: pictureFrame.minY)
            #if os(tvOS)
            if isChoosingTracks {
                panel
            }
            #endif
        }
        .ignoresSafeArea()
        #if os(iOS)
        .sheet(isPresented: $isChoosingTracks) {
            TrackPickerPanel(tuner: tuner)
                .screenBackground()
                .presentationDetents([.medium, .large])
        }
        #endif
    }

    private var button: some View {
        LiveTracksButton { isChoosingTracks = true }
        #if os(tvOS)
            .disabled(!isTopBarActive || isChoosingTracks)
            .focused($isButtonFocused)
            .onMoveCommand(perform: onMoveOut)
            .onExitCommand(perform: onCloseGuide)
            .onChange(of: focusSerial) { isButtonFocused = true }
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
        .onExitCommand {
            isChoosingTracks = false
            isButtonFocused = true
        }
    }
    #endif
}
