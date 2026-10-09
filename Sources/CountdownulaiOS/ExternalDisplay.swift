import SwiftUI
import UIKit

/// A TV or projector connected by AirPlay or a cable: instead of mirroring the phone, it shows the
/// countdown full screen (the same layout as the Mac and the web's present page), and the phone
/// keeps its controls. Which countdown is the one picked on the phone, else Next Up.
@MainActor
@Observable
final class ExternalDisplay {
    static let shared = ExternalDisplay()

    /// A big screen is connected and showing a countdown.
    private(set) var isConnected = false
    /// The countdown picked to show; nil shows Next Up.
    var presentedID: UUID?

    fileprivate func connected() {
        isConnected = true
        // The phone is the remote now: keep it from locking while the room watches.
        UIApplication.shared.isIdleTimerDisabled = true
        let countdown = Self.countdown(in: PhoneStore.shared)
        Analytics.log(.presentStarted, slug: countdown?.extras.link?.slug ?? countdown?.extras.subscription?.slug, source: "tv")
    }

    fileprivate func disconnected() {
        isConnected = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    static func countdown(in store: PhoneStore) -> Countdown? {
        if let id = shared.presentedID, let picked = store.countdown(id: id) { return picked }
        return store.countdowns.featured(at: Date())
    }
}

/// The scene iOS creates for an external display, once the app says it has one.
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        MainActor.assumeIsolated {
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = UIHostingController(rootView: ExternalPresentation())
            window.isHidden = false
            self.window = window
            ExternalDisplay.shared.connected()
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        MainActor.assumeIsolated {
            window = nil
            ExternalDisplay.shared.disconnected()
        }
    }
}

/// What the TV shows: the picked countdown, following edits and sync, or a quiet mark when there's nothing to count.
private struct ExternalPresentation: View {
    private let store = PhoneStore.shared

    var body: some View {
        if let countdown = ExternalDisplay.countdown(in: store) {
            PresentView(countdown: countdown, photo: store.image(for: countdown).map { Image(uiImage: $0) }) {
                Analytics.log(.presentZero, slug: countdown.extras.link?.slug ?? countdown.extras.subscription?.slug, source: "tv")
            }
            .id(countdown.id)
        } else {
            ZStack {
                LinearGradient.countdownulaNight
                FangMark()
                    .foregroundStyle(Color.countdownulaBlood)
                    .frame(width: 160, height: 160)
            }
            .ignoresSafeArea()
        }
    }
}

/// On a countdown's screen while a TV is connected: put this one on it, or say it's already there.
struct ExternalDisplayButton: View {
    let countdown: Countdown
    private var display: ExternalDisplay { .shared }

    var body: some View {
        if display.isConnected {
            let showing = ExternalDisplay.countdown(in: PhoneStore.shared)?.id == countdown.id
            Button {
                display.presentedID = countdown.id
            } label: {
                Label(showing ? "Showing on the Big Screen" : "Show on the Big Screen", systemImage: "tv")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(showing)
        }
    }
}
