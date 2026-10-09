import SwiftUI

/// Count Downcula on Apple TV: your countdowns (synced through iCloud from the iPhone, Mac and
/// watch) and the Crypt, each one full screen at a press, for the room to watch zero together.
@main
struct CountdownculaTVApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = TVStore.shared
    @State private var presenting: Presentation?
    @State private var tab = "countdowns"

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                Tab("Countdowns", systemImage: "hourglass", value: "countdowns") {
                    HomeView(presenting: $presenting)
                }
                Tab("The Crypt", systemImage: "moon.stars", value: "crypt") {
                    CryptView(presenting: $presenting)
                }
                Tab("Settings", systemImage: "gearshape", value: "settings") {
                    TVSettingsView()
                }
            }
            .environment(store)
            .fullScreenCover(item: $presenting) { presentation in
                PresentingView(presentation: presentation)
                    .environment(store)
            }
            // The Top Shelf opens a countdown straight to full screen.
            .onOpenURL { url in
                if let id = CountdownLink.id(from: url), store.countdown(id: id) != nil {
                    presenting = .mine(id)
                }
            }
            #if DEBUG
            // Screenshots: -present opens Next Up full screen, -crypt opens the Crypt tab.
            .onAppear {
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("-crypt") { tab = "crypt" }
                if arguments.contains("-present"), let featured = store.featured { presenting = .mine(featured.id) }
            }
            #endif
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                Analytics.appBecameActive()
                await store.refreshShared()
            }
        }
    }
}

/// What's full screen: one of your countdowns (left and right step through the rest), or a Crypt
/// entry you haven't added.
enum Presentation: Identifiable, Hashable {
    case mine(UUID)
    case crypt(CryptEntry)

    var id: String {
        switch self {
        case let .mine(id): id.uuidString
        case let .crypt(entry): entry.slug
        }
    }
}

extension CryptEntry: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(slug) }

    /// A local, unsaved countdown to show a Crypt entry full screen before adding it.
    var preview: Countdown {
        var countdown = Countdown(title: title, details: details, targetDate: target)
        countdown.style = CountdownStyle(background: scene.map(CountdownStyle.Background.scene) ?? .automatic, font: .rounded)
        return countdown
    }
}
