import PhotosUI
import SwiftUI

struct CountdownEditorView: View {
    @Environment(PhoneStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let original: Countdown?

    @State private var title: String
    @State private var details: String
    @State private var kind: Countdown.Kind
    @State private var targetDate: Date
    @State private var days = 0
    @State private var hours = 0
    @State private var minutes = 25
    @State private var isPinned: Bool
    @State private var photoItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var imageUpdate: ImageUpdate = .unchanged
    @State private var isLoadingPhoto = false

    init(original: Countdown?) {
        self.original = original
        _title = State(initialValue: original?.title ?? "")
        _details = State(initialValue: original?.details ?? "")
        _kind = State(initialValue: original?.kind ?? .event)
        _targetDate = State(initialValue: original?.targetDate
            ?? Calendar.current.date(byAdding: .day, value: 7, to: Date())!)
        _isPinned = State(initialValue: original?.isPinned ?? false)
        if let original, original.kind == .timer {
            let remaining = max(0, Int(original.targetDate.timeIntervalSinceNow))
            _days = State(initialValue: remaining / 86_400)
            _hours = State(initialValue: remaining % 86_400 / 3_600)
            _minutes = State(initialValue: remaining % 3_600 / 60)
        }
    }

    private var durationSeconds: Int { days * 86_400 + hours * 3_600 + minutes * 60 }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (kind == .event || durationSeconds > 0) && !isLoadingPhoto
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    photoSection
                }
                .listRowInsets(EdgeInsets())

                Section {
                    TextField("Title", text: $title, prompt: Text("Summer vacation"))
                        .font(.headline)
                    TextField("Description", text: $details, prompt: Text("Two weeks on the coast"), axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Picker("Type", selection: $kind) {
                        Text("Date & Time").tag(Countdown.Kind.event)
                        Text("Timer").tag(Countdown.Kind.timer)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)

                    if kind == .event {
                        DatePicker("Counts down to", selection: $targetDate, displayedComponents: [.date, .hourAndMinute])
                    } else {
                        durationPicker
                    }
                } footer: {
                    if kind == .timer && original?.kind == .timer {
                        Text("Saving restarts the timer from now.")
                    }
                }

                Section {
                    Toggle("Pin", isOn: $isPinned)
                } footer: {
                    Text("Pinned countdowns are featured in widgets and go live on the Lock Screen during their final 8 hours.")
                }
            }
            .navigationTitle(original == nil ? "New Countdown" : "Edit Countdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(original == nil ? "Add" : "Save", action: save)
                        .disabled(!canSave)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                loadPhoto(item)
            }
            .task {
                if let original { previewImage = store.image(for: original) }
            }
        }
    }

    private var photoSection: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            ZStack {
                if let previewImage {
                    Color.clear.overlay {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFill()
                    }
                } else {
                    LinearGradient.countdownulaNight
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 34))
                        Text("Add a Photo")
                            .font(.callout.weight(.medium))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                }
                if isLoadingPhoto {
                    ProgressView().controlSize(.large).tint(.white)
                }
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if previewImage != nil {
                Button {
                    previewImage = nil
                    photoItem = nil
                    imageUpdate = .remove
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Remove photo")
                .padding(10)
            }
        }
    }

    private var durationPicker: some View {
        HStack(spacing: 0) {
            wheel("days", selection: $days, range: 0...365)
            wheel("hr", selection: $hours, range: 0...23)
            wheel("min", selection: $minutes, range: 0...59)
        }
        .frame(height: 150)
    }

    private func wheel(_ unit: String, selection: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Picker(unit, selection: selection) {
            ForEach(range, id: \.self) { Text("\($0) \(unit)").tag($0) }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // MARK: - Actions

    private func loadPhoto(_ item: PhotosPickerItem) {
        isLoadingPhoto = true
        Task {
            defer { isLoadingPhoto = false }
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            let prepared = await Task.detached(priority: .userInitiated) { PhoneStore.prepareImage(data) }.value
            guard let prepared else { return }
            previewImage = prepared.preview
            imageUpdate = prepared.update
        }
    }

    private func save() {
        let now = Date()
        var countdown = original ?? Countdown(title: "", details: "", targetDate: now)
        countdown.title = title.trimmingCharacters(in: .whitespaces)
        countdown.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        countdown.kind = kind
        countdown.isPinned = isPinned

        if kind == .event {
            countdown.targetDate = targetDate
            if original == nil { countdown.createdAt = now }
        } else {
            countdown.createdAt = now
            countdown.targetDate = now.addingTimeInterval(TimeInterval(durationSeconds))
        }

        store.upsert(countdown, image: imageUpdate)
        // New timers go live on the Lock Screen right away (pinned countdowns are handled by the store).
        if original == nil, kind == .timer { LiveActivities.start(countdown) }
        dismiss()
    }
}
