import AppKit
import SwiftUI

/// From Calendar on the Mac: the next 90 days of events, ticked to become countdowns. The same
/// rules as the iPhone: a scene from the title, the event's repeat when we can follow it, and what
/// doesn't fit the free tier waits for Unlimited.
struct CalendarImportView: View {
    let store: CountdownStore
    let onDone: () -> Void
    let onLimit: () -> Void

    private enum Phase { case loading, denied, ready([CalendarEventRow]) }

    @State private var phase = Phase.loading
    @State private var picked = Set<String>()
    /// How many picks were held back by the free limit on the last Add.
    @State private var heldBack = 0

    private var imported: Set<String> { Set(store.countdowns.compactMap(\.extras.calendarEventID)) }

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            HStack {
                if heldBack > 0 {
                    Text("\(heldBack) didn't fit the free tier.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Unlock Unlimited", action: onLimit)
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(Color.countdownulaBlood)
                }
                Spacer()
                Button("Cancel", action: onDone)
                    .keyboardShortcut(.cancelAction)
                Button(picked.isEmpty ? "Add" : "Add \(picked.count)", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(picked.isEmpty)
            }
            .padding(14)
        }
        .frame(width: 440, height: 560)
        .task { phase = await CalendarEvents.upcoming().map(Phase.ready) ?? .denied }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .denied:
            ContentUnavailableView {
                Label("No Access to Calendars", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text("Allow Count Downcula to read your calendars in System Settings to pick events here. Events stay on your Mac; only the countdowns you add sync.")
            } actions: {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .ready(rows) where rows.isEmpty:
            ContentUnavailableView("Nothing Coming Up", systemImage: "calendar",
                                   description: Text("There are no events in your calendars for the next 90 days."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .ready(rows):
            List {
                if let room = CountdownImport.room(in: store.countdowns, unlocked: store.entitlements.isUnlocked) {
                    Text(room == 0
                         ? "Free includes \(SharedConfig.freeActiveLimit) countdowns at a time, and you're there. Pick what you like; Unlimited adds them all."
                         : "Free includes \(SharedConfig.freeActiveLimit) at a time, so \(room) more will fit. Pick more and Unlimited adds the rest.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(CalendarEvents.byMonth(rows), id: \.title) { month in
                    Section(month.title) {
                        ForEach(month.rows) { row in rowView(row) }
                    }
                }
            }
        }
    }

    private func rowView(_ row: CalendarEventRow) -> some View {
        let added = row.externalID.map(imported.contains) ?? false
        let selected = picked.contains(row.id)
        return Button {
            if selected { picked.remove(row.id) } else { picked.insert(row.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: added ? "checkmark.circle" : selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(added ? Color.secondary : selected ? Color.countdownulaBlood : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                    Text(row.isAllDay
                         ? row.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                         : row.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                        + Text(row.repetition.map { " · \($0.label)" } ?? "")
                        + Text(added ? " · Added" : "")
                }
                .font(.callout)
                Spacer()
                Circle().fill(row.calendarColor).frame(width: 8, height: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(added)
    }

    /// Adds what fits and closes; with picks held back by the free limit, stays open on them so
    /// Unlock Unlimited and Add again finishes the job.
    private func add() {
        guard case let .ready(rows) = phase else { return }
        let chosen = rows.filter { picked.contains($0.id) }
        let held = store.addImported(chosen.map(\.countdown), source: "calendar")
        guard !held.isEmpty else { return onDone() }
        let heldIDs = Set(held.compactMap(\.extras.calendarEventID))
        picked = Set(chosen.filter { $0.externalID.map(heldIDs.contains) ?? false }.map(\.id))
        heldBack = held.count
    }
}
