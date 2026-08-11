import SwiftUI

/// Everything overlaid on the AR world: the countdown, event prompts,
/// combat gestures and feedback. Combat must be understandable within
/// seconds: tap = attack, swipe = dodge, hold = Core ability.
struct AdventureHUD: View {
    @ObservedObject var engine: AdventureEngine
    @State private var flashOpacity: Double = 0

    var body: some View {
        ZStack {
            // Full-screen gesture layer, active only in combat.
            if case .combat = engine.phase {
                combatGestureLayer
            }

            VStack {
                topBar
                Spacer()
                eventLayer
            }
            .padding()

            combatFlashView
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 8) {
            Text(engine.formattedTime)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(engine.secondsRemaining <= 30 ? .orange : .white)
                .shadow(radius: 4)

            // Creature health.
            HStack(spacing: 8) {
                Text("❤️")
                healthBar(
                    value: engine.creatureHealth,
                    max: engine.creature.stats.maxHealth,
                    tint: .green
                )
            }
            .frame(maxWidth: 220)

            // Enemy health while fighting.
            if case .combat(let enemy) = engine.phase {
                HStack(spacing: 8) {
                    Text(enemy.isBoss ? "👿" : "😈")
                    healthBar(value: enemy.health, max: enemy.maxHealth, tint: .red)
                }
                .frame(maxWidth: 220)
                Text(enemy.kind.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private func healthBar(value: Int, max maxValue: Int, tint: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.4))
                Capsule().fill(tint)
                    .frame(width: geo.size.width * CGFloat(Swift.max(0, Swift.min(1, Double(value) / Double(Swift.max(maxValue, 1))))))
            }
        }
        .frame(height: 10)
    }

    // MARK: - Events

    @ViewBuilder
    private var eventLayer: some View {
        switch engine.phase {
        case .exploring:
            VStack(spacing: 10) {
                logView
                Button("Return to camp") { engine.leaveAdventure() }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

        case .somethingNearby(let message):
            promptCard(message) {
                Button("Follow \(engine.creature.name)") { engine.investigate() }
                    .buttonStyle(HUDButtonStyle(color: .cyan))
            }

        case .choice(let enemy):
            promptCard("A \(enemy.kind.displayName) blocks the path!") {
                HStack(spacing: 16) {
                    Button("Fight") { engine.chooseFight() }
                        .buttonStyle(HUDButtonStyle(color: .red))
                    Button("Explore") { engine.chooseExplore() }
                        .buttonStyle(HUDButtonStyle(color: .blue))
                }
            }

        case .discovery(let reward):
            promptCard(reward.title) {
                VStack(spacing: 8) {
                    if let core = reward.fragmentCore, reward.fragmentCount > 0 {
                        Text("\(core.symbol) \(core.displayName) Fragment ×\(reward.fragmentCount)")
                            .font(.headline)
                            .foregroundStyle(core.color)
                    }
                    if let item = reward.item {
                        Text("🎒 \(item.displayName)")
                            .font(.headline)
                            .foregroundStyle(.yellow)
                    }
                    Button("Collect") { engine.collectDiscovery() }
                        .buttonStyle(HUDButtonStyle(color: .green))
                }
            }

        case .combat:
            VStack(spacing: 6) {
                logView
                Text("Tap to attack · Swipe to dodge · Hold for \(engine.creature.cores.first?.ability.name ?? "ability")")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                if engine.abilityCooldownRemaining > 0 {
                    Text("Ability ready in \(Int(engine.abilityCooldownRemaining))s")
                        .font(.caption2)
                        .foregroundStyle(.orange.opacity(0.8))
                }
            }
            .padding(.bottom, 12)

        case .frozen, .complete:
            EmptyView()
        }
    }

    private var logView: some View {
        VStack(spacing: 2) {
            ForEach(engine.eventLog.suffix(3), id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .shadow(radius: 2)
            }
        }
    }

    private func promptCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            content()
        }
        .padding(20)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
        .padding(.bottom, 20)
    }

    // MARK: - Combat gestures

    private var combatGestureLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { engine.perform(.tapAttack) }
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { _ in engine.perform(.swipeDodge) }
            )
            .onLongPressGesture(minimumDuration: 0.5) {
                engine.perform(.ability)
            }
    }

    private var combatFlashView: some View {
        Group {
            if let flash = engine.combatFlash {
                Text(flash)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(flash.hasPrefix("-") ? .red : .yellow)
                    .shadow(radius: 4)
                    .opacity(flashOpacity)
                    .onAppear {
                        flashOpacity = 1
                        withAnimation(.easeOut(duration: 0.9)) { flashOpacity = 0 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                            if engine.combatFlash == flash { engine.combatFlash = nil }
                        }
                    }
                    .id(flash + String(describing: engine.secondsRemaining))
            }
        }
        .offset(y: -60)
    }
}

struct HUDButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 26)
            .padding(.vertical, 10)
            .background(color.opacity(configuration.isPressed ? 0.5 : 0.85), in: Capsule())
            .foregroundStyle(.white)
    }
}
