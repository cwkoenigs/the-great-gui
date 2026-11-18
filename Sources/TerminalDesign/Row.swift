import SwiftUI

/// One terminal row: exactly one line tall, never wrapping, filled to the pane.
public struct Row: View {
    private let spans: AttributedString
    private let background: Color?

    public init(_ spans: AttributedString = .span(" "), background: Color? = nil) {
        self.spans = spans.cells == 0 ? .span(" ") : spans
        self.background = background
    }

    public var body: some View {
        Text(spans)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: TermFont.line)
            .background(background ?? Color.clear)
    }
}
