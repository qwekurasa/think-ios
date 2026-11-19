import Foundation

/// Single source of truth for the seven-day idea lifecycle.
/// Pure calculations keep the rules deterministic and easy to test.
enum ThinkIdeaRules {
    static let lifetime: TimeInterval = 7 * 24 * 60 * 60
    static let reviewCooldown: TimeInterval = 24 * 60 * 60
    static let fadingWindow: TimeInterval = 24 * 60 * 60

    static func deadline(lastTouched: Date, protectedUntil: Date?) -> Date {
        max(lastTouched.addingTimeInterval(lifetime), protectedUntil ?? .distantPast)
    }

    static func isExpired(lastTouched: Date, protectedUntil: Date?, now: Date) -> Bool {
        now >= deadline(lastTouched: lastTouched, protectedUntil: protectedUntil)
    }

    static func isFading(lastTouched: Date, protectedUntil: Date?, now: Date) -> Bool {
        let timeLeft = deadline(lastTouched: lastTouched, protectedUntil: protectedUntil).timeIntervalSince(now)
        return timeLeft > 0 && timeLeft <= fadingWindow
    }

    static func shouldRewardReview(lastReward: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastReward) >= reviewCooldown
    }

    static func remainingDays(lastTouched: Date, protectedUntil: Date?, now: Date) -> Int {
        let seconds = deadline(lastTouched: lastTouched, protectedUntil: protectedUntil).timeIntervalSince(now)
        return max(0, Int(ceil(seconds / (24 * 60 * 60))))
    }
}
