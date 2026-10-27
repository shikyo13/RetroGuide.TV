#if os(iOS)
import UIKit

/// The view controller ads and consent forms present from: the top of the
/// key window's presentation stack.
@MainActor
enum PresentingViewController {
    static var current: UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
#endif
