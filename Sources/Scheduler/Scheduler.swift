import CryptoKit
import Foundation
import Registry

/// launchd runs the scheduled commands: one LaunchAgent per command with a schedule, calling this app's binary
/// with `run NAME`, so runs happen whether or not the window is open and catch up after sleep. The registry is
/// the source of truth and `sync` makes the agents match it. A paused command keeps its agent file but is not
/// loaded. Every scheduled run appends to one log per command, with a header and a footer the window reads.
public struct Scheduler {
    public let agentsDir: URL
    public let logsDir: URL
    public let stateURL: URL
    public let program: URL
    public let labelPrefix: String
    private static let personalPrefix = "com.cwkoenigs.the-great-gui.cmd."
    private let owner: URL
    private let legacyStateURL: URL
    private let usesSeparateState: Bool
    private let migrateLegacyAgents: Bool
    /// What a scheduled run inherits: every GREAT_GUI_* override and the shell, plus GREAT_GUI_SCHEDULED=1.
    public let environment: [String: String]
    /// Runs launchctl; tests put a recorder here.
    public var launchctl: ([String]) -> (status: Int32, output: String) = Scheduler.realLaunchctl

    /// `program` is the binary that runs the commands: this app's own, inside its bundle. The folders follow
    /// GREAT_GUI_AGENTS, GREAT_GUI_LOGS and GREAT_GUI_SCHEDULER_STATE; the label prefix GREAT_GUI_AGENT_PREFIX.
    public init(program: URL, registryURL: URL? = nil, environment env: [String: String] = ProcessInfo.processInfo.environment) {
        self.program = program
        let home = FileManager.default.homeDirectoryForCurrentUser
        func path(_ key: String, _ fallback: URL) -> URL {
            if let p = env[key], !p.isEmpty { return URL(fileURLWithPath: NSString(string: p).expandingTildeInPath) }
            return fallback
        }
        let registry = registryURL ?? Registry.defaultURL(environment: env)
        let personal = Registry.defaultURL(environment: [:])
        owner = Self.identity(of: registry)
        let alternate = owner != Self.identity(of: personal)
        let explicitPrefix = env["GREAT_GUI_AGENT_PREFIX"].flatMap { $0.isEmpty ? nil : $0 }
        let digest = SHA256.hash(data: Data(owner.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let support = home.appendingPathComponent("Library/Application Support/the-great-gui")
        let logs = home.appendingPathComponent("Library/Logs/the-great-gui")
        agentsDir = path("GREAT_GUI_AGENTS", home.appendingPathComponent("Library/LaunchAgents"))
        legacyStateURL = path("GREAT_GUI_SCHEDULER_STATE", support.appendingPathComponent("scheduler.json"))
        stateURL = path("GREAT_GUI_SCHEDULER_STATE", (alternate ? support.appendingPathComponent(digest) : support).appendingPathComponent("scheduler.json"))
        usesSeparateState = legacyStateURL != stateURL
        logsDir = path("GREAT_GUI_LOGS", alternate ? logs.appendingPathComponent(digest) : logs)
        labelPrefix = explicitPrefix ?? (alternate ? "com.cwkoenigs.the-great-gui.registry.\(digest)." : Self.personalPrefix)
        migrateLegacyAgents = alternate && explicitPrefix == nil
        var passed: [String: String] = ["GREAT_GUI_SCHEDULED": "1"]
        for (k, v) in env where k.hasPrefix("GREAT_GUI_") && k != "GREAT_GUI_SCHEDULED" { passed[k] = v }
        if alternate || env["GREAT_GUI_REGISTRY"] != nil { passed["GREAT_GUI_REGISTRY"] = registry.path }
        if usesSeparateState { passed["GREAT_GUI_SCHEDULER_STATE"] = stateURL.path }
        if let shell = env["SHELL"], !shell.isEmpty { passed["SHELL"] = shell }
        environment = passed
    }

    private static func identity(of url: URL) -> URL {
        // Atomic saves replace the directory entry. Resolve aliases to its parent, independent of file existence.
        url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent(url.lastPathComponent)
    }

    public func label(for name: String) -> String { labelPrefix + name }
    public func agentURL(for name: String) -> URL { agentsDir.appendingPathComponent(label(for: name) + ".plist") }
    public func logURL(for name: String) -> URL { logsDir.appendingPathComponent(name + ".log") }
    var domain: String { "gui/\(getuid())" }

    // MARK: the agent

    /// The LaunchAgent for a scheduled command, as launchd reads it.
    public func plist(for c: Command) throws -> Data {
        guard let s = c.schedule else { throw RegistryError("\(c.name) has no schedule", fix: "add one with great-gui edit \(c.name) --schedule \"…\"") }
        var dict: [String: Any] = [
            "Label": label(for: c.name),
            "ProgramArguments": [program.path, "run", c.name],
            "StandardOutPath": logURL(for: c.name).path,
            "StandardErrorPath": logURL(for: c.name).path,
            "EnvironmentVariables": environment,
            "RunAtLoad": false,
        ]
        switch s.kind {
        case .interval(let seconds):
            dict["StartInterval"] = seconds
        case .calendar(let entries):
            dict["StartCalendarInterval"] = entries.map { e -> [String: Int] in
                var d = ["Minute": e.minute]
                if let h = e.hour { d["Hour"] = h }
                if let w = e.weekday { d["Weekday"] = w }
                if let day = e.day { d["Day"] = day }
                return d
            }
        }
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    // MARK: paused

    struct State: Codable { var paused: [String] }

    public func paused() -> Set<String> { Self.paused(at: stateURL) }

    private static func paused(at url: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(State.self, from: data) else { return [] }
        return Set(s.paused)
    }

    func setPaused(_ set: Set<String>) throws {
        let data = try JSONEncoder().encode(State(paused: set.sorted()))
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: stateURL, options: .atomic)
    }

    /// Unloads the agent and remembers; `sync` keeps it unloaded until `resume`.
    public func pause(_ name: String, in registry: Registry) throws {
        try changePause(name, in: registry, paused: true)
    }

    public func resume(_ name: String, in registry: Registry) throws {
        try changePause(name, in: registry, paused: false)
    }

    private func changePause(_ name: String, in registry: Registry, paused: Bool) throws {
        guard registry.command(named: name)?.schedule != nil else {
            throw RegistryError("\(name) has no schedule", fix: "only a scheduled command can be paused or resumed")
        }
        let report = sync(registry, pauseChange: (name, paused))
        if !report.problems.isEmpty { throw RegistryError(report.problems.joined(separator: "\n")) }
    }

    // MARK: launchd's view

    public struct Status: Equatable {
        public var loaded: Bool
        public var running: Bool
        public var lastExit: Int32?
    }

    public func status(_ name: String) -> Status {
        let r = launchctl(["print", "\(domain)/\(label(for: name))"])
        guard r.status == 0 else { return Status(loaded: false, running: false, lastExit: nil) }
        var lastExit: Int32?
        if let m = r.output.range(of: "last exit code = ") {
            lastExit = Int32(r.output[m.upperBound...].prefix { $0.isNumber || $0 == "-" })
        }
        return Status(loaded: true, running: r.output.contains("state = running"), lastExit: lastExit)
    }

    public func isLoaded(_ name: String) -> Bool { status(name).loaded }

    // MARK: sync

    public struct Report: Equatable {
        public var written: [String] = []
        public var removed: [String] = []
        public var loaded: [String] = []
        public var unloaded: [String] = []
        public var problems: [String] = []
        public var changed: Bool { !(written.isEmpty && removed.isEmpty && loaded.isEmpty && unloaded.isEmpty) }
    }

    /// Makes the agents match the registry: one per scheduled command, loaded unless paused; agents of ours
    /// for commands that lost their schedule or are gone are unloaded and removed. Safe to call often.
    @discardableResult
    public func sync(_ registry: Registry) -> Report {
        sync(registry, pauseChange: nil)
    }

    private func sync(_ registry: Registry, pauseChange: (name: String, paused: Bool)?) -> Report {
        var report = Report()
        do {
            guard Self.identity(of: registry.url) == owner else { throw RegistryError("scheduler belongs to another registry") }
            let wanted = registry.personal.filter { $0.schedule != nil }
            if wanted.isEmpty, !FileManager.default.fileExists(atPath: agentsDir.path) { return report }
            try DirectoryLock.withExclusiveAccess(to: agentsDir, createIfMissing: !wanted.isEmpty) {
                try reconcile(wanted, pauseChange: pauseChange, into: &report)
            }
        } catch {
            report.problems.append("\(error)")
        }
        return report
    }

    private func reconcile(_ wanted: [Command], pauseChange: (name: String, paused: Bool)?, into report: inout Report) throws {
        let fm = FileManager.default
        var paused = paused()
        if let pauseChange {
            if pauseChange.paused { paused.insert(pauseChange.name) }
            else { paused.remove(pauseChange.name) }
            try setPaused(paused)
        }
        let wantedNames = Set(wanted.map(\.name))
        var blocked: Set<String> = []
        for filename in try fm.contentsOfDirectory(atPath: agentsDir.path) where filename.hasSuffix(".plist") {
            let label = String(filename.dropLast(".plist".count))
            let prefix: String
            if label.hasPrefix(labelPrefix) { prefix = labelPrefix }
            else if migrateLegacyAgents, label.hasPrefix(Self.personalPrefix) { prefix = Self.personalPrefix }
            else { continue }
            let name = String(label.dropFirst(prefix.count))
            let legacy = prefix != labelPrefix
            guard legacy || !wantedNames.contains(name) else { continue }
            let file = agentsDir.appendingPathComponent(filename)
            guard ownsAgent(at: file, label: label, command: name) else { continue }
            do {
                // Older alternate registries shared the personal label and pause file. Migrate only
                // a plist whose saved child environment identifies this registry.
                if legacy, wantedNames.contains(name), name != pauseChange?.name, !paused.contains(name), Self.paused(at: legacyStateURL).contains(name) {
                    paused.insert(name)
                    try setPaused(paused)
                }
                let service = "\(domain)/\(label)"
                if try loadedAgent(label: label, at: file), launchctl(["bootout", service]).status != 0 {
                    throw RegistryError("launchd could not unload \(label)")
                }
                try fm.removeItem(at: file)
                report.removed.append(name)
            } catch {
                blocked.insert(name)
                report.problems.append("\(name): \(error)")
            }
        }
        for c in wanted where !blocked.contains(c.name) {
            let url = agentURL(for: c.name)
            if fm.fileExists(atPath: url.path), !ownsAgent(at: url, label: label(for: c.name), command: c.name) {
                report.problems.append("\(c.name): a different or unrecognized job owns \(url.lastPathComponent)")
                continue
            }
            guard let data = try? plist(for: c) else { report.problems.append("\(c.name): its agent could not be written"); continue }
            let loaded: Bool
            do { loaded = try loadedAgent(label: label(for: c.name), at: url) }
            catch { report.problems.append("\(error)"); continue }
            let previous = try? Data(contentsOf: url)
            if usesSeparateState, c.name != pauseChange?.name, !paused.contains(c.name), let previous,
               let old = (try? PropertyListSerialization.propertyList(from: previous, format: nil)) as? [String: Any],
               let env = old["EnvironmentVariables"] as? [String: String], env["GREAT_GUI_SCHEDULER_STATE"] == nil,
               Self.paused(at: legacyStateURL).contains(c.name) {
                paused.insert(c.name)
                try setPaused(paused)
            }
            let shouldLoad = !paused.contains(c.name)
            if previous != data {
                if loaded, !bootout(c.name) {
                    report.problems.append("\(c.name): launchd could not unload the previous job")
                    continue
                }
                do {
                    try fm.createDirectory(at: agentsDir, withIntermediateDirectories: true)
                    try fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
                    try data.write(to: url, options: .atomic)
                    report.written.append(c.name)
                } catch {
                    report.problems.append("\(c.name): \(error.localizedDescription)")
                    continue
                }
                if shouldLoad { load(c.name, into: &report) }
            } else if loaded, !shouldLoad {
                if bootout(c.name) { report.unloaded.append(c.name) }
                else { report.problems.append("\(c.name): launchd could not unload the job") }
            } else if !loaded, shouldLoad {
                load(c.name, into: &report)
            }
        }
    }

    /// Labels are global even when two installations choose different LaunchAgents directories.
    private func loadedAgent(label: String, at file: URL) throws -> Bool {
        let job = launchctl(["print", "\(domain)/\(label)"])
        guard job.status == 0 else { return false }
        let path = job.output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("path = ") }
        guard let path, FileManager.default.fileExists(atPath: file.path),
              Self.identity(of: URL(fileURLWithPath: String(path.dropFirst("path = ".count)))) == Self.identity(of: file) else {
            throw RegistryError("another loaded job owns \(label)")
        }
        return true
    }

    private func ownsAgent(at url: URL, label: String, command: String) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              plist["Label"] as? String == label,
              let args = plist["ProgramArguments"] as? [String], args.count == 3, args[1] == "run", args[2] == command,
              let env = plist["EnvironmentVariables"] as? [String: String], env["GREAT_GUI_SCHEDULED"] == "1" else { return false }
        return Self.identity(of: Registry.defaultURL(environment: env)) == owner
    }

    private func load(_ name: String, into report: inout Report) {
        let r = launchctl(["bootstrap", domain, agentURL(for: name).path])
        if r.status == 0 { report.loaded.append(name) } else { report.problems.append("\(name): launchd did not load its agent: \(r.output.trimmingCharacters(in: .whitespacesAndNewlines))") }
    }

    @discardableResult
    func bootout(_ name: String) -> Bool { launchctl(["bootout", "\(domain)/\(label(for: name))"]).status == 0 }

    /// When the next run is: the calendar's next date, or the last run plus the interval, or unknown.
    public func nextRun(for c: Command, lastRun: Date?, now: Date = Date()) -> Date? {
        guard let s = c.schedule else { return nil }
        switch s.kind {
        case .calendar: return s.next(after: now)
        case .interval(let seconds): return lastRun.map { $0.addingTimeInterval(TimeInterval(seconds)) }
        }
    }

    /// A coming time as the window and the command line say it: 08:30 today, Tue 08:30 this week, Dec 1, 07:00 later.
    public static func when(_ d: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: d)).day ?? 0
        let f = DateFormatter()
        f.calendar = calendar
        f.dateFormat = days == 0 ? "HH:mm" : (days < 7 ? "EEE HH:mm" : "MMM d, HH:mm")
        return f.string(from: d)
    }

    // MARK: the log

    public static let runMarker = "═══ "

    public static func header(name: String, at date: Date = Date()) -> String { "\(runMarker)\(stamp(date)) · \(name)" }
    public static func footer(code: Int32, seconds: Double) -> String { "─── exit \(code) · \(seconds)s" }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    /// The last run's section of the log, from its header to the end; nil when there is no log yet.
    public func lastLog(for name: String) -> String? {
        guard let text = try? String(contentsOf: logURL(for: name), encoding: .utf8), !text.isEmpty else { return nil }
        if let r = text.range(of: Self.runMarker, options: .backwards) { return String(text[r.lowerBound...]) }
        return text
    }

    /// Past a megabyte, the log keeps its last 256 KB. Done in place, so launchd's open file keeps working.
    public func trimLog(for name: String) {
        let url = logURL(for: name)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1_048_576,
              let data = try? Data(contentsOf: url), let h = try? FileHandle(forWritingTo: url) else { return }
        try? h.truncate(atOffset: 0)
        try? h.write(contentsOf: data.suffix(262_144))
        try? h.close()
    }

    static func realLaunchctl(_ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (127, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
