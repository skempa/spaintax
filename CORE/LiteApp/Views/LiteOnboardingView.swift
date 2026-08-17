import SwiftUI

/// Onboarding pitched at the focus loop — the story of the creature, in four
/// beats: you draw it, it comes to life, it lives with you, your focus grows it.
struct LiteOnboardingView: View {
    @EnvironmentObject private var app: LiteAppState
    @State private var page = 0

    private struct Page { let symbol, title, body: String }

    private var pages: [Page] {
        let awaken = Tuning.evolutionPointThresholds[1]
        let ascend = Tuning.evolutionPointThresholds[2]
        return [
            Page(symbol: "🖍️",
                 title: "Draw a creature",
                 body: "Anything you like. Crude, strange, beautiful — it's yours, and it's permanent."),
            Page(symbol: "✨",
                 title: "It comes to life",
                 body: "An AI reads your drawing, paints it, and sculpts it in 3D.\n\nThat part takes a few minutes. We'll give you a nudge when it's ready."),
            Page(symbol: "🏠",
                 title: "It lives in your room",
                 body: "Through your camera, your creature stands on your floor and waits for you."),
            Page(symbol: "🌱",
                 title: "Your focus makes it grow",
                 body: "Time off your phone earns Growth Points. Focus sessions earn more.\n\nAt \(awaken) points it Awakens. At \(ascend) it Ascends.\n\nPut the phone down. Your creature is growing.")
        ]
    }

    var body: some View {
        VStack {
            Spacer()
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: 20) {
                        Text(pages[index].symbol).font(.system(size: 72))
                        Text(pages[index].title)
                            .font(.largeTitle.bold())
                            .foregroundStyle(Theme.text)
                        Text(pages[index].body)
                            .font(.body)
                            .foregroundStyle(Theme.textDim)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page)
            .frame(height: 420)

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
            }
            .buttonStyle(.primary)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }
}
