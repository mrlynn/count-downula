import TVServices

/// The Top Shelf: when Count Downcula sits in the top row of the Home Screen, what's coming up
/// shows above it, and selecting one opens it full screen. Read from the snapshot the app writes
/// to the App Group whenever its countdowns change.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        let now = Date()
        let countdowns = WidgetSnapshot.read()
        let upcoming = countdowns.filter { $0.isUpcoming(at: now) }.sorted { $0.targetDate < $1.targetDate }
        let countingUp = countdowns.filter(\.countsUp)
        guard !upcoming.isEmpty || !countingUp.isEmpty else { return nil }

        func items(_ list: [Countdown]) -> [TVTopShelfSectionedItem] {
            list.prefix(10).map { countdown in
                let item = TVTopShelfSectionedItem(identifier: countdown.id.uuidString)
                item.title = "\(countdown.title) · \(CountdownFormat.compact(countdown, at: now))"
                item.imageShape = .hdtv
                if let url = WidgetSnapshot.thumbnailFileURL(for: countdown) {
                    item.setImageURL(url, for: .screenScale1x)
                    item.setImageURL(url, for: .screenScale2x)
                }
                item.displayAction = TVTopShelfAction(url: CountdownLink.url(for: countdown.id))
                return item
            }
        }

        var sections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = []
        if !upcoming.isEmpty {
            let section = TVTopShelfItemCollection(items: items(upcoming))
            section.title = L("Coming Up")
            sections.append(section)
        }
        if !countingUp.isEmpty {
            let section = TVTopShelfItemCollection(items: items(countingUp))
            section.title = L("Counting Up")
            sections.append(section)
        }
        return TVTopShelfSectionedContent(sections: sections)
    }
}
