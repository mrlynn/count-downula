import Foundation

/// Identifiers that must match project.yml and the entitlements files.
enum SharedConfig {
    static let cloudKitContainer = "iCloud.com.countdownula.app"
    #if os(macOS)
    /// On the Mac, app groups are named with the team ID: this one lets the menu bar app share its
    /// countdowns with its desktop widgets.
    static let appGroup = "YZ36Z8GSEN.com.countdownula.app"
    #else
    static let appGroup = "group.com.countdownula.app"
    #endif
    static let widgetKind = "CountdownComplication"

    /// One-time, non-consumable "Count Downcula Unlimited" in-app purchase (App Store Connect + Countdownula.storekit).
    static let unlimitedProductID = "com.countdownula.app.unlimited"
    /// Consumable "Host Pass": hosts one shared countdown (custom link, no branding, bigger coffin, keepsake).
    static let hostPassProductID = "com.countdownula.app.hostpass"
    /// Active countdowns (upcoming, running timers and count-ups) allowed without Unlimited. Finished ones don't count.
    static let freeActiveLimit = 3

    /// Pass `-localOnly` to run without iCloud (unsigned simulator builds, debugging).
    static var isLocalOnly: Bool {
        ProcessInfo.processInfo.arguments.contains("-localOnly")
    }
}

/// `countdownula://countdown/<uuid>` opens a countdown's detail screen (widgets, Live Activities, notifications).
enum CountdownLink {
    static let scheme = "countdownula"

    static func url(for id: UUID) -> URL {
        URL(string: "\(scheme)://countdown/\(id.uuidString)")!
    }

    static func id(from url: URL) -> UUID? {
        guard url.scheme == scheme, url.host() == "countdown" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
