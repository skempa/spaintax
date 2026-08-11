import SwiftUI

@main
struct COREApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Re-evaluate earned time whenever the player returns —
                // usage may have accrued while the app was closed.
                appState.refreshDailyRecord()
            case .background:
                appState.persist()
            default:
                break
            }
        }
    }
}
