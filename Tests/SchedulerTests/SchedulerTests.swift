import XCTest
import Registry
@testable import Scheduler

/// A launchd that remembers what is loaded and what was asked of it.
final class FakeLaunchd {
    var loaded: Set<String> = []
    var calls: [[String]] = []
    func run(_ args: [String]) -> (status: Int32, output: String) {
        calls.append(args)
        switch args[0] {
        case "bootstrap":
            let label = URL(fileURLWithPath: args[2]).deletingPathExtension().lastPathComponent
            loaded.insert(label)
            return (0, "")
        case "bootout":
            let label = args[1].split(separator: "/").last.map(String.init) ?? ""
            return loaded.remove(label) == nil ? (113, "Boot-out failed: 113: Could not find specified service") : (0, "")
        case "print":
            let label = args[1].split(separator: "/").last.map(String.init) ?? ""
            return loaded.contains(label) ? (0, "\tstate = waiting\n\tlast exit code = 0\n") : (113, "Could not find service")
        default:
            return (1, "unexpected")
        }
    }
}

final class SchedulerTests: XCTestCase {
    var dir: URL!
    var launchd: FakeLaunchd!
    var scheduler: Scheduler!
    let program = URL(fileURLWithPath: "/Applications/the-great-gui.app/Contents/MacOS/the-great-gui")

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("gg-sched-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        launchd = FakeLaunchd()
        scheduler = Scheduler(program: program, environment: [
            "GREAT_GUI_AGENTS": dir.appendingPathComponent("agents").path,
            "GREAT_GUI_LOGS": dir.appendingPathComponent("logs").path,
            "GREAT_GUI_SCHEDULER_STATE": dir.appendingPathComponent("state.json").path,
            "GREAT_GUI_AGENT_PREFIX": "test.gg.",
            "GREAT_GUI_REGISTRY": "/tmp/r.toml",
            "SHELL": "/bin/zsh",
            "PATH": "/usr/bin",
        ])
        scheduler.launchctl = { [launchd] in launchd!.run($0) }
    }

    func registry(_ commands: [Command]) -> Registry { Registry(url: URL(fileURLWithPath: "/tmp/r.toml"), commands: commands) }

    func testPlistCarriesScheduleProgramLogAndEnvironment() throws {
        let c = Command(name: "brew", run: "brew outdated", schedule: try Schedule("weekdays 08:30"))
        let dict = try PropertyListSerialization.propertyList(from: try scheduler.plist(for: c), format: nil) as! [String: Any]
        XCTAssertEqual(dict["Label"] as? String, "test.gg.brew")
        XCTAssertEqual(dict["ProgramArguments"] as? [String], [program.path, "run", "brew"])
        XCTAssertEqual(dict["StandardOutPath"] as? String, dir.appendingPathComponent("logs/brew.log").path)
        let cal = dict["StartCalendarInterval"] as! [[String: Int]]
        XCTAssertEqual(cal.count, 5)
        XCTAssertEqual(cal[0], ["Minute": 30, "Hour": 8, "Weekday": 1])
        let env = dict["EnvironmentVariables"] as! [String: String]
        XCTAssertEqual(env["GREAT_GUI_SCHEDULED"], "1")
        XCTAssertEqual(env["GREAT_GUI_REGISTRY"], "/tmp/r.toml")
        XCTAssertEqual(env["SHELL"], "/bin/zsh")
        XCTAssertNil(env["PATH"], "only our overrides and the shell travel")
        let every = Command(name: "tick", run: "true", schedule: try Schedule("every 15m"))
        let d2 = try PropertyListSerialization.propertyList(from: try scheduler.plist(for: every), format: nil) as! [String: Any]
        XCTAssertEqual(d2["StartInterval"] as? Int, 900)
        XCTAssertNil(d2["StartCalendarInterval"])
        XCTAssertThrowsError(try scheduler.plist(for: Command(name: "plain", run: "true")))
    }

    func testSyncWritesLoadsRemovesAndIsIdempotent() throws {
        let a = Command(name: "a", run: "true", schedule: try Schedule("daily 09:00"))
        let b = Command(name: "b", run: "true", schedule: try Schedule("every 1h"))
        let plain = Command(name: "plain", run: "true")
        let r1 = scheduler.sync(registry([a, b, plain]))
        XCTAssertEqual(r1.written.sorted(), ["a", "b"])
        XCTAssertEqual(r1.loaded.sorted(), ["a", "b"])
        XCTAssertTrue(r1.problems.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: scheduler.agentURL(for: "a").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scheduler.agentURL(for: "plain").path))
        XCTAssertEqual(launchd.loaded, ["test.gg.a", "test.gg.b"])

        let r2 = scheduler.sync(registry([a, b, plain]))
        XCTAssertFalse(r2.changed, "nothing to do the second time")

        // b loses its schedule, a changes its time
        let a2 = Command(name: "a", run: "true", schedule: try Schedule("daily 10:00"))
        let r3 = scheduler.sync(registry([a2, Command(name: "b", run: "true"), plain]))
        XCTAssertEqual(r3.removed, ["b"])
        XCTAssertEqual(r3.written, ["a"])
        XCTAssertEqual(r3.loaded, ["a"])
        XCTAssertEqual(launchd.loaded, ["test.gg.a"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: scheduler.agentURL(for: "b").path))
        XCTAssertTrue(launchd.calls.contains(["bootout", "gui/\(getuid())/test.gg.a"]), "a was unloaded before its agent was rewritten")
    }

    func testPauseAndResume() throws {
        let a = Command(name: "a", run: "true", schedule: try Schedule("daily 09:00"))
        let reg = registry([a])
        scheduler.sync(reg)
        try scheduler.pause("a", in: reg)
        XCTAssertEqual(scheduler.paused(), ["a"])
        XCTAssertEqual(launchd.loaded, [], "paused means unloaded")
        XCTAssertTrue(FileManager.default.fileExists(atPath: scheduler.agentURL(for: "a").path), "the agent file stays")
        XCTAssertFalse(scheduler.sync(reg).changed, "sync respects the pause")
        try scheduler.resume("a", in: reg)
        XCTAssertEqual(scheduler.paused(), [])
        XCTAssertEqual(launchd.loaded, ["test.gg.a"])
        XCTAssertThrowsError(try scheduler.pause("nope", in: reg))
        XCTAssertEqual(scheduler.status("a"), Scheduler.Status(loaded: true, running: false, lastExit: 0))
        XCTAssertEqual(scheduler.status("nope").loaded, false)
    }

    func testLogSectionsAndTrim() throws {
        try FileManager.default.createDirectory(at: scheduler.logsDir, withIntermediateDirectories: true)
        let url = scheduler.logURL(for: "a")
        let text = Scheduler.header(name: "a", at: Date(timeIntervalSince1970: 0)) + "\nfirst\n" + Scheduler.footer(code: 0, seconds: 1) + "\n"
            + Scheduler.header(name: "a", at: Date(timeIntervalSince1970: 60)) + "\nsecond\n" + Scheduler.footer(code: 3, seconds: 2) + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
        let last = try XCTUnwrap(scheduler.lastLog(for: "a"))
        XCTAssertTrue(last.hasPrefix(Scheduler.runMarker))
        XCTAssertTrue(last.contains("second") && !last.contains("first"))
        XCTAssertTrue(last.hasSuffix("─── exit 3 · 2.0s\n"))
        XCTAssertNil(scheduler.lastLog(for: "none"))
        try Data(repeating: 0x61, count: 1_200_000).write(to: url)
        scheduler.trimLog(for: "a")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path))[.size] as? Int, 262_144)
    }

    func testNextRun() throws {
        let cal = Command(name: "a", run: "true", schedule: try Schedule("daily 09:00"))
        XCTAssertNotNil(scheduler.nextRun(for: cal, lastRun: nil))
        let every = Command(name: "b", run: "true", schedule: try Schedule("every 15m"))
        XCTAssertNil(scheduler.nextRun(for: every, lastRun: nil))
        let t = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(scheduler.nextRun(for: every, lastRun: t), t.addingTimeInterval(900))
        XCTAssertNil(scheduler.nextRun(for: Command(name: "c", run: "true"), lastRun: t))
    }
}
