import AVKit
import CoreTransferable
import PhotosUI
import SwiftUI

// MARK: - Detail screen section

/// The sealed coffin on a shared countdown's detail screen: how many are sealed, your own, a way
/// to add one, and at zero, the reveal.
struct CoffinSection: View {
    @Environment(Router.self) private var router
    let countdown: Countdown
    let now: Date

    @State private var state: Coffin.State?
    @State private var composing = false
    @State private var revealing = false
    @State private var errorMessage: String?

    var body: some View {
        if let access = Coffin.access(for: countdown) {
            content(access)
                .task(id: "\(countdown.id)-\(countdown.isPast(at: now))") { await load(access) }
                .sheet(isPresented: $composing) {
                    CoffinComposeSheet(countdown: countdown, access: access) { await load(access) }
                }
                .fullScreenCover(isPresented: $revealing) {
                    CoffinRevealView(countdown: countdown, access: access, initial: state)
                }
                // "Open the Coffin" under the alert at zero.
                .onChange(of: router.pending, initial: true) { _, pending in
                    guard pending == .openCoffin(countdown.id), countdown.isPast(at: Date()) || countdown.countsUp else { return }
                    router.pending = nil
                    revealing = true
                }
                .alert("Sealed Coffin", isPresented: Binding(get: { errorMessage != nil },
                                                            set: { if !$0 { errorMessage = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(errorMessage ?? "")
                }
        }
    }

    @ViewBuilder
    private func content(_ access: (slug: String, token: String)) -> some View {
        let open = state?.open ?? countdown.isPast(at: now)
        let count = state?.sealedCount ?? 0
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("🦇").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sealed Coffin").font(.headline)
                    Text(summary(open: open, count: count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if open {
                Button {
                    revealing = true
                } label: {
                    Label(count == 0 ? "The Coffin Is Empty" : "Open the Coffin", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(count == 0)
            } else {
                let mine = state?.contributions.filter(\.mine) ?? []
                ForEach(mine) { contribution in
                    HStack {
                        Image(systemName: contribution.hasPhoto ? "photo" : "text.quote")
                            .foregroundStyle(.secondary)
                        Text(contribution.text.isEmpty ? "A photo" : contribution.text)
                            .lineLimit(1)
                        Spacer()
                        Button(role: .destructive) {
                            Task { await remove(contribution, access) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Take it back out")
                    }
                    .font(.subheadline)
                }
                Button {
                    composing = true
                } label: {
                    Label("Add to the Coffin", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .controlSize(.large)
    }

    private func summary(open: Bool, count: Int) -> String {
        if open {
            return count == 0 ? L("Nobody left anything this time.") : L("\(count) notes are waiting.")
        }
        return count == 0 ? L("Leave a note or photo. Opens for everyone at zero.") : L("\(count) sealed. Opens for everyone at zero.")
    }

    private func load(_ access: (slug: String, token: String)) async {
        state = try? await LiveLinkAPI.coffin(slug: access.slug, token: access.token)
    }

    private func remove(_ contribution: Coffin.Contribution, _ access: (slug: String, token: String)) async {
        do {
            try await LiveLinkAPI.removeFromCoffin(slug: access.slug, token: access.token, id: contribution.id)
            await load(access)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Adding

struct CoffinComposeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let countdown: Countdown
    let access: (slug: String, token: String)
    let onAdded: () async -> Void

    /// Remembered so people only type their name once.
    @AppStorage("Coffin.name") private var name = ""
    @State private var text = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photos: [UIImage] = []
    @State private var videoItem: PhotosPickerItem?
    @State private var video: URL?
    @State private var preparingVideo = false
    @State private var sending = false
    @State private var errorMessage: String?

    /// A Host Pass lets each note carry several photos and a short video.
    private var hosted: Bool { Coffin.isHosted(countdown) }
    private var maxPhotos: Int { Coffin.maxPhotos(hosted: hosted) }

    private var canSend: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty) && !sending && !preparingVideo
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                        .onChange(of: name) { _, new in if new.count > Coffin.maxName { name = String(new.prefix(Coffin.maxName)) } }
                } footer: {
                    Text("Shown with your note when the coffin opens.")
                }
                Section {
                    TextField("A note for when it's here", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .onChange(of: text) { _, new in if new.count > Coffin.maxText { text = String(new.prefix(Coffin.maxText)) } }
                    if !photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(photos.enumerated()), id: \.offset) { _, photo in
                                    Image(uiImage: photo)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: photos.count == 1 ? 260 : 140, height: photos.count == 1 ? 200 : 140)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: maxPhotos, matching: .images) {
                        Label(photos.isEmpty ? (maxPhotos > 1 ? "Add Photos" : "Add a Photo")
                                             : (maxPhotos > 1 ? "Change Photos" : "Change Photo"), systemImage: "photo")
                    }
                    if hosted {
                        PhotosPicker(selection: $videoItem, matching: .videos) {
                            Label(preparingVideo ? "Preparing Video…" : video == nil ? "Add a Short Video" : "Change Video",
                                  systemImage: "video")
                        }
                        .disabled(preparingVideo)
                        if video != nil {
                            Text("Video added. The first \(Int(Coffin.maxVideoSeconds)) seconds are kept.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Sealed until \(countdown.targetDate.formatted(.dateTime.month(.wide).day().hour().minute())). Nobody sees it before then, not even the owner. \(text.count)/\(Coffin.maxText)")
                }
            }
            .navigationTitle("Add to the Coffin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "Sealing…" : "Seal It") { Task { await send() } }
                        .disabled(!canSend)
                }
            }
            .onChange(of: photoItems) { _, items in
                Task {
                    var loaded: [UIImage] = []
                    for item in items.prefix(maxPhotos) {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = PhoneStore.prepareImage(data)?.preview {
                            loaded.append(image)
                        }
                    }
                    photos = loaded
                }
            }
            .onChange(of: videoItem) { _, item in
                guard let item else { return }
                Task {
                    preparingVideo = true
                    defer { preparingVideo = false }
                    do {
                        guard let movie = try await item.loadTransferable(type: PickedMovie.self) else { return }
                        video = try await CoffinVideo.prepare(movie.url)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .alert("Couldn't seal it", isPresented: Binding(get: { errorMessage != nil },
                                                             set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            let jpegs = photos.compactMap { LinkBackdrop.jpeg($0, maxDimension: 1080) }
            let added = try await LiveLinkAPI.addToCoffin(slug: access.slug, token: access.token,
                                                          name: name.trimmingCharacters(in: .whitespaces),
                                                          text: text.trimmingCharacters(in: .whitespacesAndNewlines), photos: jpegs)
            if let video, let data = try? Data(contentsOf: video) {
                try await LiveLinkAPI.addCoffinVideo(slug: access.slug, token: access.token, id: added.id, video: data)
            }
            await onAdded()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - The reveal

/// Opening the coffin at zero: confetti, then everyone's notes arriving one after another.
struct CoffinRevealView: View {
    @Environment(\.dismiss) private var dismiss
    let countdown: Countdown
    let access: (slug: String, token: String)
    let initial: Coffin.State?

    @State private var state: Coffin.State?
    @State private var shown = 0
    @State private var reported: Set<String> = []
    @State private var confettiID = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    Text("🦇").font(.system(size: 56))
                    Text("The coffin is open")
                        .font(countdown.style.font(.largeTitle))
                        .multilineTextAlignment(.center)
                    Text(countdown.title)
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    ForEach(Array((state?.contributions ?? []).prefix(shown).enumerated()), id: \.element.id) { _, contribution in
                        CoffinCard(contribution: contribution, access: access, accent: countdown.style.accentColor)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .contextMenu { menu(for: contribution) }
                    }
                }
                .padding()
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .overlay {
                ConfettiView(accent: countdown.style.accentColor)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .id(confettiID)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                state = initial
                if let fresh = try? await LiveLinkAPI.coffin(slug: access.slug, token: access.token) { state = fresh }
                // One at a time, like opening letters.
                for index in 0..<(state?.contributions.count ?? 0) {
                    try? await Task.sleep(for: .milliseconds(index == 0 ? 900 : 650))
                    withAnimation(.spring(duration: 0.5)) { shown = index + 1 }
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: shown)
        }
    }

    @ViewBuilder
    private func menu(for contribution: Coffin.Contribution) -> some View {
        if state?.isOwner == true || contribution.mine {
            Button("Remove", systemImage: "trash", role: .destructive) {
                Task {
                    try? await LiveLinkAPI.removeFromCoffin(slug: access.slug, token: access.token, id: contribution.id)
                    state?.contributions.removeAll { $0.id == contribution.id }
                    shown = min(shown, state?.contributions.count ?? 0)
                }
            }
        }
        if !contribution.mine {
            Button(reported.contains(contribution.id) ? "Reported" : "Report", systemImage: "flag") {
                Task {
                    try? await LiveLinkAPI.reportInCoffin(slug: access.slug, token: access.token, id: contribution.id)
                    reported.insert(contribution.id)
                }
            }
            .disabled(reported.contains(contribution.id))
        }
    }
}

/// One opened note: who it's from, what they wrote, its photos and video.
struct CoffinCard: View {
    let contribution: Coffin.Contribution
    let access: (slug: String, token: String)
    let accent: Color
    @State private var photos: [Int: UIImage] = [:]
    @State private var video: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if contribution.photos > 0 {
                TabView {
                    ForEach(0..<contribution.photos, id: \.self) { index in
                        ZStack {
                            Color.primary.opacity(0.06)
                            if let photo = photos[index] {
                                Image(uiImage: photo).resizable().scaledToFill()
                            } else {
                                ProgressView()
                            }
                        }
                        .clipped()
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: contribution.photos > 1 ? .automatic : .never))
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if contribution.hasVideo == true {
                ZStack {
                    Color.primary.opacity(0.06)
                    if let video {
                        VideoPlayer(player: video)
                    } else {
                        ProgressView()
                    }
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if !contribution.text.isEmpty {
                Text(contribution.text)
                    .font(.body)
            }
            Text("From \(contribution.name)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task(id: contribution.id) {
            for index in 0..<contribution.photos where photos[index] == nil {
                if let data = try? await LiveLinkAPI.coffinPhoto(slug: access.slug, token: access.token, id: contribution.id, index: index) {
                    photos[index] = UIImage(data: data)
                }
            }
            // Videos are private, so they're downloaded with the key and played from a file.
            if contribution.hasVideo == true, video == nil,
               let data = try? await LiveLinkAPI.coffinVideo(slug: access.slug, token: access.token, id: contribution.id) {
                let file = URL.temporaryDirectory.appending(path: "coffin-\(contribution.id).mp4")
                try? data.write(to: file)
                video = AVPlayer(url: file)
            }
        }
    }
}

// MARK: - Videos

/// A video picked from Photos, copied out of the picker's temporary location.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = URL.temporaryDirectory.appending(path: "picked-\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

/// Fits a picked video into a coffin note: the first 15 seconds, as an MP4 small enough to send in
/// one request, stepping down in quality until it is.
enum CoffinVideo {
    enum Failure: LocalizedError {
        case tooLarge, couldNotExport
        var errorDescription: String? {
            switch self {
            case .tooLarge: L("That video is too large even at a lower quality. Try a shorter one.")
            case .couldNotExport: L("Couldn't prepare that video. Try another.")
            }
        }
    }

    static func prepare(_ source: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let range = CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, CMTime(seconds: Coffin.maxVideoSeconds, preferredTimescale: 600)))
        for preset in [AVAssetExportPreset1280x720, AVAssetExportPreset960x540, AVAssetExportPreset640x480] {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            let output = URL.temporaryDirectory.appending(path: "coffin-upload-\(UUID().uuidString).mp4")
            session.outputURL = output
            session.outputFileType = .mp4
            session.timeRange = range
            session.shouldOptimizeForNetworkUse = true
            await session.export()
            guard session.status == .completed else { continue }
            let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? .max
            if size <= Coffin.maxVideoBytes { return output }
            try? FileManager.default.removeItem(at: output)
        }
        throw Failure.tooLarge
    }
}
