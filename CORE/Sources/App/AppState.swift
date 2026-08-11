import Foundation
import SwiftUI
import Combine

/// Top-level app orchestration: which screen is showing, today's earned
/// Adventure Time, condition updates, and applying adventure results.
@MainActor
final class AppState: ObservableObject {

    enum Screen: Equatable {
        case onboarding
        case drawing
        case generating
        case reveal
        case camp
        case adventure
        case evolution(ElementalCore)
        case settings
    }

    @Published var screen: Screen = .onboarding
    @Published var gameState: GameState
    @Published var todayRecord: DailyRecord?
    @Published var pendingSummary: AdventureSummary?
    @Published var generationError: String?

    /// Swap for a `SimulatedScreenTimeProvider` in the simulator, or a
    /// remote generator when server-side art lands.
    let screenTime: ScreenTimeProviding
    let generator: CreatureGenerating
    private let store = GameStore.shared

    init(screenTime: ScreenTimeProviding? = nil,
         generator: CreatureGenerating = HeuristicCreatureGenerator()) {
        #if targetEnvironment(simulator)
        self.screenTime = screenTime ?? SimulatedScreenTimeProvider()
        #else
        self.screenTime = screenTime ?? DeviceActivityScreenTimeProvider()
        #endif
        self.generator = generator

        var state = store.load()
        // Reset the daily usage meter when the day rolls over.
        let today = DayKey.today()
        if state.adventureUsageDay != today {
            state.adventureUsageDay = today
            state.adventureSecondsUsedToday = 0
        }
        self.gameState = state

        if state.creature == nil {
            screen = state.hasCompletedOnboarding ? .drawing : .onboarding
        } else {
            screen = .camp
        }
        refreshDailyRecord()
    }

    var creature: Creature? { gameState.creature }

    // MARK: - Daily Adventure Time

    /// Evaluates today's usage into an Attention Score and Adventure Time,
    /// records it, and updates the creature's condition.
    func refreshDailyRecord() {
        let usage = screenTime.todayUsage()
        let result = AttentionScoreCalculator.evaluate(
            distractionMinutes: usage.distractionMinutes,
            totalScreenMinutes: usage.totalScreenMinutes
        )
        let record = DailyRecord(
            day: usage.day,
            distractionMinutes: usage.distractionMinutes,
            totalScreenMinutes: usage.totalScreenMinutes,
            attentionScore: result.attentionScore,
            adventureSecondsEarned: result.adventureSeconds
        )
        todayRecord = record
        gameState.dailyRecords[usage.day] = record
        updateCondition()
        persist()
    }

    /// Adventure Time still available today.
    var adventureSecondsAvailable: Int {
        guard let record = todayRecord else { return 0 }
        return max(0, record.adventureSecondsEarned - gameState.adventureSecondsUsedToday)
    }

    // MARK: - Condition system

    /// The creature's condition follows a rolling view of recent days.
    /// Bad days pull it down; good days pull it back up — a positive
    /// feedback loop, not a punishment system. Always recoverable.
    private func updateCondition() {
        guard var creature = gameState.creature else { return }

        let recentDays = (0..<3).compactMap { offset -> DailyRecord? in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return gameState.dailyRecords[DayKey.key(for: date)]
        }
        guard !recentDays.isEmpty else { return }
        let average = recentDays.map(\.attentionScore).reduce(0, +) / Double(recentDays.count)
        let goodStreak = recentDays.prefix(while: { $0.attentionScore >= Tuning.goodDayScore }).count

        switch average {
        case ..<Tuning.badDayScore:          creature.condition = .weak
        case ..<55:                          creature.condition = .tired
        case ..<Tuning.goodDayScore:         creature.condition = .normal
        case ..<90:                          creature.condition = .happy
        default:                             creature.condition = goodStreak >= 2 ? .energised : .happy
        }

        // Happiness drifts toward the attention average.
        let target = Int(average)
        if creature.happiness < target { creature.happiness = min(100, creature.happiness + 5) }
        if creature.happiness > target { creature.happiness = max(10, creature.happiness - 3) }

        gameState.creature = creature
    }

    /// True if today is better than yesterday — used for "Milo is
    /// recovering." messaging.
    var isImproving: Bool {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()),
              let yesterdayRecord = gameState.dailyRecords[DayKey.key(for: yesterday)],
              let today = todayRecord else { return false }
        return today.attentionScore > yesterdayRecord.attentionScore
    }

    // MARK: - Creature creation

    func createCreature(from drawingData: DrawingSubmission) {
        screen = .generating
        Task {
            do {
                let creature = try await generator.generate(
                    from: drawingData.drawing,
                    canvasSize: drawingData.canvasSize,
                    name: drawingData.name
                )
                gameState.creature = creature
                gameState.hasCompletedOnboarding = true
                persist()
                screen = .reveal
            } catch {
                generationError = "Something went wrong bringing your creature to life. Try again?"
                screen = .drawing
            }
        }
    }

    // MARK: - Adventure flow

    func beginAdventure() -> AdventureEngine? {
        guard let creature = gameState.creature, adventureSecondsAvailable >= 10 else { return nil }
        let engine = AdventureEngine(
            creature: creature,
            gameState: gameState,
            secondsAvailable: adventureSecondsAvailable
        )
        engine.onEnd = { [weak self] creature, summary, frozen in
            self?.finishAdventure(creature: creature, summary: summary, frozen: frozen)
        }
        screen = .adventure
        return engine
    }

    private func finishAdventure(creature: Creature, summary: AdventureSummary, frozen: AdventureSnapshot?) {
        gameState.creature = creature
        gameState.frozenAdventure = frozen
        gameState.adventureSecondsUsedToday += summary.secondsPlayed
        gameState.hasCompletedTutorialBattle = true

        for (coreKey, count) in summary.fragmentsFound {
            if let core = ElementalCore(rawValue: coreKey) {
                gameState.addFragments(count, for: core)
            }
        }
        for (itemKey, count) in summary.itemsFound {
            if let item = ItemKind(rawValue: itemKey) {
                gameState.addItem(item, count: count)
            }
        }

        pendingSummary = summary
        persist()

        // A completed Core triggers evolution — the emotional payoff.
        if let newCore = gameState.completedUnclaimedCore {
            screen = .evolution(newCore)
        } else {
            screen = .camp
        }
    }

    /// Consumes fragments, grants the Core, and evolves the creature.
    func claimCore(_ core: ElementalCore) {
        guard var creature = gameState.creature else { return }
        creature.acquire(core: core)
        gameState.fragments[core.rawValue] = max(0, gameState.fragmentCount(for: core) - Tuning.fragmentsPerCore)
        gameState.creature = creature
        persist()
        screen = .camp
    }

    // MARK: - Persistence

    func persist() {
        store.save(gameState)
    }
}
