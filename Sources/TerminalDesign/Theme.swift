import AppKit
import SwiftUI

/// Dark is the default; light flips the ramp.
public enum TermScheme: String, CaseIterable, Codable, Sendable {
    case dark, light
    public var toggled: TermScheme { self == .dark ? .light : .dark }
}

/// The colour roles for one scheme, and the semantic aliases the primitives draw with.
/// Colour names a voice or an outcome, never decoration.
public struct TermTheme: Equatable, Sendable {
    public let scheme: TermScheme
    /// The token set the roles read from; the one chosen in Settings unless a caller names another.
    public let palette: TermPalette
    public init(_ scheme: TermScheme, palette: TermPalette = .current) {
        self.scheme = scheme
        self.palette = palette
    }
    public static var dark: TermTheme { TermTheme(.dark) }
    public static var light: TermTheme { TermTheme(.light) }

    public func color(_ role: Tokens.Role) -> Color { Color(hex: hex(role)) }
    public func color(of kind: OutcomeKind) -> Color { color(kind.role) }

    public var bg: Color { color(.bg) }
    public var surface: Color { color(.surface) }
    public var text: Color { color(.text) }
    public var muted: Color { color(.muted) }
    public var dim: Color { color(.dim) }
    public var rule: Color { color(.rule) }
    public var accent: Color { color(.accent) }
    public var strong: Color { color(.strong) }
    public var brand: Color { color(.brand) }
    public var ok: Color { color(.ok) }
    public var warn: Color { color(.warn) }
    public var err: Color { color(.err) }
    public var hl: Color { color(.hl) }

    public var voiceYou: Color { color(Tokens.Semantic.voiceYou) }
    public var voiceAgent: Color { color(Tokens.Semantic.voiceAgent) }
    public var voiceMachine: Color { color(Tokens.Semantic.voiceMachine) }
    public var edgeInput: Color { color(Tokens.Semantic.edgeInput) }
    public var edgeApproval: Color { color(Tokens.Semantic.edgeApproval) }
    public var bandBg: Color { color(Tokens.Semantic.bandBg) }
    public var bandFg: Color { color(Tokens.Semantic.bandFg) }
    public var keyBg: Color { color(Tokens.Semantic.keyBg) }
    public var keyFg: Color { color(Tokens.Semantic.keyFg) }
    public var cursorBg: Color { color(Tokens.Semantic.cursorBg) }
    public var cursorFg: Color { color(Tokens.Semantic.cursorFg) }
}

/// ✓ ⚠ ✗: the only glyphs that carry ok/warn/err.
public enum OutcomeKind: String, CaseIterable, Sendable {
    case ok, warn, err
    public var glyph: String {
        switch self {
        case .ok: Tokens.Glyph.ok
        case .warn: Tokens.Glyph.warn
        case .err: Tokens.Glyph.err
        }
    }
    public var role: Tokens.Role {
        switch self {
        case .ok: .ok
        case .warn: .warn
        case .err: .err
        }
    }
}

public extension Color {
    /// "#rrggbb" → Color. Anything else is magenta, so a bad token shows instead of hiding.
    init(hex: String) {
        var digits = Substring(hex)
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        guard digits.count == 6, let v = UInt32(digits, radix: 16) else {
            self = Color(red: 1, green: 0, blue: 1)
            return
        }
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

private struct TermThemeKey: EnvironmentKey { static var defaultValue: TermTheme { .dark } }
private struct TermColsKey: EnvironmentKey { static let defaultValue: Int = Tokens.Grid.cols }

public extension EnvironmentValues {
    /// The scheme every primitive inside a `Term` draws with.
    var termTheme: TermTheme {
        get { self[TermThemeKey.self] }
        set { self[TermThemeKey.self] = newValue }
    }
    /// How many cells wide the pane is; frames and rules fill to it.
    var termCols: Int {
        get { self[TermColsKey.self] }
        set { self[TermColsKey.self] = newValue }
    }
}

public extension TermTheme {
    /// The role's "#rrggbb", for code that wants components rather than a SwiftUI Color (the terminal pane).
    func hex(_ role: Tokens.Role) -> String { palette.roles(scheme)[role] ?? "#ff00ff" }

    /// "#rrggbb" → 8-bit components.
    static func rgb8(_ hex: String) -> (r: UInt16, g: UInt16, b: UInt16) {
        var digits = Substring(hex)
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        guard digits.count == 6, let v = UInt32(digits, radix: 16) else { return (255, 0, 255) }
        return (UInt16((v >> 16) & 0xff), UInt16((v >> 8) & 0xff), UInt16(v & 0xff))
    }
}
