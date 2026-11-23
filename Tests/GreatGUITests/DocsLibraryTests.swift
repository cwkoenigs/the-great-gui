import Foundation
import Registry
import XCTest
@testable import GreatGUI

@MainActor
final class DocsLibraryTests: XCTestCase {
    func testOpenAndRefreshKeepServingLastSuccessfulBuild() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("docs-test-\(UUID())", isDirectory: true)
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: root) }
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        let revision = root.appendingPathComponent("revision")
        let builder = root.appendingPathComponent("builder.sh")
        try """
        set -eu
        content="$(cat \(Registry.shellQuote(revision.path)))"
        mkdir -p "$1/standards/testing" "$1/assets"
        printf '%s' "$content" > "$1/index.html"
        [ "$content" != "broken" ] || { echo "fixture build failure" >&2; exit 3; }
        printf 'Testing and QA' > "$1/standards/testing/index.html"
        printf 'const loaded = true;' > "$1/assets/site.js"
        ln -s \(Registry.shellQuote(revision.path)) "$1/escape.txt"
        """.write(to: builder, atomically: true, encoding: .utf8)
        try "first".write(to: revision, atomically: true, encoding: .utf8)
        var opened: [URL] = []
        let docs = DocsLibrary(cache: cache, rebuild: {
            try DocsBuild.rebuild(in: $0, command: "exec /bin/sh " + Registry.shellQuote(builder.path))
        }, openURL: { opened.append($0); return true })

        docs.openCanon()
        try await waitFor { docs.url != nil }
        XCTAssertTrue(opened.isEmpty)
        let url = try XCTUnwrap(docs.url)
        XCTAssertEqual(url.host, "127.0.0.1")
        let first = try await read(url)
        XCTAssertEqual(first.body, "first")
        let standard = try await read(url.appendingPathComponent("standards/testing"))
        XCTAssertEqual(standard.body, "Testing and QA")
        let script = try await read(url.appendingPathComponent("assets/site.js"))
        XCTAssertEqual(script.type, "text/javascript")
        let escaped = try await read(url.appendingPathComponent("escape.txt"))
        XCTAssertEqual(escaped.code, 404)

        let second = DocsLibrary(cache: cache, rebuild: { _ in throw DocsBuild.Failure(message: "cache should be reused") },
                                 openURL: { _ in true })
        second.openCanon()
        try await waitFor { second.url != nil }
        XCTAssertNotEqual(second.url?.port, url.port)

        try "second".write(to: revision, atomically: true, encoding: .utf8)
        docs.refresh()
        try await waitFor { !docs.building }
        XCTAssertEqual(docs.note?.ok, true)
        XCTAssertEqual(docs.url, url)
        XCTAssertEqual(docs.revision, 2)
        let refreshed = try await read(url)
        XCTAssertEqual(refreshed.body, "second")

        try "broken".write(to: revision, atomically: true, encoding: .utf8)
        docs.refresh()
        try await waitFor { !docs.building }
        XCTAssertEqual(docs.note?.ok, false)
        XCTAssertTrue(docs.note?.fix.contains("fixture build failure") == true)
        let retained = try await read(url)
        XCTAssertEqual(retained.body, "second")
        XCTAssertEqual(docs.revision, 2)
        docs.openInBrowser()
        XCTAssertEqual(opened, [url])
    }

    private func read(_ url: URL) async throws -> (body: String, code: Int, type: String?) {
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        return (String(decoding: data, as: UTF8.self), http.statusCode, http.value(forHTTPHeaderField: "Content-Type"))
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw DocsBuild.Failure(message: "Timed out waiting for the docs library")
    }
}
