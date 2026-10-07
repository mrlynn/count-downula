import Observation
import SwiftUI
import UserNotifications
import WidgetKit

@MainActor
@Observable
final class PhoneStore {
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

    /// Prepares the display and thumbnail JPEGs that get stored and synced, from any photo's raw data.
    nonisolated static func prepareImage(_ data: Data) -> (preview: UIImage, update: ImageUpdate)? {
        guard let full = ImageDownsampling.jpegData(from: data, maxPixelDimension: 1400),
              let thumb = ImageDownsampling.jpegData(from: data, maxPixelDimension: 240, quality: 0.8),
              let preview = UIImage(data: full) else { return nil }
        return (preview, .set(image: full, thumbnail: thumb))
    }

    // MARK: - Mutations

    func upsert(_ countdown: Countdown, image: ImageUpdate = .unchanged) {
        var countdown = countdown
        if !countdown.isPast(at: Date()) { countdown.hasNotified = false }
        repository.upsert(countdown, image: image)
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

    /// One-tap timer from the list's + menu. Timers go live on the Lock Screen straight away.
    func startQuickTimer(minutes: Int) {
        let now = Date()
        let countdown = Countdown(
            title: "\(Self.durationLabel(minutes)) timer", details: "",
            targetDate: now.addingTimeInterval(TimeInterval(minutes * 60)), kind: .timer, createdAt: now
        )
        upsert(countdown)
        LiveActivities.start(countdown)
    }

    static func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        return hours == hours.rounded() ? "\(Int(hours)) hr" : String(format: "%.1f hr", hours)
    }

    // MARK: - Sync side effects

    func reload() {
        let fresh = repository.fetchAll()
        if fresh != countdowns { countdowns = fresh }
        publishToWidgets()
        scheduleNotifications()
        LiveActivities.sync(with: countdowns)
    }

    private func publishToWidgets() {
        let repository = repository
        let changed = WidgetSnapshot.write(
            countdowns,
            thumbnail: { repository.thumbnailData(for: $0) },
            photo: { repository.imageData(for: $0) }
        )
        if changed { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// The phone can't rely on the Mac being awake, so it schedules its own completion alerts.
    private func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date()
        // iOS keeps at most 64 pending requests per app.
        for countdown in upcoming(at: now).prefix(60) {
            let content = UNMutableNotificationContent()
            content.title = countdown.kind == .timer ? "⏰ \(countdown.title)" : "🎉 \(countdown.title)"
            content.body = countdown.details.isEmpty ? "The countdown is complete!" : countdown.details
            content.sound = .default
            content.userInfo = ["countdownID": countdown.id.uuidString]
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
        var samples = [
            Countdown(title: "Sonoma Wine Weekend", details: "Three days of vineyards, long lunches and zero laptops.",
                      targetDate: now + 16 * day + 25_200, isPinned: true, createdAt: now - 30 * day),
            Countdown(title: "Focus Block", details: "Heads down on the release notes",
                      targetDate: now + 18 * 60, kind: .timer, createdAt: now - 7 * 60),
            Countdown(title: "Sam's 30th Birthday", details: "Dinner at 7 — pick up the cake!",
                      targetDate: now + 9 * day + 10_800, createdAt: now - 20 * day),
            Countdown(title: "Product Launch", details: "Ship it.",
                      targetDate: now + 5 * 3_600 + 1_200, createdAt: now - 2 * day),
            Countdown(title: "Conference Talk", details: "Nailed it.",
                      targetDate: now - 3 * day, createdAt: now - 60 * day, hasNotified: true),
        ]
        samples[2].style = CountdownStyle(background: .scene(.balloons), font: .serif, weight: .heavy,
                                          textColor: RGBAColor(hex: 0x1C1C1E), accent: RGBAColor(hex: 0xFF5D73))
        samples[3].style = CountdownStyle(background: .gradient(GradientSpec.presets[4].spec), font: .expanded,
                                          accent: RGBAColor(hex: 0xFFD166))
        samples[0].style = CountdownStyle(background: .scene(.sunset), font: .rounded)
        samples.forEach { repository.upsert($0) }
    }
    #endif
}
