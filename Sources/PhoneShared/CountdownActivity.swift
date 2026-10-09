import ActivityKit
import Foundation

/// Live Activity for a countdown in its final hours: Lock Screen banner, Dynamic Island and StandBy.
/// The views tick on their own (`Text(timerInterval:)`), so the app only updates it when the countdown is edited.
struct CountdownActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var startDate: Date
        var targetDate: Date
        /// Set by the server's push at zero for shared countdowns: everyone's activity celebrates together.
        var celebrating = false

        /// The range the live timer and progress views count across; never inverted.
        var interval: ClosedRange<Date> { min(startDate, targetDate)...targetDate }
    }

    var countdownID: UUID
    var kind: Countdown.Kind
    /// The countdown's accent color when the activity started (nil: Countdownula red).
    var accent: RGBAColor?
}

extension CountdownActivityAttributes.ContentState {
    private enum CodingKeys: String, CodingKey { case title, startDate, targetDate, celebrating }

    /// `celebrating` is optional in the JSON, so states from older builds and pushes still decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        startDate = try c.decode(Date.self, forKey: .startDate)
        targetDate = try c.decode(Date.self, forKey: .targetDate)
        celebrating = try c.decodeIfPresent(Bool.self, forKey: .celebrating) ?? false
    }
}
