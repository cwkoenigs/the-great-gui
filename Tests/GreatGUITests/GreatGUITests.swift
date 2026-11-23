import XCTest
import AppKit
import SwiftUI
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

    func testCredentialProfileSetupReuseRotationAndChecks() async throws {
        let suite = "great-gui-credentials-tests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = SecretStore(service: suite)
        let registry = dir.appendingPathComponent("credentials.toml")
        let history = HistoryStore(url: dir.appendingPathComponent("credential-history.json"))
        let name = "fixture-token"
        defer {
            try? store.delete(name)
            preferences.removePersistentDomain(forName: suite)
        }
        try "".write(to: registry, atomically: true, encoding: .utf8)
        let m = AppModel(registryURL: registry, store: history, secrets: store,
                         scheduler: Snapshot.inertScheduler(in: dir, registryURL: registry), watch: false, preferences: preferences)
        m.openSecretSheet(named: name)
        m.newSecretValue = "fixture8"
        m.saveSecretFromSheet()
        XCTAssertTrue(store.exists(name))

        let profiles = m.credentialProfiles
        profiles.open()
        profiles.draft.label = "Example API"
        profiles.draft.destination = "api.example.com"
        profiles.draft.bindings = "API_TOKEN=fixture8"
        XCTAssertFalse(profiles.save())
        XCTAssertFalse(profiles.note?.text.contains("fixture8") ?? true)
        profiles.draft.bindings = "API_TOKEN=keychain:\(name)"
        profiles.draft.checkCommand = "test \"${#API_TOKEN}\" -eq 8"
        XCTAssertTrue(profiles.save())
        let profile = try XCTUnwrap(profiles.entries.first)
        let reloaded = CredentialProfiles(registryURL: registry, service: store.service, preferences: preferences)
        XCTAssertEqual(reloaded.entries, [profile])
        XCTAssertTrue(CredentialProfiles(registryURL: registry, service: suite + ".other", preferences: preferences).entries.isEmpty)

        profiles.check(profile, files: [], secrets: store)
        try await waitFor { profiles.checking == nil }
        XCTAssertEqual(profiles.results[profile.id]?.text, "Live check passed")
        XCTAssertTrue(history.load().isEmpty)

        let commands = ["first-check", "second-check"]
        for command in commands {
            m.openNewCommand()
            m.draft.name = command
            m.draft.run = "printf '%s\\n' \"${#API_TOKEN}\""
            m.useCredentialProfileInDraft(profile)
            m.saveDraft()
            XCTAssertEqual(m.registry?.command(named: command)?.env["API_TOKEN"], .keychain(name))
            m.runSelected()
            try await waitFor { m.run?.isDone == true }
            XCTAssertEqual(m.run?.lines, ["8"])
        }

        m.openSecretSheet(named: name, rotating: true)
        m.newSecretValue = "rotated-value"
        m.saveSecretFromSheet()
        XCTAssertNil(profiles.results[profile.id])
        for command in commands {
            m.select(command)
            m.runSelected()
            try await waitFor { m.run?.isDone == true }
            XCTAssertEqual(m.run?.lines, ["13"])
        }
        profiles.check(profile, files: [], secrets: store)
        try await waitFor { profiles.checking == nil }
        XCTAssertEqual(profiles.results[profile.id]?.text, "Live check failed (exit 1)")

        var missing = profile
        missing.bindings = "API_TOKEN=keychain:missing-fixture"
        profiles.check(missing, files: [], secrets: store)
        try await waitFor { profiles.checking == nil }
        XCTAssertTrue(profiles.results[profile.id]?.text.contains("missing-fixture") ?? false)
        let saved = try String(contentsOf: registry, encoding: .utf8)
        XCTAssertFalse(saved.contains("fixture8"))
        XCTAssertFalse(saved.contains("rotated-value"))
    }

    func testCredentialProfileDistinguishesEnvInjectionFromRequiredFile() async throws {
        let suite = "great-gui-credential-file-tests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = SecretStore(service: suite)
        let name = "fixture-env"
        defer {
            try? store.delete(name)
            preferences.removePersistentDomain(forName: suite)
        }
        _ = try store.set(name, value: "FIXTURE_ENV=fixture\n")
        let uri = dir.appendingPathComponent("fixture.env")
        let file = SecretFile(name: name, path: uri.path)
        let profiles = CredentialProfiles(registryURL: dir.appendingPathComponent("other.toml"),
                                          service: suite, preferences: preferences)
        var profile = CredentialProfile(label: "Test file", destination: "Test client", file: name,
                                        checkCommand: "test -n \"$FIXTURE_ENV\"")
        profiles.check(profile, files: [file], secrets: store)
        try await waitFor { profiles.checking == nil }
        XCTAssertEqual(profiles.results[profile.id]?.text, "Live check passed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: uri.path))

        profile.fileUse = .localFile
        profiles.check(profile, files: [file], secrets: store)
        try await waitFor { profiles.checking == nil }
        XCTAssertEqual(profiles.results[profile.id]?.text, "Credential file fixture-env is not on this Mac")
        XCTAssertFalse(FileManager.default.fileExists(atPath: uri.path))
    }

    func testTerminalNavigationPreservesOutputAndOnlyRunStartsAnotherShell() async throws {
        let m = try model("""
            [[command]]
            name = "counter"
            interactive = true
            cwd = "\(dir.path)"
            run = "echo turn >> turns.txt && echo finished"
            """)
        m.select("counter")
        m.runSelected()
        try await waitFor { m.run?.isDone == true }
        let first = try XCTUnwrap(m.run?.terminalSession)
        let command = try XCTUnwrap(m.selectedCommand)
        let frame = NSRect(x: 0, y: 0, width: 900, height: 740)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = NSHostingView(rootView: CommandDetail(command: command).environment(m))
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        try await waitFor { first.terminal.window === window }
        m.detailTab = .history
        try await waitFor { first.terminal.window == nil }
        m.detailTab = .terminal
        try await waitFor { first.terminal.window === window }
        XCTAssertTrue(String(decoding: first.terminal.getBufferAsData(), as: UTF8.self).contains("finished"))
        let second = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: true)
        let host = CommandTerminalPane.Host(frame: frame)
        second.contentView = host
        defer { second.orderOut(nil) }
        host.display(first, theme: .dark)
        XCTAssertTrue(first.terminal.window === window)
        let transfer = try XCTUnwrap(host.subviews.compactMap { $0 as? NSButton }.first)
        transfer.performClick(nil)
        XCTAssertTrue(first.terminal.window === second)
        XCTAssertTrue(String(decoding: first.terminal.getBufferAsData(), as: UTF8.self).contains("finished"))
        let turns = dir.appendingPathComponent("turns.txt")
        XCTAssertEqual(try String(contentsOf: turns, encoding: .utf8), "turn\n")
        m.runSelected()
        try await waitFor { m.run?.isDone == true && m.run?.terminalSession?.terminal.window === window }
        XCTAssertFalse(m.run?.terminalSession === first)
        XCTAssertEqual(try String(contentsOf: turns, encoding: .utf8), "turn\nturn\n")
        XCTAssertEqual(m.history.map(\.name), ["counter", "counter"])
    }

    func testExitFromReplacedProcessCannotFinishTheNewTerminalRun() async throws {
        let m = try model("")
        let marker = dir.appendingPathComponent("release-first").path
        m.startAsIs(name: "first", run: "while [ ! -f '\(marker)' ]; do sleep 0.05; done; exit 17", interactive: false)
        m.startAsIs(name: "second", run: "read -r answer; echo finished", interactive: true)
        let session = try XCTUnwrap(m.run?.terminalSession)
        try Data().write(to: URL(fileURLWithPath: marker))
        // Let the first process exit while the second is still waiting for input.
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(m.run?.status, .running)
        session.terminal.send(txt: "done\n")
        try await waitFor { m.run?.isDone == true }
        XCTAssertEqual(m.history.filter { $0.name == "second" }.map(\.code), [0])
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NSError(domain: "ScratchSessionTest", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for the shell"])
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
