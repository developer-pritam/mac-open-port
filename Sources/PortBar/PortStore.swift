import AppKit
import ServiceManagement

@MainActor
final class PortStore: ObservableObject {
    struct Banner: Equatable {
        let text: String
        let isError: Bool
    }

    @Published private(set) var processes: [PortProcess] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isScanning = false
    @Published var query = ""
    @Published var kind: LauncherKind?
    @Published var showSystem = UserDefaults.standard.bool(forKey: "showSystem") {
        didSet { UserDefaults.standard.set(showSystem, forKey: "showSystem") }
    }
    @Published private(set) var stopping: Set<Int32> = []
    /// Processes that ignored SIGTERM — the row offers a force kill instead.
    @Published private(set) var stubborn: Set<Int32> = []
    @Published private(set) var banner: Banner?
    /// Rows showing their detail section; kept here so it survives refreshes.
    @Published var expanded: Set<Int32> = []
    /// Bumped whenever the panel opens, so the view can move keyboard focus to the search field.
    @Published private(set) var focusToken = 0

    func focusSearch() { focusToken += 1 }

    var onUpdate: (() -> Void)?
    private var bannerTask: Task<Void, Never>?

    /// Everything except macOS daemons and app helpers, unless the user asked to see them.
    var relevant: [PortProcess] { showSystem ? processes : processes.filter { !$0.isNoise } }

    var visible: [PortProcess] {
        let base = kind.map { k in processes.filter { $0.launcher.kind == k } } ?? relevant
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { p in
            p.ports.contains { String($0).hasPrefix(q) } || String(p.pid) == q
                || [p.name, p.args, p.cwd, p.launcher.label].contains { $0.lowercased().contains(q) }
        }
    }

    var kindCounts: [(LauncherKind, Int)] {
        LauncherKind.allCases.compactMap { k in
            let n = processes.filter { $0.launcher.kind == k }.count
            return n > 0 ? (k, n) : nil
        }
    }

    var relevantPortCount: Int { relevant.reduce(0) { $0 + $1.ports.count } }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        Task.detached(priority: .userInitiated) {
            let result = PortScanner.scan()
            await MainActor.run {
                self.processes = result
                self.lastUpdated = Date()
                self.isScanning = false
                let live = Set(result.map(\.pid))
                self.stubborn.formIntersection(live)
                self.onUpdate?()
            }
        }
    }

    func stop(_ processes: [PortProcess], force: Bool) {
        let targets = processes.filter { !$0.isSelf && !stopping.contains($0.pid) }
        guard !targets.isEmpty else { return }
        targets.forEach { stopping.insert($0.pid) }
        Task {
            var stopped = 0
            var failures: [String] = []
            await withTaskGroup(of: (PortProcess, StopResult).self) { group in
                for p in targets { group.addTask { (p, await PortScanner.stop(pid: p.pid, force: force)) } }
                for await (p, result) in group {
                    stopping.remove(p.pid)
                    switch result {
                    case .stopped:
                        stopped += 1
                        stubborn.remove(p.pid)
                    case .stillRunning:
                        stubborn.insert(p.pid)
                        failures.append("\(p.name) ignored the stop request — use Force Kill")
                    case .failed(let msg):
                        failures.append("\(p.name): \(msg)")
                    }
                }
            }
            if let first = failures.first {
                show(failures.count > 1 ? "\(first) (+\(failures.count - 1) more)" : first, error: true)
            } else {
                let ports = targets.flatMap(\.ports).sorted().map(String.init).prefix(4).joined(separator: ", ")
                show(stopped == 1 ? "Stopped \(targets[0].name) · freed \(ports)" : "Stopped \(stopped) processes")
            }
            refresh()
        }
    }

    func show(_ text: String, error: Bool = false) {
        banner = Banner(text: text, isError: error)
        bannerTask?.cancel()
        bannerTask = Task {
            try? await Task.sleep(nanoseconds: error ? 6_000_000_000 : 3_000_000_000)
            if !Task.isCancelled { banner = nil }
        }
    }

    // MARK: - Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                show("Couldn't change login item: \(error.localizedDescription)", error: true)
            }
            objectWillChange.send()
        }
    }
}
