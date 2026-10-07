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
        countdowns.filter { !$0.isPast(at: now) }.sorted { $0.targetDate < $1.targetDate }
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
        let fresh = repository.fetchAll()
        if fresh != countdowns { countdowns = fresh }
        onUpdate?()
    }

    private func tick() {
        now = Date()
        let due = countdowns.filter { $0.isPast(at: now) && !$0.hasNotified }
        if due.isEmpty {
            onUpdate?()
            return
        }
        due.forEach(Notifier.post(for:))
        repository.markNotified(ids: due.map(\.id))
        reload()
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
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = countdown.kind == .timer ? "⏰ \(countdown.title)" : "🎉 \(countdown.title)"
        content.body = countdown.details.isEmpty ? "The countdown is complete!" : countdown.details
        content.sound = .default
        let request = UNNotificationRequest(identifier: countdown.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
