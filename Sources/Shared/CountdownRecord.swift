import Foundation
import SwiftData

/// SwiftData model synced through the user's private iCloud database.
/// CloudKit requires every attribute to be optional or have a default, and no unique constraints.
@Model
final class CountdownRecord {
    var uuid: UUID = UUID()
    var title: String = ""
    var details: String = ""
    var targetDate: Date = Date()
    var kindRaw: String = Countdown.Kind.event.rawValue
    var isPinned: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var hasNotified: Bool = false
    /// Display-size JPEG (≤1400px). Stored outside the SQLite file and synced as a CKAsset.
    @Attribute(.externalStorage) var imageData: Data?
    /// Small JPEG (≤240px) for lists, the menu bar and complications.
    @Attribute(.externalStorage) var thumbnailData: Data?

    init(uuid: UUID = UUID()) {
        self.uuid = uuid
    }

    var countdown: Countdown {
        Countdown(
            id: uuid,
            title: title,
            details: details,
            targetDate: targetDate,
            kind: Countdown.Kind(rawValue: kindRaw) ?? .event,
            isPinned: isPinned,
            createdAt: createdAt,
            updatedAt: updatedAt,
            hasNotified: hasNotified,
            hasImage: imageData != nil
        )
    }

    func apply(_ countdown: Countdown) {
        title = countdown.title
        details = countdown.details
        targetDate = countdown.targetDate
        kindRaw = countdown.kind.rawValue
        isPinned = countdown.isPinned
        createdAt = countdown.createdAt
        hasNotified = countdown.hasNotified
        updatedAt = Date()
    }
}
