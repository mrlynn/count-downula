import SwiftUI

@main
struct CountdownulaWatchApp: App {
    @State private var store = WatchStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            rootView
                .environment(store)
                .tint(.countdownulaBlood)
        }
        .onChange(of: scenePhase) { _, phase in
            // Pick up anything CloudKit imported while we were in the background.
            if phase == .active { store.reload() }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-complicationGallery") {
            ComplicationGallery()
        } else {
            WatchCountdownList()
        }
        #else
        WatchCountdownList()
        #endif
    }
}
