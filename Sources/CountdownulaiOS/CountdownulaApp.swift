import CoreSpotlight
import SwiftUI
import UserNotifications

@main
struct CountdownulaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = PhoneStore.shared
    @State private var joiner = JoinCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    /// Widgets, Live Activities and notifications open a countdown; a shared link counts you in.
    private func open(_ url: URL) {
        if let id = CountdownLink.id(from: url) {
            appDelegate.router.show(id)
        } else if SharedCountdowns.slug(from: url.absoluteString) != nil {
            Task { await joiner.join(url.absoluteString, store: store, router: appDelegate.router) }
        }
    }

    var body: some Scene {
        WindowGroup {
            CountdownListView()
                .environment(store)
                .environment(appDelegate.router)
                .environment(joiner)
                .tint(.countdownulaBlood)
                .onOpenURL { url in open(url) }
                // A tapped go.countdowncula.com link arrives as a web browsing activity. SwiftUI doesn't
                // reliably pass it to onOpenURL once the view handles other activities (Spotlight below).
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { open(url) }
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
                // A countdown tapped in Spotlight search.
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let raw = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String, let id = UUID(uuidString: raw) {
                        appDelegate.router.show(id)
                    }
                }
                .onAppear {
                    appDelegate.store = store
                    SynchronizedZero.start(store: store)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Pick up anything CloudKit imported while we were in the background, and
            // start Live Activities for pinned countdowns that entered their final hours.
            if phase == .active {
                store.reload()
                // Countdowns confirmed in the share sheet while the app was closed.
                if let added = store.importSharedDrafts() { appDelegate.router.show(added) }
                Task {
                    // Countdowns kept in the App Clip before the app was installed.
                    for slug in ClipHandoff.pending {
                        if await joiner.join(slug, store: store, router: appDelegate.router) { ClipHandoff.done(slug) }
                    }
                    await store.refreshShared(force: true)
                    await store.registerPushForShared()
                    await SynchronizedZero.registerAll(store: store)
                }
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

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PhoneStore.deviceToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in await store?.registerPushForShared() }
    }

    /// A silent push from Count Downcula's server: an owner edited a countdown you joined.
    /// CloudKit's own pushes also land here; SwiftData handles those, so they're left alone.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard userInfo["countdownula"] != nil else { return completionHandler(.noData) }
        Task { @MainActor in
            guard let store else { return completionHandler(.noData) }
            await store.refreshShared(force: true)
            completionHandler(.newData)
        }
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
