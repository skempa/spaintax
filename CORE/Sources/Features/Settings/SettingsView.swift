import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

/// Distraction configuration and (in the simulator) the debug usage panel
/// that stands in for real Screen Time data.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    #if canImport(FamilyControls)
    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false
    #endif

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let record = appState.todayRecord {
                        LabeledContent("Distraction apps", value: minutesLabel(record.distractionMinutes))
                        LabeledContent("Total screen time", value: minutesLabel(record.totalScreenMinutes))
                        LabeledContent("Attention Score", value: String(format: "%.0f", record.attentionScore))
                        LabeledContent("Adventure Time earned", value: secondsLabel(record.adventureSecondsEarned))
                    }
                } header: {
                    Text("Today")
                } footer: {
                    Text("Use your phone less and you earn more Adventure Time — up to 5:00 on a normal day, more on an exceptional one. Adventure Time can never be bought.")
                }

                Section("Distracting apps") {
                    #if canImport(FamilyControls)
                    Button("Choose apps & categories") { showPicker = true }
                    #else
                    Text("App selection requires Screen Time access on a real device.")
                        .foregroundStyle(.secondary)
                    #endif
                }

                #if targetEnvironment(simulator)
                if let simulated = appState.screenTime as? SimulatedScreenTimeProvider {
                    SimulatedUsageSection(provider: simulated) {
                        appState.refreshDailyRecord()
                    }
                }
                #endif

                Section("About") {
                    LabeledContent("Version", value: "0.1 (MVP)")
                    Text("Your attention powers your adventure.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { appState.screen = .camp }
                }
            }
            #if canImport(FamilyControls)
            .familyActivityPicker(isPresented: $showPicker, selection: $selection)
            .onChange(of: selection) { _, newSelection in
                if let provider = appState.screenTime as? DeviceActivityScreenTimeProvider {
                    try? provider.startMonitoring(selection: newSelection)
                }
            }
            #endif
        }
        .preferredColorScheme(.dark)
    }

    private func minutesLabel(_ minutes: Double) -> String {
        let m = Int(minutes)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    private func secondsLabel(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

#if targetEnvironment(simulator)
/// Debug sliders that simulate a day's usage so the reward loop can be
/// tuned and demoed without a device.
struct SimulatedUsageSection: View {
    @ObservedObject var provider: SimulatedScreenTimeProvider
    let onChange: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading) {
                Text("Distraction apps: \(Int(provider.distractionMinutes))m")
                Slider(value: $provider.distractionMinutes, in: 0...300, step: 5) { _ in onChange() }
            }
            VStack(alignment: .leading) {
                Text("Total screen time: \(Int(provider.totalScreenMinutes))m")
                Slider(value: $provider.totalScreenMinutes, in: 0...600, step: 15) { _ in onChange() }
            }
        } header: {
            Text("Simulated usage (debug)")
        } footer: {
            Text("Stands in for Screen Time data in the simulator.")
        }
    }
}
#endif
