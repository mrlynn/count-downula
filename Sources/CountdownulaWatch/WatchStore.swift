import Observation
import SwiftUI
import UserNotifications
import WidgetKit

@MainActor
@Observable
final class WatchStore {
    private(set) var countdowns: [Countdown] = []

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
        countdowns.filter { !$0.isPast(at: now) }.sorted { $0.targetDate < $1.targetDate }
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
    }

    func delete(_ countdown: Countdown) {
        repository.delete(id: countdown.id)
        reload()
    }

    func togglePin(_ countdown: Countdown) {
        repository.setPinned(!countdown.isPinned, id: countdown.id)
        reload()
    }

    // MARK: - Sync side effects

    func reload() {
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

    /// The watch can't rely on the Mac being awake, so it schedules its own completion alerts.
    private func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date()
        for countdown in upcoming(at: now).prefix(50) {
            let content = UNMutableNotificationContent()
            content.title = countdown.kind == .timer ? "⏰ \(countdown.title)" : "🎉 \(countdown.title)"
            content.body = countdown.details.isEmpty ? "The countdown is complete!" : countdown.details
            content.sound = .default
            let interval = countdown.targetDate.timeIntervalSince(now)
            guard interval > 1 else { continue }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: countdown.id.uuidString, content: content, trigger: trigger))
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
