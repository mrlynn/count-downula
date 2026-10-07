import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    let store: CountdownStore
    let original: Countdown?
    /// Called with the saved countdown, or nil on cancel.
    let onFinish: (Countdown?) -> Void

    @State private var title: String
    @State private var details: String
    @State private var kind: Countdown.Kind
    @State private var targetDate: Date
    @State private var days = 0
    @State private var hours = 0
    @State private var minutes = 25
    @State private var previewImage: NSImage?
    @State private var imageUpdate: ImageUpdate = .unchanged
    @State private var isPinned: Bool
    @State private var isDropTargeted = false

    init(store: CountdownStore, original: Countdown?, onFinish: @escaping (Countdown?) -> Void) {
        self.store = store
        self.original = original
        self.onFinish = onFinish
        _title = State(initialValue: original?.title ?? "")
        _details = State(initialValue: original?.details ?? "")
        _kind = State(initialValue: original?.kind ?? .event)
        _targetDate = State(initialValue: original?.targetDate
            ?? Calendar.current.date(byAdding: .day, value: 7, to: Date())!)
        _previewImage = State(initialValue: original.flatMap { store.image(for: $0) })
        _isPinned = State(initialValue: original?.isPinned ?? false)
    }

    private var durationSeconds: Int { days * 86_400 + hours * 3_600 + minutes * 60 }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (kind != .timer || durationSeconds > 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    photoPicker
                }

                Section {
                    TextField("Title", text: $title, prompt: Text("Summer vacation"))
                    TextField("Description", text: $details, prompt: Text("Two weeks on the coast"), axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Picker("Type", selection: $kind) {
                        Text("Date & Time").tag(Countdown.Kind.event)
                        Text("Timer").tag(Countdown.Kind.timer)
                        Text("Since").tag(Countdown.Kind.countUp)
                    }
                    .pickerStyle(.segmented)

                    if kind == .event {
                        DatePicker("Counts down to", selection: $targetDate, displayedComponents: [.date, .hourAndMinute])
                    } else if kind == .countUp {
                        DatePicker("Started", selection: $targetDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    } else {
                        Stepper("\(days) day\(days == 1 ? "" : "s")", value: $days, in: 0...365)
                        Stepper("\(hours) hour\(hours == 1 ? "" : "s")", value: $hours, in: 0...23)
                        Stepper("\(minutes) minute\(minutes == 1 ? "" : "s")", value: $minutes, in: 0...59)
                        if original?.kind == .timer {
                            Text("Saving restarts the timer from now.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle("Pin to menu bar", isOn: $isPinned)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(original == nil ? "Create" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(14)
        }
        .frame(width: 440, height: 600)
        .onAppear {
            if let original, original.kind == .timer {
                let remaining = max(0, Int(original.targetDate.timeIntervalSinceNow))
                days = remaining / 86_400
                hours = remaining % 86_400 / 3_600
                minutes = remaining % 3_600 / 60
            }
        }
    }

    private var photoPicker: some View {
        VStack(spacing: 10) {
            ZStack {
                if let image = previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 160)
                        .frame(maxWidth: .infinity)
                        .clipped()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 30))
                        Text("Drop a photo here")
                            .font(.callout)
                    }
                    .foregroundStyle(.secondary)
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isDropTargeted ? Color.accentColor : .clear, lineWidth: 2)
            )
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                setImage(from: url)
                return true
            } isTargeted: { isDropTargeted = $0 }

            HStack {
                Button("Choose Photo…", action: choosePhoto)
                if previewImage != nil {
                    Button("Remove", role: .destructive) {
                        previewImage = nil
                        imageUpdate = .remove
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - Actions

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose a Photo"
        if panel.runModal() == .OK, let url = panel.url {
            setImage(from: url)
        }
    }

    private func setImage(from url: URL) {
        guard let prepared = CountdownStore.prepareImage(from: url) else { return }
        previewImage = prepared.preview
        imageUpdate = prepared.update
    }

    private func cancel() {
        onFinish(nil)
    }

    private func save() {
        var countdown = original ?? Countdown(title: "", details: "", targetDate: Date())
        countdown.title = title.trimmingCharacters(in: .whitespaces)
        countdown.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        countdown.kind = kind
        countdown.isPinned = isPinned

        if kind == .event || kind == .countUp {
            countdown.targetDate = targetDate
        } else {
            countdown.createdAt = Date()
            countdown.targetDate = Date().addingTimeInterval(TimeInterval(durationSeconds))
        }

        // A newly chosen photo should show even if the iPhone gave this countdown a scene or gradient.
        if case .set = imageUpdate, !countdown.style.background.usesPhoto { countdown.style.background = .photo }
        store.upsert(countdown, image: imageUpdate)
        onFinish(countdown)
    }
}
