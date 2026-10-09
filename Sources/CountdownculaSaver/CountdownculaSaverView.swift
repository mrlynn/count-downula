import AppKit
import OSLog
import ScreenSaver
import SwiftUI

/// The Count Downcula screensaver: pinned countdowns full screen in their styles (Next Up when none
/// are pinned), the same layout as Present on the Mac and the web. It reads the copy of the
/// countdowns the Mac app leaves in the screensaver host's container (`SaverSnapshot`).
///
/// Third-party screensavers run inside Apple's `legacyScreenSaver` host, which has known problems on
/// Sonoma and later: `stopAnimation` is never called outside System Settings' preview, every start
/// makes a new view while the old ones keep running, and the host process is never terminated. The
/// workarounds here follow Aerial's ScreenSaverMinimal template: one live instance per screen, and
/// exiting the host when the system says the screensaver is stopping.
final class CountdownculaSaverView: ScreenSaverView {
    static let log = Logger(subsystem: "com.countdowncula.saver", category: "saver")
    /// Every instance this process has made, so a new one can retire the ones it replaces.
    private static var instances: [WeakSaver] = []
    private static var counter = 0
    private static var observingStop = false

    private let number: Int
    private var host: NSHostingView<SaverRoot>?
    /// Watches for the window going away without a stop (see `checkVisibility`).
    private var watchdog: Timer?
    private var hiddenSince: Date?

    override init?(frame: NSRect, isPreview: Bool) {
        Self.counter += 1
        number = Self.counter
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        Self.log.notice("init #\(self.number) preview=\(isPreview) frame=\(frame.width)x\(frame.height) pid=\(ProcessInfo.processInfo.processIdentifier)")
        Self.observeStop()
        SaverSpike.probe(instance: number)
    }

    required init?(coder: NSCoder) { nil }

    override func startAnimation() {
        super.startAnimation()
        // Retire older instances on the same screen: the host makes a new one each time and never
        // stops the old, so they would otherwise all keep drawing.
        for other in Self.instances.compactMap(\.view) where other !== self && other.frame.size == frame.size {
            other.retire()
        }
        Self.instances.removeAll { $0.view == nil }
        Self.instances.append(WeakSaver(view: self))
        guard host == nil else { return }
        WidgetSnapshot.directoryOverride = SaverSnapshot.readDirectory
        let view = NSHostingView(rootView: SaverRoot())
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        host = view
        Self.log.notice("start #\(self.number) instances=\(Self.instances.count)")
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkVisibility() }
        }
    }

    /// The backstop for a stop that never comes: on macOS 26 the full-screen Preview's copy keeps
    /// running (and drawing) after it's dismissed, with no stop and no willstop broadcast. Once the
    /// window has been off screen for 10 seconds, stop drawing, and leave the host if no copy is
    /// visible anywhere. System Settings' small preview gets proper stops, so it's left alone.
    private func checkVisibility() {
        let visible = window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false
        if visible { hiddenSince = nil; return }
        let since = hiddenSince ?? Date()
        hiddenSince = since
        guard Date().timeIntervalSince(since) >= 10, !isPreview else { return }
        Self.log.notice("hidden 10s #\(self.number): retiring")
        retire()
        let anyVisible = Self.instances.compactMap(\.view).contains { $0.window?.occlusionState.contains(.visible) == true }
        if !anyVisible {
            Self.log.notice("no copy visible: leaving the host")
            exit(0)
        }
    }

    override func stopAnimation() {
        super.stopAnimation()
        Self.log.notice("stop #\(self.number)")
        retire()
    }

    /// Drawing is SwiftUI's job (TimelineView ticks on its own); `animateOneFrame` isn't relied on.
    override func animateOneFrame() {}

    override var hasConfigureSheet: Bool { false }

    private func retire() {
        watchdog?.invalidate()
        watchdog = nil
        host?.removeFromSuperview()
        host = nil
        Self.log.notice("retired #\(self.number)")
    }

    /// The system's "screensaver will stop" broadcast is the one signal that still arrives. Leaving
    /// the host then is heavy-handed, but it's the only way found to stop instances piling up and
    /// running on in the background. Never in System Settings' preview, which lives in that host too.
    private static func observeStop() {
        guard !observingStop else { return }
        observingStop = true
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screensaver.willstop"), object: nil, queue: .main) { _ in
            log.notice("willstop: leaving the host")
            if !instances.compactMap(\.view).allSatisfy(\.isPreview) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
            }
        }
    }
}

private struct WeakSaver {
    weak var view: CountdownculaSaverView?
}

/// What the screensaver shows: the countdown in rotation, read again every few seconds so edits in
/// the Mac app show up, or a word on what to do when there's nothing to show.
private struct SaverRoot: View {
    @State private var countdowns: [Countdown] = []
    @State private var photos: [String: Image] = [:]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            Group {
                if let countdown = SaverSnapshot.showing(countdowns, at: context.date) {
                    PresentView(countdown: countdown, photo: photos[countdown.imageCacheKey])
                        .id(countdown.id)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 16) {
                        FangMark()
                            .foregroundStyle(Color.countdownulaBlood)
                            .frame(width: 120, height: 120)
                        Text(verbatim: "Count Downcula")
                            .font(.system(size: 34, weight: .bold, design: .serif))
                        Text("Open Count Downcula on this Mac to show your countdowns here.")
                            .font(.title3)
                            .opacity(0.7)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LinearGradient.countdownulaNight)
                }
            }
            .animation(.easeInOut(duration: 0.8), value: SaverSnapshot.showing(countdowns, at: context.date)?.id)
            .task(id: Int(context.date.timeIntervalSinceReferenceDate / 5)) { reload() }
        }
    }

    private func reload() {
        let fresh = WidgetSnapshot.read()
        if fresh != countdowns { countdowns = fresh }
        for countdown in fresh where countdown.hasImage && photos[countdown.imageCacheKey] == nil {
            if let data = WidgetSnapshot.photo(for: countdown), let image = NSImage(data: data) {
                photos[countdown.imageCacheKey] = Image(nsImage: image)
            }
        }
    }
}
