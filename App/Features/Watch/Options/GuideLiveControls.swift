import SwiftUI

/// The "Options" button on the guide's live picture, drawn above the
/// video layer (which sits over the guide). The panel it opens is presented
/// by the watch screen (see ``WatchOptionsPresentation``).
///
/// On Apple TV the button belongs to the guide's top row: it can take focus
/// only while Search and Settings can (reach it with Left from Search), and
/// Back from it closes the guide like Back from the top row.
struct GuideLiveControls: View {
    /// Where the live picture is, in screen coordinates.
    let pictureFrame: CGRect
    let isTopBarActive: Bool
    @Binding var isShowingOptions: Bool
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
        }
        .ignoresSafeArea()
    }

    private var button: some View {
        WatchOptionsButton { isShowingOptions = true }
        #if os(tvOS)
            .disabled(!isTopBarActive || isShowingOptions)
            .focused($isButtonFocused)
            .onMoveCommand(perform: onMoveOut)
            .remoteExitCommand(perform: onCloseGuide)
            .onChange(of: focusSerial) { isButtonFocused = true }
            // Closing the panel returns to the button that opened it.
            .onChange(of: isShowingOptions) { _, isOpen in
                if !isOpen { isButtonFocused = true }
            }
        #endif
    }
}
