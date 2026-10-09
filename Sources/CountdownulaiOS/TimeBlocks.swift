import SwiftUI

/// Days / hours / minutes / seconds tiles, or the countdown's own unit: "12 SLEEPS", "6 WEEKS 5 DAYS".
struct TimeBlocks: View {
    let parts: TimeParts
    var reading: UnitReading?
    var tileColor = Color.primary.opacity(0.06)
    var size: CGFloat = 34
    var style = CountdownStyle.default

    var body: some View {
        if let reading {
            HStack(spacing: 8) {
                ForEach(reading.tiles, id: \.self) { tile in block(tile.value, tile.label) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reading.long)
        } else {
            clock
        }
    }

    private var clock: some View {
        HStack(spacing: 8) {
            block(String(format: "%02d", parts.days), L("Days"))
            block(String(format: "%02d", parts.hours), L("Hours"))
            block(String(format: "%02d", parts.minutes), L("Min"))
            block(String(format: "%02d", parts.seconds), L("Sec"))
        }
        .opacity(parts.isPast ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(parts.isPast
            ? "Finished"
            : "\(parts.days) days, \(parts.hours) hours, \(parts.minutes) minutes, \(parts.seconds) seconds \(parts.countsUp ? L("so far") : L("left"))")
    }

    private func block(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: value)
                .font(style.font(size: size))
                .monospacedDigit()
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(tileColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
