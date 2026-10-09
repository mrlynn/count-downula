import Foundation

/// Counts what happens in the app (a countdown made, the paywall shown, a day the app was used) for
/// the server's metrics dashboard. Events carry no titles, names or dates: only what happened, a
/// short `source` like "screenshot", a shared countdown's slug, and a random install ID that has
/// nothing to do with the device or the person and can be reset. Off when Share Analytics is off.
///
/// Events queue in UserDefaults and go to `POST /api/events` in batches, when the app comes forward
/// or once enough are waiting. The server's half is `server/src/lib/events.ts`.
enum Analytics {
    /// Names the server knows (`CLIENT_EVENTS` in events.ts). It drops ones it doesn't.
    enum Event: String {
        case active
        case countdownCreated = "countdown_created"
        case shareSheetOpened = "share_sheet_opened"
        case videoExported = "video_exported"
        case imageExported = "image_exported"
        case paywallShown = "paywall_shown"
        case purchaseCompleted = "purchase_completed"
        case installFromLink = "install_from_link"
        case clipLaunch = "clip_launch"
        case clipKeepIt = "clip_keep_it"
        case countdownFinished = "countdown_finished"
        case keepCounting = "keep_counting"
        case countdownDeleted = "countdown_deleted"
        case notificationAction = "notification_action"
        case widgetAction = "widget_action"
        /// An edit switched a countdown to a unit (sleeps, weeks...). Creations and exports carry it too.
        case unitChosen = "unit_chosen"
        /// A countdown put on a big screen: source "mac" (full screen) or "tv" (an iPhone's external display).
        case presentStarted = "present_started"
        /// Still on the big screen when it hit zero.
        case presentZero = "present_zero"
    }

    struct Queued: Codable, Equatable {
        var name: String
        var at: Date
        var slug: String?
        var source: String?
        /// What the countdown counts in, when it isn't days and hours.
        var unit: String?
    }

    /// The Share Analytics setting (iPhone: the Settings app; Mac: the menu bar popover). On unless turned off.
    static let enabledKey = "shareAnalytics"
    private static let queueKey = "Analytics.queue"
    private static let installKey = "Analytics.installID"
    private static let lastActiveKey = "Analytics.lastActiveDay"
    private static let resetKey = "resetAnalyticsID"
    /// Enough for a long stretch offline; older ones are dropped first.
    static let queueLimit = 500
    static let batchSize = 100

    nonisolated(unsafe) static var defaults = UserDefaults.standard
    /// Tests keep the queue and never send.
    nonisolated(unsafe) static var isSendingPaused = false
    private static let lock = NSLock()
    nonisolated(unsafe) private static var isFlushing = false

    static var isEnabled: Bool {
        #if os(watchOS)
        // The watch has no place for the setting yet, so it stays quiet.
        return false
        #else
        return defaults.object(forKey: enabledKey) as? Bool ?? true
        #endif
    }

    static func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: enabledKey)
        if !enabled { lock.withLock { defaults.removeObject(forKey: queueKey) } }
    }

    /// A random ID for this install. Resetting it makes the next events look like a new install.
    static var installID: String {
        lock.withLock {
            if let id = defaults.string(forKey: installKey) { return id }
            let id = UUID().uuidString
            defaults.set(id, forKey: installKey)
            return id
        }
    }

    static func resetInstallID() {
        lock.withLock {
            defaults.removeObject(forKey: installKey)
            defaults.removeObject(forKey: lastActiveKey)
            defaults.removeObject(forKey: queueKey)
        }
    }

    // MARK: - Platform

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var platform: String {
        #if os(watchOS)
        return "watchos"
        #elseif os(macOS)
        return "macos"
        #else
        if Bundle.main.bundleIdentifier?.hasSuffix(".Clip") == true { return "clip" }
        return deviceModel.hasPrefix("iPad") ? "ipados" : "ios"
        #endif
    }

    /// "iPhone17,1", "iPad16,3". Read without UIKit so it works off the main thread.
    private static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// Sent with every request to the server, so its own events know the platform: "ios/1.2.0".
    static var clientHeader: String? { isEnabled ? "\(platform)/\(appVersion)" : nil }

    // MARK: - Logging

    static func log(_ event: Event, slug: String? = nil, source: String? = nil, unit: CountUnit? = nil, at now: Date = Date()) {
        guard isEnabled else { return }
        let count: Int = lock.withLock {
            var queue = read()
            queue.append(Queued(name: event.rawValue, at: now, slug: slug, source: source,
                                unit: unit == .daysHours ? nil : unit?.rawValue))
            if queue.count > queueLimit { queue.removeFirst(queue.count - queueLimit) }
            write(queue)
            return queue.count
        }
        if count >= 20 { flush() }
    }

    /// Call when the app comes forward: logs `active` once per day (UTC), then sends what's waiting.
    static func appBecameActive(at now: Date = Date()) {
        // The iPhone's Settings pane can't run code, so it asks for a reset with a switch.
        if defaults.bool(forKey: resetKey) {
            resetInstallID()
            defaults.set(false, forKey: resetKey)
        }
        guard isEnabled else { return }
        let day = String(ISO8601DateFormatter.string(from: now, timeZone: .gmt, formatOptions: [.withFullDate]))
        if defaults.string(forKey: lastActiveKey) != day {
            defaults.set(day, forKey: lastActiveKey)
            log(.active, at: now)
        }
        flush()
    }

    // MARK: - After zero

    private static let finishedKey = "Analytics.finishedIDs"

    /// Logs `countdown_finished` once per countdown that reached zero in the last week. Older ones
    /// finished before this build, so counting them would skew the after-zero numbers.
    static func noteFinished(_ countdowns: [Countdown], at now: Date = Date()) {
        guard isEnabled else { return }
        let fresh = countdowns.filter { $0.hasReachedZero(at: now) && now.timeIntervalSince($0.targetDate) < 7 * 86_400 }
        guard !fresh.isEmpty else { return }
        var seen = Set(defaults.stringArray(forKey: finishedKey) ?? [])
        for countdown in fresh where !seen.contains(countdown.id.uuidString) {
            seen.insert(countdown.id.uuidString)
            log(.countdownFinished, slug: countdown.extras.link?.slug ?? countdown.extras.subscription?.slug,
                source: countdown.extras.subscription != nil ? "member" : countdown.extras.link != nil ? "owner" : "solo", at: now)
        }
        defaults.set(Array(seen.suffix(500)), forKey: finishedKey)
    }

    /// When a deleted countdown went: before its zero, within 30 days after, or later.
    static func deletionSource(for countdown: Countdown, at now: Date = Date()) -> String {
        if countdown.kind == .timer { return "timer" }
        if countdown.countsUp, countdown.extras.keptCountingAt == nil { return "count_up" }
        guard countdown.targetDate <= now else { return "before_zero" }
        return now.timeIntervalSince(countdown.targetDate) <= 30 * 86_400 ? "after_zero_30d" : "after_zero_later"
    }

    /// The source to record for a countdown nobody said how it was made.
    static func source(for countdown: Countdown) -> String {
        if countdown.extras.auto != nil { return "vampire_hours" }
        if countdown.extras.pool != nil { return "pool" }
        switch countdown.kind {
        case .timer: return "timer"
        case .countUp: return "count_up"
        case .event:
            switch countdown.extras.repetition {
            case nil: return "typed"
            case .yearly: return "typed_yearly"
            case .some: return "typed_repeating"
            }
        }
    }

    // MARK: - Sending

    static var pending: [Queued] { lock.withLock { read() } }

    /// The request body for a batch, as the server expects it.
    static func body(for events: [Queued]) throws -> Data {
        struct Batch: Encodable {
            let installId: String, platform: String, appVersion: String, events: [Queued]
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Batch(installId: installID, platform: platform, appVersion: appVersion, events: events))
    }

    /// Sends up to one batch. Events leave the queue once the server has them, or if it refuses the
    /// batch outright; a network failure keeps them for next time.
    static func flush() {
        guard isEnabled, !isSendingPaused else { return }
        let batch: [Queued]? = lock.withLock {
            guard !isFlushing else { return nil }
            let queue = read()
            guard !queue.isEmpty else { return nil }
            isFlushing = true
            return Array(queue.prefix(batchSize))
        }
        guard let batch else { return }
        Task.detached(priority: .utility) {
            defer { lock.withLock { isFlushing = false } }
            guard let data = try? body(for: batch),
                  let (_, status) = try? await LiveLinkAPI.raw("POST", path: "/api/events", body: data) else { return }
            // 429 means try later; any other answer means the server has them or never will.
            guard status != 429, status < 500 else { return }
            lock.withLock { write(Array(read().dropFirst(batch.count))) }
        }
    }

    // MARK: - Storage (call with the lock held)

    private static func read() -> [Queued] {
        guard let data = defaults.data(forKey: queueKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Queued].self, from: data)) ?? []
    }

    private static func write(_ queue: [Queued]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if queue.isEmpty { defaults.removeObject(forKey: queueKey) } else { defaults.set(try? encoder.encode(queue), forKey: queueKey) }
    }
}
