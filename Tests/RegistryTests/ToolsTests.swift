import XCTest
@testable import Registry

final class ToolsTests: XCTestCase {
    let mine = """
    [[command]]
    name = "hello"
    run = "echo hi"

    [[tool]]
    name = "ripgrep"
    desc = "fast search"
    method = "brew"
    bin = "rg"

    [[tool]]
    name = "uv"
    method = "script"
    install = "curl -LsSf https://astral.sh/uv/install.sh | sh"
    update = "uv self update"

    [[tool]]
    name = "ruff"
    method = "uv"
    pkg = "ruff==0.6.1"
    requires = ["uv"]

    [[tool]]
    name = "iterm"
    method = "cask"
    pkg = "iterm2"
    """

    func tools() throws -> [Tool] { try Registry.parse(mine).tools }

    func testEntriesLoadWithDerivedLines() throws {
        let t = try tools()
        XCTAssertEqual(t.map(\.name), ["ripgrep", "uv", "ruff", "iterm"])
        XCTAssertEqual(t[0].installLine, "brew install ripgrep")
        XCTAssertEqual(t[0].updateLine, "brew upgrade ripgrep")
        XCTAssertEqual(t[1].bin, "uv")                       // a script tool is found by its name unless bin says otherwise
        XCTAssertEqual(t[1].updateLine, "uv self update")
        XCTAssertEqual(t[2].key, "ruff")                     // the pin is not part of the name uv lists
        XCTAssertEqual(t[2].installLine, "uv tool install ruff==0.6.1")
        XCTAssertEqual(t[2].updateLine, "uv tool upgrade ruff")
        XCTAssertEqual(t[3].installLine, "brew install --cask iterm2")
    }

    func testMistakesAreNamed() {
        func what(_ toml: String) -> String {
            do { _ = try Registry.parse(toml); return "" } catch let e as RegistryError { return e.what } catch { return "\(error)" }
        }
        XCTAssertTrue(what("[[tool]]\nname = \"x\"\nmethod = \"apt\"").contains("method 'apt' is not one of"))
        XCTAssertTrue(what("[[tool]]\nname = \"x\"\nmethod = \"script\"").contains("no install"))
        XCTAssertTrue(what("[[tool]]\nname = \"x\"\nmethod = \"brew\"\ninstall = \"echo\"").contains("install and update are for method script"))
        XCTAssertTrue(what("[[tool]]\nname = \"x\"\nmethod = \"brew\"\npkg = \"a; rm -rf ~\"").contains("is not a package name"))
        XCTAssertTrue(what("[[tool]]\nname = \"x\"\nmethod = \"brew\"\npkg = \"--cask\"").contains("is not a package name"))
        XCTAssertTrue(what("[[tool]]\nname = \"x\"\nmethod = \"brew\"\nbin = \"/bin/sh -c\"").contains("is not a program name"))
        XCTAssertTrue(what("[[tool]]\nname = \"x\"\nmethod = \"brew\"\n\n[[tool]]\nname = \"x\"\nmethod = \"uv\"").contains("two tools are named x"))
        XCTAssertTrue(what("[[tool]]\nname = \"x\"\nmethod = \"brew\"\ncolour = \"red\"").contains("unknown key colour"))
        XCTAssertTrue(what("[[tool]]\nname = \"x\"\nmethod = \"brew\"\nrequires = [\"x\"]").contains("requires itself"))
    }

    func testStatusIsReadFromTheLook() throws {
        let output = """
        welcome to my shell
        @@have
        brew
        uv
        @@brew
        abseil 20260817.0
        ripgrep 14.0.0 14.1.0
        @@cask
        @@uv
        ruff v0.6.1
        - ruff
        @@bin
        rg
        uv
        @@version
        uv uv 0.12.23 (abc 2026-10-01)
        @@brew-outdated
        ripgrep
        @@cask-outdated
        @@uv-outdated
        ruff v0.6.1 [latest: 0.7.0]
        - ruff
        @@end
        """
        let s = ToolProbe.parse(output, tools: try tools(), outdated: true)
        XCTAssertEqual(s["ripgrep"], ToolStatus(installed: true, version: "14.1.0", outdated: true))
        XCTAssertEqual(s["uv"], ToolStatus(installed: true, version: "0.12.23"))          // a script cannot say it is behind
        XCTAssertEqual(s["ruff"], ToolStatus(installed: true, version: "0.6.1", outdated: true, latest: "0.7.0"))
        XCTAssertEqual(s["iterm"], ToolStatus(installed: false))
        XCTAssertEqual(s["ruff"]?.words, "update available 0.6.1 → 0.7.0")
    }

    func testTheOtherManagersAreRead() throws {
        let toml = """
        [[tool]]
        name = "codex"
        method = "npm"
        pkg = "@openai/codex"

        [[tool]]
        name = "linked"
        method = "npm"
        pkg = "ds-code"

        [[tool]]
        name = "bat"
        method = "cargo"

        [[tool]]
        name = "poetry"
        method = "pipx"

        [[tool]]
        name = "requests"
        method = "pip"
        pkg = "Typing_Extensions"

        [[tool]]
        name = "gopls"
        method = "go"
        pkg = "golang.org/x/tools/gopls"
        """
        let t = try Registry.parse(toml).tools
        XCTAssertEqual(t[0].updateLine, "npm install -g @openai/codex@latest")
        XCTAssertEqual(t[5].bin, "gopls")
        XCTAssertEqual(t[5].installLine, "go install golang.org/x/tools/gopls@latest")
        let output = """
        @@have
        npm
        cargo
        pipx
        python3
        @@pipx
        poetry 2.1.0
        @@pip
        typing_extensions==4.12.0
        @@npm
        /opt/homebrew/lib
        +-- @openai/codex@0.162.1
        +-- ds-code@0.1.0 -> ./../../../Users/someone/ds-code
        `-- vercel@65.0.0
        @@cargo
        bat v0.25.0:
            bat
        @@bin
        @@npm-outdated
        /opt/homebrew/lib/node_modules/@openai/codex:@openai/codex@0.167.2:@openai/codex@0.162.1:@openai/codex@0.167.2:global
        @@end
        """
        let s = ToolProbe.parse(output, tools: t, outdated: true)
        XCTAssertEqual(s["codex"], ToolStatus(installed: true, version: "0.162.1", outdated: true, latest: "0.167.2"))
        XCTAssertEqual(s["linked"], ToolStatus(installed: true, version: "0.1.0", outdated: false))
        XCTAssertEqual(s["bat"], ToolStatus(installed: true, version: "0.25.0"))
        XCTAssertEqual(s["poetry"], ToolStatus(installed: true, version: "2.1.0"))
        XCTAssertEqual(s["requests"], ToolStatus(installed: true, version: "4.12.0"))
        XCTAssertEqual(s["gopls"], ToolStatus(installed: false, managerMissing: "go"))
    }

    func testAMissingManagerAndAToolFromElsewhereAreSaid() throws {
        let s = ToolProbe.parse("@@have\n@@brew\n@@cask\n@@uv\n@@bin\nrg\n@@end", tools: try tools(), outdated: false)
        XCTAssertEqual(s["ripgrep"], ToolStatus(installed: true, elsewhere: true))        // on PATH, but brew did not put it there
        XCTAssertEqual(s["iterm"], ToolStatus(installed: false, managerMissing: "brew"))
        XCTAssertEqual(s["ruff"]?.words, "missing · needs uv")
        XCTAssertNil(s["ripgrep"]?.outdated)                                                // nobody asked
    }

    func testTheDailyLookRunsNothingTheRegistryNames() throws {
        let quiet = ToolProbe.script(for: try tools(), versions: false, outdated: true)
        XCTAssertFalse(quiet.contains("uv --version"))
        XCTAssertFalse(quiet.contains("astral.sh"))          // an install line is never part of a look
        XCTAssertFalse(quiet.contains("self update"))
        XCTAssertTrue(quiet.contains("brew outdated --formula --quiet"))
        let asked = ToolProbe.script(for: try tools(), versions: true, outdated: false)
        XCTAssertTrue(asked.contains("uv --version"))
        XCTAssertFalse(asked.contains("outdated"))
    }

    func testARunChecksWhatItNeedsAndKeepsOrder() throws {
        let t = try tools()
        XCTAssertEqual(ToolProbe.ordered([t[2], t[1]]).map(\.name), ["uv", "ruff"])
        let line = ToolProbe.runLine(t[2], update: false, among: t)
        XCTAssertTrue(line.contains("command -v uv >/dev/null 2>&1 || {"))
        XCTAssertTrue(line.hasSuffix("uv tool install ruff==0.6.1"))
        let batch = ToolProbe.batch([(t[1], false), (t[2], true)], among: t)
        XCTAssertTrue(batch.contains("uv tool upgrade ruff"))
        XCTAssertTrue(batch.hasSuffix("exit $fail"))
    }

    /// The batch the window runs, with installers that only echo: a failure is counted and the rest still run.
    func testABatchRunsEveryToolAndReportsAFailure() throws {
        let toml = """
        [[tool]]
        name = "one"
        method = "script"
        install = "echo installing one"

        [[tool]]
        name = "two"
        method = "script"
        install = "echo two breaks; exit 3"

        [[tool]]
        name = "three"
        method = "script"
        install = "echo ${HOME:+braces are fine}"
        requires = ["sh"]

        [[tool]]
        name = "four"
        method = "script"
        install = "echo never reached"
        requires = ["no-such-program-zz"]
        """
        let t = try Registry.parse(toml).tools
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", ToolProbe.batch(t.map { ($0, false) }, among: t)]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 1)
        XCTAssertTrue(text.contains("installing one\n✓ one"))
        XCTAssertTrue(text.contains("✗ two failed"))
        XCTAssertTrue(text.contains("braces are fine\n✓ three"))
        XCTAssertTrue(text.contains("✗ four failed"))
        XCTAssertFalse(text.contains("\nnever reached"))
    }

    func testTheTeamsToolsMergeBehindYours() throws {
        let theirs = """
        [[tool]]
        name = "ripgrep"
        method = "brew"

        [[tool]]
        name = "jq"
        method = "brew"
        """
        let reg = try Registry.parse(mine).merging(team: try Registry.parse(theirs, url: URL(fileURLWithPath: "/team/commands.toml")))
        XCTAssertEqual(reg.tools.map(\.name), ["ripgrep", "uv", "ruff", "iterm", "jq"])
        XCTAssertEqual(reg.tool(named: "ripgrep")?.bin, "rg")                 // yours wins the clash
        XCTAssertEqual(reg.tool(named: "ripgrep")?.overridesTeam, true)
        XCTAssertEqual(reg.tool(named: "jq")?.origin, .team)
        XCTAssertEqual(reg.teamTools.map(\.name), ["jq"])
        XCTAssertEqual(reg.team?.tools, 2)
    }

    func testAddAndRemoveKeepTheRestOfTheFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("commands.toml")
        try (mine + "\n").write(to: url, atomically: true, encoding: .utf8)
        let jq = try RegistryWriter.buildTool(name: "jq", method: "brew", desc: "json")
        XCTAssertEqual(try RegistryWriter.appendTool(jq, to: url).tools.map(\.name), ["ripgrep", "uv", "ruff", "iterm", "jq"])
        XCTAssertThrowsError(try RegistryWriter.appendTool(jq, to: url))
        let after = try RegistryWriter.removeTool("uv", from: url)
        XCTAssertEqual(after.tools.map(\.name), ["ripgrep", "ruff", "iterm", "jq"])
        XCTAssertEqual(after.commands.map(\.name), ["hello"])
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("[[tool]]\nname = \"jq\"\ndesc = \"json\"\nmethod = \"brew\"\n"))
        XCTAssertFalse(text.contains("astral.sh"))
    }
}
