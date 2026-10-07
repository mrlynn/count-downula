import SwiftUI

/// Photo for a countdown, or a colored placeholder derived from its id.
struct CountdownArtwork: View {
    let countdown: Countdown
    let store: CountdownStore
    var symbolSize: CGFloat = 22

    var body: some View {
        if !countdown.style.background.usesPhoto {
            StyledBackdrop(style: countdown.style)
        } else if let image = store.image(for: countdown) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(colors: [tint, tint.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: countdown.kind == .timer ? "timer" : "calendar")
                    .font(.system(size: symbolSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var tint: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .red]
        let hash = countdown.id.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[hash % palette.count]
    }
}

struct CountdownRow: View {
    let countdown: Countdown
    let store: CountdownStore
    @State private var isHovering = false

    var body: some View {
        let now = store.now
        let isPast = countdown.isPast(at: now)

        HStack(spacing: 12) {
            CountdownArtwork(countdown: countdown, store: store)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(countdown.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if countdown.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
                if !countdown.details.isEmpty {
                    Text(countdown.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if !isPast {
                    ProgressView(value: countdown.progress(at: now))
                        .progressViewStyle(.linear)
                        .tint(countdown.style.accentColor)
                        .controlSize(.mini)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(isPast ? "Done" : CountdownFormat.compact(from: now, to: countdown.targetDate))
                    .font(countdown.style.font(size: 15))
                    .monospacedDigit()
                    .foregroundStyle(isPast ? Color.secondary : Color.primary)
                Text(countdown.targetDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(height: 76)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.08 : 0.04))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .opacity(isPast ? 0.75 : 1)
    }
}
