import AppKit
import Observation
import UserNotifications

@MainActor
@Observable
final class CountdownStore {
    private(set) var countdowns: [Countdown] = []
    private(set) var now = Date()

    /// Called every tick and after every mutation so the menu bar items can refresh.
    @ObservationIgnored var onUpdate: (() -> Void)?

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored let imagesDirectory: URL
    @ObservationIgnored private var imageCache: [String: NSImage] = [:]
    @ObservationIgnored private var timer: Timer?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Countdownula", directoryHint: .isDirectory)
        fileURL = support.appending(path: "countdowns.json")
        imagesDirectory = support.appending(path: "images", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        load()

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

    func upsert(_ countdown: Countdown) {
        var countdown = countdown
        if !countdown.isPast(at: Date()) { countdown.hasNotified = false }
        if let index = countdowns.firstIndex(where: { $0.id == countdown.id }) {
            let oldImage = countdowns[index].imageFileName
            countdowns[index] = countdown
            if let oldImage, oldImage != countdown.imageFileName { deleteImage(named: oldImage) }
        } else {
            countdowns.append(countdown)
        }
        save()
    }

    func delete(_ countdown: Countdown) {
        countdowns.removeAll { $0.id == countdown.id }
        if let name = countdown.imageFileName { deleteImage(named: name) }
        save()
    }

    func togglePin(_ countdown: Countdown) {
        guard let index = countdowns.firstIndex(where: { $0.id == countdown.id }) else { return }
        countdowns[index].isPinned.toggle()
        save()
    }

    // MARK: - Images

    func image(named name: String?) -> NSImage? {
        guard let name else { return nil }
        if let cached = imageCache[name] { return cached }
        guard let image = NSImage(contentsOf: imagesDirectory.appending(path: name)) else { return nil }
        imageCache[name] = image
        return image
    }

    /// Copies a user-chosen photo into the app's storage, downscaled to a sane size.
    func importImage(from url: URL) -> String? {
        guard let source = NSImage(contentsOf: url),
              let data = source.jpegData(maxPixelDimension: 1400) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: imagesDirectory.appending(path: name))
            return name
        } catch {
            return nil
        }
    }

    func deleteImage(named name: String) {
        imageCache[name] = nil
        try? FileManager.default.removeItem(at: imagesDirectory.appending(path: name))
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        countdowns = (try? decoder.decode([Countdown].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(countdowns) {
            try? data.write(to: fileURL, options: .atomic)
        }
        onUpdate?()
    }

    private func tick() {
        now = Date()
        var changed = false
        for index in countdowns.indices where countdowns[index].isPast(at: now) && !countdowns[index].hasNotified {
            countdowns[index].hasNotified = true
            Notifier.post(for: countdowns[index])
            changed = true
        }
        if changed { save() } else { onUpdate?() }
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
