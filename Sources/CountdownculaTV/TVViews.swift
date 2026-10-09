import SwiftUI

// MARK: - Home

/// The next countdown big, then shelves of what's coming and what's counting up.
struct HomeView: View {
    @Environment(TVStore.self) private var store
    @Binding var presenting: Presentation?

    var body: some View {
        let upcoming = store.countdowns.filter { $0.isUpcoming(at: store.now) }.sorted { $0.targetDate < $1.targetDate }
        let countingUp = store.countdowns.filter(\.countsUp)
        ScrollView {
            if let featured = store.featured {
                VStack(alignment: .leading, spacing: 50) {
                    Button { presenting = .mine(featured.id) } label: {
                        CountdownCard(countdown: featured, photo: store.image(for: featured), now: store.now, large: true)
                    }
                    .buttonStyle(.card)

                    shelf(L("Coming Up"), upcoming.filter { $0.id != featured.id })
                    shelf(L("Counting Up"), countingUp.filter { $0.id != featured.id })
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 40)
            } else {
                EmptyHome()
            }
        }
    }

    @ViewBuilder
    private func shelf(_ title: String, _ countdowns: [Countdown]) -> some View {
        if !countdowns.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                Text(title).font(.title3).foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 48) {
                        ForEach(countdowns) { countdown in
                            Button { presenting = .mine(countdown.id) } label: {
                                CountdownCard(countdown: countdown, photo: store.image(for: countdown), now: store.now)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.vertical, 30)
                }
                .scrollClipDisabled()
            }
        }
    }
}

/// Before anything has synced: where countdowns come from, with a code to make one on the web.
private struct EmptyHome: View {
    @State private var code: CGImage?

    var body: some View {
        HStack(spacing: 80) {
            VStack(alignment: .leading, spacing: 24) {
                FangMark()
                    .foregroundStyle(Color.countdownulaBlood)
                    .frame(width: 120, height: 120)
                Text("No countdowns yet")
                    .font(.title2.weight(.bold))
                Text("Countdowns you make on your iPhone, iPad or Mac show up here through iCloud. Or scan the code to make one on the web.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 900, alignment: .leading)
            }
            if let code {
                Image(decorative: code, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 280, height: 280)
                    .padding(20)
                    .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
        .padding(120)
        .task { code = PresentRoom.qrCode(for: LiveLinkAPI.baseURL.appending(path: "new").appending(queryItems: [.init(name: "src", value: "tv")])) }
    }
}

// MARK: - Cards

/// A countdown as a focusable card: its backdrop, title and time left.
struct CountdownCard: View {
    let countdown: Countdown
    var photo: UIImage?
    let now: Date
    var large = false

    var body: some View {
        StyledBackdrop(style: countdown.style, photo: photo.map { Image(uiImage: $0) },
                       dialRemaining: countdown.dialRemaining(at: now), dialPadding: large ? 60 : 30,
                       dialAlignment: .topTrailing, dialMaxWidth: large ? 160 : 80)
            .overlay { StyleScrim(style: countdown.style) }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: large ? 12 : 6) {
                    Text(countdown.title.isEmpty ? L("Untitled") : countdown.title)
                        .font(countdown.style.font(size: large ? 64 : 30))
                        .lineLimit(2)
                    CountdownTimeText(countdown: countdown, now: now)
                        .font(countdown.style.font(size: large ? 44 : 26))
                        .monospacedDigit()
                }
                .foregroundStyle(countdown.style.foregroundColor)
                .padding(large ? 48 : 24)
            }
            .frame(width: large ? 1760 : 520, height: large ? 620 : 292)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - The Crypt

/// Public countdowns anyone can count down to: holidays, eclipses, big games. Select to show one
/// full screen; press and hold to add it to your countdowns.
struct CryptView: View {
    @Environment(TVStore.self) private var store
    @Binding var presenting: Presentation?
    @State private var entries: [CryptEntry] = []
    @State private var categories: [LiveLinkAPI.CryptCategory] = []
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                if failed {
                    ContentUnavailableView("The Crypt is out of reach", systemImage: "wifi.slash",
                                           description: Text("Check the network and try again."))
                }
                ForEach(categories) { category in
                    let rows = entries.filter { $0.category == category.slug && $0.target > store.now }
                    if !rows.isEmpty {
                        Text(category.name).font(.title3).foregroundStyle(.secondary)
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 48) {
                                ForEach(rows) { entry in card(entry) }
                            }
                            .padding(.vertical, 30)
                        }
                        .scrollClipDisabled()
                    }
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .task {
            do {
                (categories, entries) = try await LiveLinkAPI.crypt()
            } catch {
                failed = true
            }
        }
    }

    private func card(_ entry: CryptEntry) -> some View {
        let added = store.countdowns.contains { $0.extras.subscription?.slug == entry.slug }
        return Button { presenting = .crypt(entry) } label: {
            CountdownCard(countdown: entry.preview, now: store.now)
                .overlay(alignment: .topLeading) {
                    if added {
                        Label("Added", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .padding(10)
                            .background(.thinMaterial, in: Capsule())
                            .padding(16)
                    }
                }
        }
        .buttonStyle(.card)
        .contextMenu {
            if !added {
                Button("Add to My Countdowns", systemImage: "plus") {
                    Task { _ = try? await store.join(slug: entry.slug) }
                }
            }
        }
    }
}

// MARK: - Full screen

/// A countdown on the TV: the shared present layout, kept awake. Left and right on the remote
/// step through your countdowns; Menu goes back.
struct PresentingView: View {
    @Environment(TVStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var presentation: Presentation

    var body: some View {
        Group {
            switch presentation {
            case let .mine(id):
                if let countdown = store.countdown(id: id) {
                    PresentView(countdown: countdown, photo: store.image(for: countdown).map { Image(uiImage: $0) }) {
                        Analytics.log(.presentZero, slug: countdown.extras.link?.slug ?? countdown.extras.subscription?.slug, source: "appletv")
                    }
                    .id(id)
                }
            case let .crypt(entry):
                PresentView(countdown: entry.preview)
            }
        }
        .focusable()
        .onMoveCommand { direction in step(direction) }
        .onExitCommand { dismiss() }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            Analytics.log(.presentStarted, source: "appletv")
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func step(_ direction: MoveCommandDirection) {
        guard case let .mine(id) = presentation else { return }
        let order = store.upcoming
        guard let index = order.firstIndex(where: { $0.id == id }), !order.isEmpty else { return }
        switch direction {
        case .left: presentation = .mine(order[(index - 1 + order.count) % order.count].id)
        case .right: presentation = .mine(order[(index + 1) % order.count].id)
        default: break
        }
    }
}
