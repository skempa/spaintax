import Foundation

/// The complete persisted game state. Saved after every meaningful change;
/// the creature, world state, progression and daily behaviour records are
/// all permanent.
struct GameState: Codable {
    var creature: Creature?

    /// Core fragments collected, keyed by Core. A full Core requires
    /// `Tuning.fragmentsPerCore` fragments — intentionally multi-session.
    var fragments: [String: Int] = [:]

    /// Items in the player's pack.
    var items: [String: Int] = [:]

    /// Zones the player has entered at least once.
    var visitedZones: Set<String> = [MeadowZone.camp.rawValue]

    /// Adventure state frozen when time ran out (nil if the last session
    /// ended cleanly at camp).
    var frozenAdventure: AdventureSnapshot?

    /// One record per day, keyed by yyyy-MM-dd.
    var dailyRecords: [String: DailyRecord] = [:]

    /// Seconds of Adventure Time already spent today.
    var adventureSecondsUsedToday: Int = 0
    /// The day `adventureSecondsUsedToday` refers to.
    var adventureUsageDay: String = ""

    var hasCompletedOnboarding = false
    var hasCompletedTutorialBattle = false

    /// Progress for the simplified CORE Lite app (draw → focus → evolve).
    /// Optional so saves from the full game keep decoding unchanged.
    var lite: LiteProgress?

    // MARK: - Fragments

    func fragmentCount(for core: ElementalCore) -> Int {
        fragments[core.rawValue] ?? 0
    }

    mutating func addFragments(_ count: Int, for core: ElementalCore) {
        fragments[core.rawValue] = fragmentCount(for: core) + count
    }

    /// A Core whose fragment threshold has been reached and which the
    /// creature does not yet hold, if any.
    var completedUnclaimedCore: ElementalCore? {
        guard let creature else { return nil }
        return ElementalCore.allCases.first { core in
            !creature.cores.contains(core) && fragmentCount(for: core) >= Tuning.fragmentsPerCore
        }
    }

    // MARK: - Items

    mutating func addItem(_ kind: ItemKind, count: Int = 1) {
        items[kind.rawValue] = (items[kind.rawValue] ?? 0) + count
    }
}

/// CORE Lite progression: Growth Points from daily behaviour and focus
/// sessions drive evolution directly — no combat, no fragments.
struct LiteProgress: Codable, Equatable {
    var growthPoints: Int = 0
    /// Day (yyyy-MM-dd) whose *previous* day has been scored and awarded.
    var pointsAwardedDay: String = ""
    var focusMinutesTotal: Int = 0
    /// Consecutive good days (Attention Score ≥ Tuning.goodDayScore).
    var streak: Int = 0
    /// Last evolution stage celebrated, so each threshold fires once.
    var celebratedStage: Int = 1
    /// Active focus session, persisted so a killed app can reconcile.
    var activeFocus: FocusRecord?
    /// In-flight creature generation, persisted so a suspended or killed
    /// app can resume polling Tripo instead of losing the run.
    var spawn: SpawnRecord?
}

/// A focus session in flight (or being reconciled after relaunch).
struct FocusRecord: Codable, Equatable {
    var startedAt: Date
    var minutes: Int
}

/// Everything needed to resume a Tripo generation from where it left off.
/// Each stage writes its task ID here as soon as the task is created;
/// on resume, stages with an ID skip creation and go straight to waiting.
struct SpawnRecord: Codable, Equatable {
    var startedAt: Date
    var description: String?
    var drawingToken: String?
    var conceptTaskID: String?
    var conceptImageURL: String?
    var conceptFile: String?
    var modelTaskID: String?
    var rigCheckTaskID: String?
    var rigType: String?
    var rigTaskID: String?
    var retargetTaskID: String?
    var convertTaskID: String?
    var animated: Bool = false
    var notes: [String] = []
    /// Set when the run died with an error; cleared by a fresh run.
    var failedMessage: String?
}

/// One day of real-world behaviour and the resulting reward.
struct DailyRecord: Codable, Equatable {
    var day: String                     // yyyy-MM-dd
    var distractionMinutes: Double
    var totalScreenMinutes: Double
    var attentionScore: Double          // 0–100
    var adventureSecondsEarned: Int
}

enum DayKey {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar.current
        f.timeZone = TimeZone.current
        return f
    }()

    static func today() -> String { formatter.string(from: Date()) }

    static func key(for date: Date) -> String { formatter.string(from: date) }
}
