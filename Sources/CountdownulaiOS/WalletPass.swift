import PassKit
import SwiftUI

/// "Add to Apple Wallet" for a shared countdown: an event ticket that comes to the Lock Screen as
/// the day approaches, with a QR code back to the live page.
struct WalletPassButton: View {
    let slug: String
    @State private var pass: PKPass?
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        if PKAddPassesViewController.canAddPasses() {
            Button {
                Task { await load() }
            } label: {
                Label(loading ? "Preparing Pass…" : "Add to Apple Wallet", systemImage: "wallet.pass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(loading)
            .sheet(item: $pass) { pass in
                AddPassSheet(pass: pass).ignoresSafeArea()
            }
            .alert("Apple Wallet", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            pass = try PKPass(data: try await LiveLinkAPI.walletPass(slug: slug))
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't make the pass right now. Try again in a moment."
        }
    }
}

extension PKPass: @retroactive Identifiable {
    public var id: String { serialNumber }
}

private struct AddPassSheet: UIViewControllerRepresentable {
    let pass: PKPass

    func makeUIViewController(context: Context) -> UIViewController {
        PKAddPassesViewController(pass: pass) ?? UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}
