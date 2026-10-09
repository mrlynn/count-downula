import Foundation

/// The sealed coffin: notes and photos people drop into a shared countdown. The server keeps them
/// sealed until zero; before then the app only ever sees a count and the person's own.
enum Coffin {
    struct State: Decodable, Equatable {
        var opensAt: Date
        var open: Bool
        var sealedCount: Int
        /// "owner" or "member"; nil when this device isn't in the countdown.
        var role: String?
        var contributions: [Contribution]

        var isOwner: Bool { role == "owner" }
    }

    struct Contribution: Decodable, Identifiable, Equatable {
        var id: String
        var name: String
        var text: String
        var hasPhoto: Bool
        /// How many photos; older servers only say whether there's one.
        var photoCount: Int?
        var hasVideo: Bool?
        var createdAt: Date
        var mine: Bool

        var photos: Int { photoCount ?? (hasPhoto ? 1 : 0) }
    }

    static let maxName = 40
    static let maxText = 500
    /// Photos per note: one, or more on a hosted countdown, which can also carry a short video.
    static func maxPhotos(hosted: Bool) -> Int { hosted ? 4 : 1 }
    static let maxVideoBytes = 4_300_000
    static let maxVideoSeconds: Double = 15

    /// A Host Pass is applied to this countdown, as far as this device knows.
    static func isHosted(_ countdown: Countdown) -> Bool {
        countdown.extras.link?.isHosted == true || countdown.extras.subscription?.isHosted == true
    }

    /// The slug and key this device uses for a countdown's coffin: the owner's for one you
    /// published, the member's for one you joined. Count-ups have no coffin, and neither do public
    /// crypt countdowns (thousands of strangers, no owner to moderate).
    static func access(for countdown: Countdown) -> (slug: String, token: String)? {
        guard countdown.extras.subscription?.isPublic != true else { return nil }
        return sharedAccess(for: countdown)
    }

    /// The slug and owner or member key for any shared countdown, public ones included.
    static func sharedAccess(for countdown: Countdown) -> (slug: String, token: String)? {
        // Count-ups have no coffin, except a countdown kept counting up after its zero.
        guard !countdown.countsUp || countdown.extras.keptCountingAt != nil else { return nil }
        if let link = countdown.extras.link, let token = OwnerTokens.token(for: countdown.id) {
            return (link.slug, token)
        }
        if let subscription = countdown.extras.subscription, let token = MemberTokens.token(for: countdown.id) {
            return (subscription.slug, token)
        }
        return nil
    }
}

extension LiveLinkAPI {
    static func coffin(slug: String, token: String) async throws -> Coffin.State {
        let (data, status) = try await raw("GET", path: "api/countdowns/\(slug)/coffin", token: token, body: nil)
        if status == 404 { throw NotShared() }
        try check(status, data)
        return try decoder.decode(Coffin.State.self, from: data)
    }

    @discardableResult
    static func addToCoffin(slug: String, token: String, name: String, text: String, photos: [Data]) async throws -> Coffin.Contribution {
        var body: [String: Any] = ["name": name, "text": text]
        // One photo goes up the way older servers expect it.
        if photos.count == 1 { body["photo"] = photos[0].base64EncodedString() }
        if photos.count > 1 { body["photos"] = photos.map { $0.base64EncodedString() } }
        let (data, status) = try await raw("POST", path: "api/countdowns/\(slug)/coffin", token: token,
                                           body: try JSONSerialization.data(withJSONObject: body))
        try check(status, data)
        return try decoder.decode(Coffin.Contribution.self, from: data)
    }

    static func removeFromCoffin(slug: String, token: String, id: String) async throws {
        let (data, status) = try await raw("DELETE", path: "api/countdowns/\(slug)/coffin/\(id)", token: token, body: nil)
        try check(status, data)
    }

    static func reportInCoffin(slug: String, token: String, id: String) async throws {
        let (data, status) = try await raw("POST", path: "api/countdowns/\(slug)/coffin/\(id)/report", token: token, body: nil)
        try check(status, data)
    }

    static func coffinPhoto(slug: String, token: String, id: String, index: Int = 0) async throws -> Data? {
        let (data, status) = try await raw("GET", path: "api/countdowns/\(slug)/coffin/\(id)/photo?i=\(index)", token: token, body: nil)
        return status == 200 && !data.isEmpty ? data : nil
    }

    /// Adds a short video (MP4, under `Coffin.maxVideoBytes`) to your own note on a hosted countdown.
    static func addCoffinVideo(slug: String, token: String, id: String, video: Data) async throws {
        let (data, status) = try await upload("POST", path: "api/countdowns/\(slug)/coffin/\(id)/video", token: token,
                                              body: video, contentType: "video/mp4")
        try check(status, data)
    }

    static func coffinVideo(slug: String, token: String, id: String) async throws -> Data? {
        let (data, status) = try await raw("GET", path: "api/countdowns/\(slug)/coffin/\(id)/video", token: token, body: nil)
        return status == 200 && !data.isEmpty ? data : nil
    }
}
