import ActivityKit
import Foundation

/// Live Activity for a countdown in its final hours: Lock Screen banner, Dynamic Island and StandBy.
/// The views tick on their own (`Text(timerInterval:)`), so the app only updates it when the countdown is edited.
struct CountdownActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var startDate: Date
        var targetDate: Date

        /// The range the live timer and progress views count across; never inverted.
        var interval: ClosedRange<Date> { min(startDate, targetDate)...targetDate }
    }

    var countdownID: UUID
    var kind: Countdown.Kind
    /// The countdown's accent color when the activity started (nil: Countdownula red).
    var accent: RGBAColor?
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
