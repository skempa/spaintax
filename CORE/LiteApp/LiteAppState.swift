import Foundation
import SwiftUI
import Combine
import UserNotifications
import UIKit

/// CORE Lite orchestration: draw → companion in your room → Growth
/// Points from real-world focus → evolution. No combat, no adventure.
@MainActor
final class LiteAppState: ObservableObject {

    enum Screen: Equatable {
        case onboarding
        case drawing
        case generating
        /// The AI has looked at the drawing; the player confirms/edits what it is.
        case describing
        case reveal
        case companion
    }

    @Published var screen: Screen = .onboarding
    @Published var gameState: GameState
    @Published var todayRecord: DailyRecord?
    @Published var generationError: String?

    // MARK: Describe step

    @Published var describeDraft = ""
    @Published var isDescribing = false
    @Published var describeError: String?
    /// Set when a points threshold was just crossed — shows the
    /// evolution celebration.
    @Published var celebration: EvolutionStage?

    // MARK: Focus session

    enum FocusPhase: Equatable {
        case idle
        case running(endsAt: Date)
        case finished(pointsEarned: Int, completed: Bool)
    }
    @Published var focusPhase: FocusPhase = .idle
    @Published var focusRemaining: TimeInterval = 0

    private var focusTimer: AnyCancellable?
    private var backgroundedAt: Date?
    private var lockedWhileBackgrounded = false

    let screenTime: ScreenTimeProviding
    let generator: CreatureGenerating
    private let store = GameStore.shared

    /// Simulator sessions run at 2 s per "minute" so the loop is testable.
    var secondsPerFocusMinute: TimeInterval {
        #if targetEnvironment(simulator)
        return 2
        #else
        return 60
        #endif
    }

    init(screenTime: ScreenTimeProviding? = nil,
         generator: CreatureGenerating = HeuristicCreatureGenerator()) {
        #if targetEnvironment(simulator)
        self.screenTime = screenTime ?? SimulatedScreenTimeProvider()
        #else
        self.screenTime = screenTime ?? DeviceActivityScreenTimeProvider()
        #endif
        self.generator = generator

        var state = store.load()
        if state.lite == nil { state.lite = LiteProgress() }
        self.gameState = state

        screen = state.creature == nil
            ? (state.hasCompletedOnboarding ? .drawing : .onboarding)
            : .companion

        // Locking the phone is GOOD during focus — track it so a lock
        // never ends a session.
        NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.lockedWhileBackgrounded = true }
        }

        reconcileInterruptedFocus()
        refreshDaily()
    }

    var creature: Creature? { gameState.creature }
    var lite: LiteProgress { gameState.lite ?? LiteProgress() }

    // MARK: - Points & evolution

    var stage: EvolutionStage { Tuning.liteStage(forPoints: lite.growthPoints) }

    var nextThreshold: Int? {
        Tuning.evolutionPointThresholds.first { $0 > lite.growthPoints }
    }

    /// Progress 0–1 toward the next evolution (1 when fully evolved).
    var evolutionProgress: Double {
        guard let next = nextThreshold else { return 1 }
        let previous = Tuning.evolutionPointThresholds.last { $0 <= lite.growthPoints } ?? 0
        return Double(lite.growthPoints - previous) / Double(max(next - previous, 1))
    }

    private func award(points: Int) {
        guard points > 0 else { return }
        var progress = lite
        progress.growthPoints += points
        gameState.lite = progress
        checkEvolution()
        persist()
    }

    private func checkEvolution() {
        var progress = lite
        let reached = Tuning.liteStage(forPoints: progress.growthPoints)
        if reached.rawValue > progress.celebratedStage {
            progress.celebratedStage = reached.rawValue
            gameState.lite = progress
            celebration = reached
        }
    }

    // MARK: - Daily behaviour scoring

    /// Awards the previous day's finalised score once per day, updates the
    /// streak, refreshes today's provisional numbers and the creature's
    /// condition.
    func refreshDaily() {
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

        // New day: yesterday's record is final — convert it to points.
        var progress = lite
        if progress.pointsAwardedDay != usage.day {
            progress.pointsAwardedDay = usage.day
            if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()),
               let final = gameState.dailyRecords[DayKey.key(for: yesterday)] {
                progress.growthPoints += Tuning.litePoints(forEarnedSeconds: final.adventureSecondsEarned)
                progress.streak = final.attentionScore >= Tuning.goodDayScore ? progress.streak + 1 : 0
            }
            gameState.lite = progress
            checkEvolution()
        }

        updateCondition()
        persist()
    }

    /// Points today is on track to earn (finalised tomorrow).
    var todayProvisionalPoints: Int {
        guard let record = todayRecord else { return 0 }
        return Tuning.litePoints(forEarnedSeconds: record.adventureSecondsEarned)
    }

    private func updateCondition() {
        guard var creature = gameState.creature else { return }
        let recent = (0..<3).compactMap { offset -> DailyRecord? in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return gameState.dailyRecords[DayKey.key(for: date)]
        }
        guard !recent.isEmpty else { return }
        let average = recent.map(\.attentionScore).reduce(0, +) / Double(recent.count)
        switch average {
        case ..<Tuning.badDayScore:  creature.condition = .weak
        case ..<55:                  creature.condition = .tired
        case ..<Tuning.goodDayScore: creature.condition = .normal
        case ..<90:                  creature.condition = .happy
        default:                     creature.condition = .energised
        }
        gameState.creature = creature
    }

    var isImproving: Bool {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()),
              let previous = gameState.dailyRecords[DayKey.key(for: yesterday)],
              let today = todayRecord else { return false }
        return today.attentionScore > previous.attentionScore
    }

    // MARK: - Focus sessions

    func startFocus(minutes: Int) {
        let now = Date()
        var progress = lite
        progress.activeFocus = FocusRecord(startedAt: now, minutes: minutes)
        gameState.lite = progress
        persist()

        let duration = TimeInterval(minutes) * secondsPerFocusMinute
        focusPhase = .running(endsAt: now.addingTimeInterval(duration))
        focusRemaining = duration
        scheduleCompletionNotification(in: duration)

        focusTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tickFocus() }
    }

    private func tickFocus() {
        guard case .running(let endsAt) = focusPhase else { return }
        focusRemaining = max(0, endsAt.timeIntervalSinceNow)
        if focusRemaining <= 0 {
            finishFocus(completed: true)
        }
    }

    /// Player gives up early: completed minutes still bank (recoverable,
    /// never punitive).
    func abandonFocus() {
        finishFocus(completed: false)
    }

    private func finishFocus(completed: Bool) {
        focusTimer?.cancel(); focusTimer = nil
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.focusNotificationID])

        guard let record = lite.activeFocus else { focusPhase = .idle; return }
        let minutesDone = completed
            ? record.minutes
            : min(record.minutes, Int(Date().timeIntervalSince(record.startedAt) / secondsPerFocusMinute))
        let points = minutesDone / Tuning.focusMinutesPerPoint

        var progress = lite
        progress.activeFocus = nil
        progress.focusMinutesTotal += minutesDone
        gameState.lite = progress
        focusPhase = .finished(pointsEarned: points, completed: completed)
        award(points: points)
    }

    func dismissFocusResult() { focusPhase = .idle }

    /// A session that was running when the app was killed: award what was
    /// actually completed.
    private func reconcileInterruptedFocus() {
        guard let record = lite.activeFocus else { return }
        let duration = TimeInterval(record.minutes) * secondsPerFocusMinute
        let completed = Date() >= record.startedAt.addingTimeInterval(duration)
        finishFocus(completed: completed)
        if case .finished(let pts, _) = focusPhase, pts == 0 { focusPhase = .idle }
    }

    // MARK: App lifecycle during focus

    func appDidEnterBackground() {
        guard case .running = focusPhase else { return }
        backgroundedAt = Date()
        lockedWhileBackgrounded = false
    }

    func appDidBecomeActive() {
        refreshDaily()
        guard case .running = focusPhase, let left = backgroundedAt else { return }
        backgroundedAt = nil
        // Locked phone = focusing. Unlocked app-switching beyond the
        // grace period ends the session, banking completed minutes.
        if !lockedWhileBackgrounded,
           Date().timeIntervalSince(left) > Tuning.focusGraceSeconds {
            finishFocus(completed: false)
        }
    }

    private func scheduleCompletionNotification(in seconds: TimeInterval) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Focus complete"
            content.body = "\(self.gameState.creature?.name ?? "Your creature") grew from your focus. Come see!"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
            center.add(UNNotificationRequest(identifier: Self.focusNotificationID, content: content, trigger: trigger))
        }
    }

    static let focusNotificationID = "core.focus.done"

    // MARK: - Creature creation

    func createCreature(from submission: DrawingSubmission) {
        screen = .generating
        Task {
            do {
                let creature = try await generator.generate(
                    from: submission.drawing,
                    canvasSize: submission.canvasSize,
                    name: submission.name
                )
                gameState.creature = creature
                gameState.hasCompletedOnboarding = true
                persist()
                describeDraft = ""
                describeError = nil
                screen = .describing
            } catch {
                generationError = "Something went wrong bringing your creature to life. Try again?"
                screen = .drawing
            }
        }
    }

    // MARK: - Describe (Claude vision)

    var hasClaudeKey: Bool { KeychainHelper.claudeKey() != nil }

    /// Asks Claude to put the drawing into words and fills the draft the
    /// player edits. Silent no-op without a key; errors are surfaced for
    /// the view to show inline.
    func describeDrawing() async {
        guard let key = KeychainHelper.claudeKey(),
              let creature = gameState.creature,
              let image = store.loadImage(named: creature.appearance.originalDrawingFile) else { return }
        isDescribing = true
        describeError = nil
        defer { isDescribing = false }
        do {
            let text = try await ClaudeVisionClient(apiKey: key).describeDrawing(image)
            if !text.isEmpty { describeDraft = text }
        } catch {
            describeError = error.localizedDescription
        }
    }

    /// Player confirmed the description. Moves on to the reveal; once the
    /// spawn pipeline lands (next increment) this also kicks off generation.
    func confirmDescriptionAndContinue() {
        screen = .reveal
    }

    // MARK: - Tripo enhancement

    /// Applies a completed Tripo generation to the creature: the AR view
    /// switches from the voxel mesh to the generated USDZ model.
    func applyEnhancement(_ result: TripoCreatureEnhancer.Result) {
        guard var creature = gameState.creature else { return }
        creature.appearance.conceptImageFile = result.conceptImageFile ?? creature.appearance.conceptImageFile
        creature.appearance.tripoModelFile = result.modelFile ?? creature.appearance.tripoModelFile
        if result.modelFile != nil {
            creature.appearance.tripoModelRevision = (creature.appearance.tripoModelRevision ?? 0) + 1
        }
        gameState.creature = creature
        persist()
    }

    var hasTripoKey: Bool { KeychainHelper.tripoKey() != nil }

    /// Persists the player's creature description (drives HD generation).
    func setCreatureDescription(_ text: String) {
        guard var creature = gameState.creature else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        creature.creatureDescription = trimmed.isEmpty ? nil : trimmed
        gameState.creature = creature
        persist()
    }

    /// Drops a broken HD model so generation can be retried; keeps the
    /// concept art.
    func discardHDModel() {
        guard var creature = gameState.creature else { return }
        creature.appearance.tripoModelFile = nil
        gameState.creature = creature
        persist()
    }

    // MARK: - Reset (testing)

    /// Wipes everything back to first launch so the onboarding + creation
    /// flow can be trialled repeatedly. Optionally forgets the API keys too.
    func resetAll(forgetKeys: Bool) {
        focusTimer?.cancel(); focusTimer = nil
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        store.wipeAll()
        var fresh = GameState()
        fresh.lite = LiteProgress()
        gameState = fresh

        focusPhase = .idle
        focusRemaining = 0
        celebration = nil
        generationError = nil
        todayRecord = nil
        describeDraft = ""
        describeError = nil

        if forgetKeys {
            KeychainHelper.saveTripoKey("")
            KeychainHelper.saveClaudeKey("")
        }

        screen = .onboarding
    }

    // MARK: - Persistence

    func persist() { store.save(gameState) }
}
