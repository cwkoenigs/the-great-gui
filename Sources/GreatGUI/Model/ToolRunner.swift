import Foundation
import Registry
import Runner

/// Runs the look that `ToolProbe` writes: one login shell, its output parsed into a status per tool.
/// It only looks. Installing and updating are a run a person or their agent asks for.
enum ToolRunner {
    /// Blocking: call it off the main thread. An empty registry starts no shell.
    static func status(_ tools: [Tool], versions: Bool, outdated: Bool) -> [String: ToolStatus] {
        guard !tools.isEmpty else { return [:] }
        let output = capture(ToolProbe.script(for: tools, versions: versions, outdated: outdated), timeout: outdated ? 240 : 45)
        return ToolProbe.parse(output, tools: tools, outdated: outdated)
    }

    /// The script's stdout from the person's login shell, cut off after `timeout` seconds.
    static func capture(_ script: String, timeout: TimeInterval) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ProcessRun.defaultShell())
        p.arguments = ["-lc", script]
        var env = ProcessInfo.processInfo.environment
        // A look must never change what is installed: Homebrew is told not to upgrade or clean up on the side.
        env.merge(["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_INSTALL_CLEANUP": "1", "HOMEBREW_NO_ENV_HINTS": "1", "NO_COLOR": "1"]) { _, new in new }
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return String(decoding: data, as: UTF8.self)
    }
}
