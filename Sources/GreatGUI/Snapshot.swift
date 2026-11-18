import AppKit
import Registry
import Scheduler
import Secrets
import SwiftUI
import TerminalDesign

/// `GreatGUI --snapshot DIR` draws the window's screens to PNG files and exits: the look, reviewable without
/// a screen (DECISIONS local-033). Every screen is drawn from the example registry with made-up status,
/// never from your own registry, history or Keychain, and nothing is run or installed.
@MainActor
enum Snapshot {
    enum Failure: Error { case noImage }

    /// One picture: a name, and the model as that screen needs it.
    struct Screen {
        var name: String
        var model: AppModel
    }

    static let size = NSSize(width: 1120, height: 740)

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            for palette in TermPalette.allCases.prefix(CommandLine.arguments.contains("--one") ? 1 : 9) {
                for dark in [false, true].prefix(CommandLine.arguments.contains("--one") ? 1 : 2) {
                    for screen in try screens() {
                        let name = "\(screen.name)-\(palette.rawValue)-\(dark ? "dark" : "light").png"
                        try render(screen.model, palette: palette, dark: dark, to: dir.appendingPathComponent(name))
                    }
                }
            }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("✗ snapshot failed: \(error)\n".utf8))
            exit(1)
        }
    }

    // MARK: the screens

    static func screens() throws -> [Screen] {
        var out: [Screen] = []

        let commands = try model()
        out.append(Screen(name: "commands", model: commands))

        let ran = try model()
        ran.stage(run: AppModel.RunState(name: "brew-outdated", run: "brew outdated --verbose", cwd: nil, interactive: false,
                                         lines: ["ripgrep (14.1.0) < 14.1.1", "uv (0.13.7) < 0.14.0", "jq (1.7.1) < 1.8.0"],
                                         status: .done(code: 0, seconds: 1.2)))
        out.append(Screen(name: "run-done", model: ran))

        let failed = try model()
        failed.stage(run: AppModel.RunState(name: "brew-outdated", run: "brew outdated --verbose", cwd: nil, interactive: false,
                                            lines: ["Error: could not reach the tap"], status: .done(code: 1, seconds: 0.4)))
        out.append(Screen(name: "run-failed", model: failed))

        let tools = try model()
        tools.destination = .tools
        tools.toolStatus = ["ripgrep": ToolStatus(installed: false), "uv": ToolStatus(installed: true, version: "0.13.7"),
                            "ruff": ToolStatus(installed: true, version: "0.6.1", outdated: true, latest: "0.7.0")]
        tools.toolsCheckedAt = Date().addingTimeInterval(-3 * 3600)
        out.append(Screen(name: "tools", model: tools))

        let secrets = try model()
        secrets.destination = .secrets
        secrets.stage(secretRows: [
            AppModel.SecretRow(name: "gitlab-token", inKeychain: true, usedBy: ["gitlab-pipelines"]),
            AppModel.SecretRow(name: "snowflake-password", inKeychain: false, usedBy: ["warehouse-check", "nightly-load"]),
        ], fileRows: [
            AppModel.FileRow(name: "snowflake-connections", path: "~/.snowflake/connections.toml", mode: "600", state: .inSync, usedBy: []),
            AppModel.FileRow(name: "project-env", path: "~/Developer/my-project/.env", mode: "600", state: .differs, usedBy: ["report"]),
        ])
        out.append(Screen(name: "secrets", model: secrets))

        let history = try model()
        history.destination = .history
        out.append(Screen(name: "history", model: history))

        let empty = try model(registry: "")
        out.append(Screen(name: "empty", model: empty))

        return out
    }

    /// A model over the example registry (or the text given), three listed tools, a short made-up history, and
    /// a Keychain service nothing is stored under. It watches nothing and looks at nothing.
    private static func model(registry text: String? = nil) throws -> AppModel {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("the-great-gui-snapshot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let registry = tmp.appendingPathComponent("commands.toml")
        let toolEntries = """

        [[tool]]
        name = "ripgrep"
        desc = "fast search"
        method = "brew"
        bin = "rg"

        [[tool]]
        name = "uv"
        desc = "Python tools and projects"
        method = "script"
        install = "echo an installer line"

        [[tool]]
        name = "ruff"
        desc = "Python linter"
        method = "uv"
        requires = ["uv"]
        """
        try (text ?? (Registry.exampleTOML() + toolEntries)).write(to: registry, atomically: true, encoding: .utf8)
        let store = HistoryStore(url: tmp.appendingPathComponent("history.json"))
        if text == nil {
            let now = Date()
            store.save([
                HistoryEntry(name: "brew-outdated", run: "brew outdated --verbose", cwd: nil, mode: "run", code: 0, seconds: 1.2, startedAt: now.addingTimeInterval(-600)),
                HistoryEntry(name: "git-status", run: "git -C ~/Developer/my-project status --short", cwd: nil, mode: "cli", code: 0, seconds: 0.1, startedAt: now.addingTimeInterval(-3 * 3600)),
                HistoryEntry(name: "gitlab-pipelines", run: "curl -sS -H \"PRIVATE-TOKEN: $GITLAB_TOKEN\" …", cwd: nil, mode: "sched", code: 22, seconds: 0.8, startedAt: now.addingTimeInterval(-26 * 3600)),
            ])
        }
        return AppModel(registryURL: registry, teamURL: tmp.appendingPathComponent("team/commands.toml"), store: store,
                        secrets: SecretStore(service: "com.cwkoenigs.the-great-gui.snapshot"), scheduler: inertScheduler(in: tmp), watch: false)
    }

    /// A scheduler that can reach nothing real: its folders are under `dir`, its label prefix is its own,
    /// and launchctl is never called. A model always syncs the agents to its registry when it loads; with
    /// the real scheduler, drawing the example registry would unload and delete every real scheduled
    /// command's agent, because none of them is in the example (found 2026-11-13, DECISIONS local-033).
    static func inertScheduler(in dir: URL) -> Scheduler {
        var scheduler = Scheduler(program: URL(fileURLWithPath: "/usr/bin/true"), environment: [
            "GREAT_GUI_AGENTS": dir.appendingPathComponent("agents").path,
            "GREAT_GUI_LOGS": dir.appendingPathComponent("logs").path,
            "GREAT_GUI_SCHEDULER_STATE": dir.appendingPathComponent("scheduler.json").path,
            "GREAT_GUI_AGENT_PREFIX": "the-great-gui.snapshot.",
        ])
        scheduler.launchctl = { _ in (0, "") }
        return scheduler
    }

    // MARK: drawing

    /// The window as AppKit would draw it, held off screen: the theme and appearance are given to the views
    /// through the argument domain, so no setting of yours is read or written.
    private static func render(_ model: AppModel, palette: TermPalette, dark: Bool, to url: URL) throws {
        UserDefaults.standard.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        UserDefaults.standard.setVolatileDomain([TermPalette.key: palette.rawValue, Palette.appearanceKey: dark ? "dark" : "light"],
                                                forName: UserDefaults.argumentDomain)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: ModernWindow().environment(model))
        window.setContentSize(size)
        window.orderBack(nil)
        settle(1.5)
        window.displayIfNeeded()
        guard let frame = window.contentView?.superview ?? window.contentView,
              let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { throw Failure.noImage }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw Failure.noImage }
        try png.write(to: url)
        window.close()
        print("✓ \(url.path)")
    }

    /// Lets SwiftUI lay out and draw: the run loop turns for a moment.
    private static func settle(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}
