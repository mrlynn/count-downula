import AppIntents
import WidgetKit

/// Buttons on the Home Screen widgets and Control Center controls. Each type is compiled into both
/// the app and the widget extension, since the system needs to know it in both.
///
/// The ones that change countdowns (pin, start the Live Activity, start a timer, open one) are
/// `LiveActivityIntent`s or open the app, so iOS runs them in the app's process, where the store
/// lives; the app registers `WidgetActions.handler` at launch to do the work. Cycling only moves an
/// offset the widgets read from the App Group, so it runs in the extension.
enum WidgetAction: Equatable {
    case togglePin(UUID)
    case startLiveActivity(UUID)
    case quickTimer(minutes: Int)
    case open(UUID?)
}

enum WidgetActions {
    /// Set by the app at launch. Never set in the widget extension, which never runs these.
    @MainActor static var handler: ((WidgetAction) async throws -> Void)?

    @MainActor
    static func perform(_ action: WidgetAction) async throws {
        try await handler?(action)
    }
}

#if os(iOS)
struct ToggleWidgetPinIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pin or Unpin Countdown"
    static let isDiscoverable = false

    @Parameter(title: "Countdown ID")
    var countdownID: String

    init() {}
    init(countdownID: UUID) { self.countdownID = countdownID.uuidString }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: countdownID) { try await WidgetActions.perform(.togglePin(id)) }
        return .result()
    }
}

struct StartWidgetLiveActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Show Countdown on Lock Screen"
    static let isDiscoverable = false

    @Parameter(title: "Countdown ID")
    var countdownID: String

    init() {}
    init(countdownID: UUID) { self.countdownID = countdownID.uuidString }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: countdownID) { try await WidgetActions.perform(.startLiveActivity(id)) }
        return .result()
    }
}

/// Control Center's Quick Timer: makes a timer and puts it on the Lock Screen without opening the app.
struct StartQuickTimerControlIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start a Quick Timer"
    static let isDiscoverable = false

    @Parameter(title: "Minutes", default: 10, inclusiveRange: (1, 720))
    var minutes: Int

    init() {}
    init(minutes: Int) { self.minutes = minutes }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await WidgetActions.perform(.quickTimer(minutes: minutes))
        return .result()
    }
}

#endif

/// Opens the app on a countdown, or on the list.
struct OpenCountdownIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Countdown"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    @Parameter(title: "Countdown ID")
    var countdownID: String?

    init() {}
    init(countdownID: UUID?) { self.countdownID = countdownID?.uuidString }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await WidgetActions.perform(.open(countdownID.flatMap(UUID.init(uuidString:))))
        return .result()
    }
}

/// Steps a Next Up widget to the following countdown, and round again after the last.
struct CycleWidgetCountdownIntent: AppIntent {
    static let title: LocalizedStringResource = "Show the Next Countdown"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        WidgetCycle.advance()
        WidgetCenter.shared.reloadTimelines(ofKind: SharedConfig.widgetKind)
        return .result()
    }
}

/// The Next Up control's kind, which the app reloads when countdowns change.
enum NextUpControlKind {
    static let value = "com.countdownula.app.next-up"
}
