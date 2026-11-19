import Foundation

@main
struct ThinkIdeaRulesChecks {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = now.addingTimeInterval(-ThinkIdeaRules.lifetime)
        precondition(ThinkIdeaRules.isExpired(lastTouched: old, protectedUntil: nil, now: now),
                     "Exactly seven days must expire")
        precondition(!ThinkIdeaRules.isExpired(lastTouched: now.addingTimeInterval(-ThinkIdeaRules.lifetime + 1),
                                               protectedUntil: nil, now: now),
                     "One second before the deadline must be active")
        precondition(ThinkIdeaRules.isFading(lastTouched: now.addingTimeInterval(-6.5 * 86400),
                                            protectedUntil: nil, now: now),
                     "Last-day warning must appear")
        precondition(!ThinkIdeaRules.isFading(lastTouched: old, protectedUntil: nil, now: now),
                     "Expired ideas should not be marked merely fading")
        let protection = now.addingTimeInterval(30 * 86400)
        precondition(!ThinkIdeaRules.isExpired(lastTouched: old, protectedUntil: protection, now: now),
                     "Protection must override the normal deadline")
        precondition(ThinkIdeaRules.deadline(lastTouched: old, protectedUntil: protection) == protection,
                     "Protection should set the deadline")
        precondition(!ThinkIdeaRules.shouldRewardReview(lastReward: now.addingTimeInterval(-23 * 3600), now: now),
                     "No repeat bonus inside 24 hours")
        precondition(ThinkIdeaRules.shouldRewardReview(lastReward: now.addingTimeInterval(-24 * 3600), now: now),
                     "Review becomes eligible after 24 hours")
        precondition(ThinkIdeaRules.remainingDays(lastTouched: now, protectedUntil: nil, now: now) == 7,
                     "New ideas should start with seven days")
        precondition(ThinkIdeaRules.remainingDays(lastTouched: old, protectedUntil: nil, now: now) == 0,
                     "Expired ideas should show zero days")
        print("Think v2 idea lifecycle checks passed")
    }
}
