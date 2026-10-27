import Foundation

/// Bounded waits for services that explicitly ask a client to slow down.
enum RateLimitRetry {
    private enum Limits {
        static let initialDelay: TimeInterval = 5
        static let maximumWait: TimeInterval = 120
    }

    static func delay(header: String?, attempt: Int, now: Date = .now) -> TimeInterval? {
        let fallback = Limits.initialDelay * pow(2, Double(min(max(attempt, 0), 4)))
        var delay = fallback
        if let header {
            if let seconds = Double(header), seconds.isFinite {
                delay = max(0, seconds)
            } else {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
                if let date = formatter.date(from: header) {
                    delay = max(0, date.timeIntervalSince(now))
                }
            }
        }
        // A longer restriction is surfaced to the caller, never shortened
        // into an early request that would violate the service's limit.
        return delay <= Limits.maximumWait ? delay : nil
    }
}
