import XCTest
@testable import Registry

final class TeamTests: XCTestCase {
    let mine = """
    [[command]]
    name = "hello"
    run = "echo mine"

    [[command]]
    name = "deploy"
    group = "work"
    run = "echo my deploy"

    [[file]]
    name = "snowflake"
    path = "~/.snowflake/connections.toml"
    """

    let theirs = """
    [[command]]
    name = "deploy"
    group = "team"
    run = "echo team deploy"

    [[command]]
    name = "refresh"
    group = "team"
    run = "dbt run"
    schedule = "weekdays 08:30"
    env = { TOKEN = "keychain:team-token" }

    [[file]]
    name = "snowflake"
    path = "~/elsewhere/connections.toml"

    [[file]]
    name = "aws"
    path = "~/.aws/credentials"
    """

    func merged() throws -> Registry {
        try Registry.parse(mine).merging(team: try Registry.parse(theirs, url: URL(fileURLWithPath: "/team/commands.toml")))
    }

    func testPersonalWinsAClashAndIsMarked() throws {
        let reg = try merged()
        XCTAssertEqual(reg.commands.map(\.name), ["hello", "deploy", "refresh"])
        let deploy = try XCTUnwrap(reg.command(named: "deploy"))
        XCTAssertEqual(deploy.run, "echo my deploy")
        XCTAssertEqual(deploy.origin, .personal)
        XCTAssertTrue(deploy.overridesTeam)
        XCTAssertFalse(try XCTUnwrap(reg.command(named: "hello")).overridesTeam)
        XCTAssertEqual(reg.team?.overridden, ["deploy"])
        XCTAssertEqual(reg.team?.commands, 2)
        XCTAssertEqual(reg.personal.map(\.name), ["hello", "deploy"])
        XCTAssertEqual(reg.teamCommands.map(\.name), ["refresh"])
    }

    func testATeamScheduleIsHeldBack() throws {
        let refresh = try XCTUnwrap(try merged().command(named: "refresh"))
        XCTAssertEqual(refresh.origin, .team)
        XCTAssertNil(refresh.schedule, "nothing the team sends runs by itself")
        XCTAssertEqual(refresh.teamSchedule?.text, "weekdays 08:30")
        XCTAssertEqual(refresh.secretNames, ["team-token"], "the secrets a team command names are the checklist")
    }

    func testTeamFilePointersJoinAndPersonalWins() throws {
        let reg = try merged()
        XCTAssertEqual(reg.files.map(\.name), ["snowflake", "aws"])
        XCTAssertEqual(reg.file(named: "snowflake")?.path, "~/.snowflake/connections.toml")
        XCTAssertEqual(reg.file(named: "snowflake")?.team, false)
        XCTAssertEqual(reg.file(named: "aws")?.team, true)
    }

    func testTeamFolderSitsBesideTheRegistry() {
        guard ProcessInfo.processInfo.environment["GREAT_GUI_TEAM"] == nil else { return }
        let url = Registry.teamURL(for: URL(fileURLWithPath: "/Users/x/.great-gui/commands.toml"))
        XCTAssertEqual(url.path, "/Users/x/.great-gui-team/commands.toml")
    }

    func testLoadAllWithoutATeamAndWithABrokenOne() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gg-team-\(UUID().uuidString)")
        let own = dir.appendingPathComponent("own/commands.toml"), team = dir.appendingPathComponent("team/commands.toml")
        try FileManager.default.createDirectory(at: own.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: team.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try mine.write(to: own, atomically: true, encoding: .utf8)

        let alone = try Registry.loadAll(from: own, team: team)
        XCTAssertNil(alone.team)
        XCTAssertEqual(alone.commands.count, 2)

        try theirs.write(to: team, atomically: true, encoding: .utf8)
        XCTAssertEqual(try Registry.loadAll(from: own, team: team).commands.count, 3)

        try "[[command]]\nname = \"x\"\n".write(to: team, atomically: true, encoding: .utf8)
        let broken = try Registry.loadAll(from: own, team: team)
        XCTAssertEqual(broken.commands.map(\.name), ["hello", "deploy"], "a bad team file costs the person nothing")
        XCTAssertNotNil(broken.team?.problem)
    }
}
