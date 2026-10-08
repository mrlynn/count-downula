import SwiftUI

/// A countdown's background: its photo, scene, gradient or color, with the fang dial over plain backgrounds.
struct CountdownArtwork: View {
    @Environment(PhoneStore.self) private var store
    let countdown: Countdown
    var useThumbnail = false
    var now = Date()
    /// Tucks the placeholder dial into the top-right corner so text can sit over the artwork.
    var dialInCorner = false
    /// Overrides the stored photo (the editor's unsaved preview).
    var previewImage: UIImage?

    var body: some View {
        let image = previewImage ?? (useThumbnail ? store.thumbnail(for: countdown) : store.image(for: countdown))
        StyledBackdrop(
            style: countdown.style,
            photo: image.map { Image(uiImage: $0) },
            dialRemaining: countdown.dialRemaining(at: now),
            dialPadding: useThumbnail ? 8 : dialInCorner ? 18 : 40,
            dialAlignment: dialInCorner ? .topTrailing : .center,
            dialMaxWidth: dialInCorner ? 72 : nil
        )
    }
}

/// The big styled card: backdrop, title and a live D/H/M/S readout. Used for the hero, the detail
/// header and the editor's preview.
struct StyledCountdownCard: View {
    let countdown: Countdown
    let now: Date
    var badge: String?
    var subtitle: Text?
    var previewImage: UIImage?
    var height: CGFloat = 260

    var body: some View {
        let style = countdown.style
        let parts = countdown.timeParts(at: now)

        CountdownArtwork(countdown: countdown, now: now, dialInCorner: true, previewImage: previewImage)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay { StyleScrim(style: style) }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .tracking(1.2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(style.accentColor, in: Capsule())
                        }
                        subtitle
                            .font(.caption.weight(.medium))
                            .foregroundStyle(style.foregroundColor.opacity(0.8))
                    }
                    Text(countdown.title.isEmpty ? "Untitled" : countdown.title)
                        .font(style.font(.title))
                        .lineLimit(2)
                    TimeBlocks(parts: parts, tileColor: style.foregroundColor.opacity(0.14), size: 30, style: style)
                        .environment(\.colorScheme, style.hasLightText ? .dark : .light)
                }
                .foregroundStyle(style.foregroundColor)
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - Milestones

/// A progress bar with a tick for each milestone; reached ticks fill in.
struct MilestoneProgressBar: View {
    let countdown: Countdown
    let now: Date

    var body: some View {
        let progress = countdown.progress(at: now)
        let accent = countdown.style.accentColor
        let total = countdown.targetDate.timeIntervalSince(countdown.startDate)

        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(accent).frame(width: geo.size.width * progress)
                ForEach(countdown.scheduledMilestones) { scheduled in
                    let fraction = total > 0 ? scheduled.date.timeIntervalSince(countdown.startDate) / total : 0
                    let reached = scheduled.date <= now
                    Circle()
                        .fill(reached ? accent : Color(.systemBackground))
                        .overlay { Circle().strokeBorder(accent, lineWidth: 2) }
                        .frame(width: 12, height: 12)
                        .position(x: geo.size.width * fraction, y: geo.size.height / 2)
                }
            }
        }
        .frame(height: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((progress * 100).rounded(.down))) percent of the wait is behind you")
    }
}

/// Every milestone in order: reached ones checked off, the next one counting down.
struct MilestoneTimeline: View {
    let countdown: Countdown
    let now: Date

    var body: some View {
        let next = countdown.nextMilestone(at: now)

        let all = countdown.scheduledMilestones
        let reached = all.filter { $0.date <= now }
        let ahead = all.filter { $0.date > now }
        // Long lists (a count-up's yearly chips) show the last few reached and the next few ahead.
        let shown = Array(reached.suffix(3)) + Array(ahead.prefix(3))
        let hidden = all.count - shown.count

        VStack(alignment: .leading, spacing: 0) {
            Text("Milestones")
                .font(.headline)
                .padding(.bottom, 8)
            ForEach(shown) { scheduled in
                let reached = scheduled.date <= now
                let isNext = scheduled.id == next?.id
                HStack(spacing: 12) {
                    Text(scheduled.milestone.displayEmoji)
                        .font(.title3)
                        .frame(width: 36, height: 36)
                        .background(
                            (isNext ? countdown.style.accentColor.opacity(0.18) : Color.primary.opacity(0.06)),
                            in: Circle()
                        )
                        .grayscale(reached || isNext ? 0 : 0.8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(scheduled.milestone.title)
                            .font(.subheadline.weight(isNext ? .semibold : .regular))
                        Text(scheduled.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if reached {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(countdown.style.accentColor)
                            .accessibilityLabel("Reached")
                    } else if isNext {
                        Text("in \(CountdownFormat.compact(from: now, to: scheduled.date))")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(countdown.style.accentColor)
                    }
                }
                .padding(.vertical, 6)
                .opacity(reached || isNext ? 1 : 0.7)
            }
            if hidden > 0 {
                Text("\(hidden) more \(hidden == 1 ? "milestone" : "milestones")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }
}

/// The toast that drops in with the confetti.
struct CelebrationBanner: View {
    let emoji: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.system(size: 34))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}
