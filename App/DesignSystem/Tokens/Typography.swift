import SwiftUI

/// The app's type scale, sized for viewing from a couch (10-foot UI).
enum Typography {
    enum Size {
        static let display: CGFloat = 76
        static let title: CGFloat = 52
        static let headline: CGFloat = 36
        static let body: CGFloat = 29
        static let callout: CGFloat = 25
        static let caption: CGFloat = 22
        static let micro: CGFloat = 19
        static let osd: CGFloat = 96
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
