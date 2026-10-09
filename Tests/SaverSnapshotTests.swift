import XCTest

final class SaverSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func countdown(_ title: String, in seconds: TimeInterval, pinned: Bool = false, kind: Countdown.Kind = .event) -> Countdown {
        Countdown(title: title, details: "", targetDate: now + seconds, kind: kind, isPinned: pinned, createdAt: now - 86_400)
    }

    func testPinnedCountdownsRotateSoonestFirstThenCountUps() {
        let all = [
            countdown("Later", in: 9_000, pinned: true),
            countdown("Sober", in: -90_000, pinned: true, kind: .countUp),
            countdown("Soon", in: 3_000, pinned: true),
            countdown("Unpinned", in: 100),
            countdown("Done", in: -100, pinned: true),
        ]
        XCTAssertEqual(SaverSnapshot.rotation(all, at: now).map(\.title), ["Soon", "Later", "Sober"])
    }

    func testWithNothingPinnedItShowsNextUp() {
        let all = [countdown("B", in: 9_000), countdown("A", in: 3_000)]
        XCTAssertEqual(SaverSnapshot.rotation(all, at: now).map(\.title), ["A"])
        XCTAssertNil(SaverSnapshot.showing([], at: now))
    }

    func testOneAboutToHitZeroHoldsTheScreen() {
        let all = [countdown("Later", in: 9_000, pinned: true), countdown("Launch", in: 45, pinned: true)]
        for step in 0..<4 {
            XCTAssertEqual(SaverSnapshot.showing(all, at: now + Double(step) * 10)?.title, "Launch")
        }
    }

    func testRotationStepsEveryInterval() {
        let all = [countdown("A", in: 9_000, pinned: true), countdown("B", in: 19_000, pinned: true)]
        let first = SaverSnapshot.showing(all, at: now, interval: 30)?.title
        let next = SaverSnapshot.showing(all, at: now + 30, interval: 30)?.title
        XCTAssertNotEqual(first, next)
    }

    func testMirrorCopiesChangesAndRemovesWhatsGone() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: UUID().uuidString)
        let source = root.appending(path: "source"), destination = root.appending(path: "dest")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("[1]".utf8).write(to: source.appending(path: "countdowns.json"))
        try Data("jpg".utf8).write(to: source.appending(path: "A.jpg"))
        XCTAssertTrue(SaverSnapshot.mirror(from: source, to: destination, requireHost: false))
        XCTAssertEqual(try Data(contentsOf: destination.appending(path: "A.jpg")), Data("jpg".utf8))

        try fm.removeItem(at: source.appending(path: "A.jpg"))
        try Data("[2]".utf8).write(to: source.appending(path: "countdowns.json"))
        SaverSnapshot.mirror(from: source, to: destination, requireHost: false)
        XCTAssertFalse(fm.fileExists(atPath: destination.appending(path: "A.jpg").path))
        XCTAssertEqual(try Data(contentsOf: destination.appending(path: "countdowns.json")), Data("[2]".utf8))
        try? fm.removeItem(at: root)
    }

    func testMirrorWaitsForTheHostToExist() {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString)/Data/Library/Application Support/Count Downcula")
        XCTAssertFalse(SaverSnapshot.mirror(from: FileManager.default.temporaryDirectory, to: missing))
    }

    func testExportPathIsTheHostsContainer() {
        let path = SaverSnapshot.exportDirectory(home: URL(fileURLWithPath: "/Users/sam")).path
        XCTAssertEqual(path, "/Users/sam/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support/Count Downcula")
    }
}
