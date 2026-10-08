import SwiftUI

/// Days / hours / minutes / seconds tiles.
struct TimeBlocks: View {
    let parts: TimeParts
    var tileColor = Color.primary.opacity(0.06)
    var size: CGFloat = 34
    var style = CountdownStyle.default

    var body: some View {
        HStack(spacing: 8) {
            block(parts.days, "Days")
            block(parts.hours, "Hours")
            block(parts.minutes, "Min")
            block(parts.seconds, "Sec")
        }
        .opacity(parts.isPast ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(parts.isPast
            ? "Finished"
            : "\(parts.days) days, \(parts.hours) hours, \(parts.minutes) minutes, \(parts.seconds) seconds \(parts.countsUp ? "so far" : "left")")
    }

    private func block(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%02d", value))
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
