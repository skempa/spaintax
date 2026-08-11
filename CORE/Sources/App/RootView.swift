import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch appState.screen {
            case .onboarding:
                OnboardingView()
            case .drawing:
                DrawingCanvasView()
            case .generating:
                GeneratingView()
            case .reveal:
                CreatureRevealView()
            case .camp:
                CampView()
            case .adventure:
                AdventureContainerView()
            case .evolution(let core):
                EvolutionView(newCore: core)
            case .settings:
                SettingsView()
            }
        }
        .animation(.easeInOut(duration: 0.4), value: appState.screen)
    }
}

/// Brief "the AI is working" interstitial while the creature is generated.
struct GeneratingView: View {
    @State private var messageIndex = 0
    private let messages = [
        "Studying your drawing…",
        "Tracing its silhouette…",
        "Listening for a heartbeat…",
        "Choosing its Core…",
        "Waking it up…"
    ]

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.6)
                .tint(.white)
            Text(messages[messageIndex])
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .transition(.opacity)
                .id(messageIndex)
        }
        .onReceive(Timer.publish(every: 1.4, on: .main, in: .common).autoconnect()) { _ in
            withAnimation { messageIndex = (messageIndex + 1) % messages.count }
        }
    }
}
