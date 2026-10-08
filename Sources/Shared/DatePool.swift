import Foundation

// The pool's model lives with the other extras in CountdownExtras.swift; this is its server side.

extension DatePool {
    /// The pool and its guesses, as `GET /api/countdowns/<slug>/pool` returns them.
    struct State: Decodable, Equatable {
        var closed: Bool
        var answer: Date?
        var isOwner: Bool
        var guesses: [Guess]

        var mine: Guess? { guesses.first(where: \.mine) }
        var winners: [Guess] { guesses.filter { $0.place == 1 } }
    }

    struct Guess: Decodable, Identifiable, Equatable {
        var id: String
        var name: String
        var guess: Date
        var mine: Bool
        /// Once settled: how far off, and the place (ties share one).
        var offBySeconds: Int?
        var place: Int?
    }

    static let maxName = 40

    /// "off by 2d 4h", or "spot on" within a minute.
    static func offBy(_ seconds: Int) -> String {
        if seconds < 60 { return "spot on" }
        let days = seconds / 86_400, hours = seconds % 86_400 / 3_600, minutes = seconds % 3_600 / 60
        if days > 0 { return "off by \(days)d \(hours)h" }
        if hours > 0 { return "off by \(hours)h \(minutes)m" }
        return "off by \(minutes)m"
    }

    /// The slug and key to guess with: the owner's or member's, so a guess follows the person
    /// across their devices. Only pools on a shared countdown.
    static func access(for countdown: Countdown) -> (slug: String, token: String)? {
        guard countdown.extras.pool != nil else { return nil }
        return Coffin.sharedAccess(for: countdown)
    }
}

extension LiveLinkAPI {
    static func pool(slug: String, token: String) async throws -> DatePool.State {
        let (data, status) = try await raw("GET", path: "api/countdowns/\(slug)/pool", token: token, body: nil)
        if status == 404 { throw NotShared() }
        try check(status, data)
        return try decoder.decode(DatePool.State.self, from: data)
    }

    static func guess(slug: String, token: String, name: String, date: Date) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["name": name, "guess": ISO8601DateFormatter().string(from: date)])
        let (data, status) = try await raw("POST", path: "api/countdowns/\(slug)/pool/guesses", token: token, body: body)
        try check(status, data)
    }

    static func removeGuess(slug: String, token: String, id: String) async throws {
        let (data, status) = try await raw("DELETE", path: "api/countdowns/\(slug)/pool/guesses/\(id)", token: token, body: nil)
        try check(status, data)
    }

    enum PoolAction { case close, reopen, settle(Date) }

    /// Owner only. Settling also moves the countdown to the real date on the server.
    static func poolAction(_ action: PoolAction, slug: String, token: String) async throws -> DatePool.State {
        var body: [String: Any]
        switch action {
        case .close: body = ["action": "close"]
        case .reopen: body = ["action": "reopen"]
        case let .settle(date): body = ["action": "settle", "answer": ISO8601DateFormatter().string(from: date)]
        }
        let (data, status) = try await raw("PUT", path: "api/countdowns/\(slug)/pool", token: token,
                                           body: try JSONSerialization.data(withJSONObject: body))
        try check(status, data)
        return try decoder.decode(DatePool.State.self, from: data)
    }
}
