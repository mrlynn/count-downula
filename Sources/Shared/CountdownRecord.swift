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
    /// JSON-encoded `CountdownStyle`; nil means the default look. Older builds ignore it and leave it alone.
    var styleData: Data?

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
            hasImage: imageData != nil,
            style: styleData.flatMap { try? JSONDecoder().decode(CountdownStyle.self, from: $0) } ?? .default
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
        if countdown.style != .default {
            styleData = try? JSONEncoder().encode(countdown.style)
        } else if let styleData, (try? JSONDecoder().decode(CountdownStyle.self, from: styleData)) != nil {
            // Only clear a style this build understands; one from a newer build stays put.
            self.styleData = nil
        }
        updatedAt = Date()
    }
}
