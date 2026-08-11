import SwiftUI

/// Introduces the concept: an adventure you earn. Positioning is the
/// game, never productivity.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var page = 0

    private struct Page {
        let symbol: String
        let title: String
        let body: String
    }

    private let pages = [
        Page(symbol: "🖍️",
             title: "Draw a creature",
             body: "Anything you like. Crude, strange, beautiful — it doesn't matter. It's yours."),
        Page(symbol: "✨",
             title: "Watch it come alive",
             body: "Your drawing becomes a living companion with one of six elemental Cores. You don't choose which — the drawing does."),
        Page(symbol: "🌍",
             title: "It lives in your world",
             body: "Through your camera, your creature stands in your room, walks your floor, and fights at your side."),
        Page(symbol: "⏳",
             title: "Adventure is earned",
             body: "Each day you get about five minutes in its world. Use your phone less, and you earn more time together.\n\nPut the phone down. Your creature is waiting.")
    ]

    var body: some View {
        VStack {
            Spacer()
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: 20) {
                        Text(pages[index].symbol)
                            .font(.system(size: 72))
                        Text(pages[index].title)
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        Text(pages[index].body)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page)
            .frame(height: 380)

            Spacer()

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    Task {
                        try? await appState.screenTime.requestAuthorization()
                        appState.gameState.hasCompletedOnboarding = true
                        appState.persist()
                        appState.screen = .drawing
                    }
                }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Draw your companion")
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
