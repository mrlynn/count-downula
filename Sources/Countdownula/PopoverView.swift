import SwiftUI

struct PopoverActions {
    var add: () -> Void
    var edit: (Countdown) -> Void
    var unlock: () -> Void
    var quit: () -> Void
}

struct PopoverView: View {
    let store: CountdownStore
    let navigation: PopoverNavigation
    let actions: PopoverActions

    var body: some View {
        Group {
            if let id = navigation.selectedID, let countdown = store.countdown(id: id) {
                DetailView(
                    countdown: countdown,
                    store: store,
                    onBack: { navigation.selectedID = nil },
                    onEdit: { actions.edit(countdown) }
                )
            } else {
                CountdownListView(store: store, navigation: navigation, actions: actions)
            }
        }
        .frame(width: 380, height: 540)
    }
}

private struct CountdownListView: View {
    enum Tab: String, CaseIterable { case upcoming = "Upcoming", past = "Past" }

    let store: CountdownStore
    let navigation: PopoverNavigation
    let actions: PopoverActions
    @State private var tab: Tab = .upcoming

    /// Count-ups never finish, so they live under Upcoming after the countdowns.
    private var items: [Countdown] { tab == .upcoming ? store.upcoming + store.countingUp : store.past }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label {
                    Text("Count Downcula")
                } icon: {
                    if let mark = NSImage.countdownulaMark {
                        Image(nsImage: mark).foregroundStyle(.red)
                    }
                }
                .font(.headline)
                Spacer()
                Button(action: actions.add) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .help("New countdown")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Picker("", selection: $tab) {
                Text("Upcoming (\(store.upcoming.count + store.countingUp.count))").tag(Tab.upcoming)
                Text("Past (\(store.past.count))").tag(Tab.past)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider()

            if items.isEmpty {
                EmptyStateView(tab: tab, onAdd: actions.add)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { countdown in
                            CountdownRow(countdown: countdown, store: store)
                                .onTapGesture { navigation.selectedID = countdown.id }
                                .contextMenu {
                                    if countdown.extras.subscription == nil {
                                        Button("Edit…") { actions.edit(countdown) }
                                    }
                                    Button(countdown.isPinned ? "Unpin from Menu Bar" : "Pin to Menu Bar") {
                                        store.togglePin(countdown)
                                    }
                                    Divider()
                                    Button(countdown.extras.subscription == nil ? "Delete" : "Leave", role: .destructive) {
                                        store.delete(countdown)
                                    }
                                }
                        }
                    }
                    .padding(12)
                }
            }

            Divider()

            HStack {
                if store.entitlements.isUnlocked {
                    Text("\(store.countdowns.filter(\.isPinned).count) pinned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let active = Entitlements.activeCount(in: store.countdowns, at: store.now)
                    Text(active >= SharedConfig.freeActiveLimit ? "Free limit reached" : "\(active) of \(SharedConfig.freeActiveLimit) free")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Unlock Unlimited", action: actions.unlock)
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(Color.countdownulaBlood)
                }
                Spacer()
                PrivacyMenu()
                Button("Quit", action: actions.quit)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

private struct EmptyStateView: View {
    let tab: CountdownListView.Tab
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: tab == .upcoming ? "calendar.badge.clock" : "checkmark.seal")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(tab == .upcoming ? "Nothing to count down to… yet" : "No finished countdowns")
                .font(.headline)
                .foregroundStyle(.secondary)
            if tab == .upcoming {
                Button("Create a Countdown", action: onAdd)
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Share Analytics: anonymous counts for the metrics dashboard (see `Analytics`). On unless turned off.
private struct PrivacyMenu: View {
    @AppStorage(Analytics.enabledKey) private var shareAnalytics = true

    var body: some View {
        Menu {
            Toggle("Share Analytics", isOn: $shareAnalytics)
            Button("Reset Analytics ID") { Analytics.resetInstallID() }
                .disabled(!shareAnalytics)
            Divider()
            Text("Anonymous counts, like how many countdowns get made. No titles, dates or names.")
        } label: {
            Image(systemName: "hand.raised")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Privacy")
        .onChange(of: shareAnalytics) { _, on in Analytics.setEnabled(on) }
    }
}
