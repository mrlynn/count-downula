import AppKit
import SwiftUI

/// Which screen the popover is showing.
@MainActor
@Observable
final class PopoverNavigation {
    var selectedID: UUID?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = CountdownStore()
    private let navigation = PopoverNavigation()
    private let popover = NSPopover()
    private var mainItem: NSStatusItem!
    private var pinnedItems: [UUID: NSStatusItem] = [:]
    private var thumbnailCache: [String: NSImage] = [:]
    private var editorWindow: NSWindow?
    private var paywallWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        mainItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = mainItem.button {
            button.image = NSImage.countdownulaMark
            button.image?.accessibilityDescription = "Count Downcula"
            button.target = self
            button.action = #selector(mainItemClicked(_:))
        }

        let actions = PopoverActions(
            add: { [weak self] in self?.openEditor(for: nil) },
            edit: { [weak self] countdown in self?.openEditor(for: countdown) },
            unlock: { [weak self] in self?.openPaywall() },
            quit: { NSApp.terminate(nil) }
        )
        let host = NSHostingController(rootView: PopoverView(store: store, navigation: navigation, actions: actions))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true

        store.onUpdate = { [weak self] in self?.refreshPinnedItems() }
        refreshPinnedItems()
        Notifier.requestAuthorization()

        #if DEBUG
        // Screenshots: -openPopover shows the list without clicking the menu bar, -select "<title>" opens a
        // countdown in it, -openEditor "<title>" edits one and -openPaywall shows the upsell.
        let arguments = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        }
        let named = { [store] (title: String?) in title.flatMap { t in store.countdowns.first { $0.title == t } } }
        if arguments.contains("-openPopover"), let button = mainItem.button {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.togglePopover(from: button, selecting: named(value(after: "-select"))?.id)
            }
        }
        if let countdown = named(value(after: "-openEditor")) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.openEditor(for: countdown) }
        }
        if arguments.contains("-openPaywall") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.openPaywall() }
        }
        #endif
    }

    // MARK: - Popover

    @objc private func mainItemClicked(_ sender: NSStatusBarButton) {
        togglePopover(from: sender, selecting: nil)
    }

    @objc private func pinnedItemClicked(_ sender: NSStatusBarButton) {
        let id = sender.identifier.flatMap { UUID(uuidString: $0.rawValue) }
        togglePopover(from: sender, selecting: id)
    }

    private func togglePopover(from button: NSStatusBarButton, selecting id: UUID?) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        navigation.selectedID = id
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: - Pinned menu bar items

    private func refreshPinnedItems() {
        let pinned = store.countdowns.filter(\.isPinned)
        let pinnedIDs = Set(pinned.map(\.id))

        for (id, item) in pinnedItems where !pinnedIDs.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            pinnedItems[id] = nil
        }

        for countdown in pinned {
            let item = pinnedItems[countdown.id] ?? makePinnedItem(for: countdown.id)
            guard let button = item.button else { continue }

            let time = CountdownFormat.compact(countdown, at: store.now)
            let title = " \(truncated(countdown.title, to: 18)) · \(time)"
            if button.title != title {
                button.attributedTitle = NSAttributedString(string: title, attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                    .baselineOffset: 0.5,
                ])
            }
            button.image = menuBarImage(for: countdown)
            button.imagePosition = .imageLeading
            button.toolTip = countdown.details.isEmpty ? countdown.title : "\(countdown.title)\n\(countdown.details)"
        }
    }

    private func makePinnedItem(for id: UUID) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        item.button?.target = self
        item.button?.action = #selector(pinnedItemClicked(_:))
        pinnedItems[id] = item
        return item
    }

    private func menuBarImage(for countdown: Countdown) -> NSImage? {
        if countdown.hasImage {
            let key = countdown.imageCacheKey
            if let cached = thumbnailCache[key] { return cached }
            if let image = store.image(for: countdown) {
                let thumb = image.roundedThumbnail(side: 16)
                thumbnailCache[key] = thumb
                return thumb
            }
        }
        let symbol = countdown.kind == .timer ? "timer" : "calendar"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    private func truncated(_ text: String, to length: Int) -> String {
        text.count > length ? String(text.prefix(length - 1)) + "…" : text
    }

    // MARK: - Editor window

    private func openEditor(for countdown: Countdown?) {
        popover.performClose(nil)
        if countdown == nil, !store.entitlements.canAdd(to: store.countdowns) {
            openPaywall()
            return
        }
        editorWindow?.close()

        let view = EditorView(store: store, original: countdown, onLimit: { [weak self] in self?.openPaywall() }) { [weak self] saved in
            self?.editorWindow?.close()
            if let saved { self?.navigation.selectedID = saved.id }
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = countdown == nil ? "New Countdown" : "Edit Countdown"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        editorWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Unlimited

    private func openPaywall() {
        popover.performClose(nil)
        if let paywallWindow {
            NSApp.activate(ignoringOtherApps: true)
            paywallWindow.makeKeyAndOrderFront(nil)
            return
        }
        let view = PaywallView(entitlements: store.entitlements) { [weak self] in self?.paywallWindow?.close() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Count Downcula Unlimited"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        paywallWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === editorWindow { editorWindow = nil }
        if (notification.object as? NSWindow) === paywallWindow { paywallWindow = nil }
    }

    // MARK: - Main menu

    /// Menu-bar-only apps have no visible main menu, but text fields still need one
    /// for ⌘C / ⌘V / ⌘A / ⌘Z key equivalents to work.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Count Downcula", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}
