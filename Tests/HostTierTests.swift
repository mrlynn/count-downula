import XCTest

final class HostTierTests: XCTestCase {
    func testTheServerSaysWhenACountdownIsHostedAndWhatItsRealSlugIs() throws {
        let json = """
        {"url":"https://go.countdowncula.com/c/sarah-and-tom","memberCount":3,
         "countdown":{"slug":"k7Pq2mXa","title":"Sarah & Tom","details":"","targetDate":"2027-06-12T22:00:00.000Z",
         "createdAt":"2026-10-01T00:00:00.000Z","updatedAt":"2026-10-09T00:00:00.000Z","kind":"event","hasPhoto":false,
         "host":true,"alias":"sarah-and-tom"}}
        """
        let remote = try RemoteCountdown.decode(Data(json.utf8))
        XCTAssertTrue(remote.isHosted)
        XCTAssertEqual(remote.slug, "k7Pq2mXa")
        // Joined through the custom link: the real slug is kept, and the custom link is the one shared.
        let joined = SharedCountdowns.makeCountdown(from: remote, slug: "sarah-and-tom", url: remote.url!)
        XCTAssertEqual(joined.extras.subscription?.slug, "k7Pq2mXa")
        XCTAssertEqual(joined.extras.subscription?.url.absoluteString, "https://go.countdowncula.com/c/sarah-and-tom")
        XCTAssertEqual(joined.extras.subscription?.isHosted, true)
        XCTAssertTrue(Coffin.isHosted(joined))
        XCTAssertEqual(Coffin.maxPhotos(hosted: true), 4)
        XCTAssertEqual(Coffin.maxPhotos(hosted: false), 1)
    }

    func testOlderServersStillDecode() throws {
        let json = """
        {"url":"https://go.countdowncula.com/c/k7Pq2mXa","countdown":{"title":"Trip","details":"","targetDate":"2027-06-12T22:00:00.000Z",
         "createdAt":"2026-10-01T00:00:00.000Z","updatedAt":"2026-10-09T00:00:00.000Z","kind":"event","hasPhoto":false}}
        """
        let remote = try RemoteCountdown.decode(Data(json.utf8))
        XCTAssertFalse(remote.isHosted)
        XCTAssertNil(remote.slug)
        let joined = SharedCountdowns.makeCountdown(from: remote, slug: "k7Pq2mXa", url: remote.url!)
        XCTAssertEqual(joined.extras.subscription?.slug, "k7Pq2mXa")
    }

    func testCoffinNotesReportTheirPhotosEitherWay() throws {
        let decoder = LiveLinkAPI.decoder
        let new = try decoder.decode(Coffin.Contribution.self, from: Data(#"{"id":"a","name":"Ana","text":"","hasPhoto":true,"photoCount":3,"hasVideo":true,"createdAt":"2026-10-09T00:00:00.000Z","mine":false}"#.utf8))
        XCTAssertEqual(new.photos, 3)
        XCTAssertEqual(new.hasVideo, true)
        let old = try decoder.decode(Coffin.Contribution.self, from: Data(#"{"id":"b","name":"Ben","text":"hi","hasPhoto":true,"createdAt":"2026-10-09T00:00:00.000Z","mine":true}"#.utf8))
        XCTAssertEqual(old.photos, 1, "Older servers only say whether there's a photo")
    }

    func testQueriesStayQueries() {
        let url = LiveLinkAPI.endpoint("api/countdowns/k7Pq2mXa/coffin/abc/photo?i=2")
        XCTAssertEqual(url.query(), "i=2")
        XCTAssertTrue(url.path().hasSuffix("/api/countdowns/k7Pq2mXa/coffin/abc/photo"))
        XCTAssertTrue(LiveLinkAPI.endpoint("api/countdowns").path().hasSuffix("/api/countdowns"))
    }
}
