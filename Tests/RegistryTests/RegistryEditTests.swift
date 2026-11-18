import XCTest
@testable import Registry

final class RegistryEditTests: XCTestCase {
    let sample = """
    # my registry
    # two lines of notes

    [[command]]
    name = "a"
    run = "echo a"

    # b is special
    [[command]]
    name = "b"
    desc = "old"
    run = "echo {x}"
    [[command.param]]
    name = "x"
    default = "1"

    [[command]]
    name = "c"
    run = "echo c"

    """

    func temp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gg-edit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("commands.toml")
        try sample.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testSplitFindsBlocksAndTheirComments() {
        let parts = RegistryWriter.split(sample)
        XCTAssertEqual(parts.preamble, "# my registry\n# two lines of notes\n\n")
        XCTAssertEqual(parts.blocks.map(\.name), ["a", "b", "c"])
        XCTAssertTrue(parts.blocks[1].text.hasPrefix("# b is special\n[[command]]\n"))
        XCTAssertEqual(RegistryWriter.leadingComments(parts.blocks[1].text), "# b is special\n")
        XCTAssertEqual(RegistryWriter.trailingBlanks(parts.blocks[1].text), "\n")
        XCTAssertEqual(parts.preamble + parts.blocks.map(\.text).joined(), sample, "split loses nothing")
        XCTAssertEqual(RegistryWriter.split("# nothing here\n").blocks.count, 0)
    }

    func testReplaceKeepsTheRestOfTheFile() throws {
        let url = try temp()
        let reg = try RegistryWriter.replace("b", with: Command(name: "b2", desc: "new", run: "echo b2"), in: url)
        XCTAssertEqual(reg.commands.map(\.name), ["a", "b2", "c"])
        let out = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(out, """
        # my registry
        # two lines of notes

        [[command]]
        name = "a"
        run = "echo a"

        # b is special
        [[command]]
        name = "b2"
        desc = "new"
        run = "echo b2"

        [[command]]
        name = "c"
        run = "echo c"

        """)
        XCTAssertThrowsError(try RegistryWriter.replace("zzz", with: Command(name: "z", run: "true"), in: url)) {
            XCTAssertEqual(($0 as? RegistryError)?.what, "no command named zzz")
        }
        XCTAssertThrowsError(try RegistryWriter.replace("a", with: Command(name: "c", run: "true"), in: url)) {
            XCTAssertEqual(($0 as? RegistryError)?.what, "a command named c exists")
        }
        XCTAssertEqual(try Registry.load(from: url).commands.map(\.name), ["a", "b2", "c"], "a refused replace changes nothing")
    }

    func testRemoveTakesTheBlockAndItsComment() throws {
        let url = try temp()
        let reg = try RegistryWriter.remove("b", from: url)
        XCTAssertEqual(reg.commands.map(\.name), ["a", "c"])
        let out = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(out.contains("b is special"))
        XCTAssertEqual(out, "# my registry\n# two lines of notes\n\n[[command]]\nname = \"a\"\nrun = \"echo a\"\n\n[[command]]\nname = \"c\"\nrun = \"echo c\"\n")
        try RegistryWriter.remove("c", from: url)
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).hasSuffix("run = \"echo a\"\n"), "the file ends with one newline")
        XCTAssertThrowsError(try RegistryWriter.remove("b", from: url))
    }

    func testReorderKeepsBlocksWhole() throws {
        let url = try temp()
        let reg = try RegistryWriter.reorder(["c", "a", "b"], in: url)
        XCTAssertEqual(reg.commands.map(\.name), ["c", "a", "b"])
        let out = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(out.hasPrefix("# my registry\n# two lines of notes\n\n[[command]]\nname = \"c\"\nrun = \"echo c\"\n\n[[command]]\nname = \"a\""))
        XCTAssertTrue(out.hasSuffix("# b is special\n[[command]]\nname = \"b\"\ndesc = \"old\"\nrun = \"echo {x}\"\n[[command.param]]\nname = \"x\"\ndefault = \"1\"\n"))
        XCTAssertThrowsError(try RegistryWriter.reorder(["a", "b"], in: url)) {
            XCTAssertEqual(($0 as? RegistryError)?.what, "reorder needs every command exactly once")
        }
    }

    func testSpecsRoundTrip() throws {
        for p in [Param(name: "x"), Param(name: "x", desc: "how long", defaultValue: "3600", required: true),
                  Param(name: "repo", defaultValue: "~/a:b"), Param(name: "x", required: true)] {
            XCTAssertEqual(try RegistryWriter.parseParam(RegistryWriter.paramSpec(p)), p)
        }
        let params = [Param(name: "a", desc: "first"), Param(name: "b", defaultValue: "2")]
        XCTAssertEqual(try RegistryWriter.parseParams(RegistryWriter.paramsSpec(params)), params)
        let env: [String: EnvValue] = ["TOKEN": .keychain("gitlab"), "PAGER": .literal("cat")]
        XCTAssertEqual(RegistryWriter.envSpec(env), "PAGER=cat; TOKEN=keychain:gitlab")
        XCTAssertEqual(try RegistryWriter.parseEnvs(RegistryWriter.envSpec(env)), env)
    }
}
