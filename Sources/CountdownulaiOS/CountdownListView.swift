import SwiftUI

/// What the editor sheet is open for.
enum EditorTarget: Identifiable {
    case new
    case edit(Countdown)

    var id: String {
        switch self {
        case .new: "new"
        case let .edit(countdown): countdown.id.uuidString
        }
    }
}

struct CountdownListView: View {
    @Environment(PhoneStore.self) private var store
    @Environment(Router.self) private var router
    @State private var editorTarget: EditorTarget?
    @State private var pendingDelete: Countdown?
    @State private var showingPaywall = false
    /// Why the paywall is up, for the metrics dashboard.
    @State private var paywallReason = "free_limit"
    @State private var showingCalendarImport = false
    @State private var showingContactPicker = false
    /// Picked in the calendar sheet, added once it has closed.
    @State private var pendingImport: (countdowns: [Countdown], source: String)?
    /// Picked past the free limit, added if Unlimited is bought while the paywall is up.
    @State private var heldBack: (countdowns: [Countdown], source: String)?
    @State private var importNotice: String?
    @State private var showingJoin = false
    @State private var showingCrypt = false

    private let quickTimers = [5, 10, 15, 25, 45, 60]

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.path) {
            // Rows under a day old use self-updating timer text; everything else only needs a per-minute refresh.
            TimelineView(.everyMinute) { context in
                let now = context.date
                let upcoming = store.upcoming(at: now)
                let past = store.past(at: now)
                let hero = store.countdowns.featured(at: now)

                List {
                    if let hero {
                        // The link sits invisibly behind the card so the row gets no disclosure chevron.
                        HeroCard(countdown: hero)
                            .background {
                                NavigationLink(value: hero.id) { EmptyView() }.opacity(0)
                            }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .contextMenu { menuItems(for: hero, now: now) }
                    }

                    let rest = upcoming.filter { $0.id != hero?.id }
                    if !rest.isEmpty {
                        Section("Upcoming") {
                            ForEach(rest) { row(for: $0, now: now) }
                        }
                    }
                    let counting = store.countingUp.filter { $0.id != hero?.id }
                    if !counting.isEmpty {
                        Section("Counting Up") {
                            ForEach(counting) { row(for: $0, now: now) }
                        }
                    }
                    if !past.isEmpty {
                        Section("Past") {
                            ForEach(past) { row(for: $0, now: now) }
                        }
                    }
                    if !store.entitlements.isUnlocked, !store.countdowns.isEmpty {
                        FreeTierFooter(active: Entitlements.activeCount(in: store.countdowns, at: now)) {
                            paywallReason = "footer"
                            showingPaywall = true
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.insetGrouped)
                .overlay {
                    if store.countdowns.isEmpty {
                        EmptyState(onAdd: { addCountdown() },
                                   onCalendar: { showingCalendarImport = true },
                                   onContacts: { showingContactPicker = true })
                    }
                }
            }
            .navigationTitle("Count Downcula")
            .navigationDestination(for: UUID.self) { id in
                CountdownDetailView(id: id, onEdit: { editorTarget = .edit($0) })
            }
            .toolbar {
                // Always on screen for free users, even with an empty list, so the purchase is never hidden
                // behind having made a countdown first (App Review couldn't find it in 1.1.0).
                if !store.entitlements.isUnlocked {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Unlock Unlimited") {
                            paywallReason = "toolbar"
                            showingPaywall = true
                        }
                        .tint(Color.countdownulaBlood)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("New Countdown", systemImage: "calendar.badge.plus") { addCountdown() }
                        Button("Join Shared Countdown…", systemImage: "person.2.badge.plus") { showingJoin = true }
                        Button("Browse the Crypt", systemImage: "moon.stars") { showingCrypt = true }
                        Section("Add From") {
                            Button("Calendar…", systemImage: "calendar") { showingCalendarImport = true }
                            Button("Birthdays from Contacts…", systemImage: "gift") { showingContactPicker = true }
                        }
                        Section("Quick Timer") {
                            ForEach(quickTimers, id: \.self) { minutes in
                                Button(PhoneStore.durationLabel(minutes), systemImage: "timer") {
                                    if store.entitlements.canAdd(to: store.countdowns) {
                                        store.startQuickTimer(minutes: minutes)
                                    } else {
                                        paywallReason = "quick_timer_limit"
                                        showingPaywall = true
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    } primaryAction: {
                        addCountdown()
                    }
                    .accessibilityLabel("New countdown")
                }
            }
            .sheet(item: $editorTarget) { target in
                switch target {
                case .new: CountdownEditorView(original: nil)
                case let .edit(countdown): CountdownEditorView(original: countdown)
                }
            }
            .sheet(isPresented: $showingPaywall, onDismiss: finishHeldBackImport) { PaywallView(reason: paywallReason) }
            .sheet(isPresented: $showingCalendarImport, onDismiss: {
                if let pending = pendingImport { importCountdowns(pending.countdowns, source: pending.source) }
                pendingImport = nil
            }) {
                CalendarImportSheet { pendingImport = ($0, "calendar") }
            }
            #if DEBUG
            // Screenshots and testing: -openImport calendar (or contacts) opens a picker at launch.
            .task {
                switch UserDefaults.standard.string(forKey: "openImport") {
                case "calendar": showingCalendarImport = true
                case "contacts": showingContactPicker = true
                default: break
                }
            }
            #endif
            .background(ContactBirthdayPicker(isPresented: $showingContactPicker) { picked in
                // Let the picker finish closing before anything else (the paywall) comes up.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { importCountdowns(picked, source: "contacts") }
            })
            .alert("Some Didn’t Fit",
                   isPresented: Binding(get: { importNotice != nil }, set: { if !$0 { importNotice = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importNotice ?? "")
            }
            .onChange(of: store.draftsWaitingForUnlock, initial: true) { _, waiting in
                // Something was shared in while at the free limit; it's waiting for Unlimited.
                if waiting { paywallReason = "screenshot_limit"; showingPaywall = true; store.draftsWaitingForUnlock = false }
            }
            .sheet(isPresented: $showingJoin) { JoinSharedSheet() }
            .sheet(isPresented: $showingCrypt) { CryptBrowser() }
            .confirmationDialog("Delete \(pendingDelete?.title ?? "countdown")?",
                                isPresented: .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let pendingDelete { store.delete(pendingDelete) }
                    pendingDelete = nil
                }
            }
        }
    }

    /// Adds what fits the free tier; the rest wait on the Unlimited offer.
    private func importCountdowns(_ countdowns: [Countdown], source: String) {
        guard !countdowns.isEmpty else { return }
        let waiting = store.addImported(countdowns, source: source)
        guard !waiting.isEmpty else { return }
        heldBack = (waiting, source)
        paywallReason = "import_limit"
        showingPaywall = true
    }

    private func finishHeldBackImport() {
        guard let held = heldBack else { return }
        if store.entitlements.isUnlocked {
            store.addImported(held.countdowns, source: held.source)
        } else {
            let count = held.countdowns.count
            let names = Array(held.countdowns.map(\.title).prefix(3)).formatted(.list(type: .and))
            importNotice = count == 1
                ? L("1 countdown didn't fit the free tier: \(names). Unlock Unlimited and add it again any time.")
                : count > 3
                ? L("\(count) countdowns didn't fit the free tier, including \(names). Unlock Unlimited and add them again any time.")
                : L("\(count) countdowns didn't fit the free tier: \(names). Unlock Unlimited and add them again any time.")
        }
        heldBack = nil
    }

    /// Opens the editor, or the paywall once a free user has reached the limit.
    private func addCountdown() {
        if store.entitlements.canAdd(to: store.countdowns) {
            editorTarget = .new
        } else {
            paywallReason = "free_limit"
            showingPaywall = true
        }
    }

    private func row(for countdown: Countdown, now: Date) -> some View {
        NavigationLink(value: countdown.id) {
            CountdownRow(countdown: countdown, now: now)
        }
        .swipeActions(edge: .leading) {
            Button {
                store.togglePin(countdown)
            } label: {
                Label(countdown.isPinned ? "Unpin" : "Pin", systemImage: countdown.isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.delete(countdown)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu { menuItems(for: countdown, now: now) }
    }

    @ViewBuilder
    private func menuItems(for countdown: Countdown, now: Date) -> some View {
        // Only the owner edits a shared countdown.
        if countdown.extras.subscription == nil {
            Button("Edit", systemImage: "pencil") { editorTarget = .edit(countdown) }
        }
        Button(countdown.isPinned ? "Unpin" : "Pin",
               systemImage: countdown.isPinned ? "pin.slash" : "pin") { store.togglePin(countdown) }
        if LiveActivities.isEligible(countdown, at: now) && !LiveActivities.isRunning(countdown.id) {
            Button("Show on Lock Screen", systemImage: "lock.iphone") { LiveActivities.start(countdown) }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = countdown }
    }
}

// MARK: - Hero

/// The featured countdown (soonest pinned, else soonest): full-bleed photo with a live D/H/M/S readout.
private struct HeroCard: View {
    let countdown: Countdown

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            StyledCountdownCard(
                countdown: countdown, now: context.date,
                badge: countdown.isPinned ? L("PINNED") : L("UP NEXT"),
                subtitle: countdown.countsUp
                    ? Text("Since \(countdown.targetDate.formatted(.dateTime.month().day().year()))")
                    : Text(countdown.targetDate, format: .dateTime.weekday(.abbreviated).month().day().hour().minute())
            )
        }
    }
}

// MARK: - Row

private struct CountdownRow: View {
    let countdown: Countdown
    let now: Date
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let isPast = countdown.isPast(at: now)

        HStack(spacing: 12) {
            CountdownArtwork(countdown: countdown, useThumbnail: true, now: now)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // At the largest text sizes the time goes under the title instead of
            // squeezing it into a sliver.
            if dynamicTypeSize >= .xxxLarge {
                VStack(alignment: .leading, spacing: 4) {
                    details(isPast: isPast)
                    time(isPast: isPast)
                }
            } else {
                details(isPast: isPast)
                Spacer(minLength: 8)
                time(isPast: isPast)
            }
        }
        .padding(.vertical, 4)
        .opacity(isPast ? 0.7 : 1)
    }

    private func time(isPast: Bool) -> some View {
        CountdownTimeText(countdown: countdown, now: now)
            .font(countdown.style.font(.title3))
            .foregroundStyle(isPast ? Color.secondary : countdown.style.accentColor)
            .lineLimit(1)
            .fixedSize()
    }

    private func details(isPast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(countdown.title)
                    .font(.headline)
                    .lineLimit(1)
                if countdown.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Pinned")
                }
            }
            if let next = countdown.nextMilestone(at: now) {
                Text("\(next.milestone.displayEmoji) \(next.milestone.title) in \(CountdownFormat.compact(from: now, to: next.date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if countdown.countsUp {
                Text("Since \(countdown.targetDate.formatted(.dateTime.month(.abbreviated).day().year()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(countdown.targetDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !isPast {
                ProgressView(value: countdown.progress(at: now))
                    .tint(countdown.style.accentColor)
            }
        }
    }
}

// MARK: - Free tier

/// "2 of 3 free countdowns · Unlock Unlimited" under the list, so the upgrade and Restore are always reachable.
private struct FreeTierFooter: View {
    let active: Int
    let onUnlock: () -> Void

    var body: some View {
        Button(action: onUnlock) {
            VStack(spacing: 4) {
                Text("\(min(active, SharedConfig.freeActiveLimit)) of \(SharedConfig.freeActiveLimit) free countdowns")
                    .foregroundStyle(.secondary)
                Text("Unlock Unlimited")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.countdownulaBlood)
            }
            .font(.footnote)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty

private struct EmptyState: View {
    let onAdd: () -> Void
    let onCalendar: () -> Void
    let onContacts: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            FangMark()
                .foregroundStyle(Color.countdownulaBlood)
                .frame(width: 88, height: 88)
            Text("No countdowns yet")
                .font(.title2.bold())
            Text("Add a trip, a launch, a birthday or a quick timer.\nCountdowns from your Mac and Apple Watch show up here too.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Countdown", action: onAdd)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            // The quickest start: the dates people already have.
            HStack(spacing: 10) {
                Button("From Calendar", systemImage: "calendar", action: onCalendar)
                Button("Birthdays", systemImage: "gift", action: onContacts)
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
    }
}
