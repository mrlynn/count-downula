import AVFoundation
import SwiftUI

// MARK: - Frame

/// One frame of the share video, 360 × 640 points (1080 × 1920 rendered): the fang ring drains to
/// where the countdown stands, the seconds tick, and it closes on the title and the mark.
struct ShareVideoFrame: View {
    let countdown: Countdown
    var photo: UIImage?
    let now: Date
    /// How full the ring is drawn on this frame.
    let dial: Double
    /// 0 while counting, rising to 1 as the closing title card fades in.
    let outro: Double

    static let size = CGSize(width: 360, height: 640)

    var body: some View {
        let style = countdown.style
        let headline = ShareCardView.headline(for: countdown, at: now)

        ZStack {
            StyledBackdrop(style: style, photo: photo.map { Image(uiImage: $0) })
            StyleScrim(style: style, strength: 1.3)

            VStack(alignment: .leading, spacing: 10) {
                FangDial(remaining: dial, trackOpacity: 0.3)
                    .foregroundStyle(style.accentColor)
                    .frame(width: 150, height: 150)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                Spacer()
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
                    .fixedSize(horizontal: false, vertical: true)
                Text(headline.value)
                    .font(style.font(size: 64))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(headline.caption)
                    .font(.system(size: 17, weight: .medium))
                    .opacity(0.85)
                if !countdown.isPast(at: now) {
                    Text(Self.clock(countdown.timeParts(at: now)))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .padding(.top, 4)
                }
                Spacer().frame(height: 36)
            }
            .foregroundStyle(style.foregroundColor)
            .padding(28)
            .opacity(1 - outro)

            outroCard(style: style)
                .opacity(outro)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }

    private func outroCard(style: CountdownStyle) -> some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 18) {
                Text(countdown.title)
                    .font(style.font(size: 34))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .foregroundStyle(.white)
                FangMark()
                    .foregroundStyle(style.accentColor)
                    .frame(width: 120, height: 120)
                Text("Count Downcula")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(36)
        }
    }

    /// "12d 04:33:09", ticking every second.
    static func clock(_ parts: TimeParts) -> String {
        let time = String(format: "%02d:%02d:%02d", parts.hours, parts.minutes, parts.seconds)
        return parts.days > 0 ? "\(parts.days)d \(time)" : time
    }
}

// MARK: - Rendering

/// Renders the 6 second share loop to an H.264 file at 1080 × 1920, 30 fps.
@MainActor
enum ShareVideo {
    static let duration: Double = 6
    static let fps = 30
    /// The ring sweeps in over the first part, the closing card fades in over the last.
    static let sweepEnd: Double = 1.5
    static let outroStart: Double = 4.5
    static let outroFade: Double = 0.5

    enum Failure: LocalizedError {
        case couldNotWrite

        var errorDescription: String? { "Couldn't make the video. Try again." }
    }

    /// What frame `index` shows: the countdown at `start` plus the elapsed time, with the ring
    /// easing from full (empty for a count-up) to where it really is.
    static func frame(_ index: Int, of countdown: Countdown, photo: UIImage?, start: Date) -> ShareVideoFrame {
        let t = Double(index) / Double(fps)
        let now = start + t
        let target = countdown.dialRemaining(at: now)
        let from: Double = countdown.countsUp ? 0 : 1
        let sweep = min(t / sweepEnd, 1)
        let eased = 1 - pow(1 - sweep, 3)
        let outro = min(max((t - outroStart) / outroFade, 0), 1)
        return ShareVideoFrame(countdown: countdown, photo: photo, now: now,
                               dial: from + (target - from) * eased, outro: outro)
    }

    static func render(_ countdown: Countdown, photo: UIImage?, start: Date = Date(),
                       progress: (Double) -> Void) async throws -> URL {
        let width = Int(ShareVideoFrame.size.width * 3), height = Int(ShareVideoFrame.size.height * 3)
        let name = countdown.title.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        let url = URL.temporaryDirectory.appending(path: "\(name.isEmpty ? "Countdown" : name).mp4")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw Failure.couldNotWrite }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failure.couldNotWrite }
        writer.startSession(atSourceTime: .zero)

        let renderer = ImageRenderer(content: frame(0, of: countdown, photo: photo, start: start))
        renderer.scale = 3
        let frameCount = Int(duration) * fps
        for index in 0..<frameCount {
            try Task.checkCancellation()
            renderer.content = frame(index, of: countdown, photo: photo, start: start)
            guard let image = renderer.cgImage, let buffer = pixelBuffer(from: image, pool: adaptor.pixelBufferPool)
            else { writer.cancelWriting(); throw Failure.couldNotWrite }
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps)))
            else { writer.cancelWriting(); throw writer.error ?? Failure.couldNotWrite }
            progress(Double(index + 1) / Double(frameCount))
            // Let the progress label draw between frames.
            await Task.yield()
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? Failure.couldNotWrite }
        return url
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        return buffer
    }
}

// MARK: - Instagram Stories

/// Hands a video straight to the Instagram Stories composer through the pasteboard.
enum InstagramStories {
    /// Meta requires a Facebook app ID on every Stories share. It's `FacebookAppID` in project.yml;
    /// while that's empty the Instagram option stays hidden.
    static var facebookAppID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String,
              !id.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return id
    }

    static var isAvailable: Bool {
        guard facebookAppID != nil, let url = URL(string: "instagram-stories://share") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    static func share(video: URL) {
        guard let appID = facebookAppID,
              let url = URL(string: "instagram-stories://share?source_application=\(appID)"),
              let data = try? Data(contentsOf: video) else { return }
        UIPasteboard.general.setItems([["com.instagram.sharedSticker.backgroundVideo": data]],
                                      options: [.expirationDate: Date().addingTimeInterval(5 * 60)])
        UIApplication.shared.open(url)
    }
}

// MARK: - Detail screen control

/// "Share" on the detail screen: the still card, the video, or the video straight to Instagram Stories.
struct ShareCardMenu: View {
    let countdown: Countdown
    let photo: UIImage?
    let now: Date

    private enum Destination { case sheet, instagram }

    @State private var progress: Double?
    @State private var videoURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            ShareLink(item: ShareCard(countdown: countdown, photo: photo, now: now),
                      preview: SharePreview(countdown.title)) {
                Label("Image", systemImage: "photo")
            }
            Button("Video", systemImage: "film") { Task { await makeVideo(for: .sheet) } }
            if InstagramStories.isAvailable {
                Button("Instagram Stories", systemImage: "camera") { Task { await makeVideo(for: .instagram) } }
            }
        } label: {
            Label(progress.map { "Making Video… \(Int($0 * 100))%" } ?? "Share Card",
                  systemImage: "square.and.arrow.up")
                .monospacedDigit()
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(progress != nil)
        .sheet(item: $videoURL) { url in
            ActivitySheet(items: [url])
                .presentationDetents([.medium, .large])
        }
        .alert("Share", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func makeVideo(for destination: Destination) async {
        progress = 0
        defer { progress = nil }
        do {
            let url = try await ShareVideo.render(countdown, photo: photo) { progress = $0 }
            switch destination {
            case .sheet: videoURL = url
            case .instagram: InstagramStories.share(video: url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
