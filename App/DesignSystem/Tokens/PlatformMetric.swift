/// Chooses between a value for the 10-foot Apple TV interface and one for the
/// touch interface on iPhone and iPad.
///
/// Every size in the design system is defined once for each, so a view reads
/// the same on both and never needs its own platform checks for sizing.
enum PlatformMetric {
    static func value<Value>(tv: Value, touch: Value) -> Value {
        #if os(tvOS)
        tv
        #else
        touch
        #endif
    }

    /// Whether the app is running with the Siri Remote rather than touch.
    static let isTV = value(tv: true, touch: false)
}
