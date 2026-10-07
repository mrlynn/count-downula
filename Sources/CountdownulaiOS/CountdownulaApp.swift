import SwiftUI
import UserNotifications

@main
struct CountdownulaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = PhoneStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            CountdownListView()
                .environment(store)
                .environment(appDelegate.router)
                .tint(.countdownulaBlood)
                .onOpenURL { url in
                    if let id = CountdownLink.id(from: url) { appDelegate.router.show(id) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Pick up anything CloudKit imported while we were in the background, and
            // start Live Activities for pinned countdowns that entered their final hours.
            if phase == .active { store.reload() }
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

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
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
