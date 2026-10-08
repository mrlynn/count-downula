import AppKit
import Observation
import UserNotifications

@MainActor
@Observable
final class CountdownStore {
    private(set) var countdowns: [Countdown] = []
    private(set) var now = Date()

    /// Called every tick and after every change so the menu bar items can refresh.
    @ObservationIgnored var onUpdate: (() -> Void)?

    @ObservationIgnored private let repository: CountdownRepository
    @ObservationIgnored private let supportDirectory: URL
    @ObservationIgnored private var imageCache: [String: NSImage] = [:]
    @ObservationIgnored private var timer: Timer?

    init() {
        supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Countdownula", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)

        repository = CountdownRepository(storeURL: supportDirectory.appending(path: "Countdownula.store"))
        repository.onRemoteChange = { [weak self] in self?.reload() }
        LegacyImporter.importIfNeeded(from: supportDirectory, into: repository)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedDemo") { seedDemoData() }
        #endif
        reload()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common keeps the timer firing while menus are tracking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Queries

    var upcoming: [Countdown] {
        countdowns.filter { $0.isUpcoming(at: now) }.sorted { $0.targetDate < $1.targetDate }
    }

    /// Count-ups, longest-running first.
    var countingUp: [Countdown] {
        countdowns.filter(\.countsUp).sorted { $0.targetDate < $1.targetDate }
    }

    var past: [Countdown] {
        countdowns.filter { $0.isPast(at: now) }.sorted { $0.targetDate > $1.targetDate }
    }

    func countdown(id: UUID) -> Countdown? {
        countdowns.first { $0.id == id }
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

    // MARK: - Images

    func image(for countdown: Countdown) -> NSImage? {
        guard countdown.hasImage else { return nil }
        if let cached = imageCache[countdown.imageCacheKey] { return cached }
        guard let data = repository.imageData(for: countdown.id), let image = NSImage(data: data) else { return nil }
        imageCache[countdown.imageCacheKey] = image
        return image
    }

    /// Reads a user-chosen photo and prepares the display and thumbnail JPEGs that get stored and synced.
    static func prepareImage(from url: URL) -> (preview: NSImage, update: ImageUpdate)? {
        guard let source = NSImage(contentsOf: url) else { return nil }
        return prepareImage(source)
    }

    static func prepareImage(_ source: NSImage) -> (preview: NSImage, update: ImageUpdate)? {
        guard let full = source.jpegData(maxPixelDimension: 1400),
              let thumb = source.jpegData(maxPixelDimension: 240, quality: 0.8),
              let preview = NSImage(data: full) else { return nil }
        return (preview, .set(image: full, thumbnail: thumb))
    }

    // MARK: - Sync

    private func reload() {
        repository.rollOverRepeatingCountdowns()
        let fresh = repository.fetchAll()
        if fresh != countdowns { countdowns = fresh }
        onUpdate?()
    }

    #if DEBUG
    /// Sample countdowns for screenshots, with macOS wallpapers standing in for photos.
    private func seedDemoData() {
        guard repository.fetchAll().isEmpty else { return }
        let now = Date()
        let day: TimeInterval = 86_400
        let wallpapers = URL(filePath: "/System/Library/Desktop Pictures/.thumbnails")
        func photo(_ name: String) -> ImageUpdate {
            Self.prepareImage(from: wallpapers.appending(path: "\(name).heic"))?.update ?? .unchanged
        }
        let halloween = Calendar.current.nextDate(
            after: now, matching: DateComponents(month: 10, day: 31, hour: 19), matchingPolicy: .nextTime
        ) ?? now + 24 * day
        let samples: [(Countdown, ImageUpdate)] = [
            (Countdown(title: "Focus Block", details: "Heads down on the release notes",
                       targetDate: now + 18 * 60, kind: .timer, isPinned: true, createdAt: now - 7 * 60), .unchanged),
            (Countdown(title: "Sam's 30th Birthday", details: "Dinner at 7 — pick up the cake!",
                       targetDate: now + 9 * day + 10_800, createdAt: now - 20 * day), photo("Light Stream Pink")),
            (Countdown(title: "Sonoma Wine Weekend", details: "Three days of vineyards, long lunches and zero laptops.",
                       targetDate: now + 16 * day + 25_200, isPinned: true, createdAt: now - 30 * day), photo("Sonoma")),
            (Countdown(title: "Halloween", details: "Costume: obviously Dracula.",
                       targetDate: halloween, createdAt: now - 10 * day), photo("Hello Metallic Purple")),
            (Countdown(title: "v2.0 Launch", details: "Ship it.",
                       targetDate: now + 41 * day, createdAt: now - 5 * day), photo("Chroma Blue")),
            (Countdown(title: "Conference Talk", details: "Nailed it.",
                       targetDate: now - 3 * day, createdAt: now - 60 * day, hasNotified: true), .unchanged),
        ]
        for (countdown, image) in samples { repository.upsert(countdown, image: image) }
    }
    #endif

    private func tick() {
        now = Date()
        postDueMilestones()
        if countdowns.contains(where: { $0.nextOccurrence(after: now) != nil }) {
            reload()
        }
        let due = countdowns.filter { $0.isPast(at: now) && !$0.hasNotified }
        if due.isEmpty {
            onUpdate?()
            return
        }
        due.forEach(Notifier.post(for:))
        repository.markNotified(ids: due.map(\.id))
        reload()
    }

    /// Milestone alerts reached in the last day that this Mac hasn't shown yet. Tracked per device
    /// in UserDefaults; the phone and watch schedule their own.
    private func postDueMilestones() {
        let key = "Notifier.postedMilestones"
        var posted = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        var live: Set<String> = []
        var changed = false
        for countdown in countdowns {
            for scheduled in countdown.scheduledMilestones where scheduled.date > now - 86_400 {
                let item = NotificationPlan.milestone(scheduled, of: countdown)
                let id = "\(item.identifier)@\(Int(item.date.timeIntervalSince1970))"
                live.insert(id)
                guard item.date <= now, !posted.contains(id) else { continue }
                Notifier.post(item)
                posted.insert(id)
                changed = true
            }
        }
        // Forget milestones that are over a day old, edited or deleted.
        if changed || !posted.isSubset(of: live) {
            UserDefaults.standard.set(Array(posted.intersection(live)), forKey: key)
        }
    }
}

/// One-time import of the JSON + images folder used by Countdownula 1.0.
private enum LegacyImporter {
    private struct LegacyCountdown: Decodable {
        var id: UUID
        var title: String
        var details: String
        var targetDate: Date
        var kind: Countdown.Kind?
        var imageFileName: String?
        var isPinned: Bool?
        var createdAt: Date?
        var hasNotified: Bool?
    }

    @MainActor
    static func importIfNeeded(from directory: URL, into repository: CountdownRepository) {
        let jsonURL = directory.appending(path: "countdowns.json")
        guard let data = try? Data(contentsOf: jsonURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let legacy = try? decoder.decode([LegacyCountdown].self, from: data) else { return }

        for old in legacy {
            let countdown = Countdown(
                id: old.id, title: old.title, details: old.details, targetDate: old.targetDate,
                kind: old.kind ?? .event, isPinned: old.isPinned ?? false,
                createdAt: old.createdAt ?? Date(), hasNotified: old.hasNotified ?? false
            )
            var image = ImageUpdate.unchanged
            if let name = old.imageFileName,
               let source = NSImage(contentsOf: directory.appending(path: "images").appending(path: name)),
               let prepared = CountdownStore.prepareImage(source) {
                image = prepared.update
            }
            repository.upsert(countdown, image: image)
        }

        // Keep the old files around (renamed) rather than deleting the user's data.
        try? FileManager.default.moveItem(at: jsonURL, to: directory.appending(path: "countdowns.imported.json"))
    }
}

enum Notifier {
    private static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(for countdown: Countdown) {
        post(NotificationPlan.completion(for: countdown))
    }

    static func post(_ item: NotificationPlan.Item) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: item.identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
