import SwiftUI

/// The app's type scale: sized for viewing from a couch on Apple TV (10-foot UI)
/// and at standard reading sizes on iPhone and iPad.
enum Typography {
    enum Size {
        static let display = PlatformMetric.value(tv: CGFloat(76), touch: 40)
        static let title = PlatformMetric.value(tv: CGFloat(52), touch: 28)
        static let headline = PlatformMetric.value(tv: CGFloat(36), touch: 20)
        static let body = PlatformMetric.value(tv: CGFloat(29), touch: 17)
        static let callout = PlatformMetric.value(tv: CGFloat(25), touch: 15)
        static let caption = PlatformMetric.value(tv: CGFloat(22), touch: 13)
        static let micro = PlatformMetric.value(tv: CGFloat(19), touch: 11)
        static let osd = PlatformMetric.value(tv: CGFloat(96), touch: 56)
    }

    /// How far text may shrink to fit before truncating.
    static let minimumScaleFactor: CGFloat = 0.75

    static let display = Font.system(size: Size.display, weight: .heavy, design: .rounded)
    static let title = Font.system(size: Size.title, weight: .bold, design: .rounded)
    static let headline = Font.system(size: Size.headline, weight: .semibold, design: .rounded)
    static let body = Font.system(size: Size.body, weight: .regular)
    static let bodyEmphasis = Font.system(size: Size.body, weight: .semibold)
    static let callout = Font.system(size: Size.callout, weight: .medium)
    static let caption = Font.system(size: Size.caption, weight: .medium)
    static let captionEmphasis = Font.system(size: Size.caption, weight: .bold)
    static let micro = Font.system(size: Size.micro, weight: .semibold)

    /// Time and channel digits use a monospaced face so columns don't jitter.
    static let clock = Font.system(size: Size.callout, weight: .semibold, design: .monospaced)
    static let channelNumber = Font.system(size: Size.headline, weight: .heavy, design: .monospaced)
    static let callSign = Font.system(size: Size.micro, weight: .heavy, design: .monospaced)
    static let osd = Font.system(size: Size.osd, weight: .black, design: .monospaced)
    static let linkCode = Font.system(size: Size.display, weight: .black, design: .monospaced)
}
