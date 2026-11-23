import Foundation
import TerminalDesign

/// Map the docs renderer's semantic colors to the same grey-and-steel tokens as the window.
/// The renderer still owns page layout, typography sizes, code highlighting and its color-mode switch.
enum DocsTheme {
    private static let endOfHead = Data("</head>".utf8)
    private static let style = Data("""
    <style id="great-gui-docs-theme">
    \(colors(.light, selector: ":root"))
    \(colors(.dark, selector: ":root[data-theme='dark']"))
    :root, :root[data-theme] {
      --ifm-background-color: var(--gg-bg);
      --ifm-background-surface-color: var(--gg-surface);
      --ifm-font-color-base: var(--gg-text);
      --ifm-color-content-secondary: var(--gg-muted);
      --ifm-color-emphasis-200: var(--gg-rule);
      --ifm-color-primary: var(--gg-brand);
      --ifm-link-color: var(--gg-accent);
      --ifm-link-hover-color: var(--gg-strong);
      --ifm-navbar-background-color: var(--gg-surface);
      --ifm-navbar-link-color: var(--gg-text);
      --ifm-navbar-link-hover-color: var(--gg-accent);
      --ifm-navbar-search-input-background-color: var(--gg-bg);
      --ifm-navbar-search-input-color: var(--gg-text);
      --ifm-navbar-search-input-placeholder-color: var(--gg-muted);
      --ifm-menu-color: var(--gg-muted);
      --ifm-menu-color-active: var(--gg-strong);
      --ifm-menu-color-background-active: var(--gg-hl);
      --ifm-toc-border-color: var(--gg-rule);
      --ifm-code-background: var(--gg-surface);
      --docusaurus-highlighted-code-line-bg: var(--gg-hl);
      --ifm-footer-background-color: var(--gg-surface);
      --ifm-footer-color: var(--gg-muted);
      --ifm-footer-link-color: var(--gg-accent);
      --ifm-footer-link-hover-color: var(--gg-strong);
      --search-local-modal-background: var(--gg-surface);
      --search-local-input-active-border-color: var(--gg-accent);
      --search-local-hit-background: var(--gg-bg);
      --search-local-hit-color: var(--gg-text);
      --search-local-muted-color: var(--gg-muted);
      --search-local-highlight-color: var(--gg-accent);
      --search-local-hit-active-color: var(--gg-bg);
      --ifm-font-family-base: system-ui, sans-serif;
      --ifm-heading-font-family: var(--ifm-font-family-base);
    }
    </style>
    """.utf8)

    private static func colors(_ scheme: TermScheme, selector: String) -> String {
        let theme = TermTheme(scheme, palette: .dsNext)
        let roles: [Tokens.Role] = [.bg, .surface, .text, .muted, .rule, .brand, .accent, .strong, .hl]
        let properties = roles.map { "--gg-\($0.rawValue): \(theme.hex($0));" }.joined(separator: "\n")
        return "\(selector) {\n\(properties)\n}"
    }

    static func apply(to html: Data, palette: TermPalette) -> Data {
        guard palette == .dsNext, let insertion = html.range(of: endOfHead)?.lowerBound else { return html }
        var themed = html
        themed.insert(contentsOf: style, at: insertion)
        return themed
    }
}
