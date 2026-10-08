import StoreKit
import SwiftUI

/// The App Clip: opens from a shared countdown link on an iPhone without the app, shows it ticking
/// live, and offers to keep it. "Keep It" hands the countdown to the full app through the App Group.
@main
struct CountdownulaClipApp: App {
    @State private var model = ClipModel()

    var body: some Scene {
        WindowGroup {
            ClipView(model: model)
                .tint(.countdownulaBlood)
                .preferredColorScheme(.dark)
                // App Clip launches arrive as a web browsing activity carrying the tapped link.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    Task { await model.open(url) }
                }
                #if DEBUG
                // Xcode's App Clip launch URL, for runs that don't come from a real link tap.
                .task {
                    if case .waiting = model.state,
                       let raw = ProcessInfo.processInfo.environment["_XCAppClipURL"], let url = URL(string: raw) {
                        await model.open(url)
                    }
                }
                #endif
        }
    }
}

@MainActor
@Observable
final class ClipModel {
    enum State {
        case waiting
        case loading
        case loaded(Countdown, photo: UIImage?, slug: String, url: URL)
        case failed(String)
    }

    var state = State.waiting
    var kept = false

    func open(_ url: URL) async {
        guard let slug = SharedCountdowns.slug(from: url.absoluteString) else {
            state = .failed("That link doesn't point to a countdown.")
            return
        }
        state = .loading
        do {
            let remote = try await LiveLinkAPI.fetch(slug: slug)
            let photo = remote.hasPhoto ? (try? await LiveLinkAPI.photo(slug: slug)).flatMap(UIImage.init(data:)) : nil
            let link = remote.url ?? url
            let countdown = SharedCountdowns.makeCountdown(from: remote, slug: slug, url: link)
            state = .loaded(countdown, photo: photo, slug: slug, url: link)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func keep(_ slug: String) {
        ClipHandoff.keep(slug)
        kept = true
    }
}

struct ClipView: View {
    let model: ClipModel
    @State private var showingAppStore = false

    var body: some View {
        Group {
            switch model.state {
            case .waiting:
                // Opened without a link, say from the App Library.
                ContentUnavailableView {
                    Label("Count Downcula", systemImage: "hourglass")
                } description: {
                    Text("Open a shared countdown link to see it here, ticking live.")
                } actions: {
                    Button("Get Count Downcula") { showingAppStore = true }
                        .buttonStyle(.borderedProminent)
                }
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Countdown Unavailable", systemImage: "hourglass")
                } description: {
                    Text(message)
                } actions: {
                    Button("Get Count Downcula") { showingAppStore = true }
                        .buttonStyle(.borderedProminent)
                }
            case let .loaded(countdown, photo, slug, url):
                loaded(countdown, photo: photo, slug: slug, url: url)
            }
        }
        .background(Color.black)
        .appStoreOverlay(isPresented: $showingAppStore) {
            SKOverlay.AppClipConfiguration(position: .bottom)
        }
    }

    private func loaded(_ countdown: Countdown, photo: UIImage?, slug: String, url: URL) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ClipCard(countdown: countdown, photo: photo, now: now)

                    Label {
                        Text(countdown.targetDate, format: .dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if !countdown.details.isEmpty {
                        Text(countdown.details)
                    }

                    if let members = countdown.extras.subscription?.memberCount, members > 0 {
                        Label(members == 1 ? "1 person is counting down" : "\(members) people are counting down",
                              systemImage: "person.2.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 10) {
                        Button {
                            model.keep(slug)
                            showingAppStore = true
                        } label: {
                            Label(model.kept ? "Kept" : "Keep It", systemImage: model.kept ? "checkmark" : "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        ShareLink(item: url, subject: Text(countdown.title), message: Text(countdown.title)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.large)

                    Text(model.kept
                         ? "Get Count Downcula and open it once. This countdown will be waiting, on your Lock Screen and widgets too."
                         : "Keep it to count down together. It stays in step when it changes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                // A phone-shaped column on iPad, rather than a card stretched across the screen.
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// The countdown's backdrop, title and live tiles, like the app's own card.
struct ClipCard: View {
    let countdown: Countdown
    let photo: UIImage?
    let now: Date

    var body: some View {
        let style = countdown.style
        StyledBackdrop(style: style, photo: photo.map { Image(uiImage: $0) },
                       dialRemaining: countdown.dialRemaining(at: now), dialPadding: 18,
                       dialAlignment: .topTrailing, dialMaxWidth: 72)
            .frame(height: 360)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay { StyleScrim(style: style) }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(countdown.title)
                        .font(style.font(.largeTitle))
                        .lineLimit(3)
                    TimeBlocks(parts: countdown.timeParts(at: now), tileColor: style.foregroundColor.opacity(0.14),
                               size: 32, style: style)
                        .environment(\.colorScheme, style.hasLightText ? .dark : .light)
                }
                .foregroundStyle(style.foregroundColor)
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
