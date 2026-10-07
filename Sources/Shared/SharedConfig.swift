import Foundation

/// Identifiers that must match project.yml and the entitlements files.
enum SharedConfig {
    static let cloudKitContainer = "iCloud.com.countdownula.app"
    static let appGroup = "group.com.countdownula.app"
    static let widgetKind = "CountdownComplication"

    /// Pass `-localOnly` to run without iCloud (unsigned simulator builds, debugging).
    static var isLocalOnly: Bool {
        ProcessInfo.processInfo.arguments.contains("-localOnly")
    }
}
