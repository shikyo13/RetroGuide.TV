#if os(iOS)
import AuthenticationServices
import RetroGuideKit
import UIKit

/// Plex's sign-in page in a sheet that shares Safari's sign-in. The page never
/// returns to the app, so the owner closes the sheet once the code is approved.
@MainActor
final class PlexSignInSheet: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    /// Counts pages opened, so a late answer from an earlier one is ignored.
    private var opened = 0

    /// Opens `url`. `onClosedByViewer` runs if the viewer closes the page
    /// (not when the owner closes it after approval).
    func open(_ url: URL, onClosedByViewer: @escaping @MainActor () -> Void) {
        close()
        opened += 1
        let thisPage = opened
        let session: ASWebAuthenticationSession
        // The page never calls back, so an error here is the viewer's Cancel.
        let completion: ASWebAuthenticationSession.CompletionHandler = { [weak self] _, error in
            guard (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin else { return }
            Task { @MainActor in
                guard let self, self.session != nil, self.opened == thisPage else { return }
                self.session = nil
                onClosedByViewer()
            }
        }
        if #available(iOS 17.4, *) {
            session = ASWebAuthenticationSession(url: url, callback: .customScheme(PlexAPI.signInCallbackScheme), completionHandler: completion)
        } else {
            session = ASWebAuthenticationSession(url: url, callbackURLScheme: PlexAPI.signInCallbackScheme, completionHandler: completion)
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
