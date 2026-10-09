import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// A portrait card for Messages or Instagram: the countdown's backdrop, its title, the big number
/// and the latest milestone reached. After zero it's the recap: how long it was counted, and for a
/// shared countdown, who counted with you.
struct ShareCardView: View {
    let countdown: Countdown
    var photo: UIImage?
    let now: Date
    /// The shared countdown's people, from the server, once it reached zero.
    var recap: Recap?

    var body: some View {
        let style = countdown.style
        let headline = Self.headline(for: countdown, at: now)

        ZStack(alignment: .bottomLeading) {
            StyledBackdrop(style: style, photo: photo.map { Image(uiImage: $0) },
                           dialRemaining: countdown.dialRemaining(at: now), dialPadding: 60,
                           dialAlignment: .top, dialMaxWidth: 150)
            StyleScrim(style: style, strength: 1.2)

            VStack(alignment: .leading, spacing: 10) {
                if let reached = countdown.scheduledMilestones.last(where: { $0.date <= now }) {
                    Text("\(reached.milestone.displayEmoji) \(reached.milestone.title)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(style.accentColor, in: Capsule())
                }
                Text(countdown.title)
                    .font(style.font(size: 30))
                    .lineLimit(3)
                Text(headline.value)
                    .font(style.font(size: 64))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(headline.caption)
                    .font(.system(size: 17, weight: .medium))
                    .opacity(0.85)
                if countdown.isPast(at: now), let line = recap?.peopleLine(isPublic: countdown.extras.subscription?.isPublic == true) {
                    Text(line)
                        .font(.system(size: 15, weight: .semibold))
                        .opacity(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    FangMark()
                        .foregroundStyle(style.accentColor)
                        .frame(width: 18, height: 18)
                    Text("Count Downcula")
                        .font(.system(size: 13, weight: .semibold))
                        .opacity(0.7)
                }
                .padding(.top, 10)
            }
            .foregroundStyle(style.foregroundColor)
            .padding(28)
        }
        .frame(width: 360, height: 450)
        .clipped()
    }

    static func headline(for countdown: Countdown, at now: Date) -> (value: String, caption: String) {
        let parts = countdown.timeParts(at: now)
        if countdown.countsUp {
            let days = parts.days
            return days > 0
                ? (L("\(days) days"), L("since \(countdown.targetDate.formatted(.dateTime.month(.wide).day().year()))"))
                : (CountdownFormat.compact(countdown, at: now), L("and counting"))
        }
        if parts.isPast {
            let date = countdown.targetDate.formatted(.dateTime.month(.wide).day().year())
            // The recap: "142 days", counted.
            if countdown.kind == .event, let counted = Recap.counted(countdown) { return (counted, L("counted · \(date)")) }
            return (L("It's here!"), date)
        }
        if parts.days > 0 {
            return (L("\(parts.days) days"), L("to go · \(countdown.targetDate.formatted(.dateTime.month(.wide).day()))"))
        }
        return (CountdownFormat.compact(countdown, at: now), L("to go"))
    }
}

/// Renders the share card as a PNG only when someone actually shares it.
struct ShareCard: Transferable {
    let countdown: Countdown
    let photo: UIImage?
    let now: Date
    var recap: Recap?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in
            try await MainActor.run {
                guard let data = card.renderPNG() else { throw CocoaError(.fileWriteUnknown) }
                Analytics.log(.imageExported, slug: card.countdown.extras.link?.slug ?? card.countdown.extras.subscription?.slug,
                              source: card.countdown.hasReachedZero(at: card.now) ? "recap" : nil)
                return data
            }
        }
        .suggestedFileName { "\($0.countdown.title).png" }
    }

    @MainActor
    func renderPNG() -> Data? {
        let renderer = ImageRenderer(content: ShareCardView(countdown: countdown, photo: photo, now: now, recap: recap))
        renderer.scale = 3  // 1080 × 1350
        return renderer.uiImage?.pngData()
    }
}
