#if os(iOS)
import AuthenticationServices
import RetroGuideKit
import UIKit

/// Plex's sign-in page in a sheet that shares Safari's sign-in. The page never
/// returns to the app, so the owner closes the sheet once the code is approved.
@MainActor
final class PlexSignInSheet: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func open(_ url: URL) {
        close()
        let session: ASWebAuthenticationSession
        if #available(iOS 17.4, *) {
            session = ASWebAuthenticationSession(url: url, callback: .customScheme(PlexAPI.signInCallbackScheme)) { _, _ in }
        } else {
            session = ASWebAuthenticationSession(url: url, callbackURLScheme: PlexAPI.signInCallbackScheme) { _, _ in }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        session.start()
    }

    func close() {
        session?.cancel()
        session = nil
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            PresentingViewController.current?.view.window ?? ASPresentationAnchor()
        }
    }
}
#endif
