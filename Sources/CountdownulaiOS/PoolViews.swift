import SwiftUI

// MARK: - Detail screen section

/// A date pool on the detail screen: everyone's guesses, a way to make or change yours, and for the
/// owner, closing guessing and setting the real date, which names the winner.
struct PoolSection: View {
    @Environment(PhoneStore.self) private var store
    let countdown: Countdown

    @State private var state: DatePool.State?
    @State private var guessing = false
    @State private var settling = false
    @State private var errorMessage: String?

    var body: some View {
        if let pool = countdown.extras.pool {
            if let access = DatePool.access(for: countdown) {
                content(pool, access)
                    .task(id: "\(countdown.id)-\(pool.closed)-\(pool.answer?.timeIntervalSince1970 ?? 0)") { await load(access) }
                    .sheet(isPresented: $guessing) {
                        GuessSheet(countdown: countdown, current: state?.mine?.guess) { name, date in
                            try await LiveLinkAPI.guess(slug: access.slug, token: access.token, name: name, date: date)
                            await load(access)
                        }
                    }
                    .sheet(isPresented: $settling) {
                        SettleSheet(countdown: countdown) { date in
                            await act(.settle(date), access)
                        }
                    }
                    .alert("Date Pool", isPresented: Binding(get: { errorMessage != nil },
                                                            set: { if !$0 { errorMessage = nil } })) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(errorMessage ?? "")
                    }
            } else {
                card {
                    header(title: "Date Pool", subtitle: "Share the live link and friends can guess when it happens.")
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ pool: DatePool, _ access: (slug: String, token: String)) -> some View {
        let closed = state?.closed ?? pool.closed
        let answer = state?.answer ?? pool.answer
        let guesses = state?.guesses ?? []
        card {
            header(title: answer == nil ? "Date Pool" : "The Results Are In", subtitle: summary(answer: answer, closed: closed))

            ForEach(guesses) { guess in
                HStack(spacing: 10) {
                    Text(guess.place == 1 ? "🏆" : guess.place.map { "\($0)." } ?? "")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 28, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(guess.mine ? "\(guess.name) (you)" : guess.name)
                            .font(.subheadline.weight(.semibold))
                        Text(guess.guess, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let off = guess.offBySeconds {
                        Text(DatePool.offBy(off))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                // Removing is a long press, so the list stays a clean leaderboard.
                .contextMenu {
                    if answer == nil, state?.isOwner == true || guess.mine {
                        Button(guess.mine ? "Take Back My Guess" : "Remove Guess", systemImage: "trash", role: .destructive) {
                            Task { await remove(guess, access) }
                        }
                    }
                }
            }

            if !closed {
                Button {
                    guessing = true
                } label: {
                    Label(state?.mine == nil ? "Make Your Guess" : "Change Your Guess", systemImage: "target")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if state?.isOwner == true, answer == nil {
                Button {
                    settling = true
                } label: {
                    Label("Set the Real Date", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(closed ? "Reopen Guessing" : "Close Guessing") {
                    Task { await act(closed ? .reopen : .close, access) }
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .controlSize(.large)
    }

    private func header(title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Text("🎯").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func summary(answer: Date?, closed: Bool) -> String {
        let count = state?.guesses.count ?? 0
        if let answer {
            let names = state?.winners.map(\.name) ?? []
            let when = answer.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            let winners = ListFormatter.localizedString(byJoining: names)
            return names.isEmpty ? L("It happened \(when).") : L("\(winners) called it closest. It happened \(when).")
        }
        if count == 0 { return closed ? L("No guesses yet. Guessing is closed.") : L("No guesses yet. Closest to the real date wins.") }
        return closed ? L("\(count) guesses. Guessing is closed.") : L("\(count) guesses. Closest to the real date wins.")
    }

    private func load(_ access: (slug: String, token: String)) async {
        guard let loaded = try? await LiveLinkAPI.pool(slug: access.slug, token: access.token) else { return }
        state = loaded
        save(closed: loaded.closed, answer: loaded.answer)
    }

    private func act(_ action: LiveLinkAPI.PoolAction, _ access: (slug: String, token: String)) async {
        do {
            let updated = try await LiveLinkAPI.poolAction(action, slug: access.slug, token: access.token)
            state = updated
            save(closed: updated.closed, answer: updated.answer)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ guess: DatePool.Guess, _ access: (slug: String, token: String)) async {
        do {
            try await LiveLinkAPI.removeGuess(slug: access.slug, token: access.token, id: guess.id)
            await load(access)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Keeps the owner's copy in step with the server; a settled pool moves the countdown to the
    /// real date. Members' copies follow through the usual refresh.
    private func save(closed: Bool, answer: Date?) {
        guard countdown.extras.subscription == nil, var latest = store.countdown(id: countdown.id),
              let pool = latest.extras.pool, pool.closed != closed || pool.answer != answer else { return }
        latest.extras.pool = DatePool(closed: closed, answer: answer)
        if let answer { latest.targetDate = answer }
        store.upsert(latest)
    }
}

// MARK: - Sheets

private struct GuessSheet: View {
    @Environment(\.dismiss) private var dismiss
    let countdown: Countdown
    let current: Date?
    let send: (String, Date) async throws -> Void

    /// Shared with the coffin, so people type their name once.
    @AppStorage("Coffin.name") private var name = ""
    @State private var date = Date()
    @State private var sending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                        .onChange(of: name) { _, new in if new.count > DatePool.maxName { name = String(new.prefix(DatePool.maxName)) } }
                }
                Section {
                    DatePicker("Your guess", selection: $date, in: Date().addingTimeInterval(-3_600)...,
                               displayedComponents: [.date, .hourAndMinute])
                } footer: {
                    Text("Everyone with the link sees your guess. The closest one wins once the real date is in.")
                }
            }
            .navigationTitle(countdown.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "Saving…" : "Lock It In") {
                        Task {
                            sending = true
                            defer { sending = false }
                            do {
                                try await send(name.trimmingCharacters(in: .whitespaces), date)
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || sending)
                }
            }
            .onAppear { date = max(current ?? countdown.targetDate, Date()) }
            .alert("Couldn't save your guess", isPresented: Binding(get: { errorMessage != nil },
                                                                    set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct SettleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let countdown: Countdown
    let settle: (Date) async -> Void

    @State private var date = Date()
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("It happens", selection: $date, displayedComponents: [.date, .hourAndMinute])
                } footer: {
                    Text("The closest guess wins, guessing closes, and the countdown moves to this date for everyone. Already happened? Pick when it did.")
                }
            }
            .navigationTitle("Set the Real Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "Settling…" : "Settle") {
                        Task {
                            sending = true
                            await settle(date)
                            sending = false
                            dismiss()
                        }
                    }
                    .disabled(sending)
                }
            }
            .onAppear { date = min(countdown.targetDate, Date()) }
        }
        .presentationDetents([.medium])
    }
}
