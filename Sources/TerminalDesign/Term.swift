import SwiftUI

/// The terminal pane every other primitive renders inside: mono type, the scheme, padding 14/18,
/// and the column count the frames fill to. Measures its width unless `cols` is fixed (snapshots).
///
/// The measured width lives in a `@StateObject`, not `@State`: on the macOS 26 SDK `@State` is a macro
/// whose plugin ships only with Xcode, and this package builds with the command-line tools alone
/// (DECISIONS local-006).
public struct Term<Content: View>: View {
    private let theme: TermTheme
    private let fixedCols: Int?
    private let content: Content
    @StateObject private var measure = Measure()

    private final class Measure: ObservableObject {
        @Published var cols = Tokens.Grid.cols
    }

    public init(theme: TermTheme = .dark, cols: Int? = nil, @ViewBuilder content: () -> Content) {
        self.theme = theme
        self.fixedCols = cols
        self.content = content()
    }

    public static var padding: EdgeInsets { EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .environment(\.termTheme, theme)
            .environment(\.termCols, fixedCols ?? measure.cols)
            .font(TermFont.font())
            .foregroundStyle(theme.text)
            .padding(Self.padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(theme.bg)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
                guard fixedCols == nil else { return }
                let inner = width - Self.padding.leading - Self.padding.trailing
                let cols = max(Tokens.Grid.minCols, Int(inner / TermFont.cellWidth))
                if cols != measure.cols { measure.cols = cols }
            }
    }
}
