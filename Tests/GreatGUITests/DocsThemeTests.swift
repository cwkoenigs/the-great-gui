import Foundation
import TerminalDesign
import WebKit
import XCTest
@testable import GreatGUI

@MainActor
final class DocsThemeTests: XCTestCase {
    func testServedPagesUseSelectedPaletteAcrossNavigationAndColorModes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = root.appending(path: "standards/testing", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let html = """
        <!doctype html><html data-theme="light"><head><style>
        :root { --ifm-font-color-base: navy; --ifm-heading-font-family: Georgia; }
        body { background: var(--ifm-background-color); color: var(--ifm-font-color-base); }
        h1 { font-family: var(--ifm-heading-font-family); }
        a { color: var(--ifm-link-color); }
        </style></head><body><h1>Canon</h1><a href="/standards/testing/">Testing</a></body></html>
        """
        for directory in [root, nested] {
            try html.write(to: directory.appending(path: "index.html"), atomically: true, encoding: .utf8)
        }
        let server = try DocsServer(site: root, palette: { .dsNext })
        let base = try await server.start()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        let nestedURL = base.appending(path: "standards/testing/", directoryHint: .isDirectory)
        view.load(URLRequest(url: base))
        try await waitForPage(view, at: base)
        try await checkColors(in: view, for: .light)
        _ = try await view.evaluateJavaScript("document.documentElement.dataset.theme = 'dark'")
        try await checkColors(in: view, for: .dark)
        _ = try await view.evaluateJavaScript("document.querySelector('a').click()")
        try await waitForPage(view, at: nestedURL)
        try await checkColors(in: view, for: .light)
        let paper = try DocsServer(site: root, palette: { .paperInk })
        let paperURL = try await paper.start()
        let (data, _) = try await URLSession.shared.data(from: paperURL)
        XCTAssertEqual(data, Data(html.utf8))
        XCTAssertEqual(try Data(contentsOf: nested.appending(path: "index.html")), Data(html.utf8))
        withExtendedLifetime((server, paper)) {}
    }

    private func waitForPage(_ view: WKWebView, at url: URL) async throws {
        for _ in 0..<200 {
            if view.url == url, !view.isLoading,
               (try? await view.evaluateJavaScript("document.readyState") as? String) == "complete" { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw DocsBuild.Failure(message: "Timed out loading the test docs")
    }

    private func checkColors(in view: WKWebView, for scheme: TermScheme) async throws {
        let values = try await view.evaluateJavaScript("""
            [getComputedStyle(document.body).backgroundColor, getComputedStyle(document.body).color,
             getComputedStyle(document.querySelector('a')).color, getComputedStyle(document.querySelector('h1')).fontFamily]
            """) as? [String]
        let theme = TermTheme(scheme, palette: .dsNext)
        let colors = [Tokens.Role.bg, .text, .accent].map { role in
            let rgb = TermTheme.rgb8(theme.hex(role))
            return "rgb(\(rgb.r), \(rgb.g), \(rgb.b))"
        }
        XCTAssertEqual(values?.prefix(3).map { $0 }, colors)
        XCTAssertTrue(values?.last?.contains("system-ui") == true)
    }
}
