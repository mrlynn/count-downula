import Foundation

/// A small JSON copy of the countdowns (plus thumbnails) in the shared App Group container.
/// The watch and iPhone apps write it whenever data changes; the widget extensions only read it,
/// which keeps them away from the CloudKit-backed SwiftData store. The iPhone app also copies the
/// display-size photos, which Home Screen widgets need at more than thumbnail resolution.
enum WidgetSnapshot {
    /// Where the snapshot lives. The screensaver can't see the App Group, so it reads a copy in its
    /// own container instead (see `SaverSnapshot`).
    nonisolated(unsafe) static var directoryOverride: URL?

    static var directory: URL {
        if let directoryOverride { return directoryOverride }
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroup)
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "WidgetSnapshot", directoryHint: .isDirectory)
    }

    private static var fileURL: URL { directory.appending(path: "countdowns.json") }

    private static func thumbnailURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).jpg")
    }

    /// Named after `imageCacheKey`, so an unchanged photo is never rewritten.
    private static func photoURL(for countdown: Countdown) -> URL {
        directory.appending(path: "\(countdown.imageCacheKey).photo")
    }

    static func read() -> [Countdown] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Countdown].self, from: data)) ?? []
    }

    /// The thumbnail's file, for surfaces that take an image URL (the Apple TV's Top Shelf).
    static func thumbnailFileURL(for countdown: Countdown) -> URL? {
        let url = thumbnailURL(for: countdown.id)
        return countdown.hasImage && FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func thumbnail(for id: UUID) -> Data? {
        try? Data(contentsOf: thumbnailURL(for: id))
    }

    static func photo(for countdown: Countdown) -> Data? {
        guard countdown.hasImage else { return nil }
        return try? Data(contentsOf: photoURL(for: countdown))
    }

    /// Writes the snapshot. Returns true when the content changed (so callers can reload timelines).
    @discardableResult
    static func write(_ countdowns: [Countdown], thumbnail: (UUID) -> Data?,
                      photo: ((UUID) -> Data?)? = nil) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(countdowns) else { return false }
        if (try? Data(contentsOf: fileURL)) == data { return false }

        let ids = Set(countdowns.map(\.id))
        for countdown in countdowns {
            let url = thumbnailURL(for: countdown.id)
            if countdown.hasImage, let thumb = thumbnail(countdown.id) {
                try? thumb.write(to: url, options: .atomic)
            } else {
                try? fm.removeItem(at: url)
            }
        }
        var photoNames: Set<String> = []
        if let photo {
            // Name photos from the decoded copy: ISO-8601 drops fractional seconds from `updatedAt`,
            // and the widget only ever sees the decoded dates.
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let stored = (try? decoder.decode([Countdown].self, from: data)) ?? countdowns
            for countdown in stored where countdown.hasImage {
                let url = photoURL(for: countdown)
                photoNames.insert(url.lastPathComponent)
                if !fm.fileExists(atPath: url.path), let data = photo(countdown.id) {
                    try? data.write(to: url, options: .atomic)
                }
            }
        }
        // Drop thumbnails for deleted countdowns, and photos that were replaced or removed.
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            switch file.pathExtension {
            case "jpg":
                if let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), !ids.contains(id) {
                    try? fm.removeItem(at: file)
                }
            case "photo" where !photoNames.contains(file.lastPathComponent):
                try? fm.removeItem(at: file)
            default:
                break
            }
        }

        try? data.write(to: fileURL, options: .atomic)
        return true
    }
}

/// How many times a Next Up widget's cycle button has been pressed, kept in the App Group so the
/// widget extension (which presses it) and its timeline (which reads it) agree. Shared by every
/// Next Up widget on the device.
enum WidgetCycle {
    private static let key = "WidgetCycle.offset"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: SharedConfig.appGroup) }

    static var offset: Int { defaults?.integer(forKey: key) ?? 0 }

    static func advance() { defaults?.set(offset + 1, forKey: key) }

    /// Back to the featured countdown, when the list it steps through changes.
    static func reset() { defaults?.removeObject(forKey: key) }
}
