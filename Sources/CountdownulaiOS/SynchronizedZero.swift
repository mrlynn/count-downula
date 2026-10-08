import ActivityKit
import Foundation

/// Synchronized zero: registers this phone with each shared countdown it's in, so the server can
/// start the Live Activity eight hours before zero (push-to-start, iOS 17.2+) and celebrate on every
/// phone at once. Tokens arrive asynchronously; whenever one does, the registrations catch up.
@MainActor
enum SynchronizedZero {
    private typealias CountdownActivity = Activity<CountdownActivityAttributes>

    /// A stable random ID for this install, so the server keeps one record per phone per countdown.
    static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: "SyncZero.deviceID") { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "SyncZero.deviceID")
        return id
    }

    private static var startToken: String? {
        get { UserDefaults.standard.string(forKey: "SyncZero.startToken") }
        set { UserDefaults.standard.set(newValue, forKey: "SyncZero.startToken") }
    }

    /// What each countdown last registered ("<countdown ID>" → start token), to avoid repeating it.
    private static var registered: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "SyncZero.registered") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "SyncZero.registered") }
    }

    private static var sandbox: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static var started = false

    /// Starts watching for tokens. Call once at launch.
    static func start(store: PhoneStore) {
        guard !started else { return }
        started = true
        if #available(iOS 17.2, *) {
            Task {
                for await data in CountdownActivity.pushToStartTokenUpdates {
                    startToken = hex(data)
                    await registerAll(store: store)
                }
            }
        }
        // Activities the app or the server started: send each one's update token so zero can reach it.
        for activity in CountdownActivity.activities { watch(activity, store: store) }
        Task {
            for await activity in CountdownActivity.activityUpdates { watch(activity, store: store) }
        }
    }

    /// Registers the push-to-start token with every shared countdown that hasn't got it yet.
    static func registerAll(store: PhoneStore) async {
        guard let startToken else { return }
        var done = registered
        for countdown in store.countdowns {
            guard done[countdown.id.uuidString] != startToken, let access = Coffin.sharedAccess(for: countdown) else { continue }
            if (try? await LiveLinkAPI.registerLive(slug: access.slug, token: access.token, deviceID: deviceID,
                                                     countdownID: countdown.id, startToken: startToken,
                                                     activityToken: nil, sandbox: sandbox)) != nil {
                done[countdown.id.uuidString] = startToken
            }
        }
        let ids = Set(store.countdowns.map(\.id.uuidString))
        registered = done.filter { ids.contains($0.key) }
    }

    private static func watch(_ activity: CountdownActivity, store: PhoneStore) {
        Task {
            for await data in activity.pushTokenUpdates {
                guard let countdown = store.countdown(id: activity.attributes.countdownID),
                      let access = Coffin.sharedAccess(for: countdown) else { continue }
                try? await LiveLinkAPI.registerLive(slug: access.slug, token: access.token, deviceID: deviceID,
                                                    countdownID: countdown.id, startToken: startToken,
                                                    activityToken: hex(data), sandbox: sandbox)
            }
        }
    }

    private static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
}
