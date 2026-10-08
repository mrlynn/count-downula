import Foundation

/// The App Clip's "Keep It": the clip leaves the shared countdown's slug in the App Group, and the
/// full app joins it the first time it opens, so the countdown is waiting after install.
enum ClipHandoff {
    private static let key = "ClipHandoff.pendingSlugs"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: SharedConfig.appGroup) }

    static func keep(_ slug: String) {
        guard let defaults else { return }
        var slugs = defaults.stringArray(forKey: key) ?? []
        if !slugs.contains(slug) { slugs.append(slug) }
        defaults.set(slugs, forKey: key)
    }

    static var pending: [String] { defaults?.stringArray(forKey: key) ?? [] }

    static func done(_ slug: String) {
        guard let defaults else { return }
        defaults.set(pending.filter { $0 != slug }, forKey: key)
    }
}
