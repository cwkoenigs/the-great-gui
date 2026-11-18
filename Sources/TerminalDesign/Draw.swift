import SwiftUI

/// Pure row builders: the grid arithmetic lives here, the views only place rows.
public enum Draw {
    /// A frame rule exactly `width` cells: `left`, the content and a space when there is one, the fill, `right`.
    public static func rule(left: String, content: AttributedString? = nil, right: String, width: Int, edge: Color) -> AttributedString {
        var out = AttributedString.span(left, fg: edge)
        var used = left.count + right.count
        if let content, content.cells > 0 {
            out += content
            out += .span(" ", fg: edge)
            used += content.cells + 1
        }
        out += .fill(Tokens.Frame.rule, width - used, fg: edge)
        out += .span(right, fg: edge)
        return out
    }

    public static func centered(_ text: String, width: Int, fg: Color? = nil) -> AttributedString {
        let pad = max(0, width - text.count)
        let left = pad / 2
        var out = AttributedString.spaces(left)
        out += .span(text, fg: fg)
        out += .spaces(pad - left)
        return out
    }

    /// label + value on the shared label grid: indent · 2 (focus glyph) · 12 label · 2 (required) · value.
    public static func labelled(_ label: String, _ value: AttributedString, required: Bool = false, focused: Bool = false,
                                indent: Int = Tokens.Grid.indent, theme t: TermTheme) -> AttributedString {
        let lead = focused ? "\(Tokens.Glyph.select) " : "  "
        var out = AttributedString.spaces(indent)
        out += AttributedString.span(lead + label, fg: focused ? t.voiceYou : t.dim, bold: focused).fitted(to: Tokens.Grid.labelWidth + 2)
        out += .span(required ? "* " : "  ", fg: t.dim)
        out += value
        return out
    }

    /// The one filled run on a screen: a key (accent) or the band (brand).
    public static func key(_ text: String, band: Bool = false, theme t: TermTheme) -> AttributedString {
        .span(" \(text) ", fg: band ? t.bandFg : t.keyFg, bg: band ? t.bandBg : t.keyBg, bold: true)
    }

    /// Facts left, context right. When the pane is too narrow for both, the right side gives way first.
    public static func toolbar(left: String, right: String, width: Int, theme t: TermTheme) -> AttributedString {
        let l = AttributedString.span("  " + left, fg: t.dim)
        var r = AttributedString.span(right + "  ", fg: t.dim)
        let room = width - l.cells
        if room < 2 { return l.fitted(to: width) }
        if r.cells > room - 1 { r = AttributedString.span(right, fg: t.dim).fitted(to: max(0, room - 3)) + .span("  ", fg: t.dim) }
        return l + .spaces(max(0, width - l.cells - r.cells)) + r
    }

    public static let menuNameWidth = 22
    public static let menuKindWidth = 10

    public static func menuRow(name: String, desc: String, kind: String, active: Bool, width: Int, theme t: TermTheme) -> AttributedString {
        var out = AttributedString.span("  /" + name, bold: active).fitted(to: menuNameWidth)
        out += AttributedString.span(desc, fg: active ? t.text : t.muted).fitted(to: max(0, width - menuNameWidth - menuKindWidth))
        out += .spaces(max(0, menuKindWidth - kind.count - 2))
        out += .span(kind + "  ", fg: active ? t.text : t.dim)
        return out
    }

    public static func promptTop(tag: String, width: Int, theme t: TermTheme) -> AttributedString {
        let band = key(tag, band: true, theme: t)
        var out = AttributedString.span(Tokens.Frame.topLeft, fg: t.edgeInput)
        out += .fill(Tokens.Frame.rule, width - 1 - band.cells - 2, fg: t.edgeInput)
        out += band
        out += .span(Tokens.Frame.rule + Tokens.Frame.topRight, fg: t.edgeInput)
        return out
    }

    public static func promptLine(value: String, closed: Bool, width: Int, theme t: TermTheme) -> AttributedString {
        var out = AttributedString.span("\(Tokens.Frame.wall) ", fg: t.edgeInput)
        out += .span(Tokens.Glyph.prompt, fg: t.voiceYou, bold: true)
        out += .span(" " + value)
        out += .span(" ", bg: t.cursorBg)
        if closed {
            out += .spaces(width - out.cells - 1)
            out += .span(Tokens.Frame.wall, fg: t.edgeInput)
        }
        return out
    }
}
