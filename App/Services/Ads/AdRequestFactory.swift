#if os(iOS)
import GoogleMobileAds

/// Builds ad requests for non-personalized ads only: RetroGuide never asks to
/// track people across apps.
enum AdRequestFactory {
    private enum Parameter {
        static let nonPersonalized = "npa"
        static let enabled = "1"
    }

    static func make() -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = [Parameter.nonPersonalized: Parameter.enabled]
        request.register(extras)
        return request
    }
}
#endif
