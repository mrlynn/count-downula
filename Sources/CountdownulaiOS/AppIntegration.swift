import AppIntents
import CoreSpotlight
import UniformTypeIdentifiers

// MARK: - Drafts from the Share Extension

extension PhoneStore {
    /// Adds countdowns confirmed in the share sheet. Ones over the free limit stay waiting, and
    /// `draftsWaitingForUnlock` asks the list to show the paywall, once per new arrival.
    /// Returns the first one added.
    @discardableResult
    func importSharedDrafts() -> UUID? {
        var waiting = DraftHandoff.pending
        guard !waiting.isEmpty else {
            _ = DraftHandoff.shouldAskToUnlock(waiting: 0)
            return nil
        }
        var first: UUID?
        while let draft = waiting.first, entitlements.canAdd(to: countdowns) {
            let countdown = draft.countdown()
            upsert(countdown, source: "screenshot")
            first = first ?? countdown.id
            waiting.removeFirst()
        }
        DraftHandoff.setPending(waiting)
        draftsWaitingForUnlock = DraftHandoff.shouldAskToUnlock(waiting: waiting.count)
        return first
    }
}

// MARK: - Spotlight

/// Countdowns in Spotlight search: "sonoma" finds "Sonoma Wine Weekend · in 16 days".
enum SpotlightIndex {
    static let domain = "countdowns"
    private static var lastSignature = 0

    static func update(_ countdowns: [Countdown]) {
        // Only when something people would search for changed; reloads are frequent.
        var hasher = Hasher()
        for c in countdowns { hasher.combine(c.id); hasher.combine(c.title); hasher.combine(c.details); hasher.combine(c.targetDate) }
        let signature = hasher.finalize()
        guard signature != lastSignature else { return }
        lastSignature = signature

        let items = countdowns.map { countdown in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = countdown.title
            attributes.contentDescription = countdown.countsUp
                ? "Since \(countdown.targetDate.formatted(date: .long, time: .omitted))"
                : countdown.targetDate.formatted(date: .long, time: .shortened)
            attributes.keywords = ["countdown", countdown.details].filter { !$0.isEmpty }
            return CSSearchableItem(uniqueIdentifier: countdown.id.uuidString, domainIdentifier: domain, attributeSet: attributes)
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            index.indexSearchableItems(items) { _ in }
        }
    }
}

// MARK: - Siri and Shortcuts

struct CountdownEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Countdown"
    static var defaultQuery = CountdownQuery()

    var id: UUID
    var title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }

    init(_ countdown: Countdown) {
        id = countdown.id
        title = countdown.title
    }
}

struct CountdownQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [CountdownEntity] {
        PhoneStore.shared.countdowns.filter { identifiers.contains($0.id) }.map(CountdownEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [CountdownEntity] {
        PhoneStore.shared.countdowns
            .filter { $0.title.localizedCaseInsensitiveContains(string) }
            .map(CountdownEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [CountdownEntity] {
        let now = Date()
        let store = PhoneStore.shared
        return (store.upcoming(at: now) + store.countingUp).map(CountdownEntity.init)
    }
}

struct TimeUntilIntent: AppIntent {
    static var title: LocalizedStringResource = "How Long Until"
    static var description = IntentDescription("Says how long until a countdown, or how long since a count-up began.")

    @Parameter(title: "Countdown")
    var countdown: CountdownEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let found = PhoneStore.shared.countdown(id: countdown.id) else {
            return .result(dialog: "I couldn't find that countdown.")
        }
        return .result(dialog: IntentDialog(stringLiteral: Self.sentence(for: found, now: Date())))
    }

    static func sentence(for countdown: Countdown, now: Date) -> String {
        if countdown.countsUp {
            return "It's been \(CountdownFormat.elapsed(since: countdown.targetDate, to: now)) since \(countdown.title)."
        }
        if let reading = countdown.reading(at: now) {
            return countdown.countUnit == .percent
                ? "\(countdown.title) is \(reading.long)."
                : "\(countdown.title) is in \(reading.long)."
        }
        let relative = CountdownFormat.relative(from: now, to: countdown.targetDate)
        return countdown.isPast(at: now)
            ? "\(countdown.title) was \(relative)."
            : "\(countdown.title) is in \(relative)."
    }
}

struct StartTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Timer"
    static var description = IntentDescription("Starts a timer that shows on the Lock Screen.")
    static var openAppWhenRun = true

    @Parameter(title: "Minutes", default: 10, inclusiveRange: (1, 1440))
    var minutes: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = PhoneStore.shared
        guard store.entitlements.canAdd(to: store.countdowns) else {
            return .result(dialog: "You're at the free limit. Open Count Downcula to unlock more.")
        }
        store.startQuickTimer(minutes: minutes)
        return .result(dialog: "Started a \(PhoneStore.durationLabel(minutes)) timer.")
    }
}

struct AddCountdownIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a Countdown"
    static var description = IntentDescription("Adds a countdown to a date.")

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Date")
    var date: Date

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = PhoneStore.shared
        guard store.entitlements.canAdd(to: store.countdowns) else {
            return .result(dialog: "You're at the free limit. Open Count Downcula to unlock more.")
        }
        guard date > Date() else { return .result(dialog: "That date has already passed.") }
        store.upsert(Countdown(title: title, details: "", targetDate: date), source: "siri")
        return .result(dialog: "Added \(title). It's in \(CountdownFormat.relative(from: Date(), to: date)).")
    }
}

struct CountdownShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TimeUntilIntent(),
            phrases: ["How long until \(\.$countdown) in \(.applicationName)", "\(.applicationName) \(\.$countdown)"],
            shortTitle: "How Long Until", systemImageName: "hourglass"
        )
        AppShortcut(
            intent: StartTimerIntent(),
            phrases: ["Start a timer in \(.applicationName)", "Start a \(.applicationName) timer"],
            shortTitle: "Start a Timer", systemImageName: "timer"
        )
        AppShortcut(
            intent: AddCountdownIntent(),
            phrases: ["Add a countdown in \(.applicationName)", "New \(.applicationName) countdown"],
            shortTitle: "Add a Countdown", systemImageName: "calendar.badge.plus"
        )
    }
}
