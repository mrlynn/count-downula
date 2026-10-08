import SwiftUI
import UserNotifications

@main
struct CountdownulaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = PhoneStore()
    @State private var joiner = JoinCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            CountdownListView()
                .environment(store)
                .environment(appDelegate.router)
                .environment(joiner)
                .tint(.countdownulaBlood)
                .onOpenURL { url in
                    if let id = CountdownLink.id(from: url) {
                        appDelegate.router.show(id)
                    } else if SharedCountdowns.slug(from: url.absoluteString) != nil {
                        // A shared link (universal link or countdownula://join/<slug>) counts you in.
                        Task { await joiner.join(url.absoluteString, store: store, router: appDelegate.router) }
                    }
                }
                .overlay {
                    if joiner.isJoining {
                        ProgressView("Joining…")
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .alert("Couldn't join", isPresented: Binding(get: { joiner.errorMessage != nil },
                                                              set: { if !$0 { joiner.errorMessage = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(joiner.errorMessage ?? "")
                }
                .alert("Sharing ended", isPresented: Binding(get: { !store.sharingEnded.isEmpty },
                                                             set: { if !$0 { store.sharingEnded.removeAll() } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("The owner stopped sharing \(store.sharingEnded.formatted(.list(type: .and))). It's still here as your own countdown.")
                }
                .onAppear { appDelegate.store = store }
        }
        .onChange(of: scenePhase) { _, phase in
            // Pick up anything CloudKit imported while we were in the background, and
            // start Live Activities for pinned countdowns that entered their final hours.
            if phase == .active {
                store.reload()
                Task { await store.refreshShared(force: true) }
            }
            if phase == .background { SharedRefreshTask.schedule() }
        }
    }
}

/// Which countdown is open. Widgets, Live Activities and notification taps all route through here.
@MainActor
@Observable
final class Router {
    var path: [UUID] = []

    func show(_ id: UUID) {
        path = [id]
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor let router = Router()
    @MainActor weak var store: PhoneStore?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        SharedRefreshTask.register { [weak self] in await self?.store?.refreshShared() }
        // CloudKit pushes wake the app so widgets and alerts stay current while it's closed.
        application.registerForRemoteNotifications()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo["countdownID"] as? String,
              let id = UUID(uuidString: raw) else { return }
        await MainActor.run { router.show(id) }
    }
}
