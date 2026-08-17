import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

/// Distraction configuration plus (simulator) debug usage sliders.
struct LiteSettingsView: View {
    @EnvironmentObject private var app: LiteAppState
    @Environment(\.dismiss) private var dismiss

    #if canImport(FamilyControls)
    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false
    #endif

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let record = app.todayRecord {
                        LabeledContent("Distraction apps", value: minutesLabel(record.distractionMinutes))
                        LabeledContent("Total screen time", value: minutesLabel(record.totalScreenMinutes))
                        LabeledContent("Attention Score", value: String(format: "%.0f", record.attentionScore))
                        LabeledContent("On track for", value: "+\(app.todayProvisionalPoints) pts tomorrow")
                    }
                    LabeledContent("Growth Points", value: "\(app.lite.growthPoints)")
                    LabeledContent("Streak", value: "\(app.lite.streak) days")
                } header: {
                    Text("Today")
                } footer: {
                    Text("Yesterday's usage becomes Growth Points each morning. Less phone → more growth. Points can never be bought.")
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
                if let simulated = app.screenTime as? SimulatedScreenTimeProvider {
                    SimulatedUsageSection(provider: simulated) { app.refreshDaily() }
                }
                #endif

                Section("About") {
                    LabeledContent("Version", value: "Lite 0.1 (MVP)")
                    Text("Put the phone down. Your creature is growing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #if canImport(FamilyControls)
            .familyActivityPicker(isPresented: $showPicker, selection: $selection)
            .onChange(of: selection) { _, newSelection in
                if let provider = app.screenTime as? DeviceActivityScreenTimeProvider {
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
}

#if targetEnvironment(simulator)
/// Debug sliders standing in for Screen Time data in the simulator.
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
