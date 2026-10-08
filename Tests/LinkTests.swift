import XCTest

final class LinkTests: XCTestCase {
    private func payloadJSON(_ backdrop: LiveLinkAPI.Backdrop) throws -> [String: Any] {
        var countdown = Countdown(title: "Halloween", details: "Costumes ready.",
                                  targetDate: Date(timeIntervalSince1970: 1_793_494_800),
                                  createdAt: Date(timeIntervalSince1970: 1_790_812_800))
        countdown.style = CountdownStyle(background: .scene(.harvestMoon), font: .serif)
        countdown.milestones = [MilestonePreset.oneWeek.milestone]
        let data = try LiveLinkAPI.Payload(countdown, backdrop: backdrop,
                                             timeZone: TimeZone(identifier: "America/New_York")!).json()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testPayloadMatchesTheServerContract() throws {
        let json = try payloadJSON(.unchanged)
        let body = try XCTUnwrap(json["countdown"] as? [String: Any])
        XCTAssertEqual(body["title"] as? String, "Halloween")
        XCTAssertEqual(body["kind"] as? String, "event")
        XCTAssertEqual(body["timeZone"] as? String, "America/New_York")
        XCTAssertEqual(body["targetDate"] as? String, "2026-11-01T01:00:00Z")
        // The server reads Swift's enum encoding for backgrounds.
        let background = try XCTUnwrap((body["style"] as? [String: Any])?["background"] as? [String: Any])
        XCTAssertEqual((background["scene"] as? [String: Any])?["_0"] as? String, "harvestMoon")
        XCTAssertEqual((body["milestones"] as? [Any])?.count, 1)
        XCTAssertNil(json["photo"], "An unchanged backdrop is left out so the server keeps the current image")
    }

    func testBackdropChangesEncodeAsNullOrBase64() throws {
        XCTAssertTrue(try payloadJSON(.remove)["photo"] is NSNull)
        XCTAssertEqual(try payloadJSON(.set(Data([0xFF, 0xD8, 0xFF])))["photo"] as? String, "/9j/")
    }

    func testLinkSurvivesTheExtrasRoundTrip() throws {
        var extras = CountdownExtras()
        extras.link = PublishedLink(slug: "k7Pq2mXa", url: URL(string: "https://go.countdownula.com/c/k7Pq2mXa")!,
                                    publishedAt: Date(timeIntervalSince1970: 1_791_000_000))
        let decoded = try JSONDecoder().decode(CountdownExtras.self, from: JSONEncoder().encode(extras))
        XCTAssertEqual(decoded.link, extras.link)
        // Extras written before links existed still decode.
        XCTAssertNil(try JSONDecoder().decode(CountdownExtras.self, from: Data(#"{"repeatsYearly":true}"#.utf8)).link)
    }
}

/// Publishes to a running server, then reads the page back. Skipped unless LINK_SERVER is set:
/// `TEST_RUNNER_LINK_SERVER=http://localhost:4300 xcodebuild test -scheme CountdownulaTests …`
final class LiveServerLinkTests: XCTestCase {
    func testPublishAgainstALiveServer() async throws {
        guard let server = ProcessInfo.processInfo.environment["LINK_SERVER"] else {
            throw XCTSkip("Set LINK_SERVER to run against a live server.")
        }
        UserDefaults.standard.set(server, forKey: "linkServer")
        defer { UserDefaults.standard.removeObject(forKey: "linkServer") }

        var countdown = Countdown(title: "Swift contract check", details: "From LinkTests",
                                  targetDate: Date().addingTimeInterval(5 * 86_400 + 600))
        countdown.style = CountdownStyle(background: .gradient(GradientSpec.presets[1].spec), font: .serif,
                                         weight: .black, accent: RGBAColor(hex: 0xFFD166))
        countdown.milestones = [MilestonePreset.halfway.milestone,
                                Milestone(title: "Tickets", emoji: "🎟️", trigger: .date(Date()))]

        let published = try await LiveLinkAPI.publish(countdown, backdrop: .unchanged)
        XCTAssertTrue(published.link.url.absoluteString.hasSuffix("/c/\(published.link.slug)"))

        let (data, _) = try await URLSession.shared.data(from: URL(string: "\(server)/api/countdowns/\(published.link.slug)")!)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let stored = try XCTUnwrap(body["countdown"] as? [String: Any])
        XCTAssertEqual(stored["title"] as? String, "Swift contract check")
        XCTAssertEqual((stored["milestones"] as? [Any])?.count, 2)

        let (page, response) = try await URLSession.shared.data(from: published.link.url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: page, as: UTF8.self).contains("5 days"))

        var delete = URLRequest(url: URL(string: "\(server)/api/countdowns/\(published.link.slug)")!)
        delete.httpMethod = "DELETE"
        delete.setValue("Bearer \(published.ownerToken)", forHTTPHeaderField: "Authorization")
        let (_, deleted) = try await URLSession.shared.data(for: delete)
        XCTAssertEqual((deleted as? HTTPURLResponse)?.statusCode, 204)
    }
}
