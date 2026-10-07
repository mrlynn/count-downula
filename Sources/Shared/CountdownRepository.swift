import CoreData
import Foundation
import SwiftData

enum ImageUpdate {
    case unchanged
    case remove
    case set(image: Data, thumbnail: Data)
}

/// Platform-neutral CRUD over the SwiftData store. The Mac and watch stores wrap this
/// and add their own image decoding, ticking and side effects.
@MainActor
final class CountdownRepository {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    /// Fires on the main queue when CloudKit imports changes from another device.
    var onRemoteChange: (() -> Void)?

    init(storeURL: URL) {
        container = Self.makeContainer(storeURL: storeURL)
        context.autosaveEnabled = false
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onRemoteChange?() }
        }
    }

    private static func makeContainer(storeURL: URL) -> ModelContainer {
        let schema = Schema([CountdownRecord.self])
        if !SharedConfig.isLocalOnly {
            let cloud = ModelConfiguration(
                schema: schema, url: storeURL,
                cloudKitDatabase: .private(SharedConfig.cloudKitContainer)
            )
            if let container = try? ModelContainer(for: schema, configurations: cloud) {
                return container
            }
        }
        // No iCloud entitlement (unsigned build) or -localOnly: keep working without sync.
        let local = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            fatalError("Could not open the Countdownula store: \(error)")
        }
    }

    // MARK: - Reads

    func fetchAll() -> [Countdown] {
        let descriptor = FetchDescriptor<CountdownRecord>(sortBy: [SortDescriptor(\.targetDate)])
        let records = (try? context.fetch(descriptor)) ?? []
        // CloudKit can briefly deliver the same record twice during first sync; keep the newest.
        var seen: [UUID: Countdown] = [:]
        for record in records {
            let countdown = record.countdown
            if let existing = seen[countdown.id], existing.updatedAt >= countdown.updatedAt { continue }
            seen[countdown.id] = countdown
        }
        return seen.values.sorted { $0.targetDate < $1.targetDate }
    }

    func imageData(for id: UUID) -> Data? { record(id)?.imageData }
    func thumbnailData(for id: UUID) -> Data? { record(id)?.thumbnailData }

    // MARK: - Writes

    func upsert(_ countdown: Countdown, image: ImageUpdate = .unchanged) {
        var countdown = countdown
        countdown.resetMilestonesInFuture(at: Date())
        // A count-up never "completes". Builds that predate count-ups read it as a finished event,
        // so mark it notified or they'd post a completion alert for it.
        if countdown.countsUp { countdown.hasNotified = true }
        let record = record(countdown.id) ?? {
            let new = CountdownRecord(uuid: countdown.id)
            context.insert(new)
            return new
        }()
        record.apply(countdown)
        switch image {
        case .unchanged:
            break
        case .remove:
            record.imageData = nil
            record.thumbnailData = nil
        case let .set(full, thumbnail):
            record.imageData = full
            record.thumbnailData = thumbnail
        }
        save()
    }

    /// Moves yearly countdowns whose day has passed on to next year. Every device does this; the
    /// result is the same wherever it runs, so it doesn't matter which one gets there first.
    /// Returns true when anything changed.
    @discardableResult
    func rollOverYearlyCountdowns(at now: Date = Date()) -> Bool {
        var changed = false
        for var countdown in fetchAll() where countdown.rollToNextYear(at: now) {
            upsert(countdown)
            changed = true
        }
        return changed
    }

    func delete(id: UUID) {
        for record in records(id) { context.delete(record) }
        save()
    }

    func setPinned(_ pinned: Bool, id: UUID) {
        guard let record = record(id) else { return }
        record.isPinned = pinned
        record.updatedAt = Date()
        save()
    }

    /// Records that milestone celebrations played. Leaves `updatedAt` alone so photo caches stay valid.
    func markCelebrated(milestoneIDs: Set<UUID>, id: UUID, at date: Date = Date()) {
        guard let record = record(id) else { return }
        var milestones = record.countdown.milestones
        for index in milestones.indices where milestoneIDs.contains(milestones[index].id) {
            milestones[index].celebratedAt = date
        }
        record.milestonesData = try? JSONEncoder().encode(milestones)
        save()
    }

    func markNotified(ids: [UUID]) {
        for id in ids { record(id)?.hasNotified = true }
        save()
    }

    // MARK: - Helpers

    private func records(_ id: UUID) -> [CountdownRecord] {
        let descriptor = FetchDescriptor<CountdownRecord>(predicate: #Predicate { $0.uuid == id })
        return (try? context.fetch(descriptor)) ?? []
    }

    private func record(_ id: UUID) -> CountdownRecord? {
        records(id).max { $0.updatedAt < $1.updatedAt }
    }

    private func save() {
        do {
            try context.save()
        } catch {
            print("Countdownula: save failed: \(error)")
        }
    }
}
