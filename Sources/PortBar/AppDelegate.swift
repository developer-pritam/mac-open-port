import AppKit
import Combine
import SwiftUI

/// Borderless panel that can take keyboard focus (for the search field) without activating the app.
final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// Width is fixed; height is the starting/maximum value — the panel shrinks to fit its content.
    static let size = NSSize(width: 440, height: 600)
    static let cornerRadius: CGFloat = 22

    private let store = PortStore()
    private let settings = AppSettings()
    private let updater = Updater()
    private let hotKey = HotKey()
    private var cancellables: Set<AnyCancellable> = []

    private var statusItem: NSStatusItem!
    private var panel: GlassPanel!
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var timer: Timer?
    private var ticks = 0
    private var panelHeight: CGFloat = 220
    /// Screen y of the panel's top edge, so resizing keeps it hanging from the same place.
    private var panelTop: CGFloat = 0
    /// Set once the user drags the panel: it then stays open on outside clicks and keeps its position.
    private var detached = false
    /// Where the user last dragged the panel (top-left), used when there's no menu bar icon to hang from.
    private var draggedTopLeft: NSPoint?
    private var movingProgrammatically = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.terminalGlyph()
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        panel = makePanel()
        store.onUpdate = { [weak self] in self?.updateStatusTitle() }
        store.refresh()
        updater.notify = { [weak self] text, isError in self?.store.show(text, error: isError) }

        settings.$showStatusBarIcon
            .sink { [weak self] visible in self?.statusItem.isVisible = visible }
            .store(in: &cancellables)
        HotKey.onPress = { [weak self] in self?.togglePanel() }
        settings.$shortcut
            .sink { [weak self] shortcut in
                guard let self, !self.hotKey.register(shortcut) else { return }
                self.store.show("\(shortcut.title) is already used by another app — pick a different shortcut in ⋯", error: true)
            }
            .store(in: &cancellables)

        // Fast refresh while the panel is open; a slow background refresh keeps the menu bar count current.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.ticks += 1
                if self.panel.isVisible || self.ticks % 5 == 0 { self.store.refresh() }
                if self.ticks % 1200 == 0, self.settings.autoCheckUpdates { self.updater.checkIfDue() } // hourly look, daily check
            }
        }
        if settings.autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.updater.checkIfDue() }
        }

        if CommandLine.arguments.contains("--show") || !settings.showStatusBarIcon {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showPanel() }
        }
    }

    /// Launching the app again (Spotlight, Finder, `open -a PortBar`) shows the panel — the way back when the icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    private func makePanel() -> GlassPanel {
        let panel = GlassPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        // A plain container that always matches the window; the glass and the SwiftUI content are siblings inside it,
        // both autoresizing, so the content can never end up offset from the window.
        let container = NSView(frame: NSRect(origin: .zero, size: Self.size))
        container.autoresizesSubviews = true

        let background: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: container.bounds)
            glass.cornerRadius = Self.cornerRadius
            background = glass
        } else {
            let blur = NSVisualEffectView(frame: container.bounds)
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = Self.cornerRadius
            blur.layer?.cornerCurve = .continuous
            blur.layer?.masksToBounds = true
            background = blur
        }
        background.autoresizingMask = [.width, .height]
        container.addSubview(background)

        let hosting = NSHostingView(rootView: PanelView(
            store: store,
            settings: settings,
            updater: updater,
            close: { [weak self] in self?.hidePanel() },
            onHeightChange: { [weak self] h in self?.resizePanel(to: h) }
        ))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.sizingOptions = []
        // Clip content to the rounded shape so nothing pokes past the glass corners.
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = Self.cornerRadius
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
        container.addSubview(hosting)

        panel.contentView = container
        return panel
    }

    private func updateStatusTitle() {
        let count = store.relevantPortCount
        statusItem.button?.title = count > 0 ? " \(count)" : ""
        statusItem.button?.toolTip = "\(count) open port\(count == 1 ? "" : "s")"
    }

    @objc private func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    private func showPanel() {
        store.refresh()
        store.focusSearch()
        guard !panel.isVisible else {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let width = Self.size.width
        var origin: NSPoint
        if settings.showStatusBarIcon, let button = statusItem.button, let buttonWindow = button.window {
            // Hang from the menu bar icon.
            let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            origin = NSPoint(x: min(max(anchor.midX - width / 2, screen.minX + 8), screen.maxX - width - 8), y: anchor.minY - 6)
            button.highlight(true)
        } else if let dragged = draggedTopLeft {
            origin = dragged
        } else {
            // No icon: drop in from the top centre of the screen under the mouse, Spotlight-style.
            let mouse = NSEvent.mouseLocation
            let screen = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)?.visibleFrame ?? .zero
            origin = NSPoint(x: screen.midX - width / 2, y: screen.maxY - screen.height * 0.12)
        }
        panelTop = origin.y
        detached = false
        applyFrame(NSRect(x: origin.x, y: panelTop - panelHeight, width: width, height: panelHeight))

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1
        }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.detached else { return }
                self.hidePanel()
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                MainActor.assumeIsolated { self?.hidePanel() }
                return nil
            }
            return event
        }
    }

    private func resizePanel(to height: CGFloat) {
        let h = min(ceil(height), Self.size.height)
        guard h > 0, abs(h - panelHeight) >= 1 else { return }
        panelHeight = h
        if panel.isVisible {
            applyFrame(NSRect(x: panel.frame.minX, y: panelTop - h, width: Self.size.width, height: h))
        }
    }

    private func applyFrame(_ frame: NSRect) {
        movingProgrammatically = true
        panel.setFrame(frame, display: true)
        movingProgrammatically = false
        // The window server caches the shadow shape; refresh it after layout or the old outline shows at the corners.
        DispatchQueue.main.async { self.panel.invalidateShadow() }
    }

    func windowDidMove(_ notification: Notification) {
        guard !movingProgrammatically, panel.isVisible else { return }
        // The user dragged the panel: keep it where they put it.
        detached = true
        panelTop = panel.frame.maxY
        draggedTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        statusItem.button?.highlight(false)
    }

    /// Menu bar glyph: a terminal window with a ":" prompt and cursor (matches the app icon). Template, so macOS tints it.
    private static func terminalGlyph() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            NSColor.black.set()
            let b = r.insetBy(dx: r.width * 0.06, dy: r.height * 0.14)
            let frame = NSBezierPath(roundedRect: b, xRadius: r.width * 0.16, yRadius: r.width * 0.16)
            frame.lineWidth = r.width * 0.09
            frame.stroke()
            let d = r.width * 0.13
            for y in [b.midY + d * 0.55, b.midY - d * 1.55] {
                NSBezierPath(ovalIn: NSRect(x: b.minX + b.width * 0.24, y: y, width: d, height: d)).fill()
            }
            NSBezierPath(roundedRect: NSRect(x: b.minX + b.width * 0.5, y: b.midY - d * 1.5, width: b.width * 0.26, height: d * 0.95),
                         xRadius: d * 0.3, yRadius: d * 0.3).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Open ports"
        return image
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        detached = false
        statusItem.button?.highlight(false)
        [clickMonitor, keyMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        clickMonitor = nil
        keyMonitor = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking the status item itself also resigns key; let togglePanel handle that case.
        DispatchQueue.main.async {
            guard !self.detached else { return }
            if let event = NSApp.currentEvent, event.window == self.statusItem.button?.window { return }
            self.hidePanel()
        }
    }
}
