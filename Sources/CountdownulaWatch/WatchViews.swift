import SwiftUI

// MARK: - List

struct WatchCountdownList: View {
    @Environment(WatchStore.self) private var store
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            // Rows under a day old use self-updating timer text; everything else only needs a per-minute refresh.
            TimelineView(.everyMinute) { context in
                let now = context.date
                let upcoming = store.upcoming(at: now)
                let counting = store.countingUp
                let past = store.past(at: now)

                List {
                    if upcoming.isEmpty && counting.isEmpty {
                        EmptyWatchState(onAdd: { showingAdd = true })
                    }
                    ForEach(upcoming) { countdown in
                        NavigationLink(value: countdown.id) {
                            WatchCountdownRow(countdown: countdown, now: now)
                        }
                    }
                    if !counting.isEmpty {
                        Section("Counting Up") {
                            ForEach(counting) { countdown in
                                NavigationLink(value: countdown.id) {
                                    WatchCountdownRow(countdown: countdown, now: now)
                                }
                            }
                        }
                    }
                    if !past.isEmpty {
                        Section("Past") {
                            ForEach(past) { countdown in
                                NavigationLink(value: countdown.id) {
                                    WatchCountdownRow(countdown: countdown, now: now)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Count Downula")
            .navigationDestination(for: UUID.self) { id in
                WatchCountdownDetail(id: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus").foregroundStyle(.white)
                    }
                    .accessibilityLabel("New countdown")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddCountdownView()
            }
        }
    }
}

private struct EmptyWatchState: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            FangMark()
                .foregroundStyle(Color.countdownulaBlood)
                .frame(width: 44, height: 44)
            Text("No countdowns yet")
                .font(.headline)
            Text("Add one here or in Count Downula on your Mac.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Countdown", action: onAdd)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }
}

struct WatchCountdownRow: View {
    @Environment(WatchStore.self) private var store
    let countdown: Countdown
    let now: Date

    var body: some View {
        let isPast = countdown.isPast(at: now)

        HStack(spacing: 10) {
            Group {
                if let thumb = store.thumbnail(for: countdown) {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                } else if countdown.style.background != .automatic {
                    StyledBackdrop(style: countdown.style, dialRemaining: countdown.dialRemaining(at: now), dialPadding: 4)
                        .clipShape(Circle())
                } else {
                    FangDial(remaining: countdown.dialRemaining(at: now))
                        .foregroundStyle(isPast ? Color.secondary : countdown.style.accentColor)
                }
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Text(countdown.title)
                        .font(.headline)
                        .lineLimit(1)
                    if countdown.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
                CountdownTimeText(countdown: countdown, now: now)
                    .font(countdown.style.font(.title3))
                    .foregroundStyle(isPast ? Color.secondary : countdown.style.accentColor)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail

struct WatchCountdownDetail: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var confirmingDelete = false

    var body: some View {
        if let countdown = store.countdown(id: id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    let image = store.image(for: countdown)
                    if image != nil || countdown.style.background != .automatic {
                        StyledBackdrop(style: countdown.style, photo: image.map { Image(uiImage: $0) })
                            .frame(height: 90)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Text(countdown.title)
                        .font(countdown.style.font(.title3))

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        TimeGrid(parts: countdown.timeParts(at: context.date), style: countdown.style)
                    }

                    Text(countdown.targetDate, format: .dateTime.weekday(.abbreviated).month().day().hour().minute())
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !countdown.details.isEmpty {
                        Text(countdown.details)
                            .font(.body)
                    }

                    Button {
                        store.togglePin(countdown)
                    } label: {
                        Label(countdown.isPinned ? "Unpin" : "Pin", systemImage: countdown.isPinned ? "pin.slash" : "pin")
                    }

                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(countdown.kind == .timer ? "Timer" : countdown.countsUp ? "Since" : "Countdown")
            .confirmationDialog("Delete \(countdown.title)?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) {
                    dismiss()
                    store.delete(countdown)
                }
            }
        } else {
            Text("This countdown was deleted.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct TimeGrid: View {
    let parts: TimeParts
    var style = CountdownStyle.default

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                block(parts.days, "DAYS")
                block(parts.hours, "HRS")
            }
            GridRow {
                block(parts.minutes, "MIN")
                block(parts.seconds, "SEC")
            }
        }
        .opacity(parts.isPast ? 0.5 : 1)
    }

    private func block(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(String(format: "%02d", value))
                .font(style.font(size: 26))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(style.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Add

struct AddCountdownView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var kind: Countdown.Kind = .timer
    @State private var minutes = 25
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var isPinned = false

    private let durations = [1, 3, 5, 10, 15, 20, 25, 30, 45, 60, 90, 120, 180, 240, 480, 720]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)

                Picker("Type", selection: $kind) {
                    Text("Timer").tag(Countdown.Kind.timer)
                    Text("Date").tag(Countdown.Kind.event)
                }

                if kind == .timer {
                    Picker("Duration", selection: $minutes) {
                        ForEach(durations, id: \.self) { Text(Self.durationLabel($0)).tag($0) }
                    }
                } else {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                }

                Toggle("Pin", isOn: $isPinned)

                Button("Save", action: save)
                    .disabled(kind == .event && date <= .now)
            }
            .navigationTitle("New")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let now = Date()
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let target = kind == .timer ? now.addingTimeInterval(TimeInterval(minutes * 60)) : date
        let fallbackTitle = kind == .timer ? "\(Self.durationLabel(minutes)) timer" : "Countdown"
        store.add(Countdown(
            title: trimmed.isEmpty ? fallbackTitle : trimmed,
            details: "",
            targetDate: target,
            kind: kind,
            isPinned: isPinned,
            createdAt: now
        ))
        dismiss()
    }

    private static func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        return hours == hours.rounded() ? "\(Int(hours)) hr" : String(format: "%.1f hr", hours)
    }
}
