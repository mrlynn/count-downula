import XCTest

final class SharedCountdownTests: XCTestCase {
    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    // MARK: - Links

    func testSlugsComeFromSharedLinksJoinLinksAndPastedSlugs() {
        XCTAssertEqual(SharedCountdowns.slug(from: "https://go.countdowncula.com/c/EPdLHJj9"), "EPdLHJj9")
        XCTAssertEqual(SharedCountdowns.slug(from: "  https://go.countdowncula.com/c/EPdLHJj9/\n"), "EPdLHJj9")
        XCTAssertEqual(SharedCountdowns.slug(from: "http://localhost:4300/c/aB3d"), "aB3d")
        XCTAssertEqual(SharedCountdowns.slug(from: "countdownula://join/EPdLHJj9"), "EPdLHJj9")
        XCTAssertEqual(SharedCountdowns.slug(from: "EPdLHJj9"), "EPdLHJj9")

        XCTAssertNil(SharedCountdowns.slug(from: "https://go.countdowncula.com/"))
        XCTAssertNil(SharedCountdowns.slug(from: "https://go.countdowncula.com/privacy"))
        XCTAssertNil(SharedCountdowns.slug(from: "countdownula://countdown/\(UUID().uuidString)"), "Widget links aren't joins")
        XCTAssertNil(SharedCountdowns.slug(from: "mailto:someone@example.com"))
        XCTAssertNil(SharedCountdowns.slug(from: "two words"))
        XCTAssertNil(SharedCountdowns.slug(from: "abc"))
    }

    // MARK: - Server JSON

    private let milestoneID = UUID()

    private func serverJSON(title: String = "Sonoma Wine Weekend", updatedAt: String = "2026-10-08T10:00:00.123Z",
                            members: Int = 3) -> Data {
        // Shaped like GET /api/countdowns/<slug>: server dates carry milliseconds, the style and
        // milestones are the app's own JSON, and milestone dates went up as plain ISO 8601.
        Data("""
        {"url":"https://go.countdowncula.com/c/EPdLHJj9","memberCount":\(members),
         "countdown":{"slug":"EPdLHJj9","title":"\(title)","details":"Three days of vineyards.",
          "targetDate":"2026-10-24T14:36:07.000Z","createdAt":"2026-09-08T14:36:07.000Z",
          "updatedAt":"\(updatedAt)","kind":"event","timeZone":"America/New_York",
          "style":{"background":{"scene":{"_0":"sunset"}},"font":"rounded","weight":"bold"},
          "milestones":[{"id":"\(milestoneID.uuidString)","title":"Flights booked","emoji":"✈️",
                         "trigger":{"date":{"_0":"2026-10-08T06:36:00Z"}},"celebratedAt":"2026-10-08T07:00:00Z"}],
          "hasPhoto":true}}
        """.utf8)
    }

    func testDecodesTheServersCountdown() throws {
        let remote = try RemoteCountdown.decode(serverJSON())
        XCTAssertEqual(remote.title, "Sonoma Wine Weekend")
        XCTAssertEqual(remote.targetDate, date("2026-10-24T14:36:07Z"))
        XCTAssertEqual(remote.updatedAt.timeIntervalSince(date("2026-10-08T10:00:00Z")), 0.123, accuracy: 0.001)
        XCTAssertEqual(remote.style.background, .scene(.sunset))
        XCTAssertEqual(remote.milestones.first?.trigger, .date(date("2026-10-08T06:36:00Z")))
        XCTAssertEqual(remote.memberCount, 3)
        XCTAssertEqual(remote.url?.absoluteString, "https://go.countdowncula.com/c/EPdLHJj9")
        XCTAssertTrue(remote.hasPhoto)
    }

    func testAStyleFromANewerAppFallsBackInsteadOfFailing() throws {
        var text = String(decoding: serverJSON(), as: UTF8.self)
        text = text.replacingOccurrences(of: #"{"background":{"scene":{"_0":"sunset"}},"font":"rounded","weight":"bold"}"#,
                                         with: #"{"background":{"hologram":{}}}"#)
        let remote = try RemoteCountdown.decode(Data(text.utf8))
        XCTAssertEqual(remote.style, .default)
        XCTAssertEqual(remote.title, "Sonoma Wine Weekend")
    }

    // MARK: - Keeping in step

    func testJoiningMakesALocalCopyMarkedAsShared() throws {
        let remote = try RemoteCountdown.decode(serverJSON())
        let url = URL(string: "https://go.countdowncula.com/c/EPdLHJj9")!
        let countdown = SharedCountdowns.makeCountdown(from: remote, slug: "EPdLHJj9", url: url, now: date("2026-10-08T12:00:00Z"))
        XCTAssertEqual(countdown.title, "Sonoma Wine Weekend")
        XCTAssertEqual(countdown.createdAt, remote.createdAt)
        XCTAssertEqual(countdown.extras.subscription?.slug, "EPdLHJj9")
        XCTAssertEqual(countdown.extras.subscription?.remoteUpdatedAt, remote.updatedAt)
        XCTAssertNil(countdown.milestones.first?.celebratedAt, "The owner's celebration isn't the member's")
        XCTAssertNil(countdown.extras.link, "A joined countdown isn't published by this person")
    }

    func testOwnerEditsReplaceSharedFieldsButKeepTheMembersOwn() throws {
        let first = try RemoteCountdown.decode(serverJSON())
        var local = SharedCountdowns.makeCountdown(from: first, slug: "EPdLHJj9",
                                                   url: URL(string: "https://go.countdowncula.com/c/EPdLHJj9")!)
        local.isPinned = true
        local.extras.voice = .count
        local.milestones[0].celebratedAt = date("2026-10-08T08:00:00Z")

        let edited = try RemoteCountdown.decode(serverJSON(title: "Sonoma, Take Two", updatedAt: "2026-10-09T10:00:00.000Z"))
        XCTAssertTrue(SharedCountdowns.needsUpdate(local, from: edited))
        let updated = SharedCountdowns.apply(edited, to: local)
        XCTAssertEqual(updated.id, local.id)
        XCTAssertEqual(updated.title, "Sonoma, Take Two")
        XCTAssertTrue(updated.isPinned)
        XCTAssertEqual(updated.extras.voice, .count)
        XCTAssertEqual(updated.milestones[0].celebratedAt, date("2026-10-08T08:00:00Z"))
        XCTAssertEqual(updated.extras.subscription?.remoteUpdatedAt, edited.updatedAt)

        XCTAssertFalse(SharedCountdowns.needsUpdate(updated, from: edited), "Nothing new, nothing to write")
        let moreMembers = try RemoteCountdown.decode(serverJSON(title: "Sonoma, Take Two", updatedAt: "2026-10-09T10:00:00.000Z", members: 9))
        XCTAssertTrue(SharedCountdowns.needsUpdate(updated, from: moreMembers), "A new member count is worth saving")
    }

    func testJoinedCountdownsDontUseUpTheFreeLimit() {
        let now = date("2026-10-08T12:00:00Z")
        var countdowns = (0..<SharedConfig.freeActiveLimit).map {
            Countdown(title: "Mine \($0)", details: "", targetDate: now + 86_400)
        }
        XCTAssertFalse(Entitlements.canAdd(to: countdowns, unlocked: false, at: now))

        var joined = Countdown(title: "Wedding", details: "", targetDate: now + 86_400)
        joined.extras.subscription = SharedSubscription(slug: "EPdLHJj9", url: URL(string: "https://go.countdowncula.com/c/EPdLHJj9")!,
                                                         joinedAt: now)
        countdowns.removeLast()
        countdowns.append(joined)
        XCTAssertTrue(Entitlements.canAdd(to: countdowns, unlocked: false, at: now))
    }
}
