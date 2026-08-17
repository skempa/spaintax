import SwiftUI

/// Full-screen celebration when Growth Points cross an evolution
/// threshold. Predictable in mechanics, exciting in presentation.
struct LiteEvolutionView: View {
    @EnvironmentObject private var app: LiteAppState
    let stage: EvolutionStage
    @State private var revealed = false

    var body: some View {
        guard let creature = app.creature else { return AnyView(EmptyView()) }
        let color = creature.cores.first?.color ?? .cyan

        return AnyView(ZStack {
            RadialGradient(colors: [color.opacity(0.35), Theme.bgTop],
                           center: .center, startRadius: 0, endRadius: 500)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()
                CreatureSpriteView(creature: creature, size: revealed ? 230 : 170)
                    .animation(.spring(duration: 0.8), value: revealed)
                if revealed {
                    VStack(spacing: 10) {
                        Text("\(creature.name) has evolved!")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Theme.text)
                        Text("Stage \(stage.rawValue) — \(stage.displayName)")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(color)
                        Text("Grown from \(app.lite.growthPoints) Growth Points of real-world focus.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textDim)
                    }
                    .transition(.opacity)
                }
                Spacer()
                if revealed {
                    Button {
                        app.celebration = nil
                    } label: {
                        Text("Continue")
                    }
                    .buttonStyle(.primary)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation { revealed = true }
            }
        })
    }
}
