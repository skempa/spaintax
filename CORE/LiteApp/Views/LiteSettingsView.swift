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
    @State private var tripoKey = KeychainHelper.tripoKey() ?? ""
    @State private var keySaved = KeychainHelper.tripoKey() != nil
    @State private var claudeKey = KeychainHelper.claudeKey() ?? ""
    @State private var claudeKeySaved = KeychainHelper.claudeKey() != nil
    @State private var descriptionInput = ""
    @State private var showResetDialog = false

    private func saveKey() {
        KeychainHelper.saveTripoKey(tripoKey.trimmingCharacters(in: .whitespacesAndNewlines))
        keySaved = KeychainHelper.tripoKey() != nil
    }

    private func saveClaudeKey() {
        KeychainHelper.saveClaudeKey(claudeKey.trimmingCharacters(in: .whitespacesAndNewlines))
        claudeKeySaved = KeychainHelper.claudeKey() != nil
    }

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

                Section {
                    SecureField("Tripo API key (tsk_…)", text: $tripoKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { saveKey() }
                    if keySaved {
                        Label("Key saved — \"Bring to life in HD\" is available", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.accent)
                    } else if !tripoKey.isEmpty {
                        Button("Save key") { saveKey() }
                    }
                } header: {
                    Text("Tripo AI (HD creature generation)")
                } footer: {
                    Text("Get a key at platform.tripo3d.ai → API Keys. Stored in the device Keychain, used only to talk to Tripo, and each generation spends credits from your Tripo account. For personal builds only — a public release must proxy this through a server.")
                }

                Section {
                    SecureField("Claude API key (sk-ant-…)", text: $claudeKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { saveClaudeKey() }
                    if claudeKeySaved {
                        Label("Key saved — drawings are described automatically", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.accent)
                    } else if !claudeKey.isEmpty {
                        Button("Save key") { saveClaudeKey() }
                    }
                } header: {
                    Text("Claude AI (describes your drawing)")
                } footer: {
                    Text("Get a key at console.anthropic.com. Stored in the device Keychain, used only to look at your drawing and suggest a description you can edit. For personal builds only.")
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

                Section {
                    TextField(
                        "Describe your creature — species, personality, details…",
                        text: $descriptionInput,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                    .onSubmit { app.setCreatureDescription(descriptionInput) }
                    Button("Save description") { app.setCreatureDescription(descriptionInput) }
                        .disabled(descriptionInput == (app.creature?.creatureDescription ?? ""))
                    if app.creature?.appearance.tripoModelFile != nil {
                        Button("Regenerate HD model", role: .destructive) {
                            app.setCreatureDescription(descriptionInput)
                            app.discardHDModel()
                            dismiss()
                        }
                    }
                } header: {
                    Text("Creature")
                } footer: {
                    Text("Your description steers the HD generation; the game-art style and rig-friendly pose are added automatically. Regenerating discards the current HD model (blocks return until the new run finishes) and spends Tripo credits.")
                }

                if let diag = hdModelDiagnostics() {
                    Section {
                        LabeledContent("File", value: diag.name)
                        LabeledContent("Size", value: diag.size)
                        LabeledContent("First zip entry", value: diag.firstEntry)
                    } header: {
                        Text("HD model file (debug)")
                    } footer: {
                        Text("A real USDZ starts with a .usdc/.usda entry. An entry ending in .usdz means Tripo wrapped the model in an outer zip; 'not a zip' means the download saved something else entirely.")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "Lite 0.1 (MVP)")
                    Text("Put the phone down. Your creature is growing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Reset everything", role: .destructive) { showResetDialog = true }
                } header: {
                    Text("Testing")
                } footer: {
                    Text("Deletes your creature, drawings, HD model and all progress, and returns to onboarding. Your Screen Time app selection is kept.")
                }
            }
            .confirmationDialog("Start over from scratch?", isPresented: $showResetDialog, titleVisibility: .visible) {
                Button("Reset, keep API keys", role: .destructive) { performReset(forgetKeys: false) }
                Button("Reset and forget API keys", role: .destructive) { performReset(forgetKeys: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .tint(Theme.accent)
            .navigationTitle("Settings")
            .onAppear {
                if descriptionInput.isEmpty {
                    descriptionInput = app.creature?.creatureDescription ?? ""
                }
            }
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

    private func performReset(forgetKeys: Bool) {
        dismiss()
        // Let the sheet finish dismissing before the root screen swaps out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            app.resetAll(forgetKeys: forgetKeys)
        }
    }

    private func minutesLabel(_ minutes: Double) -> String {
        let m = Int(minutes)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    /// Inspects the downloaded HD model so display failures are
    /// diagnosable: size + the first zip entry name (a USDZ is a zip whose
    /// local-file-header filename starts at byte 30).
    private func hdModelDiagnostics() -> (name: String, size: String, firstEntry: String)? {
        guard let file = app.creature?.appearance.tripoModelFile else { return nil }
        let url = GameStore.shared.directory.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return (file, "unreadable", "—")
        }
        let sizeLabel = data.count >= 1_048_576
            ? String(format: "%.1f MB", Double(data.count) / 1_048_576)
            : "\(data.count / 1024) KB"

        var entry = "not a zip"
        if data.count > 34, data[0] == 0x50, data[1] == 0x4B {   // "PK"
            let nameLength = Int(data[26]) | (Int(data[27]) << 8)
            if nameLength > 0, data.count >= 30 + nameLength,
               let name = String(data: data.subdata(in: 30..<(30 + nameLength)), encoding: .utf8) {
                entry = name
            } else {
                entry = "zip (unreadable entry name)"
            }
        }
        return (file, sizeLabel, entry)
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
