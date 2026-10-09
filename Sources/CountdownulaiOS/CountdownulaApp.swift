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
                Analytics.appBecameActive()
                store.reload()
                // Countdowns confirmed in the share sheet while the app was closed.
                if let added = store.importSharedDrafts() { appDelegate.router.show(added) }
                Task {
                    // Countdowns kept in the App Clip before the app was installed.
                    for slug in ClipHandoff.pending {
                        if await joiner.join(slug, store: store, router: appDelegate.router) {
                            ClipHandoff.done(slug)
                            // Kept in the clip, then installed: the link brought this person in.
                            Analytics.log(.installFromLink, slug: slug)
                        }
                    }
                    Analytics.flush()
                    await store.refreshShared(force: true)
                    await store.registerPushForShared()
                    await SynchronizedZero.registerAll(store: store)
                }
            }
            if phase == .background {
                SharedRefreshTask.schedule()
                Analytics.flush()
            }
        }
    }
}

/// Which countdown is open. Widgets, Live Activities and notification taps all route through here.
@MainActor
@Observable
final class Router {
    var path: [UUID] = []
    /// Set by a notification action ("Share", "Open the Coffin"); the countdown's screen does it and clears it.
    var pending: PendingAction?

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
        NotificationActions.register()
        registerWidgetActions()
        // Delivers any Host Pass bought but not yet attached to its countdown (the app quit, or the network dropped).
        Task { @MainActor in _ = HostPassStore.shared }
        SharedRefreshTask.register { [weak self] in await self?.store?.refreshShared() }
        // CloudKit pushes wake the app so widgets and alerts stay current while it's closed.
        application.registerForRemoteNotifications()
        return true
    }

    /// What widget buttons and Control Center controls do. iOS runs them in the app (in the
    /// background when they don't need to open it), so they go through the same store as everything else.
    private func registerWidgetActions() {
        WidgetActions.handler = { [weak self] action in
            let store = PhoneStore.shared
            switch action {
            case let .togglePin(id):
                guard let countdown = store.countdown(id: id) else { return }
                store.togglePin(countdown)
                // A newly pinned countdown should be the one Next Up widgets show.
                WidgetCycle.reset()
                Analytics.log(.widgetAction, source: "pin")
            case let .startLiveActivity(id):
                guard let countdown = store.countdown(id: id) else { return }
                LiveActivities.start(countdown)
                Analytics.log(.widgetAction, source: "lockscreen")
            case let .quickTimer(minutes):
                guard store.entitlements.canAdd(to: store.countdowns) else { throw WidgetActionError.freeLimit }
                store.startQuickTimer(minutes: minutes)
                Analytics.log(.widgetAction, source: "quick_timer")
            case let .open(id):
                if let id { self?.router.show(id) }
                Analytics.log(.widgetAction, source: "open")
            }
        }
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
        let action = NotificationActions.Action(rawValue: response.actionIdentifier)
        await MainActor.run {
            switch action {
            case .lockScreen:
                // The app is in the foreground now, so ActivityKit will start it.
                if let countdown = store?.countdown(id: id) { LiveActivities.start(countdown) }
            case .share, .recap:
                router.pending = .share(id)
            case .coffin:
                router.pending = .openCoffin(id)
            case nil:
                break
            }
            router.show(id)
            if let action {
                Analytics.log(.notificationAction, source: action.rawValue)
            }
        }
    }
}

enum WidgetActionError: LocalizedError {
    case freeLimit

    var errorDescription: String? {
        L("You're at the free limit of \(SharedConfig.freeActiveLimit) countdowns. Open Count Downcula to unlock more.")
    }
}
