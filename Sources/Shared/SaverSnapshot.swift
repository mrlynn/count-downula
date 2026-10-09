import Foundation

/// The screensaver's copy of the countdowns. Third-party screensavers run inside Apple's
/// `legacyScreenSaver` host, sandboxed to its own container, so they can't read the App Group the
/// widgets use. The Mac app (the GitHub build, which isn't sandboxed) mirrors the widget snapshot
/// into that container; the screensaver reads it with `WidgetSnapshot` pointed there.
enum SaverSnapshot {
    /// The host's container. Inside it, the screensaver sees this as its own Application Support.
    static let hostContainer = "com.apple.ScreenSaver.Engine.legacyScreenSaver"
    static let folder = "Count Downcula"

    /// Where the Mac app writes it: the host's container, from outside.
    static func exportDirectory(home: URL = URL(fileURLWithPath: NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory())) -> URL {
        home.appending(path: "Library/Containers/\(hostContainer)/Data/Library/Application Support/\(folder)",
                       directoryHint: .isDirectory)
    }

    /// Where the screensaver reads it: its own Application Support, which the sandbox maps to the same place.
    static var readDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return support.appending(path: folder, directoryHint: .isDirectory)
    }

    /// Mirrors the widget snapshot (countdowns, thumbnails, photos) into `destination`, copying only
    /// what changed and removing what's gone. Quietly does nothing if the host's container doesn't
    /// exist (the screensaver has never run) or can't be written (a sandboxed build).
    @discardableResult
    static func mirror(from source: URL = WidgetSnapshot.directory, to destination: URL = exportDirectory(),
                       requireHost: Bool = true) -> Bool {
        let fm = FileManager.default
        if requireHost {
            let container = destination.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
            guard fm.fileExists(atPath: container.path) else { return false }
        }
        guard (try? fm.createDirectory(at: destination, withIntermediateDirectories: true)) != nil,
              let files = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return false }
        let names = Set(files.map(\.lastPathComponent))
        for file in files {
            let target = destination.appending(path: file.lastPathComponent)
            guard let data = try? Data(contentsOf: file) else { continue }
            if (try? Data(contentsOf: target)) != data { try? data.write(to: target, options: .atomic) }
        }
        for stale in (try? fm.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)) ?? []
        where !names.contains(stale.lastPathComponent) {
            try? fm.removeItem(at: stale)
        }
        return true
    }

    /// What the screensaver shows, in order: pinned countdowns still counting (soonest first, then
    /// pinned count-ups), else Next Up. It steps through them every `interval` seconds.
    static func rotation(_ countdowns: [Countdown], at now: Date) -> [Countdown] {
        let pinned = countdowns.filter { $0.isPinned && !$0.isPast(at: now) }
            .sorted { ($0.countsUp ? 1 : 0, $0.targetDate) < ($1.countsUp ? 1 : 0, $1.targetDate) }
        if !pinned.isEmpty { return pinned }
        return countdowns.featured(at: now).map { [$0] } ?? []
    }

    static func showing(_ countdowns: [Countdown], at now: Date, interval: TimeInterval = 30) -> Countdown? {
        let order = rotation(countdowns, at: now)
        guard !order.isEmpty else { return nil }
        // One that's about to hit zero stays up for its last minute, whatever the rotation says.
        if let close = order.first(where: { !$0.countsUp && $0.targetDate.timeIntervalSince(now) < 60 }) { return close }
        return order[Int(now.timeIntervalSinceReferenceDate / interval) % order.count]
    }
}
