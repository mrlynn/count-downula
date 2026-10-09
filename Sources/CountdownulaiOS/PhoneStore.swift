import Observation
import SwiftUI
import UserNotifications
import WidgetKit

@MainActor
@Observable
final class PhoneStore {
    /// The one store. Siri, Shortcuts and Spotlight reach it from outside the view hierarchy.
    static let shared = PhoneStore()

    private(set) var countdowns: [Countdown] = []
    /// Countdowns confirmed in the share sheet that are over the free limit, waiting for Unlimited.
    var draftsWaitingForUnlock = false
    /// The milestone or finish being celebrated on screen right now.
    var celebration: Celebration?
    /// The Unlimited purchase and the free-tier limit it lifts.
    let entitlements = Entitlements()

    /// Titles of joined countdowns whose owner stopped sharing, waiting to be mentioned once.
    var sharingEnded: [String] = []

    @ObservationIgnored let repository: CountdownRepository
    /// When each joined countdown was last checked against the owner's copy (this device only).
    @ObservationIgnored var lastSharedRefresh: [UUID: Date] = [:]
    @ObservationIgnored private var imageCache: [String: UIImage] = [:]
    @ObservationIgnored private var thumbnailCache: [String: UIImage] = [:]

    init() {
        #if DEBUG
        CloudKitSchemaInitializer.runIfRequested()
        #endif
        let directory = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        repository = CountdownRepository(storeURL: directory.appending(path: "Countdownula.store"))
        repository.onRemoteChange = { [weak self] in self?.reload() }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedDemo") { seedDemoData() }
        #endif
        reload()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Queries

    func upcoming(at now: Date) -> [Countdown] {
        countdowns.filter { $0.isUpcoming(at: now) }.sorted { $0.targetDate < $1.targetDate }
    }

    /// Count-ups, longest-running first.
    var countingUp: [Countdown] {
        countdowns.filter(\.countsUp).sorted { $0.targetDate < $1.targetDate }
    }

    func past(at now: Date) -> [Countdown] {
        countdowns.filter { $0.isPast(at: now) }.sorted { $0.targetDate > $1.targetDate }
    }

    func countdown(id: UUID) -> Countdown? {
        countdowns.first { $0.id == id }
    }

    func image(for countdown: Countdown) -> UIImage? {
        cachedImage(for: countdown, in: &imageCache) { repository.imageData(for: $0) }
    }

    func thumbnail(for countdown: Countdown) -> UIImage? {
        cachedImage(for: countdown, in: &thumbnailCache) { repository.thumbnailData(for: $0) }
    }

    private func cachedImage(for countdown: Countdown, in cache: inout [String: UIImage],
                             load: (UUID) -> Data?) -> UIImage? {
        guard countdown.hasImage else { return nil }
        if let cached = cache[countdown.imageCacheKey] { return cached }
        guard let data = load(countdown.id), let image = UIImage(data: data) else { return nil }
        cache[countdown.imageCacheKey] = image
        return image
    }

    /// Prepares the display and thumbnail JPEGs that get stored and synced, from any photo's raw data.
    nonisolated static func prepareImage(_ data: Data) -> (preview: UIImage, update: ImageUpdate)? {
        guard let full = ImageDownsampling.jpegData(from: data, maxPixelDimension: 1400),
              let thumb = ImageDownsampling.jpegData(from: data, maxPixelDimension: 240, quality: 0.8),
              let preview = UIImage(data: full) else { return nil }
        return (preview, .set(image: full, thumbnail: thumb))
    }

    // MARK: - Mutations

    /// `source` says how a new countdown was made ("screenshot", "siri"), for the metrics dashboard.
    func upsert(_ countdown: Countdown, image: ImageUpdate = .unchanged, source: String? = nil) {
        var countdown = countdown
        if !countdown.isPast(at: Date()) { countdown.hasNotified = false }
        let isNew = self.countdown(id: countdown.id) == nil
        repository.upsert(countdown, image: image)
        reload()
        // Joined countdowns are counted by the server when they're joined.
        if isNew, countdown.extras.subscription == nil {
            Analytics.log(.countdownCreated, source: source ?? Analytics.source(for: countdown))
        }
    }

    func delete(_ countdown: Countdown) {
        Analytics.log(.countdownDeleted, source: Analytics.deletionSource(for: countdown))
        // Deleting someone else's shared countdown means leaving it.
        if countdown.extras.subscription != nil {
            leave(countdown)
            return
        }
        // Deleting a published countdown takes its public page down too.
        if let link = countdown.extras.link, OwnerTokens.token(for: countdown.id) != nil {
            Task { try? await LiveLinkAPI.unpublish(countdown, slug: link.slug) }
        }
        repository.delete(id: countdown.id)
        reload()
    }

    func togglePin(_ countdown: Countdown) {
        repository.setPinned(!countdown.isPinned, id: countdown.id)
        reload()
    }

    func resetStreak(_ countdown: Countdown) {
        var countdown = countdown
        countdown.resetStreak(at: Date())
        repository.upsert(countdown)
        reload()
    }

    // MARK: - Celebrations

    func markCelebrated(_ milestones: [ScheduledMilestone], of countdown: Countdown) {
        repository.markCelebrated(milestoneIDs: Set(milestones.map(\.id)), id: countdown.id)
        reload()
    }

    /// Whether the "it's here" confetti should play: finished within the last day and not yet shown
    /// on this device. Kept per device; it's a small moment, not worth a sync round trip.
    func shouldCelebrateCompletion(of countdown: Countdown, at now: Date) -> Bool {
        guard countdown.isPast(at: now), countdown.targetDate > now - 86_400 else { return false }
        return !celebratedCompletions.contains(completionKey(countdown))
    }

    func markCompletionCelebrated(_ countdown: Countdown) {
        var keys = celebratedCompletions
        keys.insert(completionKey(countdown))
        // Only countdowns that still exist are worth remembering.
        let ids = Set(countdowns.map(\.id.uuidString))
        keys = keys.filter { ids.contains(String($0.prefix(36))) }
        UserDefaults.standard.set(Array(keys), forKey: Self.celebratedCompletionsKey)
    }

    private static let celebratedCompletionsKey = "Celebrations.completions"

    private var celebratedCompletions: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.celebratedCompletionsKey) ?? [])
    }

    private func completionKey(_ countdown: Countdown) -> String {
        "\(countdown.id.uuidString)@\(Int(countdown.targetDate.timeIntervalSince1970))"
    }

    /// One-tap timer from the list's + menu. Timers go live on the Lock Screen straight away.
    func startQuickTimer(minutes: Int) {
        let now = Date()
        let countdown = Countdown(
            title: "\(Self.durationLabel(minutes)) timer", details: "",
            targetDate: now.addingTimeInterval(TimeInterval(minutes * 60)), kind: .timer, createdAt: now
        )
        upsert(countdown, source: "quick_timer")
        LiveActivities.start(countdown)
    }

    static func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        return hours == hours.rounded() ? "\(Int(hours)) hr" : String(format: "%.1f hr", hours)
    }

    // MARK: - Sync side effects

    func reload() {
        let rolled = repository.rollOverRepeatingCountdowns()
        let fresh = repository.fetchAll()
        if fresh != countdowns { countdowns = fresh }
        // A published page follows its countdown on to next year or the next sunrise.
        for countdown in rolled { pushLinkUpdate(for: countdown) }
        publishToWidgets()
        Analytics.noteFinished(countdowns)
        SpotlightIndex.update(countdowns)
        scheduleNotifications()
        LiveActivities.sync(with: countdowns)
    }

    private func publishToWidgets() {
        let repository = repository
        let changed = WidgetSnapshot.write(
            countdowns,
            thumbnail: { repository.thumbnailData(for: $0) },
            photo: { repository.imageData(for: $0) }
        )
        if changed { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// The phone can't rely on the Mac being awake, so it schedules its own completion and milestone alerts.
    private func scheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date()
        // iOS keeps at most 64 pending requests per app.
        for item in NotificationPlan.items(for: countdowns, now: now, limit: 60, includeFinalCountdown: true) {
            let interval = item.date.timeIntervalSince(now)
            guard interval > 1 else { continue }
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            switch item.sound {
            case .standard: content.sound = .default
            case let .named(file): content.sound = UNNotificationSound(named: UNNotificationSoundName(file))
            case .silent: content.sound = nil
            }
            content.userInfo = ["countdownID": item.countdownID.uuidString]
            if let category = item.category { content.categoryIdentifier = category.rawValue }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
        }
    }

    #if DEBUG
    private func seedDemoData() {
        guard repository.fetchAll().isEmpty else { return }
        let now = Date()
        let day: TimeInterval = 86_400
        var samples = [
            Countdown(title: "Sonoma Wine Weekend", details: "Three days of vineyards, long lunches and zero laptops.",
                      targetDate: now + 16 * day + 25_200, isPinned: true, createdAt: now - 30 * day),
            Countdown(title: "Focus Block", details: "Heads down on the release notes",
                      targetDate: now + 18 * 60, kind: .timer, createdAt: now - 7 * 60),
            Countdown(title: "Sam's 30th Birthday", details: "Dinner at 7 — pick up the cake!",
                      targetDate: now + 9 * day + 10_800, createdAt: now - 20 * day),
            Countdown(title: "Product Launch", details: "Ship it.",
                      targetDate: now + 5 * 3_600 + 1_200, createdAt: now - 2 * day),
            Countdown(title: "Conference Talk", details: "Nailed it.",
                      targetDate: now - 3 * day, createdAt: now - 60 * day, hasNotified: true),
        ]
        samples[2].style = CountdownStyle(background: .scene(.birthday), font: .serif, weight: .heavy,
                                          textColor: RGBAColor(hex: 0x1C1C1E), accent: RGBAColor(hex: 0xFF5D73))
        samples[3].style = CountdownStyle(background: .gradient(GradientSpec.presets[4].spec), font: .expanded,
                                          accent: RGBAColor(hex: 0xFFD166))
        samples[0].style = CountdownStyle(background: .scene(.sunset), font: .rounded)
        samples[0].milestones = [
            Milestone(title: "Flights booked", emoji: "✈️", trigger: .date(now - 3_600)),
            MilestonePreset.halfway.milestone, MilestonePreset.oneWeek.milestone, MilestonePreset.oneDay.milestone,
        ]
        samples[2].milestones = [MilestonePreset.halfway.milestone, MilestonePreset.oneWeek.milestone]
        samples[2].extras.repeatsYearly = true

        var smokeFree = Countdown(title: "Smoke-Free", details: "Every day without one counts.",
                                  targetDate: now - 47 * day - 5 * 3_600, kind: .countUp, createdAt: now - 47 * day)
        smokeFree.style = CountdownStyle(background: .scene(.ocean), font: .rounded, accent: RGBAColor(hex: 0x1F6FB2))
        smokeFree.milestones = MilestonePreset.countUpDefaults()
        smokeFree.extras.savings = Savings(amountPerDay: 12, currencyCode: "USD")
        smokeFree.extras.streak.runs = [.init(start: now - 140 * day, end: now - 47 * day - 5 * 3_600)]
        samples.append(smokeFree)
        // A years-long count-up: the widest time text a row has to fit.
        var together = Countdown(title: "Together", details: "Since the first date.",
                                 targetDate: now - 4_652 * day, kind: .countUp, createdAt: now)
        together.style = CountdownStyle(background: .scene(.blossoms), font: .serif, accent: RGBAColor(hex: 0xD6336C))
        samples.append(together)
        // A date pool: friends guess when the baby arrives.
        var baby = Countdown(title: "Baby Chen Arrives", details: "Due date is the 30th. Place your guesses!",
                             targetDate: now + 52 * day + 4 * 3_600, createdAt: now - 180 * day)
        baby.style = CountdownStyle(background: .scene(.baby), font: .rounded, textColor: RGBAColor(hex: 0x3A3A5C),
                                    accent: RGBAColor(hex: 0xE57CA2))
        baby.extras.pool = DatePool()
        samples.append(baby)
        samples.forEach { repository.upsert($0) }
    }
    #endif
}

/// Confetti and a banner for a milestone or a finished countdown.
struct Celebration: Equatable {
    let id = UUID()
    let countdownID: UUID
    let emoji: String
    let title: String
    let subtitle: String
}
