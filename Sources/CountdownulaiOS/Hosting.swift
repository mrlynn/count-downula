import StoreKit
import SwiftUI

/// On a countdown you've shared: buy a Host Pass for it, or once it's hosted, set its custom link
/// and, after zero, save the keepsake.
struct HostSection: View {
    @Environment(PhoneStore.self) private var store
    let countdown: Countdown
    let link: PublishedLink
    let now: Date

    @State private var hostPass = HostPassStore.shared
    @State private var alias = ""
    @State private var savingAlias = false
    @State private var keepsake: [URL]?
    @State private var makingKeepsake = false
    @State private var errorMessage: String?

    private var hosted: Bool { link.isHosted == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hosted { hostedContent } else { offer }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task(id: link.slug) { await syncFromServer() }
        .sheet(isPresented: Binding(get: { keepsake != nil }, set: { if !$0 { keepsake = nil } })) {
            ActivitySheet(items: keepsake ?? []).presentationDetents([.medium, .large])
        }
        .alert("Host Pass", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Not hosted yet

    private var offer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Host This Event", systemImage: "crown")
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                feature("link", "A custom link, like /c/sarah-and-tom")
                feature("eye.slash", "No Count Downcula branding on the page or embeds")
                feature("photo.stack", "Several photos and a short video in each coffin note")
                feature("book.closed", "A keepsake of every note and photo after zero")
            }
            .font(.subheadline)
            Button {
                Task {
                    if await hostPass.buy(for: countdown, store: store) == false, case let .failed(message) = hostPass.state {
                        errorMessage = message
                    }
                }
            } label: {
                Text(hostPass.state == .buying ? "Buying…"
                     : hostPass.product.map { "Get Host Pass · \($0.displayPrice)" } ?? "Host Pass Unavailable")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(hostPass.product == nil || hostPass.state == .buying)
            Text(hostPass.state == .pending
                 ? "Waiting for approval. It's applied as soon as it goes through."
                 : "One pass hosts this countdown. Everyone counting down gets the bigger coffin too.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).foregroundStyle(.primary)
    }

    // MARK: - Hosted

    @ViewBuilder
    private var hostedContent: some View {
        Label("Hosted", systemImage: "crown.fill")
            .font(.headline)
            .foregroundStyle(countdown.style.accentColor)
        VStack(alignment: .leading, spacing: 6) {
            Text("Custom link").font(.subheadline.weight(.semibold))
            HStack(spacing: 4) {
                Text("…/c/").foregroundStyle(.secondary)
                TextField("sarah-and-tom", text: $alias)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { Task { await saveAlias() } }
                Button(savingAlias ? "Saving…" : "Save") { Task { await saveAlias() } }
                    .disabled(savingAlias || alias.trimmingCharacters(in: .whitespaces).count < 3 || link.url.lastPathComponent == alias)
            }
            .padding(10)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("The old link keeps working too.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        Button {
            Task { await makeKeepsake() }
        } label: {
            Label(makingKeepsake ? "Gathering Notes…" : "Save Keepsake", systemImage: "book.closed")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(makingKeepsake || !countdown.isPast(at: now) && !countdown.countsUp)
        Text(countdown.isPast(at: now) || countdown.countsUp
             ? "Every note, photo and video from the coffin, as a PDF guestbook and a ZIP."
             : "After zero: every note, photo and video from the coffin, as a PDF guestbook and a ZIP.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    // MARK: - Actions

    /// The server is the record: a pass bought on another device, or a link set there, shows up here.
    private func syncFromServer() async {
        if alias.isEmpty, link.url.lastPathComponent != link.slug { alias = link.url.lastPathComponent }
        guard let remote = try? await LiveLinkAPI.fetch(slug: link.slug) else { return }
        if remote.isHosted { store.markHosted(countdown.id) }
        if let url = remote.url {
            store.setLinkURL(url, for: countdown.id)
            if alias.isEmpty, url.lastPathComponent != link.slug { alias = url.lastPathComponent }
        }
    }

    private func saveAlias() async {
        guard let token = OwnerTokens.token(for: countdown.id) else {
            errorMessage = L("Only the device that shared this link, or one signed in to the same iCloud Keychain, can change it.")
            return
        }
        savingAlias = true
        defer { savingAlias = false }
        do {
            let url = try await LiveLinkAPI.setAlias(slug: link.slug, token: token, alias: alias)
            alias = url.lastPathComponent
            store.setLinkURL(url, for: countdown.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeKeepsake() async {
        guard let access = Coffin.sharedAccess(for: countdown) else { return }
        makingKeepsake = true
        defer { makingKeepsake = false }
        do {
            keepsake = try await Keepsake.make(for: countdown, access: access)
            Analytics.log(.imageExported, slug: link.slug, source: "keepsake")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - The keepsake

/// Everything the coffin held, to keep: a PDF guestbook (a cover, then each note with its photos)
/// and a ZIP with the PDF, the notes as text, and every photo and video as files. Made on the
/// phone, so names and notes in any language come out right.
enum Keepsake {
    struct Note {
        let contribution: Coffin.Contribution
        var photos: [UIImage] = []
        var video: Data?
    }

    enum Failure: LocalizedError {
        case empty
        var errorDescription: String? { L("The coffin is empty, so there's nothing to keep yet.") }
    }

    @MainActor
    static func make(for countdown: Countdown, access: (slug: String, token: String)) async throws -> [URL] {
        let state = try await LiveLinkAPI.coffin(slug: access.slug, token: access.token)
        guard !state.contributions.isEmpty else { throw Failure.empty }
        var notes: [Note] = []
        for contribution in state.contributions {
            var note = Note(contribution: contribution)
            for index in 0..<contribution.photos {
                if let data = try? await LiveLinkAPI.coffinPhoto(slug: access.slug, token: access.token, id: contribution.id, index: index),
                   let image = UIImage(data: data) {
                    note.photos.append(image)
                }
            }
            if contribution.hasVideo == true {
                note.video = try? await LiveLinkAPI.coffinVideo(slug: access.slug, token: access.token, id: contribution.id)
            }
            notes.append(note)
        }

        let name = fileName(countdown.title)
        let folder = URL.temporaryDirectory.appending(path: "\(name) Keepsake", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder.appending(path: "Photos"), withIntermediateDirectories: true)
        let pdf = folder.appending(path: "\(name) Guestbook.pdf")
        try guestbook(countdown, notes: notes).write(to: pdf)
        try text(countdown, notes: notes).write(to: folder.appending(path: "Notes.txt"), atomically: true, encoding: .utf8)
        for (n, note) in notes.enumerated() {
            let who = fileName(note.contribution.name)
            for (i, photo) in note.photos.enumerated() {
                try photo.jpegData(compressionQuality: 0.92)?.write(to: folder.appending(path: "Photos/\(n + 1) \(who)\(i > 0 ? " \(i + 1)" : "").jpg"))
            }
            if let video = note.video {
                try video.write(to: folder.appending(path: "Photos/\(n + 1) \(who).mp4"))
            }
        }
        let zip = URL.temporaryDirectory.appending(path: "\(name) Keepsake.zip")
        try zipped(folder, to: zip)
        return [pdf, zip]
    }

    /// The guestbook: US Letter, a cover page, then the notes flowing page to page.
    static func guestbook(_ countdown: Countdown, notes: [Note]) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 54
        let width = page.width - margin * 2
        let accent = UIColor(countdown.style.accentColor)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            var y = margin
            func newPage() { context.beginPage(); y = margin }
            func draw(_ string: String, _ font: UIFont, _ color: UIColor = .black, after spacing: CGFloat = 6) {
                let text = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
                let height = ceil(text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                    options: [.usesLineFragmentOrigin], context: nil).height)
                if y + height > page.height - margin { newPage() }
                text.draw(with: CGRect(x: margin, y: y, width: width, height: height), options: [.usesLineFragmentOrigin], context: nil)
                y += height + spacing
            }
            func draw(_ image: UIImage) {
                let scale = min(width / image.size.width, 380 / image.size.height, 1)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                if y + size.height > page.height - margin { newPage() }
                image.draw(in: CGRect(x: margin, y: y, width: size.width, height: size.height))
                y += size.height + 10
            }

            // Cover.
            newPage()
            y = 220
            draw(countdown.title, .systemFont(ofSize: 34, weight: .bold), after: 10)
            draw(countdown.targetDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year()), .systemFont(ofSize: 16), .darkGray, after: 24)
            if let counted = Recap.counted(countdown) { draw(L("\(counted) counted"), .systemFont(ofSize: 18, weight: .semibold), accent) }
            draw(L("\(notes.count) notes from everyone who counted down"), .systemFont(ofSize: 16), .darkGray)

            // The notes.
            newPage()
            for note in notes {
                draw(note.contribution.name, .systemFont(ofSize: 18, weight: .bold), accent, after: 2)
                draw(note.contribution.createdAt.formatted(.dateTime.month(.wide).day().year()), .systemFont(ofSize: 11), .gray, after: 8)
                if !note.contribution.text.isEmpty { draw(note.contribution.text, .systemFont(ofSize: 14), after: 10) }
                note.photos.forEach(draw)
                if note.video != nil { draw(L("A video came with this note. It's in the ZIP."), .italicSystemFont(ofSize: 12), .gray) }
                y += 18
            }
        }
    }

    static func text(_ countdown: Countdown, notes: [Note]) -> String {
        let header = "\(countdown.title)\n\(countdown.targetDate.formatted(.dateTime.month(.wide).day().year()))\n\n"
        return header + notes.map { note in
            let extras = [note.photos.isEmpty ? nil : L("\(note.photos.count) photos"),
                          note.video == nil ? nil : L("a video")].compactMap { $0 }
            return "\(note.contribution.name), \(note.contribution.createdAt.formatted(.dateTime.month(.wide).day().year()))\n"
                + (note.contribution.text.isEmpty ? "" : "\(note.contribution.text)\n")
                + (extras.isEmpty ? "" : "(\(extras.formatted(.list(type: .and))))\n")
        }.joined(separator: "\n")
    }

    /// Zips a folder with the system's own archiver: coordinating a read "for uploading" hands
    /// back a ZIP of the directory.
    static func zipped(_ folder: URL, to destination: URL) throws {
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinatorError) { zip in
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: zip, to: destination)
            } catch {
                copyError = error
            }
        }
        if let error = coordinatorError ?? copyError { throw error }
    }

    static func fileName(_ text: String) -> String {
        let cleaned = text.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Countdown" : String(cleaned.prefix(60))
    }
}
