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
    @State private var style: CountdownStyle
    @State private var milestones: [Milestone]
    @State private var extras: CountdownExtras
    @State private var tracksSavings: Bool
    @State private var savingsPerDay: Double
    @State private var showingCustomMilestone = false
    @State private var previewImage: UIImage?
    @State private var imageUpdate: ImageUpdate = .unchanged
    @State private var isLoadingPhoto = false
    @State private var isLocating = false
    @State private var templateError: String?
    @State private var showingPaywall = false

    init(original: Countdown?) {
        self.original = original
        _title = State(initialValue: original?.title ?? "")
        _details = State(initialValue: original?.details ?? "")
        _kind = State(initialValue: original?.kind ?? .event)
        _targetDate = State(initialValue: original?.targetDate
            ?? Calendar.current.date(byAdding: .day, value: 7, to: Date())!)
        _isPinned = State(initialValue: original?.isPinned ?? false)
        _style = State(initialValue: original?.style ?? .default)
        _milestones = State(initialValue: original?.milestones ?? [])
        _extras = State(initialValue: original?.extras ?? CountdownExtras())
        _tracksSavings = State(initialValue: original?.extras.savings != nil)
        _savingsPerDay = State(initialValue: original?.extras.savings?.amountPerDay ?? 10)
        if let original, original.kind == .timer {
            let remaining = max(0, Int(original.targetDate.timeIntervalSinceNow))
            _days = State(initialValue: remaining / 86_400)
            _hours = State(initialValue: remaining % 86_400 / 3_600)
            _minutes = State(initialValue: remaining % 3_600 / 60)
        }
    }

    /// The countdown as it would be saved, for the live previews.
    private var draft: Countdown {
        var countdown = original ?? Countdown(title: "", details: "", targetDate: targetDate)
        countdown.title = title
        countdown.kind = kind
        countdown.style = style
        countdown.milestones = milestones
        countdown.extras = finalExtras
        countdown.hasImage = previewImage != nil
        if kind == .event || kind == .countUp {
            countdown.targetDate = targetDate
        } else {
            countdown.createdAt = Date()
            countdown.targetDate = Date().addingTimeInterval(TimeInterval(durationSeconds))
        }
        return countdown
    }

    /// Extras as they'd be saved: savings only on count-ups, yearly repeat only on dates.
    private var finalExtras: CountdownExtras {
        var extras = extras
        extras.savings = kind == .countUp && tracksSavings && savingsPerDay > 0
            ? Savings(amountPerDay: savingsPerDay, currencyCode: currencyCode) : nil
        if kind != .event {
            extras.repeatsYearly = false
            extras.auto = nil
        }
        // A new or moved date becomes the anchor the next years are counted from.
        if !extras.repeatsYearly || targetDate != original?.targetDate { extras.yearlyAnchor = nil }
        return extras
    }

    private var currencyCode: String {
        original?.extras.savings?.currencyCode ?? Locale.current.currency?.identifier ?? "USD"
    }

    private var durationSeconds: Int { days * 86_400 + hours * 3_600 + minutes * 60 }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (kind != .timer || durationSeconds > 0)
            && !isLoadingPhoto && !isLocating
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    StyledCountdownCard(countdown: draft, now: Date(), previewImage: previewImage, height: 210)
                        .overlay {
                            if isLoadingPhoto { ProgressView().controlSize(.large).tint(.white) }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    NavigationLink {
                        StyleEditorView(draft: draft, style: $style, previewImage: $previewImage,
                                        imageUpdate: $imageUpdate, isLoadingPhoto: $isLoadingPhoto)
                    } label: {
                        Label("Appearance", systemImage: "paintpalette")
                    }
                }

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
                        Text("Since").tag(Countdown.Kind.countUp)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)

                    switch kind {
                    case .event:
                        if let auto = extras.auto {
                            LabeledContent("Next \(auto.kind.name.lowercased())") {
                                Text(targetDate, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                            }
                        } else {
                            DatePicker("Counts down to", selection: $targetDate, displayedComponents: [.date, .hourAndMinute])
                            Toggle("Repeats every year", isOn: $extras.repeatsYearly)
                        }
                    case .countUp:
                        DatePicker("Started", selection: $targetDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    case .timer:
                        durationPicker
                    }
                } footer: {
                    switch kind {
                    case .timer where original?.kind == .timer:
                        Text("Saving restarts the timer from now.")
                    case .countUp:
                        Text("Counts the time since something began: a sober date, a quit date, an anniversary.")
                    case .event where extras.auto?.needsLocation == true:
                        Text("Moves on to the next \(extras.auto!.kind.name.lowercased()) by itself, worked out for your rough location when you added it.")
                    case .event where extras.auto != nil:
                        Text("Moves on to the next full moon by itself.")
                    case .event where extras.repeatsYearly:
                        Text("After the day passes it rolls over to next year. Good for birthdays and anniversaries.")
                    default:
                        EmptyView()
                    }
                }

                if kind == .countUp {
                    Section {
                        Toggle("Track money saved", isOn: $tracksSavings)
                        if tracksSavings {
                            LabeledContent("Per day") {
                                TextField("Amount", value: $savingsPerDay, format: .currency(code: currencyCode))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    } footer: {
                        Text("What it used to cost you each day, like a pack of cigarettes.")
                    }
                }

                if !withinFreeLimit {
                    Section {
                        Button("Unlock Unlimited…") { showingPaywall = true }
                            .foregroundStyle(Color.countdownulaBlood)
                    } footer: {
                        Text("Free includes \(SharedConfig.freeActiveLimit) active countdowns at a time. Unlock Unlimited, or finish or delete one first.")
                    }
                }

                milestonesSection

                Section {
                    Toggle("Alerts in the Count's voice", isOn: Binding(
                        get: { extras.voice == .count },
                        set: { extras.voice = $0 ? .count : .standard }
                    ))
                } footer: {
                    if extras.voice == .count {
                        Text("“\(CountLines.completion(for: draft))”")
                    } else {
                        Text("Milestone and finish alerts, written in Count Downcula's own voice.")
                    }
                }

                Section {
                    Toggle("Pin", isOn: $isPinned)
                } footer: {
                    Text("Pinned countdowns are featured in widgets and go live on the Lock Screen during their final 8 hours.")
                }
            }
            .navigationTitle(original == nil ? "New Countdown" : "Edit Countdown")
            .onChange(of: kind) { _, new in
                // A count-up starts in the past; a countdown ends in the future.
                if new == .countUp, targetDate > Date() { targetDate = Date() }
                if new == .event, targetDate <= Date() {
                    targetDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
                }
                if new == .countUp, milestones.isEmpty { milestones = MilestonePreset.countUpDefaults() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if original == nil {
                    ToolbarItem(placement: .principal) {
                        templatesMenu
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(original == nil ? "Add" : "Save", action: save)
                        .disabled(!canSave || !withinFreeLimit)
                }
            }
            .task {
                if let original { previewImage = store.image(for: original) }
            }
            .overlay {
                if isLocating {
                    ProgressView("Finding the sun…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .alert("Couldn't add that", isPresented: Binding(get: { templateError != nil },
                                                              set: { if !$0 { templateError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(templateError ?? "")
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
        }
    }

    // MARK: - Templates

    private var templatesMenu: some View {
        Menu {
            Section("Count up from") {
                ForEach(CountUpTemplate.allCases) { template in
                    Button(template.name, systemImage: template.symbol) { apply(template) }
                }
            }
            Section("Vampire hours") {
                ForEach(AutoDate.Kind.allCases, id: \.self) { kind in
                    Button("Next \(kind.name)", systemImage: kind.symbolName) {
                        Task { await apply(kind) }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("New Countdown").font(.headline)
                Image(systemName: "chevron.down.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
        .accessibilityLabel("Start from a template")
    }

    private func apply(_ template: CountUpTemplate) {
        kind = .countUp
        title = template.name
        details = template.details
        targetDate = Calendar.current.startOfDay(for: Date())
        style = template.style
        milestones = MilestonePreset.countUpDefaults()
        tracksSavings = template.suggestsSavings
    }

    private func apply(_ autoKind: AutoDate.Kind) async {
        isLocating = true
        defer { isLocating = false }
        do {
            let filled = try await AutoDateTemplate.fill(autoKind)
            kind = .event
            title = filled.title
            details = filled.details
            targetDate = filled.targetDate
            style = filled.style
            extras.repeatsYearly = false
            extras.auto = filled.auto
            extras.voice = .count
        } catch {
            templateError = error.localizedDescription
        }
    }

    // MARK: - Milestones

    private var milestonesSection: some View {
        let countdown = draft
        let scheduled = countdown.scheduledMilestones
        let outside = milestones.filter { m in !scheduled.contains { $0.id == m.id } }
        let presets = MilestonePreset.available(for: countdown, now: Date())

        return Section {
            ForEach(scheduled) { item in
                milestoneRow(item.milestone, date: item.date)
            }
            .onDelete { offsets in
                let ids = offsets.map { scheduled[$0].id }
                milestones.removeAll { ids.contains($0.id) }
            }
            ForEach(outside) { milestone in
                milestoneRow(milestone, date: nil)
            }
            .onDelete { offsets in
                let ids = offsets.map { outside[$0].id }
                milestones.removeAll { ids.contains($0.id) }
            }

            if countdown.countsUp, milestones.isEmpty {
                Button("Add Standard Milestones", systemImage: "flag.2.crossed") {
                    milestones = MilestonePreset.countUpDefaults()
                }
            }
            Menu {
                ForEach(presets) { preset in
                    let milestone = preset.milestone
                    Button("\(milestone.displayEmoji) \(milestone.title)") { milestones.append(milestone) }
                }
                if !presets.isEmpty { Divider() }
                Button("Custom…", systemImage: "pencil") { showingCustomMilestone = true }
            } label: {
                Label("Add Milestone", systemImage: "flag.badge.ellipsis")
            }
        } header: {
            Text("Milestones")
        } footer: {
            Text("Little moments along the way. Each one gets a notification and a celebration.")
        }
        .sheet(isPresented: $showingCustomMilestone) {
            CustomMilestoneSheet(range: countdown.countsUp
                ? Date()...Date().addingTimeInterval(20 * 365 * 86_400)
                : Date()...max(Date(), countdown.targetDate)) { milestones.append($0) }
        }
    }

    private func milestoneRow(_ milestone: Milestone, date: Date?) -> some View {
        HStack {
            Text(milestone.displayEmoji)
            Text(milestone.title)
            Spacer()
            if let date {
                Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Outside this countdown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    /// Saving keeps a free user within the limit; turning a finished countdown back into an active one counts.
    private var withinFreeLimit: Bool {
        store.entitlements.allowsSaving(draft, replacing: original, in: store.countdowns)
    }

    // MARK: - Actions

    private func save() {
        let now = Date()
        var countdown = original ?? Countdown(title: "", details: "", targetDate: now)
        countdown.title = title.trimmingCharacters(in: .whitespaces)
        countdown.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        countdown.kind = kind
        countdown.isPinned = isPinned
        countdown.style = style
        countdown.milestones = milestones
        countdown.extras = finalExtras

        if kind == .event || kind == .countUp {
            countdown.targetDate = targetDate
            if original == nil { countdown.createdAt = now }
        } else {
            countdown.createdAt = now
            countdown.targetDate = now.addingTimeInterval(TimeInterval(durationSeconds))
        }

        // A photo hidden behind another background would only waste iCloud space.
        let image: ImageUpdate = style.background.usesPhoto ? imageUpdate
            : (original?.hasImage == true || previewImage != nil ? .remove : .unchanged)
        store.upsert(countdown, image: image)
        // A published countdown's page follows the edit, photo and all.
        store.pushLinkUpdate(for: store.countdown(id: countdown.id) ?? countdown)
        // New timers go live on the Lock Screen right away (pinned countdowns are handled by the store).
        if original == nil, kind == .timer { LiveActivities.start(countdown) }
        dismiss()
    }
}

/// Name, emoji and moment for a milestone the presets don't cover.
private struct CustomMilestoneSheet: View {
    @Environment(\.dismiss) private var dismiss
    let range: ClosedRange<Date>
    let onAdd: (Milestone) -> Void

    @State private var title = ""
    @State private var emoji = "🎉"
    @State private var date: Date

    init(range: ClosedRange<Date>, onAdd: @escaping (Milestone) -> Void) {
        self.range = range
        self.onAdd = onAdd
        _date = State(initialValue: Date(timeIntervalSince1970:
            (range.lowerBound.timeIntervalSince1970 + range.upperBound.timeIntervalSince1970) / 2))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title, prompt: Text("Book the flights"))
                TextField("Emoji", text: $emoji)
                    .onChange(of: emoji) { _, new in
                        // One character is plenty.
                        if new.count > 1 { emoji = String(new.suffix(1)) }
                    }
                DatePicker("When", selection: $date, in: range)
            }
            .navigationTitle("New Milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(Milestone(title: title.trimmingCharacters(in: .whitespaces), emoji: emoji,
                                        trigger: .date(date)))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Quick starts for count-ups.
enum CountUpTemplate: CaseIterable, Identifiable {
    case sober, smokeFree, together, newJob

    var id: Self { self }

    var name: String {
        switch self {
        case .sober: "Sober"
        case .smokeFree: "Smoke-Free"
        case .together: "Together"
        case .newJob: "New Job"
        }
    }

    var symbol: String {
        switch self {
        case .sober: "leaf"
        case .smokeFree: "nosign"
        case .together: "heart"
        case .newJob: "briefcase"
        }
    }

    var details: String {
        switch self {
        case .sober: "One day at a time."
        case .smokeFree: "Every day without one counts."
        case .together: ""
        case .newJob: ""
        }
    }

    var style: CountdownStyle {
        switch self {
        case .sober: CountdownStyle(background: .scene(.mountains), font: .rounded, accent: RGBAColor(hex: 0x2F9E6E))
        case .smokeFree: CountdownStyle(background: .scene(.ocean), font: .rounded, accent: RGBAColor(hex: 0x1F6FB2))
        case .together: CountdownStyle(background: .scene(.blossoms), font: .serif, accent: RGBAColor(hex: 0xE0457B))
        case .newJob: CountdownStyle(background: .scene(.city), font: .expanded, accent: RGBAColor(hex: 0xFFC145))
        }
    }

    var suggestsSavings: Bool { self == .smokeFree }
}
