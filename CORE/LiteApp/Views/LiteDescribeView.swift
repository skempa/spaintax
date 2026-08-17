import SwiftUI

/// Between drawing and spawning: the AI says what it sees, the player
/// corrects it. The confirmed sentence steers the concept art and 3D model.
/// Also the natural first-run moment to collect the two API keys — they're
/// asked for right where they're needed, with the drawing on screen.
struct LiteDescribeView: View {
    @EnvironmentObject private var app: LiteAppState

    @State private var claudeKeyInput = ""
    @State private var tripoKeyInput = ""
    @State private var skippedClaude = false
    @FocusState private var editingDescription: Bool

    private var hasClaudeKey: Bool { app.hasClaudeKey }
    private var hasTripoKey: Bool { app.hasTripoKey }
    private var canContinue: Bool {
        !app.describeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !app.isDescribing
    }

    var body: some View {
        guard let creature = app.creature else { return AnyView(EmptyView()) }

        return AnyView(ScrollView {
            VStack(spacing: 22) {
                Text("Tell it what it is")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.text)
                    .padding(.top, 24)

                if let drawing = GameStore.shared.loadImage(named: creature.appearance.originalDrawingFile) {
                    Image(uiImage: drawing)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .padding(12)
                        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 20))
                }

                if hasClaudeKey || skippedClaude {
                    descriptionEditor
                } else {
                    claudeKeyPrompt
                }

                if (hasClaudeKey || skippedClaude) && !hasTripoKey {
                    tripoKeyPrompt
                }

                Spacer(minLength: 12)

                actions
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .task {
            if hasClaudeKey && app.describeDraft.isEmpty {
                await app.describeDrawing()
            }
        })
    }

    // MARK: Description

    private var descriptionEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if app.isDescribing {
                    ProgressView().tint(Theme.accent).scaleEffect(0.8)
                    Text("Looking at your drawing…")
                } else if hasClaudeKey && app.describeError == nil {
                    Text("Here's what I see — fix anything I got wrong.")
                } else {
                    Text("Describe your creature in a sentence.")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.textDim)

            TextField("An orange cat with big ears and a jagged grin",
                      text: $app.describeDraft, axis: .vertical)
                .lineLimit(2...5)
                .font(.title3)
                .foregroundStyle(Theme.text)
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .focused($editingDescription)
                .disabled(app.isDescribing)

            if let error = app.describeError {
                HStack(alignment: .top, spacing: 8) {
                    Text("Couldn't read the drawing: \(error)")
                        .font(.caption)
                        .foregroundStyle(Theme.textFaint)
                    Spacer()
                    Button("Retry") { Task { await app.describeDrawing() } }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    // MARK: Keys

    private var claudeKeyPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Let an AI read your drawing")
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text("Claude looks at what you drew and puts it into words. You'll get to correct it. Needs a Claude API key — stored only in this phone's Keychain.")
                .font(.footnote)
                .foregroundStyle(Theme.textDim)
            SecureField("Claude API key (sk-ant-…)", text: $claudeKeyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Button("Save & describe") {
                    KeychainHelper.saveClaudeKey(claudeKeyInput.trimmingCharacters(in: .whitespacesAndNewlines))
                    claudeKeyInput = ""
                    Task { await app.describeDrawing() }
                }
                .buttonStyle(.ghost)
                .disabled(claudeKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                Button("Skip — I'll write it myself") { skippedClaude = true }
                    .font(.footnote)
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .padding(16)
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
    }

    private var tripoKeyPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bring it to life in 3D")
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text("Tripo turns your creature into a 3D model that stands in your room. Needs a Tripo API key (spends Tripo credits) — stored only in this phone's Keychain. Without one, your creature appears as blocks.")
                .font(.footnote)
                .foregroundStyle(Theme.textDim)
            SecureField("Tripo API key (tsk_…)", text: $tripoKeyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            Button("Save key") {
                KeychainHelper.saveTripoKey(tripoKeyInput.trimmingCharacters(in: .whitespacesAndNewlines))
                tripoKeyInput = ""
            }
            .buttonStyle(.ghost)
            .disabled(tripoKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(16)
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                app.setCreatureDescription(app.describeDraft)
                app.confirmDescriptionAndContinue()
            } label: {
                Text(hasTripoKey ? "That's it — bring it to life" : "That's it")
            }
            .buttonStyle(.primary)
            .disabled(!canContinue)

            if hasTripoKey {
                Button("Keep it as blocks for now") {
                    app.setCreatureDescription(app.describeDraft)
                    app.screen = .reveal
                }
                .font(.footnote)
                .foregroundStyle(Theme.textFaint)
            }
        }
    }
}
