import XCTest
@testable import Registry

/// `[[file]]` pointers and `env_file`: parsed loudly, written one block at a time, and never in the way
/// of the command blocks around them.
final class RegistryFilesTests: XCTestCase {
    func temp() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gg-files-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("commands.toml")
    }

    let both = """
    # mine
    [[command]]
    name = "a"
    run = "echo a"
    env_file = "keychain:proj-env"
    env = { TOKEN = "keychain:tok" }

    # the snowflake connections
    [[file]]
    name = "snowflake-connections"
    path = "~/.snowflake/connections.toml"

    [[command]]
    name = "b"
    run = "echo b"

    [[file]]
    name = "proj-env"
    path = "~/proj/.env"
    mode = "400"
    desc = "the project's env"

    """

    func testParsesFilesAndEnvFile() throws {
        let reg = try Registry.parse(both)
        XCTAssertEqual(reg.commands.map(\.name), ["a", "b"])
        XCTAssertEqual(reg.files.map(\.name), ["snowflake-connections", "proj-env"])
        XCTAssertEqual(reg.files[0].mode, "600")
        XCTAssertEqual(reg.files[1].modeBits, 0o400)
        XCTAssertEqual(reg.files[1].desc, "the project's env")
        XCTAssertTrue(reg.files[0].expandedPath.hasSuffix("/.snowflake/connections.toml"))
        XCTAssertFalse(reg.files[0].expandedPath.hasPrefix("~"))
        XCTAssertEqual(reg.commands[0].envFile, "proj-env")
        XCTAssertEqual(reg.commands[0].secretNames, ["proj-env", "tok"])
        XCTAssertEqual(try reg.resolve(reg.commands[0]).envFile, "proj-env")
        XCTAssertNil(reg.commands[1].envFile)
    }

    func testRefusals() {
        func what(_ toml: String) -> String {
            do { _ = try Registry.parse(toml); return "parsed" } catch let e as RegistryError { return e.what } catch { return "\(error)" }
        }
        XCTAssertTrue(what("[[file]]\nname = \"x\"\npath = \"~/x\"\nmode = \"644\"\n").contains("lets other users read"))
        XCTAssertTrue(what("[[file]]\nname = \"x\"\npath = \"~/x\"\nmode = \"rw\"\n").contains("three octal digits"))
        XCTAssertTrue(what("[[file]]\nname = \"x\"\npath = \"rel/x\"\n").contains("relative path"))
        XCTAssertTrue(what("[[file]]\nname = \"x\"\npath = \"\"\n").contains("empty path"))
        XCTAssertTrue(what("[[file]]\nname = \"has space\"\npath = \"~/x\"\n").contains("not a valid name"))
        XCTAssertTrue(what("[[file]]\nname = \"x\"\npath = \"~/x\"\n[[file]]\nname = \"x\"\npath = \"~/y\"\n").contains("two files are named x"))
        XCTAssertTrue(what("[[file]]\nname = \"x\"\n").contains("has no path"))
        XCTAssertTrue(what("[[command]]\nname = \"a\"\nrun = \"x\"\nenv_file = \"~/proj/.env\"\n").contains("env_file must be keychain:NAME"))
        do {
            _ = try Registry.parse("[[file]]\nname = \"x\"\npath = \"~/x\"\nvalue = \"secret\"\n")
            XCTFail("an unknown key must be refused")
        } catch let e as RegistryError {
            XCTAssertTrue(e.what.contains("unknown key value"))
            XCTAssertEqual(e.fix, "allowed: name, path, mode, desc")
        } catch { XCTFail("\(error)") }
    }

    func testRenderAndBuildRoundTrip() throws {
        let c = try RegistryWriter.build(name: "a", run: "echo a", envFile: "keychain:proj-env")
        XCTAssertEqual(c.envFile, "proj-env")
        XCTAssertTrue(RegistryWriter.render(c).contains("env_file = \"keychain:proj-env\""))
        XCTAssertEqual(try RegistryWriter.build(name: "a", run: "echo a", envFile: "proj-env").envFile, "proj-env")
        XCTAssertNil(try RegistryWriter.build(name: "a", run: "echo a", envFile: " ").envFile)
        XCTAssertThrowsError(try RegistryWriter.build(name: "a", run: "echo a", envFile: "keychain:has space"))

        let f = try RegistryWriter.buildFile(name: "snow", path: "~/.snowflake/connections.toml")
        XCTAssertEqual(RegistryWriter.render(f), "[[file]]\nname = \"snow\"\npath = \"~/.snowflake/connections.toml\"\n")
        XCTAssertThrowsError(try RegistryWriter.buildFile(name: "snow", path: "~/x", mode: "644"))
        XCTAssertThrowsError(try RegistryWriter.buildFile(name: "", path: "~/x"))
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(RegistryWriter.portable(home + "/proj/.env"), "~/proj/.env")
        XCTAssertEqual(RegistryWriter.portable("/etc/x"), "/etc/x")
    }

    func testAppendAndRemoveFileKeepTheRest() throws {
        let url = temp()
        try both.write(to: url, atomically: true, encoding: .utf8)
        let added = try RegistryWriter.appendFile(SecretFile(name: "third", path: "~/third"), to: url)
        XCTAssertEqual(added.files.map(\.name), ["snowflake-connections", "proj-env", "third"])
        XCTAssertThrowsError(try RegistryWriter.appendFile(SecretFile(name: "third", path: "~/other"), to: url))

        let removed = try RegistryWriter.removeFile("snowflake-connections", from: url)
        XCTAssertEqual(removed.files.map(\.name), ["proj-env", "third"])
        XCTAssertEqual(removed.commands.map(\.name), ["a", "b"])
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("# the snowflake connections"), "the comment above the block goes with it")
        XCTAssertTrue(text.contains("# mine"))
        XCTAssertThrowsError(try RegistryWriter.removeFile("nope", from: url))
    }

    /// The bug this guards: a `[[file]]` block after a command used to be part of that command's block,
    /// so editing or removing the command took the file pointer with it.
    func testCommandEditsLeaveFileBlocksAlone() throws {
        let url = temp()
        try both.write(to: url, atomically: true, encoding: .utf8)
        let edited = try RegistryWriter.replace("a", with: try RegistryWriter.build(name: "a", run: "echo changed"), in: url)
        XCTAssertEqual(edited.files.map(\.name), ["snowflake-connections", "proj-env"])
        XCTAssertEqual(edited.command(named: "a")?.run, "echo changed")
        XCTAssertNil(edited.command(named: "a")?.envFile)

        let reordered = try RegistryWriter.reorder(["b", "a"], in: url)
        XCTAssertEqual(reordered.commands.map(\.name), ["b", "a"])
        XCTAssertEqual(reordered.files.map(\.name), ["snowflake-connections", "proj-env"])

        let removed = try RegistryWriter.remove("b", from: url)
        XCTAssertEqual(removed.commands.map(\.name), ["a"])
        XCTAssertEqual(removed.files.map(\.name), ["snowflake-connections", "proj-env"])
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("# the snowflake connections"))
    }
}
