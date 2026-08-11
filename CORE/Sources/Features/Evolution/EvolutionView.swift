import SwiftUI

/// The evolution sequence: a completed Core is claimed and the creature
/// visibly transforms. Predictable in mechanics, exciting in presentation.
struct EvolutionView: View {
    @EnvironmentObject private var appState: AppState
    let newCore: ElementalCore

    @State private var phase = 0   // 0 build-up → 1 flash → 2 evolved
    @State private var glowScale: CGFloat = 1

    var body: some View {
        guard let creature = appState.creature else { return AnyView(EmptyView()) }

        // Preview of the creature after claiming, for the reveal.
        var evolved = creature
        evolved.acquire(core: newCore)

        return AnyView(ZStack {
            RadialGradient(
                colors: [newCore.color.opacity(0.3), .black],
                center: .center, startRadius: 0, endRadius: 500
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                switch phase {
                case 0:
                    VStack(spacing: 16) {
                        Text("\(newCore.symbol) \(newCore.displayName) Core complete!")
                            .font(.title2.bold())
                            .foregroundStyle(newCore.color)
                        CreatureSpriteView(creature: creature, size: 190, animated: false)
                            .scaleEffect(glowScale)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                                    glowScale = 1.08
                                }
                            }
                        Text("Something is happening to \(creature.name)…")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                case 1:
                    Circle()
                        .fill(newCore.color)
                        .frame(width: 320, height: 320)
                        .blur(radius: 60)
                        .transition(.scale)
                default:
                    VStack(spacing: 18) {
                        CreatureSpriteView(creature: evolved, size: 220)
                        Text("\(creature.name) has \(evolved.evolutionStage == creature.evolutionStage ? "grown stronger" : "evolved")!")
                            .font(.title.bold())
                            .foregroundStyle(.white)
                        if evolved.evolutionStage != creature.evolutionStage {
                            Text("Stage \(evolved.evolutionStage.rawValue) — \(evolved.evolutionStage.displayName)")
                                .font(.headline)
                                .foregroundStyle(newCore.color)
                        }
                        VStack(spacing: 6) {
                            Text("New ability unlocked")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                            Text("\(newCore.ability.name) — \(newCore.ability.description)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                    }
                    .transition(.opacity)
                }

                Spacer()

                if phase >= 2 {
                    Button {
                        appState.claimCore(newCore)
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                withAnimation(.easeIn(duration: 0.4)) { phase = 1 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
                withAnimation(.easeOut(duration: 0.8)) { phase = 2 }
            }
        })
    }
}
