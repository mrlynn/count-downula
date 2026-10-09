import Observation
import SwiftUI
import UserNotifications
import WidgetKit

@MainActor
@Observable
final class WatchStore {
    private(set) var countdowns: [Countdown] = []
    /// The Unlimited purchase (bought on iPhone or here) and the free-tier limit it lifts.
    let entitlements = Entitlements()

    @ObservationIgnored private let repository: CountdownRepository
    @ObservationIgnored private var imageCache: [String: UIImage] = [:]
    @ObservationIgnored private var thumbnailCache: [String: UIImage] = [:]

    init() {
        let directory = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        repository = CountdownRepository(storeURL: directory.appending(path: "Countdownula.store"))
        repository.onRemoteChange = { [weak self] in self?.reload() }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedDemo") { seedDemoData() }
        #endif
        reload()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Queries

    func upcoming(at now: Date) -> [Countdown] {
        countdowns.filter { $0.isUpcoming(at: now) }.sorted { $0.targetDate < $1.targetDate }
    }

    /// Count-ups, longest-running first.
    var countingUp: [Countdown] {
        countdowns.filter(\.countsUp).sorted { $0.targetDate < $1.targetDate }
    }

    func past(at now: Date) -> [Countdown] {
        countdowns.filter { $0.isPast(at: now) }.sorted { $0.targetDate > $1.targetDate }
    }

    func countdown(id: UUID) -> Countdown? {
        countdowns.first { $0.id == id }
    }

    func image(for countdown: Countdown) -> UIImage? {
        cachedImage(for: countdown, in: &imageCache) { repository.imageData(for: $0) }
    }

    func thumbnail(for countdown: Countdown) -> UIImage? {
        cachedImage(for: countdown, in: &thumbnailCache) { repository.thumbnailData(for: $0) }
    }

    private func cachedImage(for countdown: Countdown, in cache: inout [String: UIImage],
                             load: (UUID) -> Data?) -> UIImage? {
        guard countdown.hasImage else { return nil }
        if let cached = cache[countdown.imageCacheKey] { return cached }
        guard let data = load(countdown.id), let image = UIImage(data: data) else { return nil }
        cache[countdown.imageCacheKey] = image
        return image
    }

    // MARK: - Mutations

    func add(_ countdown: Countdown) {
        repository.upsert(countdown)
        reload()
        Analytics.log(.countdownCreated, source: "watch", unit: countdown.countUnit)
    }

    func delete(_ countdown: Countdown) {
        Analytics.log(.countdownDeleted, source: Analytics.deletionSource(for: countdown))
        repository.delete(id: countdown.id)
        reload()
    }

    func togglePin(_ countdown: Countdown) {
        repository.setPinned(!countdown.isPinned, id: countdown.id)
        reload()
    }

    // MARK: - Sync side effects

    func reload() {
        repository.rollOverRepeatingCountdowns()
        let fresh = repository.fetchAll()
        if fresh != countdowns { countdowns = fresh }
        publishToComplications()
        scheduleNotifications()
    }

    private func publishToComplications() {
        let repository = repository
        if WidgetSnapshot.write(countdowns, thumbnail: { repository.thumbnailData(for: $0) }) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// The watch can't rely on the Mac being awake, so it schedules its own completion and milestone alerts.
    private func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date()
        for item in NotificationPlan.items(for: countdowns, now: now, limit: 50) {
            let interval = item.date.timeIntervalSince(now)
            guard interval > 1 else { continue }
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
        }
    }

    #if DEBUG
    private func seedDemoData() {
        guard repository.fetchAll().isEmpty else { return }
        let now = Date()
        let day: TimeInterval = 86_400
        let samples = [
            Countdown(title: "Sonoma Wine Weekend", details: "Three days of vineyards, long lunches and zero laptops.",
                      targetDate: now + 16 * day + 25_200, isPinned: true, createdAt: now - 30 * day),
            Countdown(title: "Focus Block", details: "Heads down on the release notes",
                      targetDate: now + 18 * 60, kind: .timer, createdAt: now - 7 * 60),
            Countdown(title: "Sam's 30th Birthday", details: "Dinner at 7 — pick up the cake!",
                      targetDate: now + 9 * day + 10_800, createdAt: now - 20 * day),
            Countdown(title: "Conference Talk", details: "Nailed it.",
                      targetDate: now - 3 * day, createdAt: now - 60 * day, hasNotified: true),
        ]
        samples.forEach { repository.upsert($0) }
    }
    #endif
}
