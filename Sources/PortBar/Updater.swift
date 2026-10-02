import AppKit

/// Checks GitHub Releases for a newer version and installs it in place — no framework, no background daemon.
@MainActor
final class Updater: ObservableObject {
    struct Release: Equatable {
        let version: String
        let zipURL: URL
        let pageURL: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case installing
        case failed(String)
    }

    static let repo = "developer-pritam/mac-open-port"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases")!

    @Published private(set) var state: State = .idle
    /// Reports results of user-initiated checks (and failures) to the UI.
    var notify: ((String, Bool) -> Void)?

    private let lastCheckKey = "lastUpdateCheck"

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var availableRelease: Release? {
        if case .available(let r) = state { return r }
        return nil
    }

    /// Background check at most once a day.
    func checkIfDue() {
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 24 * 3600 else { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        guard state != .checking, state != .installing else { return }
        state = .checking
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("PortBar/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)
            if status == 404 {
                state = .upToDate
                if userInitiated { notify?("No releases published yet — you're on \(currentVersion)", false) }
                return
            }
            guard status == 200 else { throw UpdateError("GitHub returned HTTP \(status)") }
            let release = try Self.parse(data)
            if Self.isNewer(release.version, than: currentVersion) {
                state = .available(release)
                if userInitiated { notify?("PortBar \(release.version) is available", false) }
            } else {
                state = .upToDate
                if userInitiated { notify?("You're on the latest version (\(currentVersion))", false) }
            }
        } catch {
            state = .failed(error.localizedDescription)
            if userInitiated { notify?("Update check failed: \(error.localizedDescription)", true) }
        }
    }

    /// Downloads the release zip, swaps it in for the running bundle, and relaunches.
    func install(_ release: Release) async {
        let current = Bundle.main.bundleURL
        guard current.pathExtension == "app" else {
            NSWorkspace.shared.open(release.pageURL)
            return
        }
        state = .installing
        do {
            let (zip, _) = try await URLSession.shared.download(from: release.zipURL)
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("PortBarUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            let newApp = work.appendingPathComponent("PortBar.app")
            guard Bundle(url: newApp)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw UpdateError("The download doesn't contain PortBar.app")
            }
            _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp)
            // Relaunch once this process has exited.
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", current.path]
            try relaunch.run()
            NSApp.terminate(nil)
        } catch {
            state = .available(release)
            notify?("Couldn't install the update (\(error.localizedDescription)). Opening the download page.", true)
            NSWorkspace.shared.open(release.pageURL)
        }
    }

    // MARK: - Helpers

    private struct UpdateError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    private static func parse(_ data: Data) throws -> Release {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Payload: Decodable { let tag_name: String; let html_url: URL; let assets: [Asset] }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let asset = payload.assets.first(where: { $0.name == "PortBar.zip" })
            ?? payload.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
            throw UpdateError("The latest release has no .zip attached")
        }
        let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        return Release(version: version, zipURL: asset.browser_download_url, pageURL: payload.html_url)
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func run(_ path: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError("\(path) failed (\(p.terminationStatus))") }
    }
}
