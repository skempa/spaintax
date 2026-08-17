import SwiftUI

/// "Bring to life in HD": runs the Tripo pipeline with live stage
/// progress and the concept-art reveal, then swaps the creature's model.
struct EnhanceSheet: View {
    @EnvironmentObject private var app: LiteAppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var enhancer = TripoCreatureEnhancer()
    @State private var started = false
    @State private var keyInput = ""
    @State private var hasKey = KeychainHelper.tripoKey() != nil
    @State private var descriptionInput = ""

    private let stages: [(TripoCreatureEnhancer.Stage, String)] = [
        (.uploading,  "Upload your drawing"),
        (.conceptArt, "AI concept art"),
        (.modeling,   "Full 3D model"),
        (.rigging,    "Skeleton"),
        (.animating,  "Animations"),
        (.exporting,  "Into your room"),
    ]

    var body: some View {
        VStack(spacing: 20) {
            Text("Bring \(app.creature?.name ?? "it") to life")
                .font(.title2.bold())
                .padding(.top, 24)

            if let concept = enhancer.conceptImage {
                VStack(spacing: 6) {
                    Image(uiImage: concept)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Text("The AI's interpretation of your drawing")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .transition(.scale.combined(with: .opacity))
            } else if let original = GameStore.shared.loadImage(named: app.creature?.appearance.originalDrawingFile ?? "") {
                Image(uiImage: original)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 140)
                    .opacity(0.8)
            }

            if started {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(stages.indices, id: \.self) { index in
                        stageRow(index)
                    }
                }
                .padding(.horizontal, 24)
            } else {
                Text("Your drawing becomes polished concept art, then a fully 3D — ideally animated — creature that stands in your room.\n\nTakes a few minutes and uses Tripo credits from your account.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                // The player's half of the prompt; style + rig pose are
                // appended automatically.
                TextField(
                    "Describe your creature (optional) — species, personality, details…",
                    text: $descriptionInput,
                    axis: .vertical
                )
                .lineLimit(2...4)
                .padding(12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                .onAppear {
                    if descriptionInput.isEmpty {
                        descriptionInput = app.creature?.creatureDescription ?? ""
                    }
                }
            }

            if case .failed(let message) = enhancer.stage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if !enhancer.notes.isEmpty {
                VStack(spacing: 4) {
                    ForEach(enhancer.notes, id: \.self) { note in
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.orange.opacity(0.85))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer()

            actionButton
                .padding(.horizontal, 32)
                .padding(.bottom, 8)

            Text("Generation pipeline \(TripoCreatureEnhancer.pipelineRevision)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.3))
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgTop)
        .foregroundStyle(.white)
        .interactiveDismissDisabled(isRunning)
        .animation(.easeInOut, value: enhancer.stage)
    }

    private var isRunning: Bool {
        switch enhancer.stage {
        case .idle, .done, .failed: return false
        default: return true
        }
    }

    private func stageIndex(_ stage: TripoCreatureEnhancer.Stage) -> Int {
        stages.firstIndex { $0.0 == stage } ?? (stage == .done ? stages.count : -1)
    }

    @ViewBuilder
    private func stageRow(_ index: Int) -> some View {
        let current = stageIndex(enhancer.stage)
        HStack(spacing: 12) {
            if index < current || enhancer.stage == .done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint)
            } else if index == current && isRunning {
                ProgressView().tint(.white).scaleEffect(0.8)
            } else {
                Image(systemName: "circle").foregroundStyle(.white.opacity(0.25))
            }
            Text(stages[index].1)
                .font(.subheadline)
                .foregroundStyle(index <= current ? .white : .white.opacity(0.4))
            Spacer()
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch enhancer.stage {
        case .done:
            Button {
                dismiss()
            } label: {
                Text("Meet the new \(app.creature?.name ?? "creature")")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.mint, in: Capsule())
                    .foregroundStyle(.black)
            }
        case .idle, .failed:
            VStack(spacing: 10) {
                if !hasKey {
                    // First run: collect the Tripo key right here.
                    SecureField("Tripo API key (tsk_…)", text: $keyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    Text("From platform.tripo3d.ai → API Keys. Stored only in this device's Keychain.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                Button {
                    if !hasKey {
                        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        KeychainHelper.saveTripoKey(trimmed)
                        hasKey = KeychainHelper.tripoKey() != nil
                        guard hasKey else { return }
                    }
                    guard let key = KeychainHelper.tripoKey() else { return }
                    app.setCreatureDescription(descriptionInput)
                    started = true
                    enhancer.run(apiKey: key, description: descriptionInput) { result in
                        app.applyEnhancement(result)
                    }
                } label: {
                    Text(startLabel)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canStart ? Color.white : Color.gray.opacity(0.4), in: Capsule())
                        .foregroundStyle(.black)
                }
                .disabled(!canStart)
                Button("Not now") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
        default:
            Button("Cancel") {
                enhancer.cancel()
                dismiss()
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var startLabel: String {
        if case .failed = enhancer.stage { return "Try again" }
        return hasKey ? "✨ Start generation" : "Save key & start"
    }

    private var canStart: Bool {
        hasKey || !keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
