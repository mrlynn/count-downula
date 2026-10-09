import StoreKit
import SwiftUI

/// Buys Host Passes and hands them to the server, which checks Apple's signature and attaches each
/// one to a countdown. A pass is a consumable, so the transaction is finished only once the server
/// has it: if the app quits or the network drops in between, the next launch delivers it.
@MainActor
@Observable
final class HostPassStore {
    static let shared = HostPassStore()

    enum State: Equatable {
        case idle
        case buying
        /// Waiting on Ask to Buy or a payment issue; it's applied when it goes through.
        case pending
        case failed(String)
    }

    private(set) var product: Product?
    private(set) var state = State.idle

    /// Which countdown each bought-but-undelivered pass is for, by transaction ID, plus a slug
    /// waiting on Ask to Buy (whose transaction ID isn't known yet).
    private let pendingKey = "HostPass.pending"
    private let awaitingKey = "HostPass.awaitingSlug"
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    private init() {
        #if !DIRECT_DISTRIBUTION
        updatesTask = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                guard case let .verified(transaction) = update, transaction.productID == SharedConfig.hostPassProductID else { continue }
                await self?.deliver(transaction, jws: update.jwsRepresentation)
            }
        }
        Task {
            product = try? await Product.products(for: [SharedConfig.hostPassProductID]).first
            await deliverUnfinished()
        }
        #endif
    }

    /// Buys a pass for a countdown you've shared and applies it.
    func buy(for countdown: Countdown, store: PhoneStore) async -> Bool {
        guard let product, let link = countdown.extras.link else { return false }
        state = .buying
        do {
            switch try await product.purchase() {
            case let .success(verification):
                guard case let .verified(transaction) = verification else {
                    state = .failed(L("The App Store couldn't verify this purchase."))
                    return false
                }
                remember(slug: link.slug, for: transaction.id)
                return await deliver(transaction, jws: verification.jwsRepresentation)
            case .pending:
                UserDefaults.standard.set(link.slug, forKey: awaitingKey)
                state = .pending
            case .userCancelled:
                state = .idle
            @unknown default:
                state = .idle
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
        return false
    }

    /// Sends a pass to the server for its countdown; finishes the transaction once it's attached,
    /// or once the server says it never will be.
    @discardableResult
    private func deliver(_ transaction: StoreKit.Transaction, jws: String) async -> Bool {
        let pending = UserDefaults.standard.dictionary(forKey: pendingKey) as? [String: String] ?? [:]
        let awaiting = UserDefaults.standard.string(forKey: awaitingKey)
        guard let slug = pending[String(transaction.id)] ?? awaiting,
              let countdown = PhoneStore.shared.countdowns.first(where: { $0.extras.link?.slug == slug }),
              let token = OwnerTokens.token(for: countdown.id) else {
            // Bought on another device, or the countdown is gone from this one: leave it for a device that knows.
            return false
        }
        remember(slug: slug, for: transaction.id)
        UserDefaults.standard.removeObject(forKey: awaitingKey)
        do {
            try await LiveLinkAPI.applyHostPass(slug: slug, token: token, transaction: jws)
            await transaction.finish()
            forget(transaction.id)
            PhoneStore.shared.markHosted(countdown.id)
            Analytics.log(.purchaseCompleted, slug: slug, source: "host_pass")
            state = .idle
            return true
        } catch LiveLinkAPI.Failure.unreachable {
            state = .failed(L("Your Host Pass is bought but couldn't reach Count Downcula. It'll be applied next time the app opens."))
        } catch {
            // Refused for good (refunded, already used elsewhere): keeping it would retry forever.
            await transaction.finish()
            forget(transaction.id)
            state = .failed(error.localizedDescription)
        }
        return false
    }

    private func deliverUnfinished() async {
        for await result in StoreKit.Transaction.unfinished {
            guard case let .verified(transaction) = result, transaction.productID == SharedConfig.hostPassProductID else { continue }
            await deliver(transaction, jws: result.jwsRepresentation)
        }
    }

    private func remember(slug: String, for id: UInt64) {
        var pending = UserDefaults.standard.dictionary(forKey: pendingKey) as? [String: String] ?? [:]
        pending[String(id)] = slug
        UserDefaults.standard.set(pending, forKey: pendingKey)
    }

    private func forget(_ id: UInt64) {
        var pending = UserDefaults.standard.dictionary(forKey: pendingKey) as? [String: String] ?? [:]
        pending[String(id)] = nil
        UserDefaults.standard.set(pending, forKey: pendingKey)
    }
}

extension LiveLinkAPI {
    /// Attaches a Host Pass (StoreKit's signed transaction) to a countdown you own.
    static func applyHostPass(slug: String, token: String, transaction: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["transaction": transaction])
        let (data, status) = try await raw("POST", path: "api/countdowns/\(slug)/host", token: token, body: body)
        try check(status, data)
    }

    /// Sets a hosted countdown's custom link and returns it.
    static func setAlias(slug: String, token: String, alias: String) async throws -> URL {
        struct Reply: Decodable { let url: URL }
        let body = try JSONSerialization.data(withJSONObject: ["alias": alias])
        let (data, status) = try await raw("PUT", path: "api/countdowns/\(slug)/alias", token: token, body: body)
        try check(status, data)
        return try decoder.decode(Reply.self, from: data).url
    }
}

extension PhoneStore {
    /// Records a Host Pass on a countdown you own (synced, so your other devices know).
    func markHosted(_ id: UUID) {
        guard var countdown = countdown(id: id), countdown.extras.link?.isHosted != true else { return }
        countdown.extras.link?.isHosted = true
        upsert(countdown)
    }

    /// Points a published countdown at its new custom link.
    func setLinkURL(_ url: URL, for id: UUID) {
        guard var countdown = countdown(id: id), countdown.extras.link?.url != url else { return }
        countdown.extras.link?.url = url
        upsert(countdown)
    }
}
