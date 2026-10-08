import Foundation
import Security

/// Talks to the Count Downcula server (server/ in this repo), which hosts a countdown's public page
/// and its live link preview. Private countdowns never leave iCloud; only published ones get here.
enum LiveLinkAPI {
    /// `-linkServer http://localhost:4300` on the command line points debug builds at a local server.
    static var baseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "linkServer"), let url = URL(string: override) {
            return url
        }
        return URL(string: "https://go.countdowncula.com")!
    }

    enum Backdrop: Equatable {
        case unchanged
        case remove
        /// JPEG, at most 1080px and 400 KB: the photo, or a rendered scene so the page matches the app.
        case set(Data)
    }

    enum Failure: LocalizedError {
        case server(String)
        case notOwner
        case unreachable

        var errorDescription: String? {
            switch self {
            case let .server(message): message
            case .notOwner: "Only the device that published this link, or one signed in to the same iCloud Keychain, can change it."
            case .unreachable: "Couldn't reach Count Downcula. Check your connection and try again."
            }
        }
    }

    struct Published {
        let link: PublishedLink
        let ownerToken: String
    }

    // MARK: - Requests

    /// Request body for publish and update. Dates go out as ISO 8601; style and milestones keep the
    /// app's own JSON shape so the server can store them as is.
    struct Payload: Encodable {
        let countdown: Body
        let backdrop: Backdrop

        struct Body: Encodable {
            let title: String
            let details: String
            let targetDate: Date
            let createdAt: Date
            let kind: Countdown.Kind
            let timeZone: String
            let style: CountdownStyle
            let milestones: [Milestone]
        }

        init(_ countdown: Countdown, backdrop: Backdrop, timeZone: TimeZone = .current) {
            self.countdown = Body(title: countdown.title, details: countdown.details, targetDate: countdown.targetDate,
                                  createdAt: countdown.createdAt, kind: countdown.kind, timeZone: timeZone.identifier,
                                  style: countdown.style, milestones: countdown.milestones)
            self.backdrop = backdrop
        }

        private enum CodingKeys: String, CodingKey { case countdown, photo }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(countdown, forKey: .countdown)
            switch backdrop {
            case .unchanged: break  // left out: the server keeps the current image
            case .remove: try c.encodeNil(forKey: .photo)
            case let .set(jpeg): try c.encode(jpeg.base64EncodedString(), forKey: .photo)
            }
        }

        func json() throws -> Data {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(self)
        }
    }

    private struct Response: Decodable {
        let slug: String
        let url: URL
        let ownerToken: String?
    }

    private struct ErrorBody: Decodable { let error: String }

    static func publish(_ countdown: Countdown, backdrop: Backdrop) async throws -> Published {
        let response = try await send("POST", path: "api/countdowns", body: Payload(countdown, backdrop: backdrop).json())
        guard let token = response.ownerToken else { throw Failure.server("The server didn't return an owner token.") }
        return Published(link: PublishedLink(slug: response.slug, url: response.url, publishedAt: Date()), ownerToken: token)
    }

    static func update(_ countdown: Countdown, slug: String, backdrop: Backdrop) async throws {
        guard let token = OwnerTokens.token(for: countdown.id) else { throw Failure.notOwner }
        _ = try await send("PUT", path: "api/countdowns/\(slug)", token: token,
                           body: Payload(countdown, backdrop: backdrop).json())
    }

    static func unpublish(_ countdown: Countdown, slug: String) async throws {
        guard let token = OwnerTokens.token(for: countdown.id) else { throw Failure.notOwner }
        try await send("DELETE", path: "api/countdowns/\(slug)", token: token, body: nil)
        OwnerTokens.remove(for: countdown.id)
    }

    // MARK: - Shared countdowns

    struct NotShared: LocalizedError {
        var errorDescription: String? { "This countdown isn't shared anymore. The link may have been turned off." }
    }

    /// The owner's current copy. Throws `NotShared` once the owner stops sharing.
    static func fetch(slug: String) async throws -> RemoteCountdown {
        let (data, status) = try await raw("GET", path: "api/countdowns/\(slug)", body: nil)
        if status == 404 { throw NotShared() }
        try check(status, data)
        return try RemoteCountdown.decode(data)
    }

    /// The backdrop image (photo or rendered scene) for a shared countdown.
    static func photo(slug: String) async throws -> Data? {
        let (data, status) = try await raw("GET", path: "c/\(slug)/photo", body: nil)
        return status == 200 && !data.isEmpty ? data : nil
    }

    private struct Joined: Decodable {
        let memberToken: String
        let memberCount: Int
    }

    /// Counts you in. The member key only lets your devices take you back out.
    static func join(slug: String) async throws -> (memberToken: String, memberCount: Int) {
        let (data, status) = try await raw("POST", path: "api/countdowns/\(slug)/members", body: nil)
        if status == 404 { throw NotShared() }
        try check(status, data)
        let joined = try JSONDecoder().decode(Joined.self, from: data)
        return (joined.memberToken, joined.memberCount)
    }

    /// Tells the server where to send a silent push when the owner edits. Debug builds get their
    /// device tokens from Apple's sandbox, release builds from production.
    static func registerPush(slug: String, memberToken: String, deviceToken: String, sandbox: Bool) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["pushToken": deviceToken, "sandbox": sandbox])
        let (data, status) = try await raw("PUT", path: "api/countdowns/\(slug)/members", token: memberToken, body: body)
        if status == 404 { throw NotShared() }
        try check(status, data)
    }

    /// Registers this phone for a shared countdown's synchronized zero: its push-to-start token and,
    /// once one is running, its Live Activity's update token. `token` is the owner's or member's key.
    static func registerLive(slug: String, token: String, deviceID: String, countdownID: UUID, startToken: String?,
                             activityToken: String?, sandbox: Bool) async throws {
        var body: [String: Any] = ["deviceID": deviceID, "countdownID": countdownID.uuidString, "sandbox": sandbox]
        if let startToken { body["startToken"] = startToken }
        if let activityToken { body["activityToken"] = activityToken }
        let (data, status) = try await raw("PUT", path: "api/countdowns/\(slug)/live", token: token,
                                           body: try JSONSerialization.data(withJSONObject: body))
        try check(status, data)
    }

    /// The countdown's Apple Wallet pass (.pkpass).
    static func walletPass(slug: String) async throws -> Data {
        let (data, status) = try await raw("GET", path: "c/\(slug)/pass", body: nil)
        if status == 503 { throw Failure.server("Apple Wallet passes aren't available yet.") }
        if status == 404 { throw NotShared() }
        try check(status, data)
        return data
    }

    static func leave(slug: String, memberToken: String) async throws {
        let (data, status) = try await raw("DELETE", path: "api/countdowns/\(slug)/members", token: memberToken, body: nil)
        if status == 404 { return }
        try check(status, data)
    }

    // MARK: - Transport

    static func raw(_ method: String, path: String, token: String? = nil, body: Data?) async throws -> (Data, Int) {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 30
        // Members should see the owner's edit as soon as it lands, not a cached copy.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = body
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw Failure.unreachable
        }
    }

    static func check(_ status: Int, _ data: Data) throws {
        guard !(200..<300).contains(status) else { return }
        let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
        throw Failure.server(message ?? "Count Downcula's server returned an error (\(status)).")
    }

    @discardableResult
    private static func send(_ method: String, path: String, token: String? = nil, body: Data?) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            if status == 204 || data.isEmpty { return Response(slug: "", url: baseURL, ownerToken: nil) }
            return try JSONDecoder().decode(Response.self, from: data)
        case 404 where method == "DELETE":
            // Already gone; treat unpublishing as done.
            return Response(slug: "", url: baseURL, ownerToken: nil)
        case 403:
            throw Failure.notOwner
        default:
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw Failure.server(message ?? "Count Downcula's server returned an error (\(status)).")
        }
    }
}

/// Owner tokens for published countdowns, in the iCloud Keychain so your other devices can edit too.
enum OwnerTokens {
    private static let keychain = SyncedTokens(service: "com.countdownula.link-owner")

    static func save(_ token: String, for id: UUID) { keychain.save(token, for: id) }
    static func token(for id: UUID) -> String? { keychain.token(for: id) }
    static func remove(for id: UUID) { keychain.remove(for: id) }
}

/// Member keys for shared countdowns you joined, synced the same way so any of your devices can leave.
enum MemberTokens {
    private static let keychain = SyncedTokens(service: "com.countdownula.link-member")

    static func save(_ token: String, for id: UUID) { keychain.save(token, for: id) }
    static func token(for id: UUID) -> String? { keychain.token(for: id) }
    static func remove(for id: UUID) { keychain.remove(for: id) }
}

/// Small secrets in the iCloud Keychain, one per countdown.
struct SyncedTokens {
    let service: String

    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString,
         kSecAttrSynchronizable as String: kCFBooleanTrue!]
    }

    func save(_ token: String, for id: UUID) {
        SecItemDelete(query(id) as CFDictionary)
        var item = query(id)
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    func token(for id: UUID) -> String? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func remove(for id: UUID) {
        SecItemDelete(query(id) as CFDictionary)
    }
}
