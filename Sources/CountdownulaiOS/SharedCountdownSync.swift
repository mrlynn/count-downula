import BackgroundTasks
import SwiftUI

// MARK: - Store

extension PhoneStore {
    /// Joins a shared countdown and returns the local copy's ID. Joining one you already have, or
    /// your own published countdown, just returns it.
    func join(slug: String) async throws -> UUID {
        if let existing = countdowns.first(where: { $0.extras.subscription?.slug == slug || $0.extras.link?.slug == slug }) {
            return existing.id
        }
        let remote = try await LiveLinkAPI.fetch(slug: slug)
        let backdrop = remote.hasPhoto ? try? await LiveLinkAPI.photo(slug: slug) : nil
        let joined = try await LiveLinkAPI.join(slug: slug)
        let url = remote.url ?? LiveLinkAPI.baseURL.appending(path: "c/\(slug)")
        var countdown = SharedCountdowns.makeCountdown(from: remote, slug: slug, url: url)
        countdown.extras.subscription?.memberCount = joined.memberCount
        MemberTokens.save(joined.memberToken, for: countdown.id)
        upsert(countdown, image: backdrop.flatMap { Self.prepareImage($0)?.update } ?? .unchanged)
        lastSharedRefresh[countdown.id] = Date()
        Task { await registerPushForShared() }
        return countdown.id
    }

    // MARK: Push

    /// This device's APNs token, as hex. Set by the app delegate once iOS hands it over.
    static var deviceToken: String? {
        get { UserDefaults.standard.string(forKey: "Push.deviceToken") }
        set { UserDefaults.standard.set(newValue, forKey: "Push.deviceToken") }
    }

    /// Which device token each joined countdown last registered, so we only tell the server again
    /// when something changed (a new join, a reinstall, a restored phone).
    private var registeredPushTokens: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "Push.registered") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "Push.registered") }
    }

    /// Asks the server to wake this device when an owner edits one of your joined countdowns.
    func registerPushForShared() async {
        guard let deviceToken = Self.deviceToken else { return }
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif
        var registered = registeredPushTokens
        for countdown in countdowns {
            guard let subscription = countdown.extras.subscription, registered[countdown.id.uuidString] != deviceToken,
                  let memberToken = MemberTokens.token(for: countdown.id) else { continue }
            do {
                try await LiveLinkAPI.registerPush(slug: subscription.slug, memberToken: memberToken,
                                                   deviceToken: deviceToken, sandbox: sandbox)
                registered[countdown.id.uuidString] = deviceToken
            } catch {
                // Try again on the next launch or join.
            }
        }
        // Forget countdowns that are gone.
        let ids = Set(countdowns.map(\.id.uuidString))
        registeredPushTokens = registered.filter { ids.contains($0.key) }
    }

    /// Leaves a shared countdown: removes it here (and, through iCloud, on your other devices) and
    /// takes you off the owner's count.
    func leave(_ countdown: Countdown) {
        SharedCountdowns.leaveRemotely(countdown)
        repository.delete(id: countdown.id)
        reload()
    }

    /// Pulls the owner's latest copy of every joined countdown. `force` ignores the usual interval,
    /// for when the app comes to the front.
    func refreshShared(force: Bool = false) async {
        let now = Date()
        let ended = await SharedCountdowns.refresh(
            countdowns,
            shouldCheck: { countdown in
                if !force, let last = lastSharedRefresh[countdown.id],
                   now.timeIntervalSince(last) < SharedCountdowns.refreshInterval { return false }
                lastSharedRefresh[countdown.id] = now
                return true
            },
            latest: { self.countdown(id: $0) },
            prepareImage: { Self.prepareImage($0)?.update },
            save: { upsert($0, image: $1) }
        )
        sharingEnded.append(contentsOf: ended)
    }
}

// MARK: - Joining from a link

/// Joins from a tapped link or the Join sheet, then opens the countdown.
@MainActor
@Observable
final class JoinCoordinator {
    var isJoining = false
    var errorMessage: String?

    func join(_ text: String, store: PhoneStore, router: Router) async {
        guard let slug = SharedCountdowns.slug(from: text) else {
            errorMessage = "That doesn't look like a Count Downcula link. Shared links look like go.countdowncula.com/c/…"
            return
        }
        isJoining = true
        defer { isJoining = false }
        do {
            router.show(try await store.join(slug: slug))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// "Join Shared Countdown" from the + menu, for a link that arrived somewhere other than a tap.
struct JoinSharedSheet: View {
    @Environment(PhoneStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(JoinCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("go.countdowncula.com/c/…", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first { link = first }
                    }
                } footer: {
                    Text("Paste a shared countdown link. It shows up here, on your widgets and Lock Screen, and stays in step when the owner changes it.")
                }
            }
            .navigationTitle("Join Shared Countdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        let text = link
                        dismiss()
                        Task { await coordinator.join(text, store: store, router: router) }
                    }
                    .disabled(SharedCountdowns.slug(from: link) == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Detail screen

/// For a countdown you joined: who's counting, invite others, leave.
struct SharedMemberSection: View {
    @Environment(PhoneStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let countdown: Countdown
    let subscription: SharedSubscription
    @State private var confirmingLeave = false

    var body: some View {
        VStack(spacing: 10) {
            Label {
                Text(summary)
            } icon: {
                Image(systemName: "person.2.fill")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            ShareLink(item: subscription.url, subject: Text(countdown.title), message: Text(countdown.title)) {
                Label("Invite Others", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                confirmingLeave = true
            } label: {
                Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .confirmationDialog("Leave \(countdown.title)?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                dismiss()
                store.leave(countdown)
            }
        } message: {
            Text("It's removed from your devices. You can join again from the link.")
        }
    }

    private var summary: String {
        let others = max(0, (subscription.memberCount ?? 1) - 1)
        let who = others == 0 ? "Shared with you" : "You and \(others) other\(others == 1 ? "" : "s") are counting down"
        return "\(who). Only the owner can change it."
    }
}

// MARK: - Background refresh

/// Checks joined countdowns for the owner's edits while the app is closed, so widgets and the
/// Lock Screen catch up without the app being opened. iOS decides when it actually runs.
enum SharedRefreshTask {
    static let identifier = "com.countdownula.app.refresh-shared"

    static func register(_ refresh: @escaping @MainActor () async -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            schedule()
            let work = Task { @MainActor in
                await refresh()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: SharedCountdowns.refreshInterval)
        try? BGTaskScheduler.shared.submit(request)
    }
}
