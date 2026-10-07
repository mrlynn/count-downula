import Foundation

/// A small JSON copy of the countdowns (plus thumbnails) in the shared App Group container.
/// The watch app writes it whenever data changes; the complication extension only reads it,
/// which keeps the extension away from the CloudKit-backed SwiftData store.
enum WidgetSnapshot {
    private static var directory: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroup)
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "WidgetSnapshot", directoryHint: .isDirectory)
    }

    private static var fileURL: URL { directory.appending(path: "countdowns.json") }

    private static func thumbnailURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).jpg")
    }

    static func read() -> [Countdown] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Countdown].self, from: data)) ?? []
    }

    static func thumbnail(for id: UUID) -> Data? {
        try? Data(contentsOf: thumbnailURL(for: id))
    }

    /// Writes the snapshot. Returns true when the content changed (so callers can reload timelines).
    @discardableResult
    static func write(_ countdowns: [Countdown], thumbnail: (UUID) -> Data?) -> Bool {
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
        // Drop thumbnails for deleted countdowns.
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "jpg" {
            if let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), !ids.contains(id) {
                try? fm.removeItem(at: file)
            }
        }

        try? data.write(to: fileURL, options: .atomic)
        return true
    }
}
