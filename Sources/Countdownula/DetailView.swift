import SwiftUI

struct DetailView: View {
    let countdown: Countdown
    let store: CountdownStore
    let onBack: () -> Void
    let onEdit: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        let parts = countdown.timeParts(at: store.now)

        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                CountdownArtwork(countdown: countdown, store: store, symbolSize: 48)
                    .frame(width: 380, height: 190)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        StyleScrim(style: countdown.style)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Text(countdown.title)
                            .font(countdown.style.font(.title2))
                            .foregroundStyle(countdown.style.foregroundColor)
                            .lineLimit(2)
                            .shadow(radius: 4)
                            .padding(14)
                    }

                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .padding(10)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        TimeBlock(value: parts.days, label: "Days", style: countdown.style)
                        TimeBlock(value: parts.hours, label: "Hours", style: countdown.style)
                        TimeBlock(value: parts.minutes, label: "Min", style: countdown.style)
                        TimeBlock(value: parts.seconds, label: "Sec", style: countdown.style)
                    }
                    .opacity(parts.isPast ? 0.5 : 1)

                    Label {
                        (countdown.countsUp ? Text("Since ") : Text(""))
                        + Text(countdown.targetDate, format: .dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
                        + Text(parts.isPast ? "  ·  \(CountdownFormat.relative(from: store.now, to: countdown.targetDate))" : "")
                    } icon: {
                        Image(systemName: parts.isPast ? "checkmark.circle.fill" : countdown.countsUp ? "arrow.up.forward.circle" : "calendar")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    if let next = countdown.nextMilestone(at: store.now) {
                        Label {
                            Text("Next: \(next.milestone.title) · in \(CountdownFormat.compact(from: store.now, to: next.date))")
                        } icon: {
                            Text(next.milestone.displayEmoji)
                        }
                        .font(.callout)
                    }

                    if !countdown.details.isEmpty {
                        Text(countdown.details)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Button {
                    store.togglePin(countdown)
                } label: {
                    Label(countdown.isPinned ? "Unpin" : "Pin to Menu Bar",
                          systemImage: countdown.isPinned ? "pin.slash" : "pin")
                }
                Spacer()
                if confirmingDelete {
                    Button("Cancel") { confirmingDelete = false }
                    Button(countdown.extras.subscription == nil ? "Delete" : "Leave", role: .destructive) {
                        onBack()
                        store.delete(countdown)
                    }
                    .tint(.red)
                } else {
                    Button { confirmingDelete = true } label: { Image(systemName: "trash") }
                        .help(countdown.extras.subscription == nil ? "Delete" : "Leave this shared countdown")
                    // Only the owner edits a shared countdown.
                    if countdown.extras.subscription == nil {
                        Button("Edit", action: onEdit)
                    }
                }
            }
            .padding(12)
        }
    }
}

private struct TimeBlock: View {
    let value: Int
    let label: String
    var style = CountdownStyle.default

    var body: some View {
        VStack(spacing: 2) {
            Text(String(format: "%02d", value))
                .font(style.font(size: 30))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}
