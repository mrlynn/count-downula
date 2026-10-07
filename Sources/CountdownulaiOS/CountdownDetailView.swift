import SwiftUI

struct CountdownDetailView: View {
    @Environment(PhoneStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    let onEdit: (Countdown) -> Void
    @State private var confirmingDelete = false
    /// Bumped after starting or ending a Live Activity, since ActivityKit state isn't observable.
    @State private var activityRevision = 0

    var body: some View {
        if let countdown = store.countdown(id: id) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date
                let parts = TimeParts(from: now, to: countdown.targetDate)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        CountdownArtwork(countdown: countdown, now: now)
                            .frame(height: 280)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(countdown.title)
                                .font(.largeTitle.bold())
                            Label {
                                Text(countdown.targetDate, format: .dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
                                + Text(parts.isPast ? "  ·  \(CountdownFormat.relative(from: now, to: countdown.targetDate))" : "")
                            } icon: {
                                Image(systemName: parts.isPast ? "checkmark.circle.fill" : "calendar")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }

                        TimeBlocks(parts: parts)

                        if !parts.isPast {
                            VStack(alignment: .leading, spacing: 6) {
                                ProgressView(value: countdown.progress(at: now))
                                    .tint(Color.countdownulaBlood)
                                Text("\(Int((countdown.progress(at: now) * 100).rounded(.down)))% of the wait is behind you")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !countdown.details.isEmpty {
                            Text(countdown.details)
                                .font(.body)
                                .textSelection(.enabled)
                        }

                        actions(for: countdown, now: now)
                    }
                    .padding()
                }
            }
            .navigationTitle(countdown.kind == .timer ? "Timer" : "Countdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { onEdit(countdown) }
                }
            }
            .confirmationDialog("Delete \(countdown.title)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    dismiss()
                    store.delete(countdown)
                }
            }
        } else {
            ContentUnavailableView("Countdown Deleted", systemImage: "hourglass",
                                   description: Text("This countdown was deleted on another device."))
        }
    }

    @ViewBuilder
    private func actions(for countdown: Countdown, now: Date) -> some View {
        let _ = activityRevision
        VStack(spacing: 10) {
            Button {
                store.togglePin(countdown)
            } label: {
                Label(countdown.isPinned ? "Unpin" : "Pin", systemImage: countdown.isPinned ? "pin.slash" : "pin")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if LiveActivities.isRunning(countdown.id) {
                Button {
                    LiveActivities.end(countdown.id)
                    activityRevision += 1
                } label: {
                    Label("Remove from Lock Screen", systemImage: "lock.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else if LiveActivities.isEligible(countdown, at: now) {
                Button {
                    LiveActivities.start(countdown)
                    activityRevision += 1
                } label: {
                    Label("Show on Lock Screen", systemImage: "lock.iphone")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!LiveActivities.isEnabled)
            }

            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Text(footnote(for: countdown, now: now))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.large)
        .padding(.top, 4)
    }

    private func footnote(for countdown: Countdown, now: Date) -> String {
        if countdown.isPast(at: now) { return "Pinned countdowns are featured in widgets and at the top of the list." }
        if !LiveActivities.isEnabled { return "Turn on Live Activities for Count Downula in Settings to follow countdowns from the Lock Screen." }
        return countdown.isPinned
            ? "Pinned: featured in widgets and shown live on the Lock Screen and in the Dynamic Island during its final 8 hours."
            : "Pin to feature this in widgets and show it live on the Lock Screen during its final 8 hours."
    }
}
