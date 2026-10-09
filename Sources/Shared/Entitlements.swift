import Foundation
import Observation
import StoreKit

/// Tracks the one-time "Count Downcula Unlimited" purchase and the free-tier limit it lifts.
/// Direct-download builds (compiled with `-D DIRECT_DISTRIBUTION`, like the GitHub Mac app) are always
/// unlocked and never touch StoreKit.
@MainActor
@Observable
final class Entitlements {
    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case pending          // waiting on Ask to Buy or a payment issue
        case failed(String)
    }

    private(set) var isUnlocked: Bool
    private(set) var product: Product?
    private(set) var purchaseState: PurchaseState = .idle

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    /// Last known state, so an offline launch doesn't flash the paywall at someone who already paid.
    private static let cacheKey = "unlimitedUnlocked"

    init() {
        #if DIRECT_DISTRIBUTION
        isUnlocked = true
        #else
        #if DEBUG
        // Screenshots of the free tier on a machine that already bought Unlimited.
        if ProcessInfo.processInfo.arguments.contains("-freeTier") {
            isUnlocked = false
            Task { await loadProduct() }
            return
        }
        #endif
        isUnlocked = UserDefaults.standard.bool(forKey: Self.cacheKey)
        // Purchases from other devices, Ask to Buy approvals and refunds all arrive here.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                // Host Passes are finished by HostPassStore once the server has them; finishing one
                // here would lose a purchase that never reached its countdown.
                if case .verified(let transaction) = update, transaction.productID == SharedConfig.unlimitedProductID {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
        Task {
            await refresh()
            await loadProduct()
        }
        #endif
    }

    // MARK: - Free tier

    /// Countdowns that count toward the free limit: everything that isn't finished. Shared countdowns
    /// you joined don't count, so a free user can always say yes to an invite.
    nonisolated static func activeCount(in countdowns: [Countdown], at now: Date = Date()) -> Int {
        countdowns.filter { !$0.isPast(at: now) && $0.extras.subscription == nil }.count
    }

    nonisolated static func canAdd(to countdowns: [Countdown], unlocked: Bool, at now: Date = Date()) -> Bool {
        unlocked || activeCount(in: countdowns, at: now) < SharedConfig.freeActiveLimit
    }

    /// Whether saving `countdown` stays within the free tier. Editing a countdown that is already active is
    /// always allowed, so people over the limit (synced from a Mac, or after a refund) never lose access to their data.
    nonisolated static func allowsSaving(_ countdown: Countdown, replacing original: Countdown?,
                                         in countdowns: [Countdown], unlocked: Bool, at now: Date = Date()) -> Bool {
        if countdown.isPast(at: now) { return true }
        if let original, !original.isPast(at: now) { return true }
        return canAdd(to: countdowns, unlocked: unlocked, at: now)
    }

    func canAdd(to countdowns: [Countdown], at now: Date = Date()) -> Bool {
        Self.canAdd(to: countdowns, unlocked: isUnlocked, at: now)
    }

    func allowsSaving(_ countdown: Countdown, replacing original: Countdown?,
                      in countdowns: [Countdown], at now: Date = Date()) -> Bool {
        Self.allowsSaving(countdown, replacing: original, in: countdowns, unlocked: isUnlocked, at: now)
    }

    // MARK: - StoreKit

    func loadProduct() async {
        #if !DIRECT_DISTRIBUTION
        guard product == nil else { return }
        product = try? await Product.products(for: [SharedConfig.unlimitedProductID]).first
        #endif
    }

    func purchase() async {
        guard let product else { return }
        purchaseState = .purchasing
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                setUnlocked(true)
                purchaseState = .idle
                Analytics.log(.purchaseCompleted)
                Analytics.flush()
            case .success(.unverified):
                purchaseState = .failed("The App Store couldn't verify this purchase.")
            case .pending:
                purchaseState = .pending
            case .userCancelled:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func restore() async {
        purchaseState = .purchasing
        do {
            try await AppStore.sync()
            await refresh()
            purchaseState = isUnlocked ? .idle : .failed("No previous purchase found for this Apple Account.")
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    private func refresh() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == SharedConfig.unlimitedProductID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        setUnlocked(owned)
    }

    private func setUnlocked(_ unlocked: Bool) {
        if isUnlocked != unlocked { isUnlocked = unlocked }
        UserDefaults.standard.set(unlocked, forKey: Self.cacheKey)
    }
}
