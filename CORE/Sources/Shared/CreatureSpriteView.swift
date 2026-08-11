import SwiftUI

/// Renders the creature in 2D (camp, reveal, evolution) from its processed
/// drawing image, with Core-tinted aura and per-stage adornments so each
/// evolution visibly changes it.
struct CreatureSpriteView: View {
    let creature: Creature
    var size: CGFloat = 200
    var animated: Bool = true

    @State private var bob = false

    private var image: UIImage? {
        GameStore.shared.loadImage(named: creature.appearance.processedImageFile)
    }

    var body: some View {
        ZStack {
            // Aura: one ring per Core, so the collection is visible at a glance.
            ForEach(Array(creature.cores.enumerated()), id: \.offset) { index, core in
                Circle()
                    .stroke(core.color.opacity(0.55), lineWidth: 3)
                    .frame(width: size + CGFloat(index) * 18, height: size + CGFloat(index) * 18)
                    .blur(radius: 2)
            }

            // Stage glow grows with evolution.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [primaryColor.opacity(glowOpacity), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.7
                    )
                )
                .frame(width: size * 1.4, height: size * 1.4)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .shadow(color: primaryColor.opacity(0.8), radius: creature.evolutionStage == .origin ? 6 : 14)
            } else {
                // Fallback silhouette if the image is missing.
                Image(systemName: "pawprint.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(primaryColor)
            }

            // Ascended creatures gain an orbiting crown of Core motes.
            if creature.evolutionStage >= .ascended {
                ForEach(Array(creature.cores.enumerated()), id: \.offset) { index, core in
                    Text(core.symbol)
                        .font(.system(size: 18))
                        .offset(orbitOffset(index: index, count: creature.cores.count))
                }
            }
        }
        .offset(y: bob ? -6 : 6)
        .animation(
            animated ? .easeInOut(duration: 2.2).repeatForever(autoreverses: true) : nil,
            value: bob
        )
        .onAppear { if animated { bob = true } }
    }

    private var primaryColor: Color {
        creature.cores.first?.color ?? .white
    }

    private var glowOpacity: Double {
        switch creature.evolutionStage {
        case .origin:   return 0.25
        case .awakened: return 0.4
        case .ascended: return 0.55
        }
    }

    private func orbitOffset(index: Int, count: Int) -> CGSize {
        let angle = (Double(index) / Double(max(count, 1))) * 2 * .pi - .pi / 2
        let radius = size * 0.62
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }
}

/// Compact condition badge used at camp and in the adventure HUD.
struct ConditionBadge: View {
    let condition: CreatureCondition

    var body: some View {
        Text(condition.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.25), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch condition {
        case .energised: return .yellow
        case .happy:     return .green
        case .normal:    return .white
        case .tired:     return .orange
        case .weak:      return .red
        }
    }
}
