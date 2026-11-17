#if os(iOS)
import UIKit

/// Navigation-bar titles shrink to fit instead of ending in "…", so long
/// translated page names (and small iPhones) show the whole title.
enum NavigationTitleFit {
    @MainActor static func install() {
        let label = UILabel.appearance(whenContainedInInstancesOf: [UINavigationBar.self])
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = Typography.navigationTitleMinimumScaleFactor
    }
}
#endif
