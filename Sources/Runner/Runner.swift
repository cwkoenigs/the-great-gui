import Foundation

/// A run without a terminal: the login shell's environment, output as lines, one exit code.
///
/// Colour is switched off and any escapes that remain are stripped, so the window shows text. Secret
/// values are redacted from every line before anyone sees them. The shell is a login shell (`-l`) so
/// PATH is yours even when the app was started from the Dock.
public final class ProcessRun: @unchecked Sendable {
    public enum Event: Sendable {
        case started
        case line(String)
        case exited(code: Int32, seconds: Double)
    }

    public static func defaultShell() -> String {
        ProcessInfo.processInfo.environment["GREAT_GUI_SHELL"] ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    private let process = Process()
    private let pipe = Pipe()
    private let redactor: Redactor
    private let onEvent: @Sendable (Event) -> Void
    private let queue = DispatchQueue(label: "the-great-gui.run")
    private var buffer = Data()
    private var started = Date()
    private let eof = DispatchGroup()
    private var eofSeen = false

    /// `run` is the shell line; `cwd` the working directory; `env` is added to the process's environment.
    /// `redact` are the secret values no line may show.
    public init(run: String, cwd: String? = nil, env: [String: String] = [:], redact: [String] = [],
                shell: String = ProcessRun.defaultShell(), onEvent: @escaping @Sendable (Event) -> Void) {
        self.onEvent = onEvent
        self.redactor = Redactor(values: redact)
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", run]
        if let cwd, !cwd.isEmpty { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        var environment = ProcessInfo.processInfo.environment
        environment.merge(["NO_COLOR": "1", "CLICOLOR": "0", "TERM": "dumb", "PYTHONUNBUFFERED": "1"]) { _, new in new }
        environment.merge(env) { _, new in new }
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
    }

    /// Starts the process. Throws when the shell or the working directory does not exist.
    public func start() throws {
        started = Date()
        eof.enter()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            self.queue.async {
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    self.markEOF()
                } else {
                    self.buffer.append(data)
                    self.flush(final: false)
                }
            }
        }
        process.terminationHandler = { [weak self] p in
            guard let self else { return }
            self.eof.notify(queue: self.queue) {
                self.onEvent(.exited(code: p.terminationStatus, seconds: (Date().timeIntervalSince(self.started) * 10).rounded() / 10))
            }
        }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            queue.async { self.markEOF() }
            throw error
        }
        onEvent(.started)
    }

    /// On `queue`. The pipe may report EOF and a failed launch may both get here; the group is left once.
    private func markEOF() {
        guard !eofSeen else { return }
        eofSeen = true
        flush(final: true)
        eof.leave()
    }

    public var isRunning: Bool { process.isRunning }

    /// SIGTERM to the shell. Children it started may outlive it; a process group is a follow-up.
    public func terminate() {
        if process.isRunning { process.terminate() }
    }

    private func flush(final: Bool) {
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            emit(line)
        }
        if final, !buffer.isEmpty {
            emit(buffer)
            buffer.removeAll()
        }
    }

    private func emit(_ raw: Data) {
        let text = String(decoding: raw, as: UTF8.self)
        onEvent(.line(redactor.redact(Ansi.strip(text))))
    }
}

/// Strips ANSI colour and cursor sequences, OSC titles and carriage returns.
public enum Ansi {
    private static let pattern = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]|\u{1B}\\][^\u{07}\u{1B}]*(?:\u{07}|\u{1B}\\\\)|\r")
    public static func strip(_ s: String) -> String {
        pattern.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }
}

/// Replaces every secret value with a fixed mask, longest first so a value inside another is still hidden.
public struct Redactor: Sendable {
    public static let mask = "•••••"
    private let values: [String]
    public init(values: [String]) {
        self.values = values.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
    }
    public func redact(_ s: String) -> String {
        var out = s
        for v in values where out.contains(v) { out = out.replacingOccurrences(of: v, with: Self.mask) }
        return out
    }
}
