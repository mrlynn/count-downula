import ImageIO
import Observation
import UIKit
import UniformTypeIdentifiers

/// The Apple TV's countdowns: the same iCloud store as the iPhone, Mac and watch, so everything
/// made or joined elsewhere is here. The TV mostly shows; it joins Crypt countdowns and keeps
/// joined ones in step with their owners, and writes the snapshot the Top Shelf reads.
@MainActor
@Observable
final class TVStore {
    static let shared = TVStore()

    private(set) var countdowns: [Countdown] = []
    private(set) var now = Date()

    @ObservationIgnored private let repository: CountdownRepository
    @ObservationIgnored private var imageCache: [String: UIImage] = [:]
    @ObservationIgnored private var lastSharedRefresh: [UUID: Date] = [:]
    @ObservationIgnored private var ticker: Timer?

    init() {
        let directory = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        repository = CountdownRepository(storeURL: directory.appending(path: "Countdownula.store"))
        repository.onRemoteChange = { [weak self] in self?.reload() }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedDemo") { seedDemoData() }
        #endif
        reload()
        // Repeating countdowns roll over and the lists re-sort as dates pass.
        ticker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.now = Date()
                self?.reload()
            }
        }
    }

    // MARK: - Queries

    /// What's coming, soonest first, then count-ups.
    var upcoming: [Countdown] {
        countdowns.filter { $0.isUpcoming(at: now) }.sorted { $0.targetDate < $1.targetDate }
            + countdowns.filter(\.countsUp).sorted { $0.targetDate < $1.targetDate }
    }

    var featured: Countdown? { countdowns.featured(at: now) }

    func countdown(id: UUID) -> Countdown? { countdowns.first { $0.id == id } }

    func image(for countdown: Countdown) -> UIImage? {
        guard countdown.hasImage else { return nil }
        if let cached = imageCache[countdown.imageCacheKey] { return cached }
        guard let data = repository.imageData(for: countdown.id), let image = UIImage(data: data) else { return nil }
        imageCache[countdown.imageCacheKey] = image
        return image
    }

    // MARK: - Sync

    func reload() {
        repository.rollOverRepeatingCountdowns()
        let fresh = repository.fetchAll()
        if fresh != countdowns { countdowns = fresh }
        let repository = repository
        WidgetSnapshot.write(countdowns, thumbnail: { repository.thumbnailData(for: $0) })
    }

    /// Pulls owners' edits to joined countdowns, at most every ten minutes each.
    func refreshShared() async {
        let ended = await SharedCountdowns.refresh(
            countdowns,
            shouldCheck: { [lastSharedRefresh] in (lastSharedRefresh[$0.id] ?? .distantPast) < Date() - 600 },
            latest: { [weak self] in self?.countdown(id: $0) },
            prepareImage: Self.prepareImage,
            save: { [weak self] countdown, image in
                self?.lastSharedRefresh[countdown.id] = Date()
                self?.repository.upsert(countdown, image: image)
            }
        )
        if !ended.isEmpty { reload() }
        reload()
    }

    /// Joins a Crypt countdown (or any shared one) and returns the local copy's ID. One already
    /// here is just returned.
    func join(slug: String) async throws -> UUID {
        if let existing = countdowns.first(where: { $0.extras.subscription?.slug == slug || $0.extras.link?.slug == slug }) {
            return existing.id
        }
        let remote = try await LiveLinkAPI.fetch(slug: slug)
        let backdrop = remote.hasPhoto ? try? await LiveLinkAPI.photo(slug: slug) : nil
        let joined = try await LiveLinkAPI.join(slug: slug)
        let url = remote.url ?? LiveLinkAPI.baseURL.appending(path: "c/\(slug)")
        var countdown = SharedCountdowns.makeCountdown(from: remote, slug: slug, url: url)
        countdown.extras.subscription?.memberCount = joined.memberCount
        MemberTokens.save(joined.memberToken, for: countdown.id)
        repository.upsert(countdown, image: backdrop.flatMap(Self.prepareImage) ?? .unchanged)
        lastSharedRefresh[countdown.id] = Date()
        Analytics.log(.countdownCreated, slug: slug, source: "tv_join")
        reload()
        return countdown.id
    }

    /// A photo at display size and a thumbnail, from a downloaded JPEG, without decoding it whole.
    nonisolated static func prepareImage(_ data: Data) -> ImageUpdate? {
        guard let full = jpeg(data, maxPixels: 1920), let thumb = jpeg(data, maxPixels: 400) else { return nil }
        return .set(image: full, thumbnail: thumb)
    }

    private nonisolated static func jpeg(_ data: Data, maxPixels: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixels,
              ] as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }

    #if DEBUG
    /// Sample countdowns for screenshots and the simulator.
    private func seedDemoData() {
        guard repository.fetchAll().isEmpty else { return }
        let day: TimeInterval = 86_400
        var newYear = Countdown(title: "New Year's Eve Party", details: "Midnight on the roof", targetDate: Date() + 83 * day, isPinned: true,
                                createdAt: Date() - 30 * day)
        newYear.style = CountdownStyle(background: .scene(.fireworks), font: .expanded)
        var wedding = Countdown(title: "Maya & Theo's Wedding", details: "Sonoma", targetDate: Date() + 41 * day, createdAt: Date() - 200 * day)
        wedding.style = CountdownStyle(background: .scene(.wedding), font: .serif)
        var birthday = Countdown(title: "Sam's Birthday", details: "", targetDate: Date() + 9 * day, createdAt: Date() - 20 * day)
        birthday.style = CountdownStyle(background: .scene(.birthday), font: .rounded)
        birthday.extras.unit = .sleeps
        var launch = Countdown(title: "Launch", details: "", targetDate: Date() + 40, createdAt: Date() - day)
        launch.style = CountdownStyle(background: .gradient(GradientSpec.presets[4].spec), font: .rounded)
        for countdown in [newYear, wedding, birthday, launch] { repository.upsert(countdown) }
    }
    #endif
}
