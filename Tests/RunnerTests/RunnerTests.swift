import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
    /// Collects a run's events until it exits.
    func collect(run: String, cwd: String? = nil, env: [String: String] = [:], redact: [String] = [],
                 file: StaticString = #filePath, line: UInt = #line) throws -> (lines: [String], code: Int32) {
        let done = expectation(description: "exit")
        final class Box: @unchecked Sendable { var lines: [String] = []; var code: Int32 = -1 }
        let box = Box()
        let p = ProcessRun(run: run, cwd: cwd, env: env, redact: redact, shell: "/bin/sh") { event in
            switch event {
            case .started: break
            case .line(let l): box.lines.append(l)
            case .exited(let code, _): box.code = code; done.fulfill()
            }
        }
        try p.start()
        wait(for: [done], timeout: 10)
        return (box.lines, box.code)
    }

    func testLinesInOrderAndExitCode() throws {
        let r = try collect(run: "printf 'a\\nb\\n'; echo err 1>&2; printf 'no newline'; exit 3")
        XCTAssertEqual(r.lines, ["a", "b", "err", "no newline"])
        XCTAssertEqual(r.code, 3)
    }

    func testEnvironmentReachesTheCommandAndIsRedacted() throws {
        let r = try collect(run: "echo token=$TOKEN; echo plain", env: ["TOKEN": "hunter2"], redact: ["hunter2"])
        XCTAssertEqual(r.lines, ["token=\(Redactor.mask)", "plain"])
        XCTAssertEqual(r.code, 0)
    }

    func testColourIsOffAndEscapesAreStripped() throws {
        let r = try collect(run: "printf '\\033[31mred\\033[0m\\n'; echo $NO_COLOR")
        XCTAssertEqual(r.lines, ["red", "1"])
    }

    func testWorkingDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gg-cwd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try collect(run: "pwd", cwd: dir.path)
        XCTAssertEqual(r.lines.first.map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path },
                       dir.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    func testMissingDirectoryThrows() {
        let p = ProcessRun(run: "true", cwd: "/nonexistent/dir", shell: "/bin/sh") { _ in }
        XCTAssertThrowsError(try p.start())
    }

    func testRedactorHidesLongestFirst() {
        let r = Redactor(values: ["abc", "abcdef"])
        XCTAssertEqual(r.redact("x abcdef y abc"), "x \(Redactor.mask) y \(Redactor.mask)")
        XCTAssertEqual(Redactor(values: [""]).redact("keep"), "keep")
    }
}
