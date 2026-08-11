import Foundation

/// Every tuning variable in one place. The spec is explicit that the exact
/// formulas are tuning variables to be validated through testing — change
/// them here, not inline.
enum Tuning {
    // MARK: Adventure Time

    /// Normal daily maximum: 5 minutes.
    static let normalMaxAdventureSeconds = 300
    /// Exceptional bonus for very low usage: up to 2 extra minutes.
    static let maxBonusSeconds = 120
    /// Everyone gets at least one minute — the relationship with the
    /// creature should never be fully severed by one bad day.
    static let minimumAdventureSeconds = 60

    // MARK: Attention Score inputs

    /// Distraction-app minutes under this threshold cost nothing.
    static let distractionGraceMinutes = 30.0
    /// Seconds of Adventure Time lost per distraction minute over the grace.
    static let distractionCostSecondsPerMinute = 2.0
    /// Total device minutes under this threshold cost nothing.
    static let totalScreenGraceMinutes = 180.0
    /// Seconds lost per total-screen minute over the grace.
    static let totalScreenCostSecondsPerMinute = 0.5

    /// Bonus eligibility: distraction under this…
    static let bonusDistractionThresholdMinutes = 10.0
    /// …and total screen time under this.
    static let bonusTotalThresholdMinutes = 90.0
    /// Bonus seconds per distraction minute saved below the threshold.
    static let bonusPerDistractionMinute = 6.0
    /// Bonus seconds per total minute saved below the threshold.
    static let bonusPerTotalMinute = 1.0

    // MARK: Progression

    /// Fragments needed to complete a Core. A full Core should take
    /// multiple sessions — this intentionally stretches the content.
    static let fragmentsPerCore = 10

    // MARK: Condition

    /// Attention Score at or above this counts as a "good day".
    static let goodDayScore = 70.0
    /// Attention Score at or below this counts as a "bad day".
    static let badDayScore = 35.0
}

/// Pure Attention Score / Adventure Time calculator.
///
/// Reproduces the spec's worked examples:
///  - 105 min distraction + 120 min total  → 2:30
///  - 15 min distraction + 105 min total   → 5:00
///  - near-zero usage                       → up to 7:00
enum AttentionScoreCalculator {

    struct Result: Equatable {
        var attentionScore: Double      // 0–100, for display and condition
        var adventureSeconds: Int
    }

    static func evaluate(distractionMinutes: Double, totalScreenMinutes: Double) -> Result {
        let base = Double(Tuning.normalMaxAdventureSeconds)

        let distractionOverage = max(0, distractionMinutes - Tuning.distractionGraceMinutes)
        let totalOverage = max(0, totalScreenMinutes - Tuning.totalScreenGraceMinutes)

        var seconds = base
            - distractionOverage * Tuning.distractionCostSecondsPerMinute
            - totalOverage * Tuning.totalScreenCostSecondsPerMinute

        // Exceptional bonus: only when both distraction and overall usage
        // are genuinely low.
        if distractionMinutes <= Tuning.bonusDistractionThresholdMinutes,
           totalScreenMinutes <= Tuning.bonusTotalThresholdMinutes {
            let bonus = (Tuning.bonusDistractionThresholdMinutes - distractionMinutes) * Tuning.bonusPerDistractionMinute
                      + (Tuning.bonusTotalThresholdMinutes - totalScreenMinutes) * Tuning.bonusPerTotalMinute
            seconds += min(bonus, Double(Tuning.maxBonusSeconds))
        }

        let clamped = max(Double(Tuning.minimumAdventureSeconds),
                          min(seconds, base + Double(Tuning.maxBonusSeconds)))

        // Score maps earned time onto 0–100 for display and the condition
        // system (100 = full normal allowance or better).
        let score = min(100, (clamped / base) * 100)

        return Result(attentionScore: score, adventureSeconds: Int(clamped.rounded()))
    }
}
