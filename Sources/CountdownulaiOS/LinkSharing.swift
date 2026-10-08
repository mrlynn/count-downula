import SwiftUI

// MARK: - Store

extension PhoneStore {
    /// Publishes the countdown as a live link and remembers it on the countdown (synced) and the
    /// owner token in the iCloud Keychain.
    func publishLink(for countdown: Countdown) async throws -> URL {
        if let link = countdown.extras.link { return link.url }
        let backdrop = LinkBackdrop.make(for: countdown, photo: image(for: countdown))
        let published = try await LiveLinkAPI.publish(countdown, backdrop: backdrop.map { .set($0) } ?? .unchanged)
        OwnerTokens.save(published.ownerToken, for: countdown.id)
        // Re-read in case it changed while the request was in flight.
        var latest = self.countdown(id: countdown.id) ?? countdown
        latest.extras.link = published.link
        upsert(latest)
        return published.link.url
    }

    func unpublishLink(for countdown: Countdown) async throws {
        guard let link = countdown.extras.link else { return }
        try await LiveLinkAPI.unpublish(countdown, slug: link.slug)
        var latest = self.countdown(id: countdown.id) ?? countdown
        latest.extras.link = nil
        upsert(latest)
    }

    /// Keeps a published page in step after an edit. Quietly skipped on devices without the owner
    /// token, and on failure: the next edit sends the whole countdown again.
    func pushLinkUpdate(for countdown: Countdown) {
        guard let link = countdown.extras.link, OwnerTokens.token(for: countdown.id) != nil else { return }
        let backdrop = LinkBackdrop.make(for: countdown, photo: image(for: countdown))
        Task {
            try? await LiveLinkAPI.update(countdown, slug: link.slug, backdrop: backdrop.map { .set($0) } ?? .remove)
        }
    }
}

// MARK: - Backdrop image

enum LinkBackdrop {
    static let maxBytes = 380 * 1024

    /// The image the web page draws behind the countdown: the photo when the style shows it, or the
    /// scene rendered at 1080 × 1350. Gradients and colors are drawn by the page itself.
    @MainActor
    static func make(for countdown: Countdown, photo: UIImage?) -> Data? {
        switch countdown.style.background {
        case .automatic, .photo:
            return photo.flatMap { jpeg($0, maxDimension: 1080) }
        case let .scene(scene):
            let renderer = ImageRenderer(content: SceneArt(scene: scene).frame(width: 1080, height: 1350))
            renderer.scale = 1
            return renderer.uiImage.flatMap { jpeg($0, maxDimension: 1350) }
        case .gradient, .solid:
            return nil
        }
    }

    /// Scales down and steps the quality down until the JPEG fits the server's limit.
    static func jpeg(_ image: UIImage, maxDimension: CGFloat) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        for quality in [0.82, 0.72, 0.62, 0.5, 0.4] {
            let data = renderer.jpegData(withCompressionQuality: quality) { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            if data.count <= maxBytes { return data }
        }
        return nil
    }
}

// MARK: - Detail screen controls

/// "Share Live Link" on the detail screen: publishes on first use, then shares the same URL.
struct LiveLinkSection: View {
    @Environment(PhoneStore.self) private var store
    let countdown: Countdown

    @State private var confirmingPublish = false
    @State private var confirmingUnpublish = false
    @State private var working = false
    @State private var errorMessage: String?
    @State private var sharedURL: URL?
    /// How many people joined, fetched when the screen opens.
    @State private var memberCount = 0

    var body: some View {
        Group {
            if let link = countdown.extras.link {
                if memberCount > 0 {
                    Label(memberCount == 1 ? "1 person is counting down with you" : "\(memberCount) people are counting down with you",
                          systemImage: "person.2.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ShareLink(item: link.url, subject: Text(countdown.title), message: Text(countdown.title)) {
                    Label("Share Live Link", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    confirmingUnpublish = true
                } label: {
                    Label(working ? "Stopping…" : "Stop Sharing Link", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(working)
            } else {
                Button {
                    confirmingPublish = true
                } label: {
                    Label(working ? "Creating Link…" : "Share Live Link", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(working)
            }
        }
        .confirmationDialog("Create a live link?", isPresented: $confirmingPublish, titleVisibility: .visible) {
            Button("Create Link") { Task { await publish() } }
        } message: {
            Text(countdown.countsUp
                 ? "Anyone with the link can see this count-up, its start date, photo and description. You can stop sharing at any time."
                 : "Anyone with the link can see this countdown, its photo and description, ticking live. You can stop sharing at any time.")
        }
        .confirmationDialog("Stop sharing this link?", isPresented: $confirmingUnpublish, titleVisibility: .visible) {
            Button("Stop Sharing", role: .destructive) { Task { await unpublish() } }
        } message: {
            Text("The link stops working for everyone and the copy on Count Downcula's server is deleted.")
        }
        .alert("Live link", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task(id: countdown.extras.link?.slug) {
            guard let slug = countdown.extras.link?.slug else { memberCount = 0; return }
            memberCount = (try? await LiveLinkAPI.fetch(slug: slug))?.memberCount ?? memberCount
        }
        .sheet(item: $sharedURL) { url in
            ActivitySheet(items: [url])
                .presentationDetents([.medium, .large])
        }
    }

    private func publish() async {
        working = true
        defer { working = false }
        do {
            sharedURL = try await store.publishLink(for: countdown)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unpublish() async {
        working = true
        defer { working = false }
        do {
            try await store.unpublishLink(for: countdown)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// The system share sheet, for sharing something that was just made: a new link or a video.
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
