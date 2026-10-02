import AppKit
import SwiftUI

extension LauncherKind {
    var tint: Color {
        switch self {
        case .agent: .purple
        case .terminal: .green
        case .editor: .blue
        case .container: .teal
        case .service: .orange
        case .app, .system, .other: .gray
        }
    }

    var symbol: String {
        switch self {
        case .agent: "sparkles"
        case .terminal: "terminal"
        case .editor: "chevron.left.forwardslash.chevron.right"
        case .container: "shippingbox"
        case .service: "gearshape.2"
        case .app: "app"
        case .system: "apple.logo"
        case .other: "questionmark.circle"
        }
    }
}

// MARK: - Glass building blocks

/// Frosted card: a translucent fill with a light-catching hairline edge, tuned per appearance.
struct GlassCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat = 14
    var highlighted = false

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(Color.white.opacity(dark ? (highlighted ? 0.11 : 0.06) : (highlighted ? 0.55 : 0.38))))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(dark ? 0.22 : 0.9), .white.opacity(dark ? 0.04 : 0.25)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
            )
            .shadow(color: .black.opacity(dark ? 0.25 : 0.06), radius: highlighted ? 8 : 3, y: highlighted ? 3 : 1)
    }
}

extension View {
    func glassCard(radius: CGFloat = 14, highlighted: Bool = false) -> some View {
        modifier(GlassCard(radius: radius, highlighted: highlighted))
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color = .primary
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(tint.opacity(hover ? 1 : 0.75))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(hover ? 0.12 : 0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

// MARK: - Panel

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Height of everything that isn't the list (header, update banner, search, filters, footer).
private struct ChromeHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

private extension View {
    func reportChromeHeight() -> some View {
        background(GeometryReader { g in Color.clear.preference(key: ChromeHeightKey.self, value: g.size.height) })
    }
}

struct PanelView: View {
    @ObservedObject var store: PortStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var updater: Updater
    let close: () -> Void
    /// Reports the panel's natural height so the window can shrink to fit (short when there's little to show).
    let onHeightChange: (CGFloat) -> Void
    @State private var confirmStopAll = false
    @State private var listHeight: CGFloat = 0
    @State private var chromeHeight: CGFloat = 180
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .background(WindowDragArea())
                .overlay(alignment: .top) {
                    // Grabber hint: the header drags the panel.
                    Capsule().fill(Color.primary.opacity(0.18)).frame(width: 34, height: 4).padding(.top, 6)
                        .allowsHitTesting(false)
                }
            if let release = updater.availableRelease {
                updateBanner(release)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
            searchField
                .padding(.horizontal, 14)
            filterChips
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
            .reportChromeHeight()
            list
            footer
                .reportChromeHeight()
        }
        .onPreferenceChange(ChromeHeightKey.self) { chromeHeight = $0 }
        .frame(width: AppDelegate.size.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { g in Color.clear.preference(key: HeightKey.self, value: g.size.height) })
        .onPreferenceChange(HeightKey.self) { onHeightChange($0) }
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) { bannerView }
        .animation(.snappy(duration: 0.25), value: store.banner)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 44, height: 44)
                .padding(-4)

            VStack(alignment: .leading, spacing: 1) {
                Text("Open Ports")
                    .font(.system(size: 15, weight: .semibold))
                let n = store.relevantPortCount, procs = store.relevant.count
                Text("\(n) port\(n == 1 ? "" : "s") · \(procs) process\(procs == 1 ? "" : "es")")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            IconButton(symbol: "arrow.clockwise", help: "Refresh") { store.refresh() }
                .rotationEffect(.degrees(store.isScanning ? 360 : 0))
                .animation(store.isScanning ? .linear(duration: 0.6) : .default, value: store.isScanning)
            Menu {
                Section("Settings") {
                    Toggle("Show Status Bar Icon", isOn: Binding(get: { settings.showStatusBarIcon }, set: { visible in
                        settings.showStatusBarIcon = visible
                        if !visible { store.show("Menu bar icon hidden. \(settings.reopenHint)") }
                    }))
                    Picker("Open Shortcut", selection: $settings.shortcut) {
                        ForEach(Shortcut.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Show macOS & App Ports", isOn: $store.showSystem)
                    Toggle("Launch at Login", isOn: Binding(get: { store.launchAtLogin }, set: { store.launchAtLogin = $0 }))
                }
                Section("Updates") {
                    if let release = updater.availableRelease {
                        Button("Install PortBar \(release.version)…") { Task { await updater.install(release) } }
                    } else {
                        Button(updater.state == .checking ? "Checking…" : "Check for Updates…") {
                            Task { await updater.check(userInitiated: true) }
                        }
                        .disabled(updater.state == .checking || updater.state == .installing)
                    }
                    Toggle("Check Automatically", isOn: $settings.autoCheckUpdates)
                }
                Divider()
                Button("PortBar Website") { openURL("https://portbar.developerpritam.in") }
                Button("Source on GitHub") { openURL("https://github.com/developer-pritam/mac-open-port") }
                Text("Version \(updater.currentVersion)")
                Divider()
                Button("Quit PortBar") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func updateBanner(_ release: Updater.Release) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 0) {
                Text("PortBar \(release.version) is available").font(.system(size: 12, weight: .semibold))
                Text("You have \(updater.currentVersion)").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
            if updater.state == .installing {
                ProgressView().controlSize(.small)
            } else {
                Button("Release notes") { NSWorkspace.shared.open(release.pageURL) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Button { Task { await updater.install(release) } } label: {
                    Text("Install")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.blue.gradient))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .glassCard(radius: 12, highlighted: true)
    }

    private func openURL(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search port, process or folder", text: $store.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                // Return opens the top match in the browser.
                .onSubmit {
                    if let port = store.visible.first?.ports.first, let url = URL(string: "http://localhost:\(port)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .onChange(of: store.focusToken) { searchFocused = true }
            if !store.query.isEmpty {
                Button { store.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .glassCard(radius: 11)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(title: "All", count: store.relevant.count, tint: .accentColor, selected: store.kind == nil) {
                    store.kind = nil
                }
                ForEach(store.kindCounts, id: \.0) { kind, count in
                    chip(title: kind.title, count: count, tint: kind.tint, selected: store.kind == kind) {
                        store.kind = store.kind == kind ? nil : kind
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
        }
    }

    private func chip(title: String, count: Int, tint: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy(duration: 0.2)) { action() } }) {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .opacity(0.65)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background {
                if selected {
                    Capsule().fill(tint.gradient).shadow(color: tint.opacity(0.4), radius: 4, y: 1)
                }
            }
            .glassCard(radius: 20, highlighted: false)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var list: some View {
        let items = store.visible
        if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: store.processes.isEmpty && store.lastUpdated == nil ? "hourglass" : "checkmark.seal")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
                Text(store.lastUpdated == nil ? "Scanning…" : store.query.isEmpty ? "No open ports here" : "Nothing matches “\(store.query)”")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(items) { p in
                        ProcessRow(process: p, store: store)
                            .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.95))))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .animation(.snappy(duration: 0.25), value: items.map(\.pid))
                .background(GeometryReader { g in Color.clear.preference(key: ListHeightKey.self, value: g.size.height) })
            }
            .scrollIndicators(.never)
            // The list gets whatever the header and footer leave of the panel's maximum height, then scrolls.
            .frame(height: min(listHeight, max(120, AppDelegate.size.height - chromeHeight)))
            .onPreferenceChange(ListHeightKey.self) { listHeight = $0 }
        }
    }

    private var footer: some View {
        let stoppable = store.visible.filter { !$0.isSelf && !$0.isNoise }
        return HStack {
            if let updated = store.lastUpdated {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text("Updated \(max(0, Int(ctx.date.timeIntervalSince(updated))))s ago")
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            }
            Spacer()
            if stoppable.count > 1 {
                Button {
                    if confirmStopAll {
                        confirmStopAll = false
                        store.stop(stoppable, force: false)
                    } else {
                        confirmStopAll = true
                        Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            confirmStopAll = false
                        }
                    }
                } label: {
                    Text(confirmStopAll ? "Confirm stop \(stoppable.count)?" : "Stop all \(stoppable.count) shown")
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(confirmStopAll ? .white : .red)
                        .background(Capsule().fill(confirmStopAll ? AnyShapeStyle(Color.red.gradient) : AnyShapeStyle(Color.red.opacity(0.12))))
                }
                .buttonStyle(.plain)
                .help("Stops every process in the current list (skips macOS and app ports)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(alignment: .top) { Divider().opacity(0.5) }
    }

    @ViewBuilder private var bannerView: some View {
        if let banner = store.banner {
            HStack(spacing: 8) {
                Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(banner.isError ? .orange : .green)
                Text(banner.text)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .glassCard(radius: 12)
            .padding(.horizontal, 16)
            .padding(.bottom, 52)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Row

struct ProcessRow: View {
    let process: PortProcess
    @ObservedObject var store: PortStore
    @State private var hover = false
    @State private var confirming = false

    private var p: PortProcess { process }
    private var expanded: Bool { store.expanded.contains(p.pid) }
    private var tint: Color { p.launcher.kind.tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                portBadge
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(p.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        if p.exposed {
                            Label("network", systemImage: "wifi")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange.opacity(0.14)))
                                .help("Reachable from other devices on your network")
                        }
                    }
                    if !displayPath.isEmpty {
                        Text(displayPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    HStack(spacing: 6) {
                        Label(p.launcher.label, systemImage: p.launcher.kind.symbol)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(tint.opacity(0.14)))
                        if let up = p.uptime { meta("clock", Self.duration(up)) }
                        if let mem = p.memMB { meta("memorychip", "\(mem) MB") }
                    }
                    .padding(.top, 1)
                }
                Spacer(minLength: 4)
                actions
            }

            if p.ports.count > 1 {
                HStack(spacing: 5) {
                    Text("also on")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    ForEach(p.ports.dropFirst().prefix(6), id: \.self) { port in
                        Button { open(port) } label: { Text(verbatim: ":\(port)") }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                            .help(Text(verbatim: "Open http://localhost:\(port)"))
                    }
                    if p.ports.count > 7 {
                        Text("+\(p.ports.count - 7)").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 70)
            }

            if expanded { details }
        }
        .padding(12)
        .glassCard(highlighted: hover || expanded)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture {
            withAnimation(.snappy(duration: 0.22)) {
                if expanded { store.expanded.remove(p.pid) } else { store.expanded.insert(p.pid) }
            }
        }
        .contextMenu { contextMenu }
    }

    private var displayPath: String {
        guard p.cwd != "/" else { return "" }
        return p.cwd.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private var portBadge: some View {
        Button { open(p.ports[0]) } label: {
            Text(verbatim: "\(p.ports[0])")
                .font(.system(size: p.ports[0] > 9999 ? 14 : 17, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                .frame(width: 58, height: 44)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(tint.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: "Open http://localhost:\(p.ports[0])"))
    }

    private func meta(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9))
            Text(text).font(.system(size: 10.5).monospacedDigit())
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var actions: some View {
        if p.isSelf {
            EmptyView()
        } else {
            HStack(spacing: 5) {
                if hover && !confirming {
                    IconButton(symbol: "safari", help: "Open in browser") { open(p.ports[0]) }
                    if !displayPath.isEmpty {
                        IconButton(symbol: "folder", help: "Show folder in Finder") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: p.cwd)
                        }
                    }
                }
                stopButton
            }
        }
    }

    @ViewBuilder private var stopButton: some View {
        let isStopping = store.stopping.contains(p.pid)
        let isStubborn = store.stubborn.contains(p.pid)
        if isStopping {
            ProgressView().controlSize(.small).frame(width: 26, height: 26)
        } else if confirming || isStubborn {
            Button {
                confirming = false
                // Holding ⌥ (or a process that ignored SIGTERM) escalates to SIGKILL.
                store.stop([p], force: isStubborn || NSEvent.modifierFlags.contains(.option))
            } label: {
                Text(isStubborn ? "Force Kill" : "Stop")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill((isStubborn ? Color.orange : Color.red).gradient))
                    .shadow(color: .red.opacity(0.35), radius: 4, y: 1)
            }
            .buttonStyle(.plain)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        } else {
            IconButton(symbol: "stop.fill", help: "Stop process \(p.pid) — click again to confirm (⌥ to force kill)", tint: .red) {
                withAnimation(.snappy(duration: 0.18)) { confirming = true }
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation { confirming = false }
                }
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            detail("Command", p.args)
            detail("PID", "\(p.pid)   PPID \(p.ppid)   user \(p.user)")
            detail("Listening", p.addresses.map { "\($0):\(p.ports[0])" }.joined(separator: "  "))
            detail("Detected", "\(p.launcher.label) via \(p.launcher.source)")
            if !p.launcher.chain.isEmpty { detail("Parents", p.launcher.chain.joined(separator: " ← ")) }
            HStack(spacing: 6) {
                smallButton("Copy command", "doc.on.doc") { copy(p.args) }
                smallButton("Copy PID", "number") { copy("\(p.pid)") }
                Spacer()
                if !p.isSelf {
                    smallButton("Force Kill", "bolt.fill", tint: .red) { store.stop([p], force: true) }
                }
            }
            .padding(.top, 2)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.system(size: 10.5, design: .monospaced))
                .lineLimit(4)
                .textSelection(.enabled)
        }
    }

    private func smallButton(_ title: String, _ symbol: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(tint.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var contextMenu: some View {
        ForEach(p.ports, id: \.self) { port in
            Button { open(port) } label: { Text(verbatim: "Open localhost:\(port)") }
        }
        Divider()
        if !displayPath.isEmpty {
            Button("Show Folder in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: p.cwd) }
        }
        Button("Copy Command") { copy(p.args) }
        Button("Copy PID") { copy("\(p.pid)") }
        if !p.isSelf {
            Divider()
            Button("Stop") { store.stop([p], force: false) }
            Button("Force Kill") { store.stop([p], force: true) }
        }
    }

    private func open(_ port: Int) {
        if let url = URL(string: "http://localhost:\(port)") { NSWorkspace.shared.open(url) }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        store.show("Copied")
    }

    static func duration(_ s: Int) -> String {
        switch s {
        case ..<60: "\(s)s"
        case ..<3600: "\(s / 60)m"
        case ..<86400: "\(s / 3600)h \(s % 3600 / 60)m"
        default: "\(s / 86400)d \(s % 86400 / 3600)h"
        }
    }
}

/// Lets the panel be dragged by the area it sits behind (the header), while buttons on top keep working.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
