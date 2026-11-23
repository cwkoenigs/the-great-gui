import XCTest
@testable import Registry

final class RegistryWriterTests: XCTestCase {
    func temp(_ name: String = "commands.toml") -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gg-writer-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    func testParamSpecs() throws {
        XCTAssertEqual(try RegistryWriter.parseParam("seconds"), Param(name: "seconds"))
        XCTAssertEqual(try RegistryWriter.parseParam("seconds:how long=3600!"), Param(name: "seconds", desc: "how long", defaultValue: "3600", required: true))
        XCTAssertEqual(try RegistryWriter.parseParam("repo=~/Developer/x"), Param(name: "repo", defaultValue: "~/Developer/x"))
        XCTAssertEqual(try RegistryWriter.parseParam("who!"), Param(name: "who", required: true))
        XCTAssertEqual(try RegistryWriter.parseParams("a; b:desc=1 ;").map(\.name), ["a", "b"])
        XCTAssertThrowsError(try RegistryWriter.parseParam("Bad-Name"))
    }

    func testEnvTagsAndBools() throws {
        let env = try RegistryWriter.parseEnvs("TOKEN=keychain:gitlab-token; PAGER=cat")
        XCTAssertEqual(env["TOKEN"], .keychain("gitlab-token"))
        XCTAssertEqual(env["PAGER"], .literal("cat"))
        XCTAssertThrowsError(try RegistryWriter.parseEnv("novalue"))
        XCTAssertThrowsError(try RegistryWriter.parseEnv("1BAD=x"))
        XCTAssertEqual(RegistryWriter.parseTags("a, b c"), ["a", "b", "c"])
        XCTAssertTrue(try RegistryWriter.parseBool("yes", name: "gate"))
        XCTAssertFalse(try RegistryWriter.parseBool("", name: "gate"))
        XCTAssertThrowsError(try RegistryWriter.parseBool("maybe", name: "gate"))
    }

    func testBuildValidatesLikeTheLoader() throws {
        let c = try RegistryWriter.build(name: "caffeinate", run: "caffeinate -dimsu", desc: "keep awake", group: "mac")
        XCTAssertEqual(c.group, "mac")
        XCTAssertThrowsError(try RegistryWriter.build(name: "Bad Name", run: "x")) { XCTAssertTrue(($0 as! RegistryError).what.contains("not a valid name")) }
        XCTAssertThrowsError(try RegistryWriter.build(name: "x", run: "")) { XCTAssertEqual(($0 as! RegistryError).what, "x needs a run line") }
        XCTAssertThrowsError(try RegistryWriter.build(name: "x", run: "echo {who}")) { XCTAssertTrue(($0 as! RegistryError).what.contains("{who}")) }
    }

    func testRenderRoundTripsAndQuotes() throws {
        let c = Command(name: "tricky", group: "g", desc: "says \"hi\"\\ and\ttabs", run: "printf '%s\\n' \"$HOME\"", cwd: "~/x y",
                        interactive: true, gate: true, tags: ["a", "b"], env: ["TOKEN": .keychain("t"), "A": .literal("1")],
                        params: [Param(name: "who", desc: "d", defaultValue: "w", required: true)])
        let text = RegistryWriter.render(c)
        XCTAssertTrue(text.hasPrefix("[[command]]\nname = \"tricky\"\n"))
        XCTAssertTrue(text.contains("env = { A = \"1\", TOKEN = \"keychain:t\" }"))
        let back = try Registry.parse(text).commands[0]
        XCTAssertEqual(back, c)
        let plain = RegistryWriter.render(Command(name: "p", run: "true"))
        XCTAssertEqual(plain, "[[command]]\nname = \"p\"\nrun = \"true\"\n")
    }

    func testAppendCreatesThenRefusesDuplicates() throws {
        let url = temp()
        let a = try RegistryWriter.build(name: "a", run: "echo a")
        let reg1 = try RegistryWriter.append(a, to: url)
        XCTAssertEqual(reg1.commands.map(\.name), ["a"])
        try "# my notes\n".appending(try String(contentsOf: url, encoding: .utf8)).write(to: url, atomically: true, encoding: .utf8)
        let b = try RegistryWriter.build(name: "b", run: "echo b", params: [Param(name: "x", required: true)]).self
        let bWithRun = Command(name: "b", run: "echo {x}", params: [Param(name: "x", required: true)])
        _ = b
        let reg2 = try RegistryWriter.append(bWithRun, to: url)
        XCTAssertEqual(reg2.commands.map(\.name), ["a", "b"])
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("# my notes\n"), "hand-written text is kept")
        XCTAssertEqual(text.components(separatedBy: "[[command]]").count, 3)
        XCTAssertThrowsError(try RegistryWriter.append(a, to: url)) { XCTAssertEqual(($0 as! RegistryError).what, "a command named a exists") }
        XCTAssertEqual(try Registry.load(from: url).commands.count, 2, "a refused append changes nothing")
    }

    func testConcurrentRegistryMutationsKeepEveryBlock() async throws {
        let url = temp()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<16 {
                group.addTask { try RegistryWriter.append(Command(name: "c-\(i)", run: "true"), to: url) }
                group.addTask { try RegistryWriter.appendTool(Tool(name: "t-\(i)", method: .script, install: "echo ok"), to: url) }
                group.addTask { try RegistryWriter.appendFile(SecretFile(name: "f-\(i)", path: "~/fixture"), to: url) }
            }
            try await group.waitForAll()
        }
        let saved = try Registry.load(from: url)
        XCTAssertEqual(saved.commands.count, 16)
        XCTAssertEqual(saved.tools.count, 16)
        XCTAssertEqual(saved.files.count, 16)
    }

    func testStaleEditAndUnreadableRegistryPreserveExistingData() throws {
        let url = temp()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let old = Command(name: "check", run: "echo old")
        try RegistryWriter.append(old, to: url)
        let updated = Command(name: "check", run: "echo new")
        try RegistryWriter.replace("check", with: updated, in: url, expecting: old)
        XCTAssertThrowsError(try RegistryWriter.replace("check", with: old, in: url, expecting: old))
        XCTAssertEqual(try Registry.load(from: url).commands, [updated])

        let unreadable = Data([0xff, 0xfe, 0xfa])
        try unreadable.write(to: url)
        XCTAssertThrowsError(try RegistryWriter.append(old, to: url))
        XCTAssertEqual(try Data(contentsOf: url), unreadable)
    }

    func testAutoCommitOnlyInARepository() throws {
        let url = temp()
        try RegistryWriter.append(Command(name: "a", run: "true"), to: url)
        XCTAssertFalse(RegistryWriter.isRepository(url))
        XCTAssertFalse(RegistryWriter.autoCommit(url, message: "add a"))
        let dir = url.deletingLastPathComponent()
        for args in [["init", "-q"], ["config", "user.email", "t@example.com"], ["config", "user.name", "t"]] {
            XCTAssertEqual(RegistryWriter.git(args, in: dir).status, 0)
        }
        XCTAssertTrue(RegistryWriter.isRepository(url))
        XCTAssertTrue(RegistryWriter.autoCommit(url, message: "add a"))
        XCTAssertFalse(RegistryWriter.autoCommit(url, message: "nothing changed"), "no commit without a change")
        XCTAssertTrue(RegistryWriter.git(["log", "--oneline"], in: dir).output.contains("add a"))
    }
}
