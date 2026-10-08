import PhotosUI
import SwiftUI

// MARK: - Detail screen section

/// The sealed coffin on a shared countdown's detail screen: how many are sealed, your own, a way
/// to add one, and at zero, the reveal.
struct CoffinSection: View {
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
            return count == 0 ? "Nobody left anything this time." : "\(count) \(count == 1 ? "note is" : "notes are") waiting."
        }
        let sealed = count == 0 ? "Leave a note or photo" : "\(count) sealed"
        return "\(sealed). Opens for everyone at zero."
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
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var sending = false
    @State private var errorMessage: String?

    private var canSend: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photo != nil) && !sending
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
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(photo == nil ? "Add a Photo" : "Change Photo", systemImage: "photo")
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
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        photo = PhoneStore.prepareImage(data)?.preview
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
            let jpeg = photo.flatMap { LinkBackdrop.jpeg($0, maxDimension: 1080) }
            try await LiveLinkAPI.addToCoffin(slug: access.slug, token: access.token,
                                              name: name.trimmingCharacters(in: .whitespaces),
                                              text: text.trimmingCharacters(in: .whitespacesAndNewlines), photo: jpeg)
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

/// One opened note: who it's from, what they wrote, their photo.
struct CoffinCard: View {
    let contribution: Coffin.Contribution
    let access: (slug: String, token: String)
    let accent: Color
    @State private var photo: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if contribution.hasPhoto {
                ZStack {
                    Color.primary.opacity(0.06)
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
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
            guard contribution.hasPhoto, photo == nil,
                  let data = try? await LiveLinkAPI.coffinPhoto(slug: access.slug, token: access.token, id: contribution.id)
            else { return }
            photo = UIImage(data: data)
        }
    }
}
