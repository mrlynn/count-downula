import SwiftUI

/// On a countdown's detail screen once it reaches zero: what it added up to, and Keep Counting,
/// which turns it into a count-up from that day ("Married 1 year"). On a shared countdown the
/// owner's choice reaches everyone, and each member can stay at zero instead.
struct AfterZeroSection: View {
    @Environment(PhoneStore.self) private var store
    let countdown: Countdown
    let now: Date
    /// The shared countdown's people, loaded here and used by the recap card too.
    @Binding var recap: Recap?
    @State private var confirmingKeepCounting = false

    private var slug: String? { countdown.extras.link?.slug ?? countdown.extras.subscription?.slug }
    private var isMember: Bool { countdown.extras.subscription != nil }
    private var kept: Bool { countdown.extras.keptCountingAt != nil }

    var body: some View {
        if countdown.hasReachedZero(at: now) || kept {
            content
                .task(id: "\(slug ?? "")-\(countdown.kind.rawValue)") { await loadRecap() }
                .confirmationDialog("Keep counting from \(countdown.targetDate.formatted(.dateTime.month(.wide).day().year()))?",
                                    isPresented: $confirmingKeepCounting, titleVisibility: .visible) {
                    Button("Keep Counting") { keepCounting() }
                } message: {
                    Text(countdown.extras.link != nil
                         ? "It becomes a count-up from the day it happened, with yearly milestones. Everyone counting down with you sees it too, and each of them can stay at zero instead. Rename it any time with Edit."
                         : "It becomes a count-up from the day it happened, with yearly milestones. Rename it any time with Edit.")
                }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kept && countdown.countsUp ? "Counted down together" : "It happened.")
                    .font(countdown.style.font(.title2))
                if let counted = Recap.counted(countdown) {
                    Text("\(counted) counted")
                        .font(.headline)
                        .foregroundStyle(countdown.style.accentColor)
                }
                if let line = recap?.peopleLine(isPublic: countdown.extras.subscription?.isPublic == true) {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if isMember, kept {
                Toggle("Keep counting with everyone", isOn: Binding(
                    get: { countdown.extras.subscription?.staysFinished != true },
                    set: { follow($0) }
                ))
                .tint(countdown.style.accentColor)
                Text("The owner kept counting up from the day it happened. Turn this off to keep it at zero on your devices.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !isMember, !countdown.countsUp {
                Button {
                    confirmingKeepCounting = true
                } label: {
                    Label("Keep Counting", systemImage: "arrow.up.forward.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func loadRecap() async {
        guard let slug, let remote = try? await LiveLinkAPI.fetch(slug: slug) else { return }
        recap = remote.recap
    }

    private func keepCounting() {
        var updated = countdown
        updated.keepCounting()
        store.upsert(updated)
        // A shared countdown's page and every member's copy follow.
        store.pushLinkUpdate(for: store.countdown(id: updated.id) ?? updated)
        Analytics.log(.keepCounting, slug: updated.extras.link?.slug, source: updated.extras.link != nil ? "shared" : "solo")
    }

    /// A member following the owner up from zero, or staying put.
    private func follow(_ on: Bool) {
        var updated = countdown
        updated.extras.subscription?.staysFinished = on ? nil : true
        // Forces the next refresh to apply the owner's copy with the new choice.
        updated.extras.subscription?.remoteUpdatedAt = nil
        if !on {
            updated.kind = .event
            updated.milestones = updated.milestones.filter { !$0.isElapsedTrigger }
        }
        store.upsert(updated)
        Analytics.log(.keepCounting, slug: slug, source: on ? "member_follows" : "member_stays")
        Task { await store.refreshShared(force: true) }
    }
}
