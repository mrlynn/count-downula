import SwiftUI
import XCTest

final class StyleTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// A widget snapshot written by 1.1, before styles existed.
    func testOldSnapshotDecodesWithDefaultStyle() throws {
        let json = """
        [{"createdAt":"2026-01-01T00:00:00Z","details":"","hasImage":false,"hasNotified":false,
          "id":"6F1C2A3B-4D5E-4F60-8A7B-9C0D1E2F3A4B","isPinned":true,"kind":"event",
          "targetDate":"2026-12-25T08:00:00Z","title":"Christmas","updatedAt":"2026-01-01T00:00:00Z"}]
        """
        let countdowns = try decoder().decode([Countdown].self, from: Data(json.utf8))
        XCTAssertEqual(countdowns.first?.title, "Christmas")
        XCTAssertEqual(countdowns.first?.style, .default)
        XCTAssertEqual(countdowns.first?.isPinned, true)
    }

    func testStyleRoundTripsThroughJSON() throws {
        var countdown = Countdown(title: "Trip", details: "", targetDate: Date(timeIntervalSince1970: 2_000_000_000))
        countdown.style = CountdownStyle(background: .scene(.aurora), font: .serif, weight: .heavy,
                                         textColor: RGBAColor(hex: 0x111111), accent: RGBAColor(hex: 0x00FF00))
        let data = try encoder().encode([countdown])
        let decoded = try decoder().decode([Countdown].self, from: data)
        XCTAssertEqual(decoded.first?.style, countdown.style)
    }

    /// A background case added by a future build must not make the whole countdown disappear.
    func testUnknownBackgroundFallsBackToDefault() throws {
        let json = """
        [{"details":"","id":"6F1C2A3B-4D5E-4F60-8A7B-9C0D1E2F3A4B","kind":"event",
          "targetDate":"2026-12-25T08:00:00Z","title":"Future",
          "style":{"background":{"hologram":{}},"font":"rounded","weight":"bold"}}]
        """
        let countdowns = try decoder().decode([Countdown].self, from: Data(json.utf8))
        XCTAssertEqual(countdowns.first?.title, "Future")
        XCTAssertEqual(countdowns.first?.style, .default)
    }

    func testRecordStoresOnlyNonDefaultStyles() {
        let record = CountdownRecord()
        var countdown = Countdown(title: "Plain", details: "", targetDate: Date())
        record.apply(countdown)
        XCTAssertNil(record.styleData)

        countdown.style.background = .gradient(GradientSpec.presets[2].spec)
        record.apply(countdown)
        XCTAssertNotNil(record.styleData)
        XCTAssertEqual(record.countdown.style, countdown.style)

        countdown.style = .default
        record.apply(countdown)
        XCTAssertNil(record.styleData)
    }

    func testRecordKeepsStyleItCannotRead() {
        let record = CountdownRecord()
        let future = Data(#"{"background":{"hologram":{}}}"#.utf8)
        record.styleData = future
        record.apply(Countdown(title: "Edited on an older build", details: "", targetDate: Date()))
        XCTAssertEqual(record.styleData, future)
    }

    func testColorPickerRoundTrip() {
        let original = RGBAColor(hex: 0x3A7BD5)
        let captured = RGBAColor(original.color)
        XCTAssertEqual(captured.red, original.red, accuracy: 0.01)
        XCTAssertEqual(captured.green, original.green, accuracy: 0.01)
        XCTAssertEqual(captured.blue, original.blue, accuracy: 0.01)
    }

    func testScrimFollowsTextColor() {
        XCTAssertTrue(CountdownStyle.default.hasLightText)
        var style = CountdownStyle.default
        style.textColor = RGBAColor(hex: 0x1C1C1E)
        XCTAssertFalse(style.hasLightText)
    }

    func testSeededRandomIsDeterministic() {
        var a = SeededRandom(seed: 42)
        var b = SeededRandom(seed: 42)
        for _ in 0..<100 { XCTAssertEqual(a.next(), b.next()) }
    }
}
