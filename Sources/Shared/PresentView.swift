#if !os(watchOS)
import CoreImage.CIFilterBuiltins
import SwiftUI

/// A countdown on a big screen: a Mac full screen, or a TV connected to an iPhone. Huge digits in
/// the countdown's style, the final ten seconds as one number, confetti at zero, and the live
/// link's QR code in the corner so the room can join. Same layout as the web's present page.
struct PresentView: View {
    let countdown: Countdown
    var photo: Image?
    /// Called once if zero arrives while it's on screen.
    var onZero: (() -> Void)?
    @State private var reachedZero = false
    /// Drawn once, not on every tick.
    @State private var roomCode: CGImage?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let now = context.date
            GeometryReader { geo in
                let unit = min(geo.size.width, geo.size.height * 16 / 9)
                ZStack {
                    StyledBackdrop(style: countdown.style, photo: photo)
                    RadialGradient(colors: scrim, center: .center, startRadius: 0, endRadius: geo.size.width * 0.7)

                    VStack(spacing: unit * 0.03) {
                        Text(countdown.title.isEmpty ? L("Untitled") : countdown.title)
                            .font(countdown.style.font(size: unit * 0.06))
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                            .multilineTextAlignment(.center)
                        readout(at: now, unit: unit)
                    }
                    .foregroundStyle(countdown.style.foregroundColor)
                    .padding(.horizontal, unit * 0.05)
                    // Clear of the QR code in the corner.
                    .padding(.bottom, roomCode == nil ? 0 : unit * 0.12)

                    if reachedZero {
                        ConfettiView(accent: countdown.style.accentColor, duration: 8)
                            .allowsHitTesting(false)
                    }

                    if let roomCode {
                        roomCodeCard(roomCode, size: unit * 0.11)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(unit * 0.025)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .onChange(of: !countdown.countsUp && countdown.targetDate <= now) { _, isZero in
                guard isZero, !reachedZero else { return }
                reachedZero = true
                onZero?()
            }
        }
        .ignoresSafeArea()
        .task(id: PresentRoom.link(for: countdown)) {
            roomCode = PresentRoom.link(for: countdown).flatMap(PresentRoom.qrCode(for:))
        }
    }

    private var scrim: [Color] {
        countdown.style.hasLightText
            ? [.black.opacity(0.35), .black.opacity(0.7)]
            : [.white.opacity(0.2), .white.opacity(0.65)]
    }

    @ViewBuilder
    private func readout(at now: Date, unit: CGFloat) -> some View {
        let left = countdown.targetDate.timeIntervalSince(now)
        if countdown.isPast(at: now) {
            Text("It's here!")
                .font(countdown.style.font(size: unit * 0.16))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
        } else if !countdown.countsUp, left <= 10 {
            // The last ten seconds: one number, as big as the screen allows.
            Text(verbatim: "\(Int(left.rounded(.up)))")
                .font(countdown.style.font(size: unit * 0.32))
                .monospacedDigit()
                .foregroundStyle(countdown.style.accentColor)
                .contentTransition(.numericText(countsDown: true))
                .animation(.spring(duration: 0.4), value: Int(left.rounded(.up)))
        } else {
            let tiles = Self.tiles(for: countdown, at: now)
            HStack(alignment: .top, spacing: unit * 0.04) {
                ForEach(tiles, id: \.label) { tile in
                    VStack(spacing: unit * 0.01) {
                        Text(verbatim: tile.value)
                            .font(countdown.style.font(size: unit * (tiles.count > 3 ? 0.11 : tiles.count > 2 ? 0.13 : 0.2)))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                        Text(tile.label)
                            .font(.system(size: unit * 0.026, weight: .semibold))
                            .opacity(0.75)
                    }
                }
            }
        }
    }

    /// The countdown's own unit when it has one, else days, hours, minutes and seconds, dropping
    /// days and then hours as they run out.
    static func tiles(for countdown: Countdown, at now: Date) -> [UnitReading.Tile] {
        if let reading = countdown.reading(at: now) { return reading.tiles }
        let p = countdown.timeParts(at: now)
        let two = { (n: Int) in String(format: "%02d", n) }
        var tiles: [UnitReading.Tile] = []
        if p.days > 0 { tiles.append(.init(value: "\(p.days)", label: L("Days"))) }
        if p.days > 0 || p.hours > 0 { tiles.append(.init(value: two(p.hours), label: L("Hours"))) }
        tiles.append(.init(value: two(p.minutes), label: L("Min")))
        tiles.append(.init(value: two(p.seconds), label: L("Sec")))
        return tiles
    }

    private func roomCodeCard(_ code: CGImage, size: CGFloat) -> some View {
        HStack(spacing: size * 0.12) {
            Image(decorative: code, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
            VStack(alignment: .leading, spacing: 2) {
                Text("Scan to count down with us")
                    .font(.system(size: max(12, size * 0.13), weight: .semibold))
                if countdown.extras.link?.isHosted != true, countdown.extras.subscription?.isHosted != true {
                    Text(verbatim: "Count Downcula")
                        .font(.system(size: max(11, size * 0.11), weight: .medium))
                        .opacity(0.6)
                }
            }
            .frame(maxWidth: size * 1.3, alignment: .leading)
        }
        .foregroundStyle(Color(red: 0.1, green: 0.04, blue: 0.06))
        .padding(size * 0.1)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
    }
}

/// Where the room's QR code points: the countdown's live link, tagged so joins from it can be counted.
enum PresentRoom {
    static func link(for countdown: Countdown) -> URL? {
        guard let url = countdown.extras.link?.url ?? countdown.extras.subscription?.url,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.queryItems = (parts.queryItems ?? []).filter { $0.name != "src" } + [URLQueryItem(name: "src", value: "present")]
        return parts.url
    }

    static func qrCode(for url: URL) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        return CIContext().createCGImage(image, from: image.extent)
    }
}
#endif
