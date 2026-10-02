import Darwin
import Foundation

enum LauncherKind: String, CaseIterable, Identifiable {
    case agent, terminal, editor, container, service, app, system, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .agent: "Agents"
        case .terminal: "Terminal"
        case .editor: "Editors"
        case .container: "Containers"
        case .service: "Services"
        case .app: "Apps"
        case .system: "macOS"
        case .other: "Other"
        }
    }
}

struct Launcher: Hashable {
    var kind: LauncherKind
    var label: String
    var source: String
    var chain: [String]
}

struct PortProcess: Identifiable, Hashable {
    let pid: Int32
    var ports: [Int]
    var addresses: [String]
    var name: String
    var exe: String
    var args: String
    var user: String
    var ppid: Int32
    var uptime: Int?
    var memMB: Int?
    var cwd: String
    var launcher: Launcher

    var id: Int32 { pid }
    var exposed: Bool { addresses.contains { $0 == "*" || $0 == "0.0.0.0" || $0 == "[::]" } }
    /// macOS daemons, GUI apps and editor helpers — listening on ports, but not something you started.
    var isNoise: Bool { launcher.kind == .app || launcher.kind == .system || name.contains("Helper") }
    var isSelf: Bool { pid == getpid() }
}

enum StopResult {
    case stopped
    case stillRunning
    case failed(String)
}

enum PortScanner {
    private struct ProcInfo {
        var ppid: Int32 = 0
        var uptime: Int?
        var rssKB: Int = 0
        var user = ""
        var args = ""
        var exe = ""
    }

    static func scan() -> [PortProcess] {
        let listeners = listeningSockets()
        guard !listeners.isEmpty else { return [] }
        let procs = processTable()
        let pids = Array(listeners.keys)

        // Include ancestors: some servers (e.g. next-server) rewrite their process title, which hides their own env from ps.
        var envPids = Set(pids)
        for pid in pids {
            var cur = procs[pid]
            var hops = 0
            while let p = cur, p.ppid > 1, hops < 30 {
                envPids.insert(p.ppid)
                cur = procs[p.ppid]
                hops += 1
            }
        }
        let cwds = workingDirectories(pids)
        let envs = environments(Array(envPids))

        return pids.map { pid in
            let info = procs[pid] ?? ProcInfo()
            let sock = listeners[pid]!
            return PortProcess(
                pid: pid,
                ports: sock.ports.sorted(),
                addresses: sock.addresses,
                name: info.exe.isEmpty ? "?" : (info.exe as NSString).lastPathComponent,
                exe: info.exe,
                args: info.args,
                user: info.user,
                ppid: info.ppid,
                uptime: info.uptime,
                memMB: info.rssKB > 0 ? info.rssKB / 1024 : nil,
                cwd: cwds[pid] ?? "",
                launcher: launcher(for: pid, procs: procs, env: inheritedEnv(pid, procs: procs, envs: envs))
            )
        }
        .sorted { ($0.ports.first ?? 0) < ($1.ports.first ?? 0) }
    }

    static func stop(pid: Int32, force: Bool) async -> StopResult {
        guard pid > 1, pid != getpid() else { return .failed("Can't stop that process") }
        if kill(pid, force ? SIGKILL : SIGTERM) != 0 {
            switch errno {
            case ESRCH: return .stopped
            case EPERM: return .failed("Permission denied — owned by another user. Try: sudo kill \(force ? "-9 " : "")\(pid)")
            default: return .failed(String(cString: strerror(errno)))
            }
        }
        // Give it a moment to shut down so we can report whether it actually went away.
        for _ in 0..<15 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if kill(pid, 0) != 0 && errno == ESRCH { return .stopped }
        }
        return .stillRunning
    }

    // MARK: - System queries

    private static func run(_ path: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// lsof -F output: one field per line, prefixed by a type char. `p` starts a process, `n` is a socket address.
    private static func listeningSockets() -> [Int32: (ports: Set<Int>, addresses: [String])] {
        let out = run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pn"])
        var result: [Int32: (ports: Set<Int>, addresses: [String])] = [:]
        var pid: Int32?
        for line in out.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            if tag == "p" {
                pid = Int32(value)
            } else if tag == "n", let pid, let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]) {
                let address = String(value[..<colon])
                var entry = result[pid] ?? ([], [])
                entry.ports.insert(port)
                if !entry.addresses.contains(address) { entry.addresses.append(address) }
                result[pid] = entry
            }
        }
        return result
    }

    private static func processTable() -> [Int32: ProcInfo] {
        var procs: [Int32: ProcInfo] = [:]
        for line in run("/bin/ps", ["-axo", "pid=,ppid=,etime=,rss=,user="]).split(separator: "\n") {
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            guard f.count >= 5, let pid = Int32(f[0]) else { continue }
            procs[pid] = ProcInfo(ppid: Int32(f[1]) ?? 0, uptime: seconds(fromEtime: String(f[2])), rssKB: Int(f[3]) ?? 0, user: String(f[4]))
        }
        for (key, args) in [(\ProcInfo.args, ["-axww", "-o", "pid=,args="]), (\ProcInfo.exe, ["-ax", "-o", "pid=,comm="])] {
            for (pid, rest) in pidLines(run("/bin/ps", args)) where procs[pid] != nil {
                procs[pid]![keyPath: key] = rest
            }
        }
        return procs
    }

    private static func workingDirectories(_ pids: [Int32]) -> [Int32: String] {
        let out = run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", pids.map(String.init).joined(separator: ","), "-Fpn"])
        var map: [Int32: String] = [:]
        var pid: Int32?
        for line in out.split(separator: "\n") {
            if line.first == "p" { pid = Int32(line.dropFirst()) }
            else if line.first == "n", let pid { map[pid] = String(line.dropFirst()) }
        }
        return map
    }

    /// `ps -E` appends the environment to the command line; only readable for the current user's processes.
    private static func environments(_ pids: [Int32]) -> [Int32: [String: String]] {
        let out = run("/bin/ps", ["-Eww", "-o", "pid=,command=", "-p", pids.map(String.init).joined(separator: ",")])
        var map: [Int32: [String: String]] = [:]
        let pattern = try! NSRegularExpression(pattern: #"(?:^|\s)([A-Za-z_][A-Za-z0-9_]*)=(\S*)"#)
        for (pid, rest) in pidLines(out) {
            var env: [String: String] = [:]
            let ns = rest as NSString
            for m in pattern.matches(in: rest, range: NSRange(location: 0, length: ns.length)) {
                env[ns.substring(with: m.range(at: 1))] = ns.substring(with: m.range(at: 2))
            }
            map[pid] = env
        }
        return map
    }

    private static func pidLines(_ out: String) -> [(Int32, String)] {
        out.split(separator: "\n").compactMap { line in
            let trimmed = line.drop { $0 == " " }
            guard let space = trimmed.firstIndex(of: " "), let pid = Int32(trimmed[..<space]) else { return nil }
            return (pid, String(trimmed[trimmed.index(after: space)...]))
        }
    }

    /// ps etime is [[dd-]hh:]mm:ss
    private static func seconds(fromEtime etime: String) -> Int? {
        let dayParts = etime.split(separator: "-")
        let days = dayParts.count == 2 ? Int(dayParts[0]) ?? 0 : 0
        let clock = (dayParts.last ?? "").split(separator: ":").compactMap { Int($0) }
        guard (2...3).contains(clock.count) else { return nil }
        let hms = clock.count == 3 ? clock : [0] + clock
        return ((days * 24 + hms[0]) * 60 + hms[1]) * 60 + hms[2]
    }

    // MARK: - Who launched it

    private struct Rule {
        let kind: LauncherKind
        let label: String
        let pattern: String
    }

    /// Matched against each ancestor's executable path + args. Ordered by specificity; the nearest ancestor wins.
    private static let ancestorRules: [Rule] = [
        Rule(kind: .agent, label: "Claude Code", pattern: #"(^|/)claude( |$)|claude-code|@anthropic-ai/claude"#),
        Rule(kind: .agent, label: "Codex", pattern: #"(^|/)codex( |$)|@openai/codex"#),
        Rule(kind: .agent, label: "Gemini CLI", pattern: #"(^|/)gemini( |$)|@google/gemini-cli"#),
        Rule(kind: .agent, label: "Aider", pattern: #"(^|/)aider( |$)"#),
        Rule(kind: .agent, label: "Cursor Agent", pattern: #"(^|/)cursor-agent( |$)"#),
        Rule(kind: .editor, label: "Cursor", pattern: #"Cursor\.app"#),
        Rule(kind: .editor, label: "Windsurf", pattern: #"Windsurf\.app"#),
        Rule(kind: .editor, label: "VS Code", pattern: #"Visual Studio Code[^/]*\.app|Code - Insiders\.app"#),
        Rule(kind: .editor, label: "Zed", pattern: #"Zed\.app"#),
        Rule(kind: .editor, label: "JetBrains", pattern: #"(IntelliJ|WebStorm|PyCharm|GoLand|Rider|CLion|DataGrip|PhpStorm|RubyMine)[^/]*\.app"#),
        Rule(kind: .terminal, label: "Terminal", pattern: #"Terminal\.app"#),
        Rule(kind: .terminal, label: "iTerm2", pattern: #"iTerm\.app"#),
        Rule(kind: .terminal, label: "Warp", pattern: #"Warp\.app"#),
        Rule(kind: .terminal, label: "Ghostty", pattern: #"Ghostty\.app"#),
        Rule(kind: .terminal, label: "kitty", pattern: #"kitty\.app"#),
        Rule(kind: .terminal, label: "Alacritty", pattern: #"Alacritty\.app"#),
        Rule(kind: .terminal, label: "WezTerm", pattern: #"WezTerm\.app"#),
        Rule(kind: .terminal, label: "tmux", pattern: #"(^|/)tmux( |$)"#),
        Rule(kind: .container, label: "Docker", pattern: #"Docker\.app|com\.docker|(^|/)(docker|vpnkit)( |$)"#),
        Rule(kind: .container, label: "OrbStack", pattern: #"OrbStack\.app"#),
    ]

    private static let terminals = [
        "Apple_Terminal": "Terminal", "iTerm.app": "iTerm2", "WarpTerminal": "Warp", "ghostty": "Ghostty",
        "WezTerm": "WezTerm", "tmux": "tmux", "Hyper": "Hyper", "Tabby": "Tabby", "kitty": "kitty", "alacritty": "Alacritty",
    ]

    /// When the launching shell has exited (common for servers an agent starts in the background), the process is
    /// re-parented to launchd and the chain is lost — but the environment it inherited still says where it came from.
    private static func fromEnvironment(_ e: [String: String]) -> (LauncherKind, String)? {
        let bundle = e["__CFBundleIdentifier"] ?? ""
        if e["CLAUDECODE"] == "1" || e["CLAUDE_CODE_ENTRYPOINT"] != nil { return (.agent, "Claude Code") }
        if ["CODEX_SANDBOX", "CODEX_SANDBOX_NETWORK_DISABLED", "CODEX_MANAGED_BY_NPM", "CODEX_THREAD_ID"].contains(where: { e[$0] != nil }) { return (.agent, "Codex") }
        if e["GEMINI_CLI"] == "1" { return (.agent, "Gemini CLI") }
        if e["CURSOR_AGENT"] == "1" { return (.agent, "Cursor Agent") }
        if e["CURSOR_TRACE_ID"] != nil || bundle.range(of: "todesktop|cursor", options: [.regularExpression, .caseInsensitive]) != nil { return (.editor, "Cursor") }
        if bundle.range(of: "windsurf|codeium", options: [.regularExpression, .caseInsensitive]) != nil { return (.editor, "Windsurf") }
        if e["TERM_PROGRAM"] == "vscode" || e["VSCODE_PID"] != nil || e["VSCODE_IPC_HOOK"] != nil || bundle == "com.microsoft.VSCode" { return (.editor, "VS Code") }
        if let t = e["TERM_PROGRAM"], let name = terminals[t] { return (.terminal, name) }
        return nil
    }

    private static func inheritedEnv(_ pid: Int32, procs: [Int32: ProcInfo], envs: [Int32: [String: String]]) -> [String: String]? {
        var cur: Int32 = pid
        for _ in 0..<30 {
            if let env = envs[cur], !env.isEmpty { return env }
            guard let p = procs[cur], p.ppid > 1 else { return nil }
            cur = p.ppid
        }
        return nil
    }

    private static func launcher(for pid: Int32, procs: [Int32: ProcInfo], env: [String: String]?) -> Launcher {
        var chain: [String] = []
        let me = procs[pid]
        var ppid = me?.ppid ?? 0
        var seen = Set<Int32>()
        while ppid > 1, !seen.contains(ppid), let p = procs[ppid] {
            seen.insert(ppid)
            chain.append("\((p.exe as NSString).lastPathComponent) (\(ppid))")
            let haystack = p.exe + " " + p.args
            if let rule = ancestorRules.first(where: { haystack.range(of: $0.pattern, options: .regularExpression) != nil }) {
                return Launcher(kind: rule.kind, label: rule.label, source: "parent process", chain: chain)
            }
            ppid = p.ppid
        }
        if let env, let (kind, label) = fromEnvironment(env) {
            return Launcher(kind: kind, label: label, source: "inherited environment", chain: chain)
        }
        if me?.ppid == 1 {
            let exe = me?.exe ?? ""
            if exe.range(of: #"^/(System|usr/(libexec|sbin))/"#, options: .regularExpression) != nil {
                return Launcher(kind: .system, label: "macOS", source: "system path", chain: chain)
            }
            // A GUI app listening on its own (Spotify, Figma, …), started by launchd rather than from a shell.
            if let r = exe.range(of: #"[^/]+(?=\.app/Contents/MacOS/)"#, options: .regularExpression) {
                return Launcher(kind: .app, label: String(exe[r]), source: "app bundle", chain: chain)
            }
            return Launcher(kind: .service, label: "Background service", source: "launchd", chain: chain)
        }
        return Launcher(kind: .other, label: "Other", source: "unknown", chain: chain)
    }
}
