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

    // MARK: - App Clip handoff

    func testTheClipsKeptCountdownsWaitForTheAppOnce() {
        for slug in ClipHandoff.pending { ClipHandoff.done(slug) }
        ClipHandoff.keep("EPdLHJj9")
        ClipHandoff.keep("EPdLHJj9")
        ClipHandoff.keep("cb4TV7jV")
        XCTAssertEqual(ClipHandoff.pending, ["EPdLHJj9", "cb4TV7jV"], "Keeping twice doesn't join twice")
        ClipHandoff.done("EPdLHJj9")
        XCTAssertEqual(ClipHandoff.pending, ["cb4TV7jV"])
        ClipHandoff.done("cb4TV7jV")
        XCTAssertTrue(ClipHandoff.pending.isEmpty)
    }

    // MARK: - Sealed coffin

    func testDecodesTheCoffinAsTheServerSendsIt() throws {
        let json = Data("""
        {"opensAt":"2026-11-14T21:00:00.000Z","open":false,"sealedCount":12,"role":"member",
         "contributions":[{"id":"6ac787134a26e3f94eb81a22","name":"Priya","text":"Happy birthday!",
                           "hasPhoto":true,"createdAt":"2026-10-08T12:06:00.512Z","mine":true}]}
        """.utf8)
        let state = try LiveLinkAPI.decoder.decode(Coffin.State.self, from: json)
        XCTAssertEqual(state.sealedCount, 12)
        XCTAssertFalse(state.open)
        XCTAssertFalse(state.isOwner)
        XCTAssertEqual(state.opensAt, date("2026-11-14T21:00:00Z"))
        XCTAssertEqual(state.contributions.first?.name, "Priya")
        XCTAssertTrue(state.contributions.first?.mine == true)
    }

    func testCountUpsAndPrivateCountdownsHaveNoCoffin() {
        var countUp = Countdown(title: "Sober", details: "", targetDate: date("2026-01-01T00:00:00Z"), kind: .countUp)
        countUp.extras.subscription = SharedSubscription(slug: "EPdLHJj9", url: URL(string: "https://go.countdowncula.com/c/EPdLHJj9")!,
                                                          joinedAt: Date())
        XCTAssertNil(Coffin.access(for: countUp))
        XCTAssertNil(Coffin.access(for: Countdown(title: "Mine", details: "", targetDate: Date())), "Not shared")
    }

    // MARK: - Crypt

    func testAFloatingCryptTimeIsMidnightOnThisDevicesClock() throws {
        let json = Data("""
        {"url":"https://go.countdowncula.com/c/new-year-2027","memberCount":120,
         "countdown":{"slug":"new-year-2027","title":"New Year 2027","details":"",
          "targetDate":"2027-01-01T00:00:00.000Z","createdAt":"2026-10-07T00:00:00.000Z",
          "updatedAt":"2026-10-08T00:00:00.000Z","kind":"event","timeZone":"UTC",
          "style":{"background":{"scene":{"_0":"confetti"}},"font":"serif","weight":"bold"},
          "hasPhoto":false,"floating":"2027-01-01T00:00:00","isPublic":true}}
        """.utf8)
        let remote = try RemoteCountdown.decode(json)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: remote.targetDate)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute], [2027, 1, 1, 0, 0])
        XCTAssertTrue(remote.isPublic)

        let countdown = SharedCountdowns.makeCountdown(from: remote, slug: "new-year-2027",
                                                       url: URL(string: "https://go.countdowncula.com/c/new-year-2027")!,
                                                       now: date("2026-10-08T12:00:00Z"))
        XCTAssertEqual(countdown.extras.subscription?.isPublic, true)
        XCTAssertNil(Coffin.access(for: countdown), "Public countdowns have no coffin")
    }

    // MARK: - Date pools

    func testAPoolComesWithTheCopyAndTheSwitchGoesOutWithEveryEdit() throws {
        let json = Data("""
        {"url":"https://go.countdowncula.com/c/Y9YST58b","memberCount":2,
         "countdown":{"slug":"Y9YST58b","title":"Baby Lynn","details":"",
          "targetDate":"2026-11-30T12:00:00.000Z","createdAt":"2026-10-01T00:00:00.000Z",
          "updatedAt":"2026-10-08T00:00:00.000Z","kind":"event","timeZone":"America/New_York",
          "style":{"background":{"scene":{"_0":"baby"}},"font":"rounded","weight":"bold"},
          "hasPhoto":false,"pool":{"closed":true,"answer":"2026-11-28T04:12:00.000Z"}}}
        """.utf8)
        let remote = try RemoteCountdown.decode(json)
        XCTAssertEqual(remote.pool, DatePool(closed: true, answer: date("2026-11-28T04:12:00Z")))
        let joined = SharedCountdowns.makeCountdown(from: remote, slug: "Y9YST58b",
                                                    url: URL(string: "https://go.countdowncula.com/c/Y9YST58b")!)
        XCTAssertEqual(joined.extras.pool?.isSettled, true)

        var mine = Countdown(title: "Ship date", details: "", targetDate: date("2027-03-01T00:00:00Z"))
        let off = try JSONSerialization.jsonObject(with: LiveLinkAPI.Payload(mine, backdrop: .unchanged).json()) as! [String: Any]
        XCTAssertEqual((off["countdown"] as! [String: Any])["pool"] as? Bool, false, "Sent even when off, so turning it off reaches the server")
        mine.extras.pool = DatePool()
        let on = try JSONSerialization.jsonObject(with: LiveLinkAPI.Payload(mine, backdrop: .unchanged).json()) as! [String: Any]
        XCTAssertEqual((on["countdown"] as! [String: Any])["pool"] as? Bool, true)
    }

    func testOffByReadsLikeAPerson() {
        XCTAssertEqual(DatePool.offBy(20), "spot on")
        XCTAssertEqual(DatePool.offBy(25 * 60), "off by 25m")
        XCTAssertEqual(DatePool.offBy(3 * 3_600 + 120), "off by 3h 2m")
        XCTAssertEqual(DatePool.offBy(2 * 86_400 + 4 * 3_600), "off by 2d 4h")
    }
}
