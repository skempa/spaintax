import SwiftUI

/// Camp is home. The creature lives here, wandering on its own so it
/// feels alive even when the player isn't adventuring.
struct CampView: View {
    @EnvironmentObject private var appState: AppState
    @State private var wanderOffset: CGSize = .zero
    @State private var showSummary = false

    var body: some View {
        guard let creature = appState.creature else { return AnyView(EmptyView()) }

        return AnyView(ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.08, blue: 0.15), Color(red: 0.02, green: 0.10, blue: 0.06)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header(creature)

                Spacer()

                CreatureSpriteView(creature: creature, size: 190)
                    .offset(wanderOffset)
                    .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
                        withAnimation(.easeInOut(duration: 4)) {
                            wanderOffset = CGSize(
                                width: CGFloat.random(in: -70...70),
                                height: CGFloat.random(in: -30...40)
                            )
                        }
                    }

                Text(creature.condition.campMessage(name: creature.name, improving: appState.isImproving))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 24)

                Spacer()

                adventurePanel
            }
        }
        .sheet(isPresented: $showSummary) {
            if let summary = appState.pendingSummary {
                AdventureSummaryView(summary: summary, creatureName: creature.name)
            }
        }
        .onAppear {
            showSummary = appState.pendingSummary != nil
        })
    }

    // MARK: - Status header

    private func header(_ creature: Creature) -> some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(creature.name)
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    Text("Level \(creature.level) · \(creature.evolutionStage.displayName)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                ConditionBadge(condition: creature.condition)
                Button {
                    appState.screen = .settings
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            HStack(spacing: 8) {
                ForEach(creature.cores) { core in
                    Text("\(core.symbol) \(core.displayName)")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(core.color.opacity(0.2), in: Capsule())
                        .foregroundStyle(core.color)
                }
                Spacer()
            }

            VStack(spacing: 6) {
                statBar(label: "❤️", value: Double(creature.health), max: 100, tint: .red)
                statBar(label: "😊", value: Double(creature.happiness), max: 100, tint: .yellow)
                statBar(label: "XP", value: Double(creature.xp), max: Double(creature.xpForNextLevel), tint: .cyan,
                        trailing: "\(creature.xp)/\(creature.xpForNextLevel)")
            }

            fragmentStrip
        }
        .padding(20)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func statBar(label: String, value: Double, max: Double, tint: Color, trailing: String? = nil) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.caption)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(tint.opacity(0.8))
                        .frame(width: geo.size.width * CGFloat(min(1, value / Swift.max(max, 1))))
                }
            }
            .frame(height: 8)
            if let trailing {
                Text(trailing).font(.caption2).foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    /// Fragment progress toward the next Core — the "come back tomorrow" hook.
    private var fragmentStrip: some View {
        let missing = ElementalCore.allCases.filter { core in
            !(appState.creature?.cores.contains(core) ?? false) && appState.gameState.fragmentCount(for: core) > 0
        }
        return Group {
            if !missing.isEmpty {
                HStack(spacing: 12) {
                    ForEach(missing) { core in
                        Text("\(core.symbol) \(appState.gameState.fragmentCount(for: core))/\(Tuning.fragmentsPerCore)")
                            .font(.caption2)
                            .foregroundStyle(core.color.opacity(0.9))
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Adventure panel

    private var adventurePanel: some View {
        let available = appState.adventureSecondsAvailable
        let formatted = String(format: "%d:%02d", available / 60, available % 60)

        return VStack(spacing: 12) {
            Text("Today's Adventure")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.5))
            Text(formatted)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(available > 0 ? .white : .white.opacity(0.3))
                .monospacedDigit()

            if appState.gameState.frozenAdventure != nil && available > 0 {
                Text("Your adventure is waiting where you left it.")
                    .font(.caption)
                    .foregroundStyle(.cyan.opacity(0.8))
            }

            if available >= 10 {
                Button {
                    appState.screen = .adventure
                } label: {
                    Text("ENTER WORLD")
                        .font(.headline.weight(.heavy))
                        .tracking(2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing),
                            in: Capsule()
                        )
                        .foregroundStyle(.white)
                }
            } else {
                VStack(spacing: 4) {
                    Text("Adventure Time is spent for today.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(appState.creature?.name ?? "Your creature") will be waiting tomorrow.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.vertical, 12)
            }
        }
        .padding(20)
        .padding(.bottom, 16)
    }
}
