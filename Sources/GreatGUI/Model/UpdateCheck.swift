import Foundation

/// Whether the checkout this app was built from is behind its remote: a quiet `git fetch`, then a count of
/// the commits waiting. It only looks. Nothing is pulled, built or installed until Update… is pressed.
struct UpdateInfo: Equatable {
    /// Commits on the remote branch that this build does not have.
    var count: Int
    /// Their subject lines, newest first, a handful at most.
    var subjects: [String]

    var words: String { "\(count) new change\(count == 1 ? "" : "s")" }
}

enum UpdateCheck {
    enum Outcome: Equatable {
        case current
        case behind(UpdateInfo)
        /// Offline, no access to the private repository, or not on a branch that tracks one: said, never fatal.
        case unknown(String)
    }

    /// The setting, on unless turned off in Settings.
    static var enabled: Bool { UserDefaults.standard.object(forKey: "checkForUpdates") as? Bool ?? true }
    static let interval: TimeInterval = 24 * 60 * 60

    /// Blocking: call it off the main thread. Git is told never to ask for a password, so a Mac without
    /// access fails quietly instead of putting up a prompt nobody asked for.
    static func run(in root: URL) -> Outcome {
        guard git(["fetch", "--quiet"], in: root, timeout: 45).status == 0 else {
            return .unknown("could not reach the repository (offline, or no access)")
        }
        let behind = git(["rev-list", "--count", "HEAD..@{u}"], in: root, timeout: 15)
        guard behind.status == 0, let count = Int(behind.output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .unknown("this checkout's branch does not track a remote branch")
        }
        guard count > 0 else { return .current }
        let log = git(["log", "--format=%s", "-n", "6", "HEAD..@{u}"], in: root, timeout: 15)
        let subjects = log.output.split(separator: "\n").map(String.init)
        return .behind(UpdateInfo(count: count, subjects: subjects))
    }

    static func git(_ args: [String], in dir: URL, timeout: TimeInterval) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "-C", dir.path] + args
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=10"
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return (127, "") }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
