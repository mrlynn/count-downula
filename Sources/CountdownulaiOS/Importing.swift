import Contacts
import ContactsUI
import SwiftUI

// MARK: - From Calendar

/// Picks events from the next 90 days of the person's calendars to turn into countdowns. Asks for
/// calendar access only when opened, and reads events on the device; only the countdowns made
/// from them sync.
struct CalendarImportSheet: View {
    @Environment(PhoneStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Hands back the countdowns to add; the list adds what fits the free tier.
    let onImport: ([Countdown]) -> Void

    private enum Phase { case loading, denied, ready([CalendarEventRow]) }

    @State private var phase = Phase.loading
    @State private var picked = Set<String>()

    private var imported: Set<String> { Set(store.countdowns.compactMap(\.extras.calendarEventID)) }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("From Calendar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(picked.isEmpty ? "Add" : "Add \(picked.count)") { add() }
                            .disabled(picked.isEmpty)
                    }
                }
        }
        .task { await load() }
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
                Text("Allow Count Downcula to read your calendars in Settings to pick events here. Events stay on your iPhone; only the countdowns you add sync.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        case let .ready(rows) where rows.isEmpty:
            ContentUnavailableView("Nothing Coming Up", systemImage: "calendar",
                                   description: Text("There are no events in your calendars for the next 90 days."))
        case let .ready(rows):
            List {
                if let room = CountdownImport.room(in: store.countdowns, unlocked: store.entitlements.isUnlocked) {
                    Section {
                        Text(room == 0
                             ? "Free includes \(SharedConfig.freeActiveLimit) countdowns at a time, and you're there. Pick what you like; Unlimited adds them all."
                             : "Free includes \(SharedConfig.freeActiveLimit) at a time, so \(room) more will fit. Pick more and Unlimited adds the rest.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
            HStack(spacing: 12) {
                Image(systemName: added ? "checkmark.circle" : selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(added ? Color.secondary : selected ? Color.countdownulaBlood : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title).foregroundStyle(Color.primary)
                    Text(row.isAllDay
                         ? row.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                         : row.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                        + Text(row.repetition.map { " · \($0.label)" } ?? "")
                        + Text(added ? " · Added" : "")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Spacer()
                Circle().fill(row.calendarColor).frame(width: 8, height: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(added)
    }

    private func load() async {
        phase = await CalendarEvents.upcoming().map(Phase.ready) ?? .denied
    }

    private func add() {
        guard case let .ready(rows) = phase else { return }
        let countdowns = rows.filter { picked.contains($0.id) }.map(\.countdown)
        onImport(countdowns)
        dismiss()
    }
}

// MARK: - Birthdays from Contacts

/// The system contact picker, offering only people with a birthday. It runs outside the app, so
/// there's no Contacts permission to ask for: the app only ever sees the people picked.
struct ContactBirthdayPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: ([Countdown]) -> Void

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        // The picker misbehaves inside a SwiftUI sheet, so it's presented from a hidden host instead.
        guard isPresented, host.presentedViewController == nil else { return }
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForEnablingContact = NSPredicate(format: "birthday != nil")
        picker.displayedPropertyKeys = [CNContactBirthdayKey]
        DispatchQueue.main.async { host.present(picker, animated: true) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactBirthdayPicker
        init(_ parent: ContactBirthdayPicker) { self.parent = parent }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            let countdowns = contacts.compactMap { contact -> Countdown? in
                guard let birthday = contact.birthday, let month = birthday.month, let day = birthday.day else { return nil }
                let name = contact.nickname.isEmpty
                    ? (contact.givenName.isEmpty ? CNContactFormatter.string(from: contact, style: .fullName) ?? "" : contact.givenName)
                    : contact.nickname
                return CountdownImport.birthday(name: name, month: month, day: day, year: birthday.year)
            }
            parent.isPresented = false
            parent.onPick(countdowns)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.isPresented = false
        }
    }
}

// MARK: - Adding them

extension PhoneStore {
    /// Adds imported countdowns that fit the free tier, soonest first. Returns the ones held back.
    @discardableResult
    func addImported(_ countdowns: [Countdown], source: String) -> [Countdown] {
        let (fits, heldBack) = CountdownImport.split(countdowns, room: CountdownImport.room(in: self.countdowns, unlocked: entitlements.isUnlocked))
        for countdown in fits { upsert(countdown, source: source) }
        return heldBack
    }
}
