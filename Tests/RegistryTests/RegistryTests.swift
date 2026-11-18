import XCTest
@testable import Registry

final class RegistryTests: XCTestCase {
    let sample = """
    [[command]]
    name = "hello"
    desc = "say hi"
    run = "echo hi {who}"
    [[command.param]]
    name = "who"
    default = "world"

    [[command]]
    name = "status"
    group = "git"
    run = "git -C {repo} status"
    cwd = "{repo}"
    [[command.param]]
    name = "repo"
    required = true

    [[command]]
    name = "pipelines"
    group = "work"
    run = "glab ci list"
    env = { GITLAB_TOKEN = "keychain:gitlab-token", PAGER = "cat" }
    gate = true
    interactive = false
    tags = ["work"]
    """

    func testParsesCommandsGroupsAndEnv() throws {
        let reg = try Registry.parse(sample)
        XCTAssertEqual(reg.commands.map(\.name), ["hello", "status", "pipelines"])
        XCTAssertEqual(reg.groups, ["commands", "git", "work"])
        let p = try XCTUnwrap(reg.command(named: "pipelines"))
        XCTAssertEqual(p.env["GITLAB_TOKEN"], .keychain("gitlab-token"))
        XCTAssertEqual(p.env["PAGER"], .literal("cat"))
        XCTAssertEqual(p.secretNames, ["gitlab-token"])
        XCTAssertTrue(p.gate)
        XCTAssertEqual(EnvValue.keychain("x").display, "keychain:x")
    }

    func testResolvesDefaultsAndQuotesGivenValues() throws {
        let reg = try Registry.parse(sample)
        let hello = try XCTUnwrap(reg.command(named: "hello"))
        XCTAssertEqual(try reg.resolve(hello).run, "echo hi world")
        XCTAssertEqual(try reg.resolve(hello, params: ["who": "a b"]).run, "echo hi 'a b'")
        XCTAssertEqual(try reg.resolve(hello, params: ["who": "it's"]).run, "echo hi 'it'\"'\"'s'")
    }

    func testRequiredParamAndPreview() throws {
        let reg = try Registry.parse(sample)
        let status = try XCTUnwrap(reg.command(named: "status"))
        XCTAssertThrowsError(try reg.resolve(status)) { e in
            XCTAssertEqual((e as? RegistryError)?.what, "status needs repo")
        }
        XCTAssertEqual(reg.preview(status)?.run, "git -C {repo} status")
        let r = try reg.resolve(status, params: ["repo": "~/Developer/x"])
        XCTAssertEqual(r.run, "git -C '~/Developer/x' status".replacingOccurrences(of: "'~/Developer/x'", with: "~/Developer/x"))
        XCTAssertEqual(r.cwd, NSString(string: "~/Developer/x").expandingTildeInPath)
    }

    func testUnknownParamIsAnError() throws {
        let reg = try Registry.parse(sample)
        XCTAssertThrowsError(try reg.resolve(reg.commands[0], params: ["nope": "1"])) { e in
            XCTAssertEqual((e as? RegistryError)?.what, "hello has no parameter nope")
        }
    }

    func testFilterMatchesNameDescGroupAndTags() throws {
        let reg = try Registry.parse(sample)
        XCTAssertEqual(reg.filtered("hi").map(\.name), ["hello"])
        XCTAssertEqual(reg.filtered("GIT").map(\.name), ["status"])
        XCTAssertEqual(reg.filtered("work").map(\.name), ["pipelines"])
        XCTAssertEqual(reg.filtered("  ").count, 3)
    }

    func testLoudErrors() {
        func what(_ toml: String) -> String { (try? Registry.parse(toml)).map { _ in "" } ?? { do { _ = try Registry.parse(toml); return "" } catch { return (error as! RegistryError).what } }() }
        XCTAssertEqual(what("[[command]]\nname = \"a\"\nrun = \"x\"\nnmae = 1\n"), "command[0]: unknown key nmae")
        XCTAssertEqual(what("[[command]]\nname = \"a\"\n"), "command[0] has no run")
        XCTAssertEqual(what("[[command]]\nname = \"a\"\nrun = \"x\"\ninteractive = \"yes\"\n"), "command[0].interactive must be true or false")
        XCTAssertEqual(what("[[command]]\nname = \"A b\"\nrun = \"x\"\n"), "command[0]: 'A b' is not a valid name")
        XCTAssertEqual(what("[[command]]\nname = \"a\"\nrun = \"x\"\n[[command]]\nname = \"a\"\nrun = \"y\"\n"), "two commands are named a")
        XCTAssertEqual(what("[[command]]\nname = \"a\"\nrun = \"echo {who}\"\n"), "a uses {who} but declares no such parameter")
        XCTAssertTrue(what("[[command]\nname = \"a\"\n").hasPrefix("commands.toml:"))
    }

    func testMissingFileNamesTheFix() {
        XCTAssertThrowsError(try Registry.load(from: URL(fileURLWithPath: "/nonexistent/commands.toml"))) { e in
            XCTAssertTrue((e as! RegistryError).fix.contains("first launch"))
        }
    }

    func testExampleRegistryParses() throws {
        let reg = try Registry.parse(Registry.exampleTOML())
        XCTAssertGreaterThan(reg.commands.count, 5)
        XCTAssertNotNil(reg.command(named: "brew-upgrade"))
    }
}
