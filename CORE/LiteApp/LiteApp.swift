import SwiftUI

/// CORE Lite ("CORE Focus"): the simplest testable form of the product.
/// Draw a creature, it lives in your room through AR, real-world focus
/// earns Growth Points, points evolve the creature.
@main
struct LiteApp: App {
    @StateObject private var app = LiteAppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LiteRootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:     app.appDidBecomeActive()
            case .background: app.appDidEnterBackground(); app.persist()
            default:          break
            }
        }
    }
}

struct LiteRootView: View {
    @EnvironmentObject private var app: LiteAppState

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch app.screen {
            case .onboarding: LiteOnboardingView()
            case .drawing:    LiteDrawingView()
            case .generating: LiteGeneratingView()
            case .reveal:     LiteRevealView()
            case .companion:  CompanionView()
            }
        }
        .foregroundStyle(Theme.text)
        .animation(.easeInOut(duration: 0.4), value: app.screen)
    }
}

struct LiteGeneratingView: View {
    @State private var index = 0
    private let messages = [
        "Studying your drawing…",
        "Tracing its silhouette…",
        "Listening for a heartbeat…",
        "Choosing its Core…",
        "Waking it up…"
    ]

    var body: some View {
        VStack(spacing: 24) {
            ProgressView().scaleEffect(1.6).tint(Theme.accent)
            Text(messages[index])
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.textDim)
                .id(index)
        }
        .onReceive(Timer.publish(every: 1.4, on: .main, in: .common).autoconnect()) { _ in
            withAnimation { index = (index + 1) % messages.count }
        }
    }
}
