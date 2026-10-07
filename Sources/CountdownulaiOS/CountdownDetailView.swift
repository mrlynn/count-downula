import SwiftUI

struct CountdownDetailView: View {
    @Environment(PhoneStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    let onEdit: (Countdown) -> Void
    @State private var confirmingDelete = false
    @State private var confirmingReset = false
    /// Bumped after starting or ending a Live Activity, since ActivityKit state isn't observable.
    @State private var activityRevision = 0
    /// Lives in the store: saving the celebration reloads the store, which can rebuild this view.
    private var celebration: Celebration? {
        store.celebration?.countdownID == id ? store.celebration : nil
    }

    var body: some View {
        if let countdown = store.countdown(id: id) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date
                let parts = countdown.timeParts(at: now)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        StyledCountdownCard(countdown: countdown, now: now, height: 320)

                        if countdown.countsUp {
                            countUpSummary(countdown, now: now)
                        } else {
                            Label {
                                Text(countdown.targetDate, format: .dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
                                + Text(parts.isPast ? "  ·  \(CountdownFormat.relative(from: now, to: countdown.targetDate))" : "")
                            } icon: {
                                Image(systemName: parts.isPast ? "checkmark.circle.fill"
                                    : countdown.extras.repeatsYearly ? "repeat" : "calendar")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                            if !parts.isPast {
                                VStack(alignment: .leading, spacing: 6) {
                                    MilestoneProgressBar(countdown: countdown, now: now)
                                    Text("\(Int((countdown.progress(at: now) * 100).rounded(.down)))% of the wait is behind you")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if !countdown.details.isEmpty {
                            Text(countdown.details)
                                .font(.body)
                                .textSelection(.enabled)
                        }

                        if !countdown.scheduledMilestones.isEmpty {
                            MilestoneTimeline(countdown: countdown, now: now)
                        }

                        actions(for: countdown, now: now)
                    }
                    .padding()
                }
                .task(id: celebrationKey(for: countdown, at: now)) {
                    celebrateIfNeeded(countdown, at: now)
                }
            }
            .overlay {
                if let celebration {
                    ConfettiView(accent: countdown.style.accentColor)
                        .ignoresSafeArea()
                        .id(celebration.id)
                }
            }
            .overlay(alignment: .top) {
                if let celebration {
                    CelebrationBanner(emoji: celebration.emoji, title: celebration.title, subtitle: celebration.subtitle)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture { store.celebration = nil }
                }
            }
            .animation(.spring(duration: 0.45), value: celebration)
            .task(id: celebration?.id) {
                guard let shown = celebration else { return }
                // A cancelled sleep throws; bail out rather than clearing a banner that's still showing.
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                if store.celebration?.id == shown.id { store.celebration = nil }
            }
            .sensoryFeedback(.success, trigger: celebration?.id) { _, new in new != nil }
            .navigationTitle(countdown.kind == .timer ? "Timer" : countdown.countsUp ? "Count Up" : "Countdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { onEdit(countdown) }
                }
            }
            .confirmationDialog("Start fresh?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset to Now") { store.resetStreak(countdown) }
            } message: {
                Text("Your \(CountdownFormat.elapsed(since: countdown.targetDate, to: Date())) still count. They're saved in your history, and your best run is kept.")
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

            if countdown.countsUp {
                Button {
                    confirmingReset = true
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            ShareLink(item: ShareCard(countdown: countdown, photo: store.image(for: countdown), now: now),
                      preview: SharePreview(countdown.title)) {
                Label("Share as Image", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

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

    // MARK: - Celebrations

    /// Changes whenever there's something new to celebrate, so the task above re-runs.
    private func celebrationKey(for countdown: Countdown, at now: Date) -> String {
        let milestones = countdown.uncelebratedMilestones(at: now).map(\.id.uuidString).joined(separator: ",")
        return "\(milestones)|\(store.shouldCelebrateCompletion(of: countdown, at: now))"
    }

    private func celebrateIfNeeded(_ countdown: Countdown, at now: Date) {
        if store.shouldCelebrateCompletion(of: countdown, at: now) {
            store.markCompletionCelebrated(countdown)
            // Finishing outranks any milestone reached along the way; mark those too.
            let pending = countdown.uncelebratedMilestones(at: now)
            if !pending.isEmpty { store.markCelebrated(pending, of: countdown) }
            store.celebration = Celebration(countdownID: countdown.id, emoji: countdown.kind == .timer ? "⏰" : "🎉",
                                            title: countdown.title,
                                      subtitle: countdown.kind == .timer ? "Time's up!" : "The wait is over!")
            return
        }
        let pending = countdown.uncelebratedMilestones(at: now)
        guard let latest = pending.last else { return }
        store.markCelebrated(pending, of: countdown)
        store.celebration = Celebration(countdownID: countdown.id, emoji: latest.milestone.displayEmoji,
                                        title: latest.milestone.title, subtitle: countdown.title)
    }

    /// Elapsed time in words, the way to the next milestone, money saved and the best run.
    @ViewBuilder
    private func countUpSummary(_ countdown: Countdown, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(CountdownFormat.elapsed(since: countdown.targetDate, to: now))
                    .fontWeight(.semibold)
                + Text("  ·  since \(countdown.targetDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))")
            } icon: {
                Image(systemName: "arrow.up.forward.circle")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let next = countdown.nextMilestone(at: now) {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: countdown.progress(at: now))
                        .tint(countdown.style.accentColor)
                    Text("\(next.milestone.displayEmoji) \(next.milestone.title) in \(CountdownFormat.compact(from: now, to: next.date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            let stats = countUpStats(countdown, now: now)
            if !stats.isEmpty {
                HStack(spacing: 10) {
                    ForEach(stats, id: \.label) { stat in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.value)
                                .font(countdown.style.font(.title3))
                                .foregroundStyle(countdown.style.accentColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(stat.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }

    private func countUpStats(_ countdown: Countdown, now: Date) -> [(label: String, value: String)] {
        var stats: [(label: String, value: String)] = []
        if let savings = countdown.extras.savings {
            stats.append(("saved", savings.formatted(since: countdown.targetDate, at: now)))
        }
        let runs = countdown.extras.streak.runs
        if !runs.isEmpty {
            let best = countdown.bestStreak(at: now)
            stats.append(("best run", CountdownFormat.elapsed(since: now - best, to: now)))
            stats.append((runs.count == 1 ? "fresh start" : "fresh starts", "\(runs.count)"))
        }
        return stats
    }

    private func footnote(for countdown: Countdown, now: Date) -> String {
        if countdown.countsUp { return "Pinned count-ups are featured in widgets when no pinned countdown is coming up." }
        if countdown.isPast(at: now) { return "Pinned countdowns are featured in widgets and at the top of the list." }
        if !LiveActivities.isEnabled { return "Turn on Live Activities for Count Downcula in Settings to follow countdowns from the Lock Screen." }
        return countdown.isPinned
            ? "Pinned: featured in widgets and shown live on the Lock Screen and in the Dynamic Island during its final 8 hours."
            : "Pin to feature this in widgets and show it live on the Lock Screen during its final 8 hours."
    }
}
