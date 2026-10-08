import Foundation

/// Identifiers that must match project.yml and the entitlements files.
enum SharedConfig {
    static let cloudKitContainer = "iCloud.com.countdownula.app"
    static let appGroup = "group.com.countdownula.app"
    static let widgetKind = "CountdownComplication"

    /// One-time, non-consumable "Count Downcula Unlimited" in-app purchase (App Store Connect + Countdownula.storekit).
    static let unlimitedProductID = "com.countdownula.app.unlimited"
    /// Active countdowns (upcoming, running timers and count-ups) allowed without Unlimited. Finished ones don't count.
    static let freeActiveLimit = 3

    /// Pass `-localOnly` to run without iCloud (unsigned simulator builds, debugging).
    static var isLocalOnly: Bool {
        ProcessInfo.processInfo.arguments.contains("-localOnly")
    }
}
