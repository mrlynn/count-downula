import XCTest

final class FreeTierTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func event(inDays days: Double) -> Countdown {
        Countdown(title: "Event", details: "", targetDate: now + days * day, createdAt: now - day)
    }

    private func countUp() -> Countdown {
        Countdown(title: "Sober", details: "", targetDate: now - 30 * day, kind: .countUp, createdAt: now - 30 * day)
    }

    func testFinishedCountdownsDontCountButCountUpsDo() {
        let list = [event(inDays: 3), event(inDays: -2), countUp()]
        XCTAssertEqual(Entitlements.activeCount(in: list, at: now), 2)
    }

    func testFreeUsersCanAddUntilTheLimit() {
        let two = [event(inDays: 1), countUp(), event(inDays: -5)]
        XCTAssertTrue(Entitlements.canAdd(to: two, unlocked: false, at: now))

        let three = two + [event(inDays: 9)]
        XCTAssertFalse(Entitlements.canAdd(to: three, unlocked: false, at: now))
        XCTAssertTrue(Entitlements.canAdd(to: three, unlocked: true, at: now))
    }

    func testEditingAnActiveCountdownIsAlwaysAllowed() {
        // Over the limit, e.g. synced from the Mac app or after a refund.
        let list = (1...5).map { event(inDays: Double($0)) }
        var edited = list[0]
        edited.title = "Renamed"
        XCTAssertTrue(Entitlements.allowsSaving(edited, replacing: list[0], in: list, unlocked: false, at: now))
    }

    func testRevivingAFinishedCountdownCountsAsAdding() {
        let finished = event(inDays: -1)
        let list = [event(inDays: 1), event(inDays: 2), event(inDays: 3), finished]
        var revived = finished
        revived.targetDate = now + 10 * day
        XCTAssertFalse(Entitlements.allowsSaving(revived, replacing: finished, in: list, unlocked: false, at: now))

        // Saving something that stays finished never needs Unlimited.
        var renamed = finished
        renamed.title = "Renamed"
        XCTAssertTrue(Entitlements.allowsSaving(renamed, replacing: finished, in: list, unlocked: false, at: now))
    }
}
