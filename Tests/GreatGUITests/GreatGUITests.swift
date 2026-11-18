import XCTest
import Registry
import Scheduler
import Secrets
@testable import GreatGUI

/// The app's model and its command line, without a window, the real Keychain service, or launchd.
@MainActor
final class GreatGUITests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("great-gui-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// A model over the text given, with a team file beside it when one is given. Nothing real is reachable.
    private func model(_ registry: String, team: String? = nil) throws -> AppModel {
        let url = dir.appendingPathComponent("commands.toml")
        try registry.write(to: url, atomically: true, encoding: .utf8)
        let teamURL = dir.appendingPathComponent("team/commands.toml")
        if let team {
            try FileManager.default.createDirectory(at: teamURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try team.write(to: teamURL, atomically: true, encoding: .utf8)
        }
        return AppModel(registryURL: url, teamURL: teamURL, store: HistoryStore(url: dir.appendingPathComponent("history.json")),
                        secrets: SecretStore(service: "com.cwkoenigs.the-great-gui.tests.model"),
                        scheduler: Snapshot.inertScheduler(in: dir), watch: false)
    }

    // MARK: a copy of a team command (DECISIONS local-037)

    func testACopyOfATeamCommandDoesNotCarryItsSchedule() throws {
        let m = try model("", team: """
        [[command]]
        name = "nightly"
        run = "echo nightly"
        schedule = "daily 03:00"
        """)
        let team = try XCTUnwrap(m.registry?.command(named: "nightly"))
        XCTAssertEqual(team.origin, .team)
        XCTAssertNil(team.schedule, "a team schedule is held back on load")
        m.openEditCommand(team)
        XCTAssertEqual(m.copyOf, "nightly")
        XCTAssertNil(m.editingName, "a team command is copied, not edited")
        XCTAssertEqual(m.draft.schedule, "", "the copy's schedule starts empty: saving must not arm anything")
        XCTAssertEqual(m.suggestedSchedule?.text, "daily 03:00", "the team's schedule is offered, as a switch")
        m.saveDraft()
        let mine = try XCTUnwrap(m.registry?.command(named: "nightly"))
        XCTAssertEqual(mine.origin, .personal)
        XCTAssertNil(mine.schedule)
        XCTAssertNil(m.copyOf)
        XCTAssertNil(m.suggestedSchedule)
    }

    func testEditingYourOwnScheduledCommandKeepsItsSchedule() throws {
        let m = try model("""
        [[command]]
        name = "mine"
        run = "echo mine"
        schedule = "weekdays 08:30"
        """)
        m.openEditCommand(try XCTUnwrap(m.registry?.command(named: "mine")))
        XCTAssertEqual(m.editingName, "mine")
        XCTAssertEqual(m.draft.schedule, "weekdays 08:30")
        XCTAssertNil(m.suggestedSchedule)
    }

    // MARK: the scheduler a snapshot or a test gets

    func testASnapshotModelCannotReachTheRealAgents() throws {
        let real = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents").path
        for screen in try Snapshot.screens() {
            let s = screen.model.scheduler
            XCTAssertNotEqual(s.agentsDir.path, real, "\(screen.name): drawing a screen must never sync the real agents")
            XCTAssertFalse(s.label(for: "x").hasPrefix("com.cwkoenigs.the-great-gui.cmd."), "\(screen.name): not the real label prefix")
        }
    }

    // MARK: staged rows, and what a file's state allows

    func testAStagedModelNeverAsksTheKeychain() throws {
        let m = try model("")
        let rows = [AppModel.SecretRow(name: "made-up", inKeychain: true, usedBy: [])]
        m.stage(secretRows: rows)
        m.refreshSecrets()
        XCTAssertEqual(m.secretRows, rows)
    }

    func testWhatEachFileStateAllows() {
        XCTAssertEqual(AppModel.fileActions(for: .inSync), [])
        XCTAssertEqual(AppModel.fileActions(for: .notStored), [.store])
        XCTAssertEqual(AppModel.fileActions(for: .notOnDisk), [.restore])
        XCTAssertEqual(AppModel.fileActions(for: .differs), [.store, .restore])
        XCTAssertEqual(AppModel.fileActions(for: .wrongMode), [.fixMode])
        XCTAssertEqual(AppModel.fileActions(for: .missing), [])
        XCTAssertEqual(AppModel.fileActions(for: nil), [])
    }

    func testAnAbsentFileCanStillBeAddedAndAFolderCannot() {
        XCTAssertTrue(AppModel.PathCheck.Kind.found.canAdd)
        XCTAssertTrue(AppModel.PathCheck.Kind.absent.canAdd)
        for kind in [AppModel.PathCheck.Kind.empty, .folder, .tooBig, .relative] { XCTAssertFalse(kind.canAdd) }
    }

    // MARK: the list

    func testArrowKeysMoveWithinWhatIsShown() throws {
        let m = try model("""
        [[command]]
        name = "a"
        run = "echo a"
        group = "one"

        [[command]]
        name = "b"
        run = "echo b"
        group = "two"

        [[command]]
        name = "c"
        run = "echo c"
        group = "one"
        """)
        XCTAssertEqual(m.selected, "a")
        m.moveSelection(1)
        XCTAssertEqual(m.selected, "b")
        m.moveSelection(5)
        XCTAssertEqual(m.selected, "c", "it stops at the last row")
        m.destination = .group("one")
        m.clampSelection()
        m.moveSelection(-1)
        XCTAssertEqual(m.selected, "a", "within a group it skips the others")
    }

    // MARK: a run that needs no secret starts at once

    func testARunWithNoSecretIsRunningAsSoonAsItStarts() throws {
        let m = try model("""
        [[command]]
        name = "plain"
        run = "true"
        env = { PAGER = "cat" }
        """)
        m.start(try XCTUnwrap(m.registry?.command(named: "plain")), params: [:])
        XCTAssertEqual(m.run?.status, .running, "no Keychain read, so no waiting state")
        XCTAssertEqual(m.run?.env["PAGER"], "cat")
        m.terminate()
    }

    // MARK: --capture (DECISIONS local-038)

    func testCaptureKeepsTheNewestBytesAndStartsAtALine() {
        let c = CLI.Capture()
        c.append("first line\n")
        XCTAssertEqual(c.text, "first line\n")
        XCTAssertFalse(c.truncated)
        let line = String(repeating: "x", count: 99) + "\n"
        for _ in 0..<1000 { c.append(line) }          // 100,000 bytes after the first line
        XCTAssertTrue(c.truncated)
        XCTAssertLessThanOrEqual(c.text.utf8.count, CLI.Capture.limit)
        XCTAssertFalse(c.text.contains("first line"), "the front is what goes")
        XCTAssertTrue(c.text.hasPrefix("x"), "it starts at the beginning of a kept line")
        XCTAssertTrue(c.text.hasSuffix(line))
        XCTAssertEqual(c.text.split(separator: "\n").map(\.count).min(), 99, "no partial line survives the cut")
        XCTAssertEqual(c.fields["output_truncated"] as? Bool, true)
    }

    // MARK: the version a build reports

    func testOutsideABundleTheVersionIsBare() {
        XCTAssertNil(Version.commit)
        XCTAssertEqual(Version.full, Version.string)
    }
}
