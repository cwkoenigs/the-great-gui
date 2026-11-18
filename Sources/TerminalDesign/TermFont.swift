import AppKit
import SwiftUI

/// One face in the terminal: JetBrains Mono 12.5/19 when the Mac has it installed, else the system
/// monospace (SF Mono), which draws every glyph the design uses. The font is installed per machine,
/// not bundled (DECISIONS local-003).
public enum TermFont {
    public static let size = CGFloat(Tokens.Typeface.monoSize)
    /// Every terminal row is exactly this tall.
    public static let line = CGFloat(Tokens.Typeface.lineHeight)
    public static let installed: Bool = NSFontManager.shared.availableFontFamilies.contains(Tokens.Typeface.monoFamily)
    public static var familyName: String { installed ? Tokens.Typeface.monoFamily : "SF Mono" }

    public static func nsFont(bold: Bool = false) -> NSFont {
        if installed, let f = NSFont(name: bold ? "JetBrainsMono-Bold" : "JetBrainsMono-Regular", size: size) {
            return f
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    public static func font(bold: Bool = false) -> Font { Font(nsFont(bold: bold) as CTFont) }

    /// The width of one cell, measured, so frames fill to the pane exactly.
    public static let cellWidth: CGFloat = ("M" as NSString).size(withAttributes: [.font: nsFont()]).width

    public static func width(cols: Int) -> CGFloat { CGFloat(cols) * cellWidth }
}
