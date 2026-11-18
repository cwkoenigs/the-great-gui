import SwiftUI

private typealias G = Tokens.Glyph

/// One terminal row for anything the other primitives do not cover.
public struct Line: View {
    @Environment(\.termTheme) private var t
    private let spans: AttributedString?
    private let text: String
    private let role: Tokens.Role?
    public init(_ text: String = "", role: Tokens.Role? = nil) { self.text = text; self.role = role; spans = nil }
    public init(spans: AttributedString) { self.spans = spans; text = ""; role = nil }
    public var body: some View { Row(spans ?? .span(text, fg: role.map { t.color($0) })) }
}

/// What you typed: › in accent-strong, then the line.
public struct You: View {
    @Environment(\.termTheme) private var t
    private let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View { Row(.span(G.prompt, fg: t.voiceYou, bold: true) + .span(" " + text)) }
}

/// The agent's words: ● on the first line, │ on the rest. Lines are passed pre-wrapped; nothing wraps on the grid.
public struct Agent: View {
    @Environment(\.termTheme) private var t
    private let lines: [String]
    public init(lines: [String]) { self.lines = lines }
    public init(_ line: String) { lines = [line] }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                Row(.span(i == 0 ? G.agent : G.rail, fg: i == 0 ? t.voiceAgent : t.rule) + .span(" " + line))
            }
        }
    }
}

/// A tool call on the rail: → then the tool name bold, the argument muted.
public struct Run: View {
    @Environment(\.termTheme) private var t
    private let tool: String
    private let arg: String
    public init(tool: String, arg: String = "") { self.tool = tool; self.arg = arg }
    public var body: some View {
        var out = AttributedString.span(G.rail, fg: t.rule)
        out += .span(" ")
        out += .span(G.run, fg: t.voiceMachine)
        out += .span(" ")
        out += .span(tool, bold: true)
        if !arg.isEmpty { out += .span(" " + arg, fg: t.voiceMachine) }
        return Row(out)
    }
}

/// First line of a tool result at col 5, folded: ⎿ text  ┄ N more lines · ctrl-o. (`Result` is Swift's; hence the name.)
public struct ResultLine: View {
    @Environment(\.termTheme) private var t
    private let text: String
    private let more: Int
    private let error: Bool
    private let foldKey: String
    public init(_ text: String, more: Int = 0, error: Bool = false, foldKey: String = Tokens.Motion.foldKey) {
        self.text = text; self.more = more; self.error = error; self.foldKey = foldKey
    }
    public var body: some View {
        var out = AttributedString.span(G.rail, fg: t.rule)
        out += .spaces(3)
        out += .span("\(G.result) " + text, fg: error ? t.err : t.dim)
        if more > 0 { out += .span("  \(G.fold) \(more) more lines · \(foldKey)", fg: t.dim) }
        return Row(out)
    }
}

/// The one live line: ◐ step · 4s · ctrl-c interrupts. Reused in place, never stacked.
public struct Status: View {
    @Environment(\.termTheme) private var t
    private let step: String
    private let secs: Int
    private let frame: Int
    public init(step: String, secs: Int = 0, frame: Int = 0) { self.step = step; self.secs = secs; self.frame = frame }
    public var body: some View {
        let spinner = G.spinner[((frame % G.spinner.count) + G.spinner.count) % G.spinner.count]
        var out = AttributedString.span(spinner, fg: t.voiceAgent)
        out += .span(" " + step, fg: t.voiceMachine)
        out += .span(" · \(secs)s · ctrl-c interrupts", fg: t.dim)
        return Row(out)
    }
}

/// Closes a turn: ╰ then facts joined by · .
public struct Footer: View {
    @Environment(\.termTheme) private var t
    private let facts: [String]
    public init(facts: [String]) { self.facts = facts }
    public var body: some View { Row(.span(G.close, fg: t.rule) + .span(" " + facts.joined(separator: G.sep), fg: t.dim)) }
}

/// A flat outcome line with no rail: ✓ subject  detail.
public struct Outcome: View {
    @Environment(\.termTheme) private var t
    private let kind: OutcomeKind
    private let subject: String
    private let detail: String?
    public init(_ kind: OutcomeKind, _ subject: String, _ detail: String? = nil) { self.kind = kind; self.subject = subject; self.detail = detail }
    public var body: some View {
        var out = AttributedString.span(kind.glyph, fg: t.color(of: kind))
        out += .span(" ")
        out += .span(subject, bold: true)
        if let detail { out += .span("  " + detail, fg: t.muted) }
        return Row(out)
    }
}

/// label + value on the shared 12-column label grid.
public struct Labelled: View {
    @Environment(\.termTheme) private var t
    private let label: String
    private let value: AttributedString
    private let required: Bool
    private let focused: Bool
    private let indent: Int
    public init(_ label: String, _ value: AttributedString, required: Bool = false, focused: Bool = false, indent: Int = Tokens.Grid.indent) {
        self.label = label; self.value = value; self.required = required; self.focused = focused; self.indent = indent
    }
    public init(_ label: String, _ value: String, required: Bool = false, focused: Bool = false, indent: Int = Tokens.Grid.indent) {
        self.init(label, .span(value), required: required, focused: focused, indent: indent)
    }
    public var body: some View { Row(Draw.labelled(label, value, required: required, focused: focused, indent: indent, theme: t)) }
}

/// A dim hint at col 3: the fix after an error, the empty-input nudge.
public struct Hint: View {
    @Environment(\.termTheme) private var t
    private let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View { Row(.span("  " + text, fg: t.dim)) }
}

/// ✗ what failed, red only on that line, then the fix in dim.
public struct ErrorLine: View {
    @Environment(\.termTheme) private var t
    private let text: String
    private let fix: String?
    public init(_ text: String, fix: String? = nil) { self.text = text; self.fix = fix }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Row(.span(G.err, fg: t.err) + .span(" " + text))
            if let fix { Row(.span("  " + fix, fg: t.dim)) }
        }
    }
}

/// A square frame. A frame means "needs you": `.input` (dim edge) or `.approval` (warn edge).
/// `onRail` prefixes every row with │ so it sits inside a turn; `keys` renders in the bottom rule.
public struct Frame: View {
    public enum Kind { case input, approval }
    @Environment(\.termTheme) private var t
    @Environment(\.termCols) private var cols
    private let title: AttributedString?
    private let kind: Kind
    private let keys: AttributedString?
    private let onRail: Bool
    private let rows: [AttributedString]
    public init(title: AttributedString? = nil, kind: Kind = .input, keys: AttributedString? = nil, onRail: Bool = false, rows: [AttributedString]) {
        self.title = title; self.kind = kind; self.keys = keys; self.onRail = onRail; self.rows = rows
    }
    public var body: some View {
        let edge = kind == .approval ? t.edgeApproval : t.edgeInput
        let rail: AttributedString = onRail ? .span("\(G.rail) ", fg: t.rule) : .empty
        let width = cols - rail.cells
        VStack(alignment: .leading, spacing: 0) {
            Row(rail + Draw.rule(left: title == nil ? Tokens.Frame.topLeft : "\(Tokens.Frame.topLeft)\(Tokens.Frame.rule) ",
                                 content: title, right: Tokens.Frame.topRight, width: width, edge: edge))
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Row(rail + .span("\(Tokens.Frame.wall) ", fg: edge) + row.fitted(to: width - 4) + .span(" \(Tokens.Frame.wall)", fg: edge))
            }
            Row(rail + Draw.rule(left: keys == nil ? Tokens.Frame.bottomLeft : "\(Tokens.Frame.bottomLeft)\(Tokens.Frame.rule) ",
                                 content: keys, right: Tokens.Frame.bottomRight, width: width, edge: edge))
        }
    }
}

/// The framed prompt: a top rule carrying the session tag as the band, then │ › and the input with a block cursor.
public struct Prompt: View {
    @Environment(\.termTheme) private var t
    @Environment(\.termCols) private var cols
    private let tag: String
    private let value: String
    private let closed: Bool
    public init(tag: String, value: String = "", closed: Bool = true) { self.tag = tag; self.value = value; self.closed = closed }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Row(Draw.promptTop(tag: tag, width: cols, theme: t))
            Row(Draw.promptLine(value: value, closed: closed, width: cols, theme: t))
            if closed { Row(Draw.rule(left: Tokens.Frame.bottomLeft, right: Tokens.Frame.bottomRight, width: cols, edge: t.edgeInput)) }
        }
    }
}

/// The one quiet band under the prompt: facts left, context right.
public struct Toolbar: View {
    @Environment(\.termTheme) private var t
    @Environment(\.termCols) private var cols
    private let left: String
    private let right: String
    public init(left: String, right: String = "") { self.left = left; self.right = right }
    public var body: some View { Row(Draw.toolbar(left: left, right: right, width: cols, theme: t), background: t.surface) }
}

/// The slash-command menu: name · description · kind; the focused row is the only filled row.
/// (`Menu` is SwiftUI's; hence the name.)
public struct SlashMenu: View {
    public struct Item: Identifiable {
        public let name: String, desc: String, kind: String
        public var id: String { name }
        public init(_ name: String, _ desc: String, _ kind: String) { self.name = name; self.desc = desc; self.kind = kind }
    }
    @Environment(\.termTheme) private var t
    @Environment(\.termCols) private var cols
    private let items: [Item]
    private let active: Int
    private let total: Int?
    private let hint: String
    public init(items: [Item], active: Int = 0, total: Int? = nil, hint: String = "↑↓ move · tab complete · enter run") {
        self.items = items; self.active = active; self.total = total; self.hint = hint
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                Row(Draw.menuRow(name: it.name, desc: it.desc, kind: it.kind, active: i == active, width: cols, theme: t),
                    background: i == active ? t.hl : nil)
            }
            // The kit's footer glyph, kept for fidelity; tokens list ▼ as retired (README notes it).
            Row(.span("  ▼  \(active + 1)/\(total ?? items.count)\(G.sep)\(hint)", fg: t.dim))
        }
    }
}

/// The dog and the cat, arms around each other: 28×20 pixels, two pixel rows per text row.
public struct Mascot: View {
    @Environment(\.termTheme) private var t
    public init() {}
    public var body: some View {
        let cw = TermFont.cellWidth
        let ch = TermFont.line / 2
        let grid = Tokens.Mascot.grid
        Canvas { ctx, _ in
            // Same-coloured neighbours are drawn as one run, with a hair of overlap, so no seams show between pixels.
            for (r, row) in grid.enumerated() {
                var c = 0
                let cells = Array(row)
                while c < cells.count {
                    guard let color = ink(cells[c]) else { c += 1; continue }
                    var end = c + 1
                    while end < cells.count, cells[end] == cells[c] { end += 1 }
                    let rect = CGRect(x: CGFloat(c) * cw, y: CGFloat(r) * ch, width: CGFloat(end - c) * cw + 0.5, height: ch + 0.5)
                    ctx.fill(Path(rect), with: .color(color))
                    c = end
                }
            }
        }
        .frame(width: cw * CGFloat(Tokens.Mascot.width), height: ch * CGFloat(Tokens.Mascot.height))
    }
    private func ink(_ pixel: Character) -> Color? {
        switch Tokens.Mascot.legend[pixel] ?? "" {
        case "brand": t.brand
        case "strong": t.strong
        case "bg": t.bg
        default: nil
        }
    }
}

/// The two-pane banner shown once at startup: mascot and word-mark left, facts right, the path on a footer row.
/// The kit hardcodes the name ds-next; here it is a parameter.
public struct Banner: View {
    @Environment(\.termTheme) private var t
    @Environment(\.termCols) private var cols
    private let name: String
    private let version: String
    private let tagline: String
    private let facts: [(String, String)]
    private let hints: [String]
    private let path: String
    public init(name: String, version: String, tagline: String, facts: [(String, String)] = [], hints: [String] = [], path: String = "") {
        self.name = name; self.version = version; self.tagline = tagline; self.facts = facts; self.hints = hints; self.path = path
    }

    private static let bodyRows = 13
    private var left: Int { Tokens.Grid.bannerLeft }

    public var body: some View {
        let e = t.edgeInput
        let cw = TermFont.cellWidth
        VStack(alignment: .leading, spacing: 0) {
            Row(topRule)
            HStack(alignment: .top, spacing: 0) {
                wall(Tokens.Frame.wall).frame(width: cw)
                leftPane.frame(width: cw * CGFloat(left), alignment: .topLeading)
                wall("\(Tokens.Frame.wall) ").frame(width: cw * 2)
                rightPane.frame(maxWidth: .infinity, alignment: .topLeading)
                wall(Tokens.Frame.wall).frame(width: cw)
            }
            Row(joinRule)
            Row(.span(Tokens.Frame.wall, fg: e) + Draw.centered(path, width: cols - 2, fg: t.muted) + .span(Tokens.Frame.wall, fg: e))
            Row(Draw.rule(left: Tokens.Frame.bottomLeft, right: Tokens.Frame.bottomRight, width: cols, edge: e))
        }
    }

    private var topRule: AttributedString {
        let e = t.edgeInput
        var out = AttributedString.span("\(Tokens.Frame.topLeft)\(Tokens.Frame.rule) ", fg: e)
        out += .span(name, fg: t.brand, bold: true)
        out += .span(" \(version) ", fg: t.dim)
        out += .fill(Tokens.Frame.rule, left + 1 - out.cells, fg: e)
        out += .span(Tokens.Frame.joinDown, fg: e)
        out += .fill(Tokens.Frame.rule, cols - out.cells - 1, fg: e)
        out += .span(Tokens.Frame.topRight, fg: e)
        return out
    }

    private var joinRule: AttributedString {
        let e = t.edgeInput
        var out = AttributedString.span(Tokens.Frame.joinRight, fg: e)
        out += .fill(Tokens.Frame.rule, left, fg: e)
        out += .span(Tokens.Frame.joinUp, fg: e)
        out += .fill(Tokens.Frame.rule, cols - out.cells - 1, fg: e)
        out += .span(Tokens.Frame.joinLeft, fg: e)
        return out
    }

    private func wall(_ glyph: String) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<Self.bodyRows, id: \.self) { _ in Row(.span(glyph, fg: t.edgeInput)) }
        }
    }

    /// The kit puts three words of the tagline beside the name; a longer name gets as many as fit the pane.
    private var leftPane: some View {
        let words = tagline.split(separator: " ").map(String.init)
        let room = left - 2 - name.count - G.sep.count
        var first: [String] = []
        for w in words {
            let next = (first + [w]).joined(separator: " ")
            if next.count > room { break }
            first.append(w)
        }
        let rest = words.dropFirst(first.count).joined(separator: " ")
        return VStack(alignment: .leading, spacing: 0) {
            Mascot()
            Row()
            Row(.span("  ") + .span(name, bold: true) + .span(G.sep + first.joined(separator: " "), fg: t.muted))
            Row(.span("  " + rest, fg: t.muted))
        }
    }

    private var rightPane: some View {
        var rows: [AttributedString] = [.span(" ")]
        for (k, v) in facts {
            rows.append(AttributedString.span("  " + k, fg: t.dim).fitted(to: Tokens.Grid.labelWidth + 3) + .span(v))
        }
        rows.append(.span(" "))
        for h in hints { rows.append(.span("  " + h, fg: t.dim)) }
        while rows.count < Self.bodyRows { rows.append(.span(" ")) }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.prefix(Self.bodyRows).enumerated()), id: \.offset) { _, r in Row(r) }
        }
    }
}
