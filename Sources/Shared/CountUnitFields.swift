#if !os(tvOS) && !os(watchOS)
import SwiftUI

/// The editor rows for what a countdown counts in, its bedtime for sleeps, and the time zone its
/// date is set in. Shared by the iPhone and Mac editors.
struct CountUnitFields: View {
    let kind: Countdown.Kind
    @Binding var extras: CountdownExtras
    @Binding var targetDate: Date
    @State private var choosingZone = false

    var body: some View {
        Picker("Count in", selection: unit) {
            ForEach(CountUnit.available(for: kind)) { unit in
                Text(unit.name).tag(unit)
            }
        }
        if unit.wrappedValue == .sleeps {
            DatePicker("Sleeps start at", selection: bedtime, displayedComponents: .hourAndMinute)
        }
        if kind == .event, extras.auto == nil {
            Button {
                choosingZone = true
            } label: {
                LabeledContent("Time zone") {
                    Text(zone.map(\.cityName) ?? L("Where I am"))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .popover(isPresented: $choosingZone) { zoneList.frame(width: 300, height: 380) }
            #else
            .sheet(isPresented: $choosingZone) { zoneList }
            #endif
        }
    }

    /// What the footer says about the chosen unit and zone.
    static func footer(for unit: CountUnit, zone: TimeZone?) -> String? {
        var lines: [String] = []
        switch unit {
        case .daysHours: break
        case .weeks: lines.append(L("Reads as weeks and days, down to the last week."))
        case .sleeps: lines.append(L("A sleep each night before the day, counted from bedtime. Kids count to birthdays this way."))
        case .workdays: lines.append(L("Today and each weekday before the day, skipping weekends. Holidays aren't skipped yet."))
        case .weekends: lines.append(L("Weekends left before the day, this one included."))
        case .percent: lines.append(L("How much of the wait is behind you."))
        }
        if let zone { lines.append(L("The date is in \(zone.cityName) time, wherever you are.")) }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    private var zone: TimeZone? { extras.timeZone.flatMap(TimeZone.init(identifier:)) }

    private var unit: Binding<CountUnit> {
        Binding(
            get: { extras.unit.flatMap { $0.fits(kind) ? $0 : nil } ?? .daysHours },
            set: { extras.unit = $0 == .daysHours ? nil : $0 }
        )
    }

    /// Minutes after midnight, edited as a time of day.
    private var bedtime: Binding<Date> {
        Binding(
            get: {
                let minutes = extras.bedtime ?? 0
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                extras.bedtime = minutes == 0 ? nil : minutes
            }
        )
    }

    private var zoneList: some View {
        TimeZoneList(selection: zone) { picked in
            // Keep the time as typed: 6:40pm stays 6:40pm, now in the picked zone.
            targetDate = targetDate.sameClockTime(from: zone ?? .current, to: picked ?? .current)
            extras.timeZone = picked?.identifier
            choosingZone = false
        }
    }
}

/// Every time zone by city, searchable, with "Where I am" on top.
struct TimeZoneList: View {
    let selection: TimeZone?
    let onPick: (TimeZone?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var zones: [TimeZone] {
        let all = TimeZone.knownTimeZoneIdentifiers.filter { $0.contains("/") && !$0.hasPrefix("Etc/") }
            .compactMap(TimeZone.init(identifier:))
        let q = query.trimmingCharacters(in: .whitespaces)
        let matching = q.isEmpty ? all : all.filter {
            $0.cityName.localizedCaseInsensitiveContains(q) || $0.identifier.localizedCaseInsensitiveContains(q)
                || ($0.localizedName(for: .generic, locale: .current) ?? "").localizedCaseInsensitiveContains(q)
        }
        return matching.sorted { $0.cityName.localizedCompare($1.cityName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    row(nil, title: L("Where I am"), detail: TimeZone.current.cityName)
                }
                ForEach(zones, id: \.identifier) { zone in
                    row(zone, title: zone.cityName, detail: zone.localizedName(for: .shortGeneric, locale: .current) ?? zone.identifier)
                }
            }
            .searchable(text: $query, prompt: Text("City or zone"))
            .navigationTitle("Time Zone")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private func row(_ zone: TimeZone?, title: String, detail: String) -> some View {
        Button {
            onPick(zone)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if zone?.identifier == selection?.identifier {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension Date {
    /// The same wall-clock time read in another zone: 6:40pm here becomes 6:40pm in Tokyo.
    func sameClockTime(from old: TimeZone, to new: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = old
        let parts = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: self)
        calendar.timeZone = new
        return calendar.date(from: parts) ?? self
    }
}
#endif
