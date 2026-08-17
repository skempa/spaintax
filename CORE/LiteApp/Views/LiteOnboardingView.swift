import SwiftUI

/// Onboarding pitched at the focus loop — no adventure framing.
struct LiteOnboardingView: View {
    @EnvironmentObject private var app: LiteAppState
    @State private var page = 0

    private struct Page { let symbol, title, body: String }

    private let pages = [
        Page(symbol: "🖍️",
             title: "Draw a creature",
             body: "Anything you like. Crude, strange, beautiful — it's yours, and it's permanent."),
        Page(symbol: "🏠",
             title: "It lives in your room",
             body: "Through your camera, your creature stands on your floor and waits for you."),
        Page(symbol: "🌱",
             title: "Your focus makes it grow",
             body: "Time off your phone earns Growth Points. Focus sessions earn more.\n\nEnough points, and your creature evolves.\n\nPut the phone down. Your creature is growing.")
    ]

    var body: some View {
        VStack {
            Spacer()
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: 20) {
                        Text(pages[index].symbol).font(.system(size: 72))
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
            .frame(height: 400)

            Spacer()

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    Task {
                        try? await app.screenTime.requestAuthorization()
                        app.gameState.hasCompletedOnboarding = true
                        app.persist()
                        app.screen = .drawing
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
