import SwiftUI

/// A frame whose rows are views, not strings: a form with fields, an embedded terminal. `rows` says how
/// many line-high rows the content holds, so the walls are drawn without measuring. Same meaning as
/// `Frame`: a frame means "needs you".
public struct FrameBox<Content: View>: View {
    @Environment(\.termTheme) private var t
    @Environment(\.termCols) private var cols
    private let title: AttributedString?
    private let kind: Frame.Kind
    private let keys: AttributedString?
    private let rows: Int
    private let content: Content

    public init(title: AttributedString? = nil, kind: Frame.Kind = .input, keys: AttributedString? = nil, rows: Int,
                @ViewBuilder content: () -> Content) {
        self.title = title; self.kind = kind; self.keys = keys; self.rows = max(rows, 1); self.content = content()
    }

    public var body: some View {
        let edge = kind == .approval ? t.edgeApproval : t.edgeInput
        let cw = TermFont.cellWidth
        VStack(alignment: .leading, spacing: 0) {
            Row(Draw.rule(left: title == nil ? Tokens.Frame.topLeft : "\(Tokens.Frame.topLeft)\(Tokens.Frame.rule) ",
                          content: title, right: Tokens.Frame.topRight, width: cols, edge: edge))
            HStack(alignment: .top, spacing: 0) {
                walls("\(Tokens.Frame.wall) ", edge: edge).frame(width: cw * 2)
                content
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: CGFloat(rows) * TermFont.line, alignment: .top)
                    .clipped()
                walls(" \(Tokens.Frame.wall)", edge: edge).frame(width: cw * 2)
            }
            Row(Draw.rule(left: keys == nil ? Tokens.Frame.bottomLeft : "\(Tokens.Frame.bottomLeft)\(Tokens.Frame.rule) ",
                          content: keys, right: Tokens.Frame.bottomRight, width: cols, edge: edge))
        }
    }

    private func walls(_ glyph: String, edge: Color) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { _ in Row(.span(glyph, fg: edge)) }
        }
    }
}
