import SwiftUI

/// "Adventure complete" — shown back at camp after the session ends or
/// freezes.
struct AdventureSummaryView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let summary: AdventureSummary
    let creatureName: String

    var body: some View {
        VStack(spacing: 20) {
            Text("Adventure complete")
                .font(.title.bold())
                .padding(.top, 32)

            VStack(spacing: 12) {
                row("⚔️", "\(summary.enemiesDefeated) enemies defeated")
                row("✨", "+\(summary.xpEarned) XP")
                if summary.levelsGained > 0 {
                    row("⬆️", "Level up ×\(summary.levelsGained)!")
                }
                ForEach(summary.fragmentsFound.sorted(by: { $0.key < $1.key }), id: \.key) { key, count in
                    if let core = ElementalCore(rawValue: key) {
                        row(core.symbol, "\(core.displayName) Fragment ×\(count)")
                    }
                }
                ForEach(summary.itemsFound.sorted(by: { $0.key < $1.key }), id: \.key) { key, count in
                    if let item = ItemKind(rawValue: key) {
                        row("🎒", "\(item.displayName) ×\(count)")
                    }
                }
            }
            .padding(24)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))

            Spacer()

            Text("\(creatureName) will be waiting tomorrow.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                appState.pendingSummary = nil
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white, in: Capsule())
                    .foregroundStyle(.black)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.black)
        .foregroundStyle(.white)
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(symbol)
            Text(text)
            Spacer()
        }
        .font(.body.weight(.medium))
    }
}
