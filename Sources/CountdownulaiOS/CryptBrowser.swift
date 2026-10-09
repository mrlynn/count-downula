import SwiftUI

/// "Browse the Crypt": public countdowns anyone can join, from holidays to eclipses.
struct CryptBrowser: View {
    @Environment(PhoneStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var categories: [LiveLinkAPI.CryptCategory] = []
    @State private var entries: [CryptEntry] = []
    @State private var category: String?
    @State private var loading = true
    @State private var joining: String?
    @State private var errorMessage: String?

    private var joinedSlugs: Set<String> {
        Set(store.countdowns.compactMap { $0.extras.subscription?.slug })
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                List {
                    Section {
                        Picker("Category", selection: $category) {
                            Text("All").tag(String?.none)
                            ForEach(categories) { Text($0.name).tag(Optional($0.slug)) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                    ForEach(entries.filter { category == nil || $0.category == category }) { entry in
                        row(entry, now: context.date)
                    }
                }
                .listStyle(.insetGrouped)
                .overlay {
                    if loading { ProgressView() }
                    else if entries.isEmpty {
                        ContentUnavailableView("The Crypt Is Empty", systemImage: "moon.stars",
                                               description: Text("Check back soon."))
                    }
                }
            }
            .navigationTitle("The Crypt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .alert("Couldn't join", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func row(_ entry: CryptEntry, now: Date) -> some View {
        let joined = joinedSlugs.contains(entry.slug)
        return HStack(spacing: 12) {
            Group {
                if let scene = entry.scene { SceneArt(scene: scene) } else { Color.countdownulaBlood }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.headline).lineLimit(2)
                Text(CountdownFormat.compact(from: now, to: entry.target))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.countdownulaBlood)
                Text(caption(entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                Task { await join(entry) }
            } label: {
                if joining == entry.slug { ProgressView() } else { Text(joined ? "Joined" : "Join") }
            }
            .buttonStyle(.bordered)
            .disabled(joined || joining != nil)
        }
    }

    private func caption(_ entry: CryptEntry) -> String {
        let date = entry.target.formatted(.dateTime.month(.abbreviated).day().year())
        let who = entry.memberCount > 0 ? " · \(entry.memberCount) counting" : ""
        return entry.floating ? "\(date), your time\(who)" : "\(date)\(who)"
    }

    private func load() async {
        defer { loading = false }
        do {
            let result = try await LiveLinkAPI.crypt()
            categories = result.categories
            entries = result.entries
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func join(_ entry: CryptEntry) async {
        joining = entry.slug
        defer { joining = nil }
        do {
            let id = try await store.join(slug: entry.slug)
            dismiss()
            router.show(id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
