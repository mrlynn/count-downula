import StoreKit
import SwiftUI

/// The "Count Downcula Unlimited" upsell in its own window: opened when a free user hits the limit,
/// or from the popover's footer. The GitHub build is always unlocked and never shows it.
struct PaywallView: View {
    let entitlements: Entitlements
    let onClose: () -> Void

    var body: some View {
        content.onAppear {
            if !entitlements.isUnlocked { Analytics.log(.paywallShown, source: "mac") }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    FangMark()
                        .foregroundStyle(Color.countdownulaBlood)
                        .frame(width: 64, height: 64)
                    Text("Count Downcula Unlimited")
                        .font(.title2.bold())
                    Text(entitlements.isUnlocked ? "Unlocked. Thanks for supporting Count Downcula!"
                                                 : "Count down to everything, everywhere.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Feature(symbol: "infinity", title: "Unlimited countdowns",
                            detail: "Free includes \(SharedConfig.freeActiveLimit) at a time, counting timers and count-ups. Finished ones and shared countdowns you join don't count.")
                    Feature(symbol: "macbook.and.iphone", title: "On all your devices",
                            detail: "One purchase covers your Mac, iPhone, iPad and Apple Watch.")
                    Feature(symbol: "heart", title: "Pay once, keep it",
                            detail: "No subscription and no ads, ever.")
                }
            }
            .padding(28)

            Divider()

            actions
                .padding(20)
        }
        .frame(width: 420)
        .task { await entitlements.loadProduct() }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if entitlements.isUnlocked {
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            } else {
                Button {
                    Task { await entitlements.purchase() }
                } label: {
                    Group {
                        if entitlements.purchaseState == .purchasing {
                            ProgressView().controlSize(.small)
                        } else if let product = entitlements.product {
                            Text("Unlock for \(product.displayPrice)")
                        } else {
                            Text("Connecting to the App Store…")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.countdownulaBlood)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(entitlements.product == nil || entitlements.purchaseState == .purchasing)

                switch entitlements.purchaseState {
                case .pending:
                    status("Purchase pending approval.")
                case let .failed(message):
                    status(message)
                default:
                    EmptyView()
                }

                HStack {
                    Button("Restore Purchases") { Task { await entitlements.restore() } }
                        .disabled(entitlements.purchaseState == .purchasing)
                    Spacer()
                    Button("Not Now", action: onClose)
                        .keyboardShortcut(.cancelAction)
                }
                .buttonStyle(.borderless)
                .font(.callout)
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.countdownulaBlood)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
