import XCTest
@testable import Secrets

/// Whole files through the real login keychain under a throwaway service, and a scratch folder on disk.
/// Every value here is made up; every item and file is removed again.
final class FileSecretsTests: XCTestCase {
    let files = FileSecrets(store: SecretStore(service: "com.cwkoenigs.the-great-gui.tests"))
    let item = "test-file-\(UUID().uuidString.prefix(8))"
    var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("gg-filesecrets-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? files.store.delete(item)
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func mode(_ path: String) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]) as? NSNumber)?.intValue ?? -1
    }

    func testStoreCompareRestore() throws {
        let path = dir.appendingPathComponent("connections.toml").path
        XCTAssertEqual(try files.state(name: item, path: path), .missing)
        XCTAssertThrowsError(try files.keep(name: item, from: path))

        let original = Data("[default]\naccount = \"made-up\"\npassword = \"not-a-real-one\"\n".utf8)
        FileManager.default.createFile(atPath: path, contents: original, attributes: [.posixPermissions: 0o644])
        XCTAssertEqual(try files.state(name: item, path: path), .notStored)

        let kept = try files.keep(name: item, from: path)
        XCTAssertEqual(kept.bytes, original.count)
        XCTAssertFalse(kept.replaced)
        XCTAssertEqual(try files.state(name: item, path: path), .wrongMode, "the same bytes, but the file is 644")
        XCTAssertEqual(try files.restore(name: item, to: path), .modeFixed)
        XCTAssertEqual(mode(path), 0o600)
        XCTAssertEqual(try files.state(name: item, path: path), .inSync)
        XCTAssertEqual(try files.restore(name: item, to: path), .unchanged)

        try FileManager.default.removeItem(atPath: path)
        XCTAssertEqual(try files.state(name: item, path: path), .notOnDisk)
        XCTAssertEqual(try files.restore(name: item, to: path), .written(bytes: original.count))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), original)
        XCTAssertEqual(mode(path), 0o600)

        try Data("edited by hand\n".utf8).write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(try files.state(name: item, path: path), .differs)
        XCTAssertThrowsError(try files.restore(name: item, to: path)) { e in
            XCTAssertTrue((e as? FileSecretError)?.what.contains("differs") ?? false)
        }
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "edited by hand\n", "a file that differs is left alone")
        XCTAssertEqual(try files.restore(name: item, to: path, force: true), .written(bytes: original.count))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), original)
        XCTAssertTrue(try files.keep(name: item, from: path).replaced)
    }

    func testBytesThatAreNotTextSurvive() throws {
        let path = dir.appendingPathComponent("key.bin").path
        var bytes = Data((0..<20_000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        bytes.append(contentsOf: [0x00, 0xFF, 0xFE, 0x0A])
        try bytes.write(to: URL(fileURLWithPath: path))
        try files.keep(name: item, from: path)
        try FileManager.default.removeItem(atPath: path)
        XCTAssertEqual(try files.restore(name: item, to: path, mode: 0o400), .written(bytes: bytes.count))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), bytes)
        XCTAssertEqual(mode(path), 0o400)
    }

    func testRestoreMakesPrivateFoldersAndLeavesNoTempFile() throws {
        let source = dir.appendingPathComponent("src.env").path
        try Data("A=1\n".utf8).write(to: URL(fileURLWithPath: source))
        try files.keep(name: item, from: source)
        let nested = dir.appendingPathComponent("new/deeper")
        let path = nested.appendingPathComponent(".env").path
        XCTAssertEqual(try files.restore(name: item, to: path), .written(bytes: 4))
        XCTAssertEqual(mode(nested.path), 0o700)
        XCTAssertEqual(mode(nested.deletingLastPathComponent().path), 0o700)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: nested.path), [".env"])
    }

    func testRefusals() throws {
        let path = dir.appendingPathComponent("x").path
        XCTAssertThrowsError(try files.restore(name: item, to: path)) { XCTAssertEqual($0 as? SecretStore.Failure, .notFound(item)) }
        XCTAssertThrowsError(try files.restore(name: item, to: path, mode: 0o644)) { e in
            XCTAssertTrue((e as? FileSecretError)?.what.contains("lets other users read") ?? false)
        }
        FileManager.default.createFile(atPath: path, contents: Data())
        XCTAssertThrowsError(try files.keep(name: item, from: path), "an empty file is refused")
        XCTAssertThrowsError(try files.keep(name: item, from: dir.path), "a folder is refused")
        let big = dir.appendingPathComponent("big").path
        FileManager.default.createFile(atPath: big, contents: Data(count: FileSecrets.maxBytes + 1))
        XCTAssertThrowsError(try files.keep(name: item, from: big))
        XCTAssertFalse(files.store.exists(item))
    }

    func testDotEnv() throws {
        let text = """
        # a comment
        PLAIN=value
        export EXPORTED=yes
        SPACED = padded value   # trailing comment
        SINGLE='kept $literal # as is'
        DOUBLE="line one\\nline \\"two\\""
        EMPTY=
        HASH=abc#def
        URL=postgres://u:p@host/db?x=1

        """
        let pairs = try DotEnv.parse(text)
        let env = Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, $0.value) })
        XCTAssertEqual(pairs.map(\.key), ["PLAIN", "EXPORTED", "SPACED", "SINGLE", "DOUBLE", "EMPTY", "HASH", "URL"])
        XCTAssertEqual(env["PLAIN"], "value")
        XCTAssertEqual(env["EXPORTED"], "yes")
        XCTAssertEqual(env["SPACED"], "padded value")
        XCTAssertEqual(env["SINGLE"], "kept $literal # as is")
        XCTAssertEqual(env["DOUBLE"], "line one\nline \"two\"")
        XCTAssertEqual(env["EMPTY"], "")
        XCTAssertEqual(env["HASH"], "abc#def")
        XCTAssertEqual(env["URL"], "postgres://u:p@host/db?x=1")
        XCTAssertEqual(try DotEnv.parse("A=1\r\nB=2\r\n").map(\.value), ["1", "2"])
    }

    /// A message about a bad line must never carry the line: it may hold a secret.
    func testDotEnvErrorsNameTheLineAndNeverQuoteIt() {
        for bad in ["OK=1\nhunter2-not-an-assignment\n", "OK=1\n9BAD=hunter2\n", "OK=1\nQ=\"hunter2\n", "OK=1\nQ='hunter2\n"] {
            XCTAssertThrowsError(try DotEnv.parse(bad)) { e in
                let text = "\(e)"
                XCTAssertTrue(text.contains("line 2"), text)
                XCTAssertFalse(text.contains("hunter2"), text)
            }
        }
    }
}
