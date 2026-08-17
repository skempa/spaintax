import SwiftUI

/// Sits under the status card while the creature is being generated:
/// concept thumbnail + one narrative line, or the failure with a way out.
struct SpawnStatusPill: View {
    @EnvironmentObject private var app: LiteAppState

    var body: some View {
        HStack(spacing: 12) {
            if let concept = app.enhancer.conceptImage {
                Image(uiImage: concept)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                SpawnOrb(color: app.creature?.cores.first?.color ?? Theme.accent)
                    .frame(width: 44, height: 44)
                    .scaleEffect(0.35)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 3) {
                if let failure = app.spawnFailedMessage, !app.isSpawning {
                    Text("Couldn't finish bringing it to life")
                        .font(.footnote.weight(.semibold))
                    Text(failure)
                        .font(.caption2)
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(2)
                    HStack(spacing: 14) {
                        Button("Try again") { app.retrySpawn() }
                            .foregroundStyle(Theme.accent)
                        Button("Keep blocks") { app.abandonSpawn() }
                            .foregroundStyle(Theme.textDim)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.top, 2)
                } else {
                    Text(app.enhancer.stage.narrative)
                        .font(.footnote.weight(.semibold))
                        .id(app.enhancer.stage)
                    Text("A few minutes · we'll notify you")
                        .font(.caption2)
                        .foregroundStyle(Theme.textFaint)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(Theme.text)
        .padding(.top, 6)
        .animation(.easeInOut, value: app.enhancer.stage)
    }
}
