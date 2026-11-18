import Foundation

/// Which set of colours fills the thirteen roles. `dsNext` is the generated terminal set in Tokens.swift;
/// `paperInk` is the Paper and Ink theme (paper ground, ink text, teal links), kept here by hand.
public enum TermPalette: String, CaseIterable, Sendable {
    case paperInk, dsNext

    /// The UserDefaults key the choice is stored under (Settings › Look › Theme).
    public static let key = "palette"
    /// The theme a Mac starts in until one is chosen in Settings: ds-next (DECISIONS local-040).
    public static let fallback: TermPalette = .dsNext
    public static var current: TermPalette {
        TermPalette(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? fallback
    }

    public var title: String {
        switch self {
        case .paperInk: "Paper and ink"
        case .dsNext: "ds-next (grey and steel)"
        }
    }

    public func roles(_ scheme: TermScheme) -> [Tokens.Role: String] {
        switch self {
        case .paperInk: scheme == .dark ? PaperInkTokens.dark : PaperInkTokens.light
        case .dsNext: scheme == .dark ? Tokens.dark : Tokens.light
        }
    }
}

/// The Paper and Ink theme's colours on the terminal design's roles. Each value names the role it has in
/// the theme's own stylesheet; a change there is copied here by hand (DECISIONS local-026). The theme is a
/// light one: paper ground, white surfaces, ink text. Its dark set is the theme's "dark section" (ink
/// ground, berry-soft accents). It has no outcome colours, so ok / warn / err are ds-next's.
public enum PaperInkTokens {
    public static let light: [Tokens.Role: String] = [
        .bg: "#f3f7f7",       // paper (color-bg-primary)
        .surface: "#e7eff0",  // --color-bg-hover
        .text: "#021832",     // ink (color-text-primary)
        .muted: "#5d6c7d",    // muted (color-text-secondary)
        .dim: "#788697",      // --color-text-muted
        .rule: "#d9e3e5",     // line (color-border)
        .accent: "#007f7b",   // coral (color-link, color-text-emphasis)
        .strong: "#006d69",   // berry-dark
        .brand: "#021832",    // --color-cta-bg: the ink field, paper text on it
        .ok: "#2f7d4f",
        .warn: "#8a6a12",
        .err: "#b3402e",
        .hl: "#dff7f5",       // aqua
    ]

    public static let dark: [Tokens.Role: String] = [
        .bg: "#021832",       // ink (color-bg-dark)
        .surface: "#1b3054",  // blue-700
        .text: "#e3e9ea",     // neutral-100
        .muted: "#9ca9bd",    // neutral-300
        .dim: "#788697",      // neutral-400
        .rule: "#344157",     // neutral-700
        .accent: "#77d8d2",   // berry-soft (color-text-dark-accent)
        .strong: "#dff7f5",   // aqua
        .brand: "#00aba5",    // teal: the teal field, ink text on it
        .ok: "#7fd4a0",
        .warn: "#e3c56b",
        .err: "#ef8a7a",
        .hl: "#1b3054",       // blue-700
    ]

    /// A card's surface: --color-bg-surface, and the navy under the ink in dark.
    public static func card(_ scheme: TermScheme) -> String { scheme == .dark ? "#001126" : "#ffffff" }
    /// A tag's field: neutral-100.
    public static func tag(_ scheme: TermScheme) -> String { scheme == .dark ? "#1b3054" : "#e3e9ea" }
    public static let headingFamily = "Georgia"   // --font-headline, weight 500
    public static let headingTracking = -0.035    // em
    public static let labelSize = 10.0            // .label, .kicker: 700 10px mono, uppercase
    public static let labelTracking = 0.12        // em
}
