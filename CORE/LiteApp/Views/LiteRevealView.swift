import SwiftUI

/// The payoff moment: the drawing is alive, and its Core is revealed.
struct LiteRevealView: View {
    @EnvironmentObject private var app: LiteAppState
    @State private var stage = 0

    var body: some View {
        guard let creature = app.creature else { return AnyView(EmptyView()) }
        let core = creature.cores[0]

        return AnyView(VStack(spacing: 28) {
            Spacer()

            switch stage {
            case 0:
                if let original = GameStore.shared.loadImage(named: creature.appearance.originalDrawingFile) {
                    VStack(spacing: 16) {
                        Text("You drew this…")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.7))
                        Image(uiImage: original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                    }
                }
            default:
                VStack(spacing: 20) {
                    CreatureSpriteView(creature: creature, size: 210)
                    Text(creature.name)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    VStack(spacing: 6) {
                        Text("\(core.symbol) \(core.displayName) Core")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(core.color)
                        Text(core.identity)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    if !creature.analysis.impressions.isEmpty {
                        Text("The Core chose it for its " + creature.analysis.impressions.joined(separator: ", ") + ".")
                            .font(.footnote.italic())
                            .foregroundStyle(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            if stage >= 1 {
                Button {
                    app.screen = .companion
                } label: {
                    Text("Meet it in your room")
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation(.easeInOut(duration: 0.8)) { stage = 1 }
            }
        })
    }
}
