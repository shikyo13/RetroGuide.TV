import SwiftUI

/// The shared objects and values every screen reads from the environment.
///
/// Applied at the root, and again on each sheet's content by ``AppSheet``.
struct AppEnvironment: ViewModifier {
    let model: AppModel
    #if os(iOS)
    let ads: AdsController
    #endif

    func body(content: Content) -> some View {
        content
            .environment(model)
            #if os(iOS)
            .environment(ads)
            #endif
            .environment(\.theme, model.theme)
            .environment(\.artworkResolver, model.artworkResolver)
            .environment(\.showsScanlines, model.preferences.showsScanlines)
            .tint(model.theme.accent)
    }
}

/// Presents a sheet whose content carries the app's environment itself.
///
/// The iPhone and iPad app running on a Mac can build a sheet before the sheet
/// inherits the presenter's environment, and a screen that then reads a
/// missing shared object stops the app. Passing the environment in with the
/// content doesn't depend on that inheritance.
private struct AppSheet<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    @ViewBuilder let sheetContent: () -> SheetContent

    @Environment(AppModel.self) private var app
    #if os(iOS)
    @Environment(AdsController.self) private var ads
    #endif

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
            sheetContent().modifier(environment)
        }
    }

    private var environment: AppEnvironment {
        #if os(iOS)
        AppEnvironment(model: app, ads: ads)
        #else
        AppEnvironment(model: app)
        #endif
    }
}

extension View {
    /// Use instead of `sheet(isPresented:onDismiss:content:)`.
    func appSheet<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(AppSheet(isPresented: isPresented, onDismiss: onDismiss, sheetContent: content))
    }
}
