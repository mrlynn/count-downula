import StoreKit
import SwiftUI

/// The "Count Downcula Unlimited" upsell: shown when a free user hits the limit, or from the list's footer.
struct PaywallView: View {
    @Environment(PhoneStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// What opened it ("free_limit", "footer"), for the metrics dashboard.
    var reason = "unknown"

    private var entitlements: Entitlements { store.entitlements }

    var body: some View {
        content.onAppear {
            if !entitlements.isUnlocked { Analytics.log(.paywallShown, source: reason) }
        }
    }

    private var content: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 10) {
                        FangMark()
                            .foregroundStyle(Color.countdownulaBlood)
                            .frame(width: 84, height: 84)
                        Text("Count Downcula Unlimited")
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                        Text(entitlements.isUnlocked ? "Unlocked. Thanks for supporting Count Downcula!"
                                                     : "Count down to everything, everywhere.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 18) {
                        Feature(symbol: "infinity", title: "Unlimited countdowns",
                                detail: "Free includes \(SharedConfig.freeActiveLimit) at a time, counting timers and count-ups. Finished ones and shared countdowns you join don't count.")
                        Feature(symbol: "applewatch", title: "On all your devices",
                                detail: "One purchase covers your iPhone, iPad and Apple Watch.")
                        Feature(symbol: "heart", title: "Pay once, keep it",
                                detail: "No subscription and no ads, ever.")
                    }
                    .frame(maxWidth: 420, alignment: .leading)
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                actions
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 468)
                    .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(entitlements.isUnlocked ? "Done" : "Not Now") { dismiss() }
                }
            }
        }
        .task { await entitlements.loadProduct() }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if entitlements.isUnlocked {
                Button { dismiss() } label: {
                    Text("Done").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.countdownulaBlood)
                .controlSize(.large)
            } else {
                Button {
                    Task { await entitlements.purchase() }
                } label: {
                    Group {
                        if entitlements.purchaseState == .purchasing {
                            ProgressView()
                        } else if let product = entitlements.product {
                            Text("Unlock for \(product.displayPrice)")
                        } else if entitlements.productLoadFailed {
                            Text("Try Again")
                        } else {
                            Text("Connecting to the App Store…")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.countdownulaBlood)
                .controlSize(.large)
                // Disabled only while a load or purchase is under way; after a failed load it retries.
                .disabled((entitlements.product == nil && !entitlements.productLoadFailed)
                          || entitlements.purchaseState == .purchasing)

                if entitlements.product == nil, entitlements.productLoadFailed, entitlements.purchaseState != .purchasing {
                    status(L("Couldn't reach the App Store. Check your connection, then try again."))
                }

                switch entitlements.purchaseState {
                case .pending:
                    status("Purchase pending approval.")
                case let .failed(message):
                    status(message)
                default:
                    EmptyView()
                }

                Button("Restore Purchases") { Task { await entitlements.restore() } }
                    .font(.footnote)
                    .disabled(entitlements.purchaseState == .purchasing)
            }
        }
    }

    private func status(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

private struct Feature: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.countdownulaBlood)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
