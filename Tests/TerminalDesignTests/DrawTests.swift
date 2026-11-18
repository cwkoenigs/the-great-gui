import SwiftUI
import XCTest
@testable import TerminalDesign

/// The grid arithmetic: every rule and row the builders make is exactly as wide as asked.
final class DrawTests: XCTestCase {
    let t = TermTheme.dark
    let w = Tokens.Grid.cols

    func plain(_ a: AttributedString) -> String { String(a.characters) }

    func testRulesFillToWidth() {
        for width in [Tokens.Grid.minCols, w, 120] {
            XCTAssertEqual(Draw.rule(left: "┌", right: "┐", width: width, edge: t.dim).cells, width)
            let titled = Draw.rule(left: "┌─ ", content: .span("New project"), right: "┐", width: width, edge: t.dim)
            XCTAssertEqual(titled.cells, width)
            XCTAssertTrue(plain(titled).hasPrefix("┌─ New project ─"))
            XCTAssertTrue(plain(titled).hasSuffix("┐"))
        }
    }

    func testPromptRowsFillToWidth() {
        XCTAssertEqual(Draw.promptTop(tag: "New session", width: w, theme: t).cells, w)
        XCTAssertEqual(Draw.promptLine(value: "/new", closed: true, width: w, theme: t).cells, w)
        XCTAssertTrue(plain(Draw.promptLine(value: "/new", closed: false, width: w, theme: t)).hasPrefix("│ › /new "))
    }

    func testToolbarAndMenuRowsFillToWidth() {
        XCTAssertEqual(Draw.toolbar(left: "12 commands", right: "⌘t theme", width: w, theme: t).cells, w)
        let tight = Draw.toolbar(left: String(repeating: "l", count: 50), right: String(repeating: "r", count: 40), width: 60, theme: t)
        XCTAssertEqual(tight.cells, 60)
        XCTAssertTrue(plain(tight).hasPrefix("  lllll"))
        XCTAssertEqual(Draw.menuRow(name: "canon", desc: "list standards", kind: "command", active: true, width: w, theme: t).cells, w)
        XCTAssertEqual(Draw.menuRow(name: "a-very-long-command-name-here", desc: String(repeating: "x", count: 200), kind: "skill",
                                    active: false, width: w, theme: t).cells, w)
    }

    func testLabelledUsesTheLabelGrid() {
        let row = plain(Draw.labelled("purpose", .span("value"), required: true, focused: true, indent: 0, theme: t))
        // 2 (focus glyph) + 12 label = 14, then "* ", then the value at col 17
        XCTAssertEqual(row, "❯ purpose     * value")
        let quiet = plain(Draw.labelled("name", .span("v"), theme: t))
        XCTAssertEqual(quiet, "    name          v")
    }

    func testFittedPadsAndCuts() {
        XCTAssertEqual(AttributedString.span("ab").fitted(to: 5).cells, 5)
        XCTAssertEqual(plain(AttributedString.span("abcdef").fitted(to: 3)), "abc")
        XCTAssertEqual(plain(Draw.centered("path", width: 10)), "   path   ")
    }
}
