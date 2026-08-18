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
                    Text("\(app.creature?.name ?? "It") is growing in its egg")
                        .font(.footnote.weight(.semibold))
                    Text(app.enhancer.stage.narrative + " · we'll notify you when it hatches")
                        .font(.caption2)
                        .foregroundStyle(Theme.textFaint)
                        .id(app.enhancer.stage)
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

/// A 2D egg for non-AR surfaces (model view, simulator) while spawning.
struct EggShape: View {
    let color: Color
    @State private var rock = false

    var body: some View {
        ZStack {
            Ellipse()
                .fill(
                    LinearGradient(colors: [color.opacity(0.9), color.opacity(0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    Ellipse().stroke(Color.white.opacity(0.35), lineWidth: 2)
                )
                .shadow(color: color.opacity(0.5), radius: 20)
            ForEach(0..<7, id: \.self) { i in
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: 10, height: 8)
                    .offset(x: CGFloat([-30, 22, -10, 35, -38, 5, 25][i]),
                            y: CGFloat([-50, -30, 10, 30, 40, 60, -70][i]))
            }
        }
        .rotationEffect(.degrees(rock ? 3 : -3), anchor: .bottom)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { rock = true }
        }
    }
}
