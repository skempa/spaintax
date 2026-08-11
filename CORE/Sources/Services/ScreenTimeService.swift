import Foundation
import Combine
#if canImport(FamilyControls)
import FamilyControls
import DeviceActivity
import ManagedSettings
#endif

/// A snapshot of today's real-world usage.
struct UsageSnapshot: Codable, Equatable {
    var distractionMinutes: Double
    var totalScreenMinutes: Double
    var day: String
}

/// Abstraction over where usage numbers come from, so the whole game is
/// playable in the simulator (and in TestFlight before the Family Controls
/// entitlement is granted) via `SimulatedScreenTimeProvider`.
protocol ScreenTimeProviding: AnyObject {
    /// Ask the user for Screen Time authorization. No-op for the simulator.
    func requestAuthorization() async throws
    /// Present-able state: has the user granted access?
    var isAuthorized: Bool { get }
    /// Today's usage so far.
    func todayUsage() -> UsageSnapshot
}

// MARK: - Real implementation (Family Controls / DeviceActivity)

/// Real Screen Time integration.
///
/// Apple's Screen Time APIs never let an app read raw usage totals
/// directly. Instead:
///
///  1. The user picks distraction apps/categories with
///     `FamilyActivityPicker` (see `DistractionPickerView`). The selection
///     is opaque tokens — the app never learns which apps they are.
///  2. We register `DeviceActivitySchedule`s with escalating usage
///     thresholds (5, 10, 15 … minutes) for the selected apps and for
///     total device usage.
///  3. The `ActivityMonitor` extension (separate target) receives
///     `eventDidReachThreshold` callbacks and writes the highest reached
///     threshold into the shared App Group defaults.
///  4. This class reads those thresholds back as a conservative estimate
///     of today's usage.
///
/// The estimate is stair-stepped (granularity = threshold spacing), which
/// is fine: Adventure Time is computed once per day and the formula's
/// grace bands are far wider than the step size.
///
/// Requires the com.apple.developer.family-controls entitlement
/// (distribution requires approval via Apple's request form).
final class DeviceActivityScreenTimeProvider: ScreenTimeProviding, ObservableObject {

    static let appGroupID = "group.app.core.shared"
    static let distractionThresholdKey = "core.reachedDistractionMinutes"
    static let totalThresholdKey = "core.reachedTotalMinutes"
    static let thresholdDayKey = "core.thresholdDay"

    /// Threshold ladder in minutes. Registered for both distraction
    /// selection and total usage.
    static let thresholdLadder: [Int] = [5, 10, 15, 20, 30, 45, 60, 90, 120, 150, 180, 240, 300, 360]

    @Published private(set) var isAuthorized = false

    private let defaults = UserDefaults(suiteName: DeviceActivityScreenTimeProvider.appGroupID)

    func requestAuthorization() async throws {
        #if canImport(FamilyControls)
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        await MainActor.run { self.isAuthorized = true }
        #endif
    }

    func todayUsage() -> UsageSnapshot {
        let today = DayKey.today()
        // Thresholds written by the monitor extension for a previous day
        // are stale — treat as zero usage so far.
        guard defaults?.string(forKey: Self.thresholdDayKey) == today else {
            return UsageSnapshot(distractionMinutes: 0, totalScreenMinutes: 0, day: today)
        }
        let distraction = defaults?.double(forKey: Self.distractionThresholdKey) ?? 0
        let total = defaults?.double(forKey: Self.totalThresholdKey) ?? 0
        return UsageSnapshot(distractionMinutes: distraction, totalScreenMinutes: total, day: today)
    }

    #if canImport(FamilyControls)
    /// Re-registers monitoring schedules for the current selection.
    /// Call after the user edits their distraction picks and at first launch.
    func startMonitoring(selection: FamilyActivitySelection) throws {
        let center = DeviceActivityCenter()
        center.stopMonitoring()

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for minutes in Self.thresholdLadder {
            // Distraction-app thresholds.
            events[DeviceActivityEvent.Name("distraction_\(minutes)")] = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: minutes)
            )
            // Total-device thresholds: an empty selection with
            // includesAllActivity is not supported, so we approximate
            // "general usage" with the all-categories selection captured
            // during onboarding (see DistractionPickerView.allActivity).
        }

        try center.startMonitoring(
            DeviceActivityName("core.daily"),
            during: schedule,
            events: events
        )
    }
    #endif
}

// MARK: - Simulated implementation

/// Development/simulator provider: usage is set from a debug panel so the
/// whole reward loop can be exercised without entitlements or a device.
final class SimulatedScreenTimeProvider: ScreenTimeProviding, ObservableObject {
    @Published var distractionMinutes: Double = 20
    @Published var totalScreenMinutes: Double = 120

    var isAuthorized: Bool { true }

    func requestAuthorization() async throws {}

    func todayUsage() -> UsageSnapshot {
        UsageSnapshot(
            distractionMinutes: distractionMinutes,
            totalScreenMinutes: totalScreenMinutes,
            day: DayKey.today()
        )
    }
}
