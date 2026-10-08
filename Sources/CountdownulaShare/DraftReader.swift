import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads a draft out of shared text: Apple's on-device language model where the device has one
/// (iOS 26+ with Apple Intelligence), plain date detection otherwise. The model's answer is checked
/// against the heuristic, which also fills anything the model left out.
enum DraftReader {
    static func read(_ text: String, now: Date = Date()) async -> (draft: CountdownDraft, usedModel: Bool) {
        let fallback = DraftExtractor.draft(from: text, now: now)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable, !text.isEmpty {
            if let draft = try? await modelDraft(text, fallback: fallback, now: now) { return (draft, true) }
        }
        #endif
        return (fallback, false)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @Generable
    struct Extracted {
        @Guide(description: "A short name for the event, like 'Flight to Lisbon' or 'Maya & Theo's Wedding'. Under 50 characters, no booking codes.")
        var title: String
        @Guide(description: "When it starts, as ISO 8601 with time and offset if known, like 2026-11-20T19:45:00-05:00, or just 2026-11-20. Empty if there's no date.")
        var start: String
        @Guide(description: "The venue, city or address, if there is one. Empty otherwise.")
        var place: String
    }

    @available(iOS 26.0, *)
    private static func modelDraft(_ text: String, fallback: CountdownDraft, now: Date) async throws -> CountdownDraft {
        let session = LanguageModelSession(instructions: """
            You read tickets, invitations, booking confirmations and screenshots, and pull out the one \
            upcoming event they're about. Today is \(now.formatted(.iso8601.year().month().day())).
            """)
        let extracted = try await session.respond(to: text, generating: Extracted.self).content
        let title = extracted.title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Date detection reads the time as printed, on the person's clock. The model sometimes adds
        // an offset for the venue's city (a Berkeley show at 7 pm turned into 10 pm in New York), so
        // its date is only used when detection finds none, and read as wall-clock time.
        let parsed = parseDate(extracted.start).flatMap { $0 > now ? $0 : nil }
        return CountdownDraft(
            title: title.isEmpty ? fallback.title : String(title.prefix(60)),
            date: fallback.date ?? parsed,
            place: extracted.place.isEmpty ? fallback.place : extracted.place,
            scene: DraftExtractor.scene(for: "\(title) \(text)")
        )
    }
    #endif

    /// Reads the model's date as wall-clock time on this device, dropping any offset it added.
    static func parseDate(_ text: String) -> Date? {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if let offset = trimmed.range(of: #"(Z|[+-]\d{2}:?\d{2})$"#, options: .regularExpression), trimmed.contains("T") {
            trimmed.removeSubrange(offset)
        }
        let dayOnly = DateFormatter()
        dayOnly.locale = Locale(identifier: "en_US_POSIX")
        dayOnly.dateFormat = "yyyy-MM-dd"
        if let day = dayOnly.date(from: trimmed) {
            return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day)
        }
        let localTime = DateFormatter()
        localTime.locale = Locale(identifier: "en_US_POSIX")
        localTime.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return localTime.date(from: trimmed)
    }
}
