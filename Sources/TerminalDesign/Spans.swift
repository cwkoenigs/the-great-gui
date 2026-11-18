import SwiftUI

/// A row is one AttributedString: runs of text with a colour, an optional filled background and
/// optional bold, laid on the cell grid. Building rows as strings keeps alignment exact and keeps
/// the builders testable without rendering.
public extension AttributedString {
    static func span(_ text: String, fg: Color? = nil, bg: Color? = nil, bold: Bool = false) -> AttributedString {
        var a = AttributedString(text)
        if let fg { a.foregroundColor = fg }
        if let bg { a.backgroundColor = bg }
        if bold { a.font = TermFont.font(bold: true) }
        return a
    }

    static let empty = AttributedString()

    static func fill(_ glyph: String, _ count: Int, fg: Color? = nil) -> AttributedString {
        span(String(repeating: glyph, count: max(0, count)), fg: fg)
    }

    static func spaces(_ count: Int) -> AttributedString { fill(" ", count) }

    /// Cells used, counting grapheme clusters.
    var cells: Int { characters.count }

    /// Exactly `width` cells: padded with spaces, or cut (the design hides overflow, it never wraps).
    func fitted(to width: Int) -> AttributedString {
        let n = cells
        if n == width { return self }
        if n < width { return self + .spaces(width - n) }
        var cut = self
        let end = cut.characters.index(cut.startIndex, offsetBy: max(0, width))
        cut.removeSubrange(end..<cut.endIndex)
        return cut
    }
}
