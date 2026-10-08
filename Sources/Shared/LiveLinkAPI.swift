import Foundation
import Security

/// Talks to the Count Downula server (server/ in this repo), which hosts a countdown's public page
/// and its live link preview. Private countdowns never leave iCloud; only published ones get here.
enum LiveLinkAPI {
    /// `-linkServer http://localhost:4300` on the command line points debug builds at a local server.
    static var baseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "linkServer"), let url = URL(string: override) {
            return url
        }
        return URL(string: "https://go.countdownula.com")!
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
            case .unreachable: "Couldn't reach Count Downula. Check your connection and try again."
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
            throw Failure.server(message ?? "Count Downula's server returned an error (\(status)).")
        }
    }
}

/// Owner tokens for published countdowns, in the iCloud Keychain so your other devices can edit too.
enum OwnerTokens {
    private static let service = "com.countdownula.link-owner"

    private static func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString,
         kSecAttrSynchronizable as String: kCFBooleanTrue!]
    }

    static func save(_ token: String, for id: UUID) {
        SecItemDelete(query(id) as CFDictionary)
        var item = query(id)
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func token(for id: UUID) -> String? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(for id: UUID) {
        SecItemDelete(query(id) as CFDictionary)
    }
}
