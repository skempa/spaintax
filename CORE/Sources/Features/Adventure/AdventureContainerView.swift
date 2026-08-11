import SwiftUI

/// Owns the AdventureEngine for one session and layers the HUD over the
/// AR world.
struct AdventureContainerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var engine: AdventureEngine?

    var body: some View {
        ZStack {
            if let engine {
                #if targetEnvironment(simulator)
                SimulatedMeadowView(engine: engine)
                #else
                ARAdventureView(engine: engine)
                    .ignoresSafeArea()
                #endif
                AdventureHUD(engine: engine)
            } else {
                ProgressView().tint(.white)
            }
        }
        .onAppear {
            if engine == nil {
                engine = appState.beginAdventure()
                engine?.start()
                if engine == nil {
                    // No time available — bounce back to camp.
                    appState.screen = .camp
                }
            }
        }
    }
}

#if targetEnvironment(simulator)
/// Simulator stand-in for the AR camera: a painted Meadow so the whole
/// loop is playable without a device.
struct SimulatedMeadowView: View {
    @ObservedObject var engine: AdventureEngine

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.2, blue: 0.35), Color(red: 0.08, green: 0.25, blue: 0.12)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack {
                Spacer()
                Text("🌲   🏕️   🌲")
                    .font(.system(size: 48))
                Text("⛰️  The Meadow  ⛰️")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 160)
            }
        }
    }
}
#endif
