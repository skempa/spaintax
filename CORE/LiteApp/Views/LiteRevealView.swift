import SwiftUI

/// The payoff moment. Two shapes:
///
/// - **Spawning** (a Tripo run is in flight): drawing → a pulsing Core-
///   coloured orb with a single narrative line while the concept art is
///   painted → the concept art itself with the name and Core, and a note
///   that the 3D body takes a few minutes more.
/// - **Not spawning** (no key / skipped): the original sprite reveal.
struct LiteRevealView: View {
    @EnvironmentObject private var app: LiteAppState
    @State private var stage = 0
    @State private var canEscape = false

    var body: some View {
        guard let creature = app.creature else { return AnyView(EmptyView()) }
        let core = creature.cores[0]
        let spawning = app.isSpawning || app.enhancer.conceptImage != nil
        let concept = app.enhancer.conceptImage

        return AnyView(VStack(spacing: 28) {
            Spacer()

            switch stage {
            case 0:
                if let original = GameStore.shared.loadImage(named: creature.appearance.originalDrawingFile) {
                    VStack(spacing: 16) {
                        Text("You drew this…")
                            .font(.title3)
                            .foregroundStyle(Theme.textDim)
                        Image(uiImage: original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                    }
                    .transition(.opacity)
                }
            default:
                if spawning, let concept {
                    conceptReveal(creature: creature, core: core, image: concept)
                        .transition(.scale.combined(with: .opacity))
                } else if spawning {
                    spawnPlaceholder(core: core)
                        .transition(.opacity)
                } else {
                    spriteReveal(creature: creature, core: core)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Spacer()

            if stage >= 1 && (!spawning || concept != nil || canEscape) {
                Button {
                    app.screen = .companion
                } label: {
                    Text(spawning ? "Go to the egg" : "Meet it in your room")
                }
                .buttonStyle(.primary)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: concept != nil)
        .animation(.easeInOut(duration: 0.4), value: canEscape)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation(.easeInOut(duration: 0.8)) { stage = 1 }
            }
            // If concept art is slow, let the player go wait in the room.
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { canEscape = true }
        })
    }

    // MARK: Spawning

    private func spawnPlaceholder(core: ElementalCore) -> some View {
        VStack(spacing: 26) {
            SpawnOrb(color: core.color)
                .frame(width: 180, height: 180)
            VStack(spacing: 8) {
                Text(app.enhancer.stage.narrative)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.text)
                    .id(app.enhancer.stage)
                    .transition(.opacity)
                Text("Its egg is already waiting in your room.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textFaint)
            }
            .animation(.easeInOut, value: app.enhancer.stage)
        }
    }

    private func conceptReveal(creature: Creature, core: ElementalCore, image: UIImage) -> some View {
        VStack(spacing: 20) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 240, height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: core.color.opacity(0.55), radius: 24)
            Text(creature.name)
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.text)
            VStack(spacing: 6) {
                Text("\(core.symbol) \(core.displayName) Core")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(core.color)
                Text(core.identity)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textDim)
            }
            if app.isSpawning {
                Text("\(creature.name) is in its egg in your room.\nIt hatches when its body is ready — a few minutes. We'll let you know.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textFaint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    // MARK: Not spawning

    private func spriteReveal(creature: Creature, core: ElementalCore) -> some View {
        VStack(spacing: 20) {
            CreatureSpriteView(creature: creature, size: 210)
            Text(creature.name)
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.text)
            VStack(spacing: 6) {
                Text("\(core.symbol) \(core.displayName) Core")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(core.color)
                Text(core.identity)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textDim)
            }
            if !creature.analysis.impressions.isEmpty {
                Text("The Core chose it for its " + creature.analysis.impressions.joined(separator: ", ") + ".")
                    .font(.footnote.italic())
                    .foregroundStyle(Theme.textFaint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}

/// A slowly breathing orb with a few orbiting motes — the "something is
/// forming" placeholder shown before the concept art arrives.
struct SpawnOrb: View {
    let color: Color
    @State private var breathe = false
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.55), color.opacity(0.0)],
                                     center: .center, startRadius: 10, endRadius: 100))
                .scaleEffect(breathe ? 1.15 : 0.9)
            Circle()
                .fill(color.opacity(0.85))
                .frame(width: 70, height: 70)
                .blur(radius: 2)
                .scaleEffect(breathe ? 1.06 : 0.94)
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .offset(y: -78)
                    .rotationEffect(.degrees(Double(i) * 72 + (spin ? 360 : 0)))
                    .opacity(0.9)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathe = true }
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}
