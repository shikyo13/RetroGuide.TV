import Foundation

/// Shifting subtitles against the picture, for subtitle files timed for
/// another release of the same episode (a few seconds early or late).
/// Positive delays show subtitles later.
public enum SubtitleTiming {
    /// How far subtitles can be moved either way.
    public static let range: ClosedRange<TimeInterval> = -30...30
    /// The smallest step, and the precision delays are kept at.
    public static let fineStep: TimeInterval = 0.1
    /// Steps a held remote button takes as it repeats: fine at first, then faster.
    public static let acceleratingSteps: [TimeInterval] = [0.1, 0.1, 0.1, 0.5, 0.5, 1]

    /// `delay` within ``range``, rounded to ``fineStep``.
    public static func clamped(_ delay: TimeInterval) -> TimeInterval {
        let bounded = min(max(delay, range.lowerBound), range.upperBound)
        return (bounded / fineStep).rounded() * fineStep
    }

    /// The step for the `repeatCount`th repeat of a held button (0 for the first press).
    public static func step(forRepeat repeatCount: Int) -> TimeInterval {
        acceleratingSteps[min(max(repeatCount, .zero), acceleratingSteps.count - 1)]
    }

    /// "In sync", "1.5 s later" or "2 s earlier".
    public static func description(of delay: TimeInterval) -> String {
        let delay = clamped(delay)
        guard abs(delay) >= fineStep / 2 else { return "In sync" }
        let seconds = abs(delay).formatted(.number.precision(.fractionLength(0...1)))
        return delay > .zero ? "\(seconds) s later" : "\(seconds) s earlier"
    }
}
