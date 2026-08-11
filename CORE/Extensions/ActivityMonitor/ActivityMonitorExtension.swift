import DeviceActivity
import Foundation

/// DeviceActivity monitor extension (separate target: `ActivityMonitor`).
///
/// iOS wakes this extension when a registered usage threshold is crossed.
/// We record the highest threshold reached today in the shared App Group;
/// the main app reads it back as a conservative usage estimate. The app
/// never learns *which* apps were used — only that the selected set
/// crossed N minutes.
final class ActivityMonitorExtension: DeviceActivityMonitor {

    private let defaults = UserDefaults(suiteName: "group.app.core.shared")

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // New day: reset the recorded thresholds.
        stampToday()
        defaults?.set(0.0, forKey: "core.reachedDistractionMinutes")
        defaults?.set(0.0, forKey: "core.reachedTotalMinutes")
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        stampToday()

        // Event names are "<kind>_<minutes>", e.g. "distraction_45".
        let parts = event.rawValue.split(separator: "_")
        guard parts.count == 2, let minutes = Double(parts[1]) else { return }

        let key = parts[0] == "distraction"
            ? "core.reachedDistractionMinutes"
            : "core.reachedTotalMinutes"

        let current = defaults?.double(forKey: key) ?? 0
        if minutes > current {
            defaults?.set(minutes, forKey: key)
        }
    }

    private func stampToday() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        defaults?.set(formatter.string(from: Date()), forKey: "core.thresholdDay")
    }
}
