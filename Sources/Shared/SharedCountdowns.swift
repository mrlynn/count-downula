import Foundation

/// Joining someone else's shared countdown, and keeping your copy in step with theirs.
/// A joined countdown is an ordinary local countdown with `extras.subscription` set, so widgets,
/// complications, Live Activities and the Mac menu bar all work with it unchanged.
enum SharedCountdowns {
    /// How often a device checks the owner's copy. Opening the app checks right away regardless.
    static let refreshInterval: TimeInterval = 15 * 60

    /// The slug in a shared link, a `countdownula://join/<slug>` link, or a bare slug someone pasted.
    static func slug(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: String
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "https", "http":
                let parts = url.pathComponents.filter { $0 != "/" }
                guard parts.count >= 2, parts[0] == "c" else { return nil }
                candidate = parts[1]
            case "countdownula":
                guard url.host() == "join" else { return nil }
                candidate = url.lastPathComponent
            default:
                return nil
            }
        } else {
            candidate = trimmed
        }
        // Same rule as the server's isSlug.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        guard (4...40).contains(candidate.count),
              candidate.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return candidate
    }

    /// A fresh local countdown for a shared one you just joined.
    static func makeCountdown(from remote: RemoteCountdown, slug: String, url: URL, now: Date = Date()) -> Countdown {
        var countdown = Countdown(title: remote.title, details: remote.details, targetDate: remote.targetDate)
        countdown.extras.subscription = SharedSubscription(slug: slug, url: url, joinedAt: now,
                                                           remoteUpdatedAt: nil, memberCount: remote.memberCount)
        return apply(remote, to: countdown)
    }

    /// Takes the owner's shared fields and keeps the member's own: pin, alerts voice, and which
    /// milestones already got their celebration on this person's devices.
    static func apply(_ remote: RemoteCountdown, to local: Countdown) -> Countdown {
        var countdown = local
        countdown.title = remote.title
        countdown.details = remote.details
        countdown.kind = remote.kind
        countdown.targetDate = remote.targetDate
        countdown.createdAt = remote.createdAt
        countdown.style = remote.style
        let celebrated = Dictionary(local.milestones.map { ($0.id, $0.celebratedAt) }, uniquingKeysWith: { a, _ in a })
        countdown.milestones = remote.milestones.map { milestone in
            var milestone = milestone
            milestone.celebratedAt = celebrated[milestone.id] ?? nil
            return milestone
        }
        if countdown.targetDate != local.targetDate { countdown.hasNotified = false }
        countdown.extras.subscription?.remoteUpdatedAt = remote.updatedAt
        countdown.extras.subscription?.memberCount = remote.memberCount
        countdown.extras.subscription?.isPublic = remote.isPublic ? true : nil
        countdown.extras.pool = remote.pool
        return countdown
    }

    /// Pulls the owner's latest copy of each joined countdown and saves any change. The stores pass
    /// in their own pieces: the current copy, how to turn image bytes into an update, how to save.
    /// Returns the titles of countdowns whose owner stopped sharing; those become the person's own.
    @MainActor
    static func refresh(
        _ countdowns: [Countdown],
        shouldCheck: (Countdown) -> Bool,
        latest: (UUID) -> Countdown?,
        prepareImage: (Data) -> ImageUpdate?,
        save: (Countdown, ImageUpdate) -> Void
    ) async -> [String] {
        var ended: [String] = []
        for countdown in countdowns {
            guard let subscription = countdown.extras.subscription, shouldCheck(countdown) else { continue }
            do {
                let remote = try await LiveLinkAPI.fetch(slug: subscription.slug)
                guard needsUpdate(countdown, from: remote) else { continue }
                // Re-read: the person may have pinned or left it while the request was out.
                guard let current = latest(countdown.id) else { continue }
                var image = ImageUpdate.unchanged
                if subscription.remoteUpdatedAt.map({ remote.updatedAt > $0 }) ?? true {
                    if remote.hasPhoto, let data = try? await LiveLinkAPI.photo(slug: subscription.slug),
                       let update = prepareImage(data) {
                        image = update
                    } else if !remote.hasPhoto, current.hasImage {
                        image = .remove
                    }
                }
                save(apply(remote, to: current), image)
            } catch is LiveLinkAPI.NotShared {
                guard var current = latest(countdown.id) else { continue }
                current.extras.subscription = nil
                save(current, .unchanged)
                MemberTokens.remove(for: countdown.id)
                ended.append(current.title)
            } catch {
                // Offline or the server is having a moment; try again next time.
            }
        }
        return ended
    }

    /// Leaves on the server in the background. The local copy is the caller's to delete.
    static func leaveRemotely(_ countdown: Countdown) {
        guard let subscription = countdown.extras.subscription, let token = MemberTokens.token(for: countdown.id) else { return }
        Task {
            try? await LiveLinkAPI.leave(slug: subscription.slug, memberToken: token)
            MemberTokens.remove(for: countdown.id)
        }
    }

    /// Whether a refresh should rewrite the local copy.
    static func needsUpdate(_ local: Countdown, from remote: RemoteCountdown) -> Bool {
        guard let subscription = local.extras.subscription else { return false }
        return subscription.remoteUpdatedAt.map { remote.updatedAt > $0 } ?? true
            || subscription.memberCount != remote.memberCount
            // A floating time moves with the device's time zone.
            || (remote.floating != nil && local.targetDate != remote.targetDate)
    }
}

/// The owner's copy, as the server returns it.
struct RemoteCountdown: Equatable {
    var title: String
    var details: String
    var targetDate: Date
    var createdAt: Date
    var updatedAt: Date
    var kind: Countdown.Kind
    var style: CountdownStyle
    var milestones: [Milestone]
    var hasPhoto: Bool
    var memberCount: Int
    /// The public link, as the server spells it.
    var url: URL?
    /// A floating local time ("2027-01-01T00:00:00") that `targetDate` was read from on this device.
    var floating: String? = nil
    var isPublic = false
    var pool: DatePool? = nil
}

extension RemoteCountdown {
    private struct Envelope: Decodable {
        let url: URL?
        let countdown: Body
        let memberCount: Int?
    }

    private struct Body: Decodable {
        let title: String
        let details: String
        let targetDate: Date
        let createdAt: Date
        let updatedAt: Date
        let kind: String
        let style: Lenient<CountdownStyle>?
        let milestones: Lenient<[Milestone]>?
        let hasPhoto: Bool
        let floating: String?
        let isPublic: Bool?
        let pool: Lenient<DatePool>?
    }

    /// A style or milestone list written by a newer app can fail to decode here; fall back rather
    /// than refuse the whole countdown.
    private struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    /// Decodes `GET /api/countdowns/<slug>`. The server writes dates with milliseconds, and the app's
    /// own milestone dates went up as plain ISO 8601, so both are accepted.
    static func decode(_ data: Data) throws -> RemoteCountdown {
        let envelope = try LiveLinkAPI.decoder.decode(Envelope.self, from: data)
        let body = envelope.countdown
        return RemoteCountdown(
            title: body.title, details: body.details,
            // A floating time is midnight (or whenever) on this device's own clock.
            targetDate: body.floating.flatMap(localDate) ?? body.targetDate, createdAt: body.createdAt,
            updatedAt: body.updatedAt, kind: Countdown.Kind(rawValue: body.kind) ?? .event,
            style: body.style?.value ?? .default, milestones: body.milestones?.value ?? [],
            hasPhoto: body.hasPhoto, memberCount: envelope.memberCount ?? 0, url: envelope.url,
            floating: body.floating, isPublic: body.isPublic ?? false, pool: body.pool?.value
        )
    }

    /// "2027-01-01T00:00:00" on this device's clock.
    static func localDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: text)
    }
}

extension LiveLinkAPI {
    /// Reads the server's JSON: dates with milliseconds, and the app's own milestone dates, which
    /// went up as plain ISO 8601.
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) { return Date(timeIntervalSinceReferenceDate: seconds) }
            let text = try container.decode(String.self)
            let precise = ISO8601DateFormatter()
            precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = precise.date(from: text) ?? ISO8601DateFormatter().date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(text)")
        }
        return decoder
    }
}
