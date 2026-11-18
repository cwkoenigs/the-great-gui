import Registry
import SwiftUI
import TerminalDesign

/// The terminal design's roles on native materials: the steel as the tint, ok / warn / err for marks, the
/// neutral ramp for the surfaces the app draws itself (code, output). The chrome is the system's.
struct Palette {
    let scheme: ColorScheme
    var theme: TermTheme { TermTheme(scheme == .dark ? .dark : .light) }

    /// Paper and Ink's shapes and type: paper ground, white square cards with a hairline, Georgia titles,
    /// mono uppercase labels. Off for ds-next.
    var paper: Bool { theme.palette == .paperInk }
    private var termScheme: TermScheme { scheme == .dark ? .dark : .light }

    /// Buttons, selection and links: the theme's link colour in Paper and Ink.
    var tint: Color { paper ? theme.accent : theme.brand }
    var ground: Color { theme.bg }
    var card: Color { Color(hex: PaperInkTokens.card(termScheme)) }
    var tag: Color { Color(hex: PaperInkTokens.tag(termScheme)) }
    /// The shape of a code block or an output pane.
    var block: RoundedRectangle { RoundedRectangle(cornerRadius: paper ? 0 : 10, style: .continuous) }

    /// A screen or sheet title: Georgia in Paper and Ink, the system face otherwise.
    func title(_ size: CGFloat) -> Font {
        paper ? .custom(PaperInkTokens.headingFamily, size: size).weight(.medium) : .system(size: size, weight: .semibold)
    }
    func tracking(_ size: CGFloat) -> CGFloat { paper ? size * PaperInkTokens.headingTracking : 0 }

    var ok: Color { theme.ok }
    var warn: Color { theme.warn }
    var err: Color { theme.err }
    var accent: Color { theme.accent }
    var codeBackground: Color { theme.bg }
    var codeSurface: Color { theme.surface }
    var codeText: Color { theme.text }
    var muted: Color { theme.muted }
    var dim: Color { theme.dim }
    var rule: Color { theme.rule }

    /// The small mono line above a title ("COMMAND", "THIS MAC"): Paper and Ink's kicker. Nothing in ds-next.
    @ViewBuilder func kicker(_ text: String) -> some View {
        if paper { Text(text).sectionLabel(self) }
    }

    static var mono: Font { TermFont.font() }
    static var monoBold: Font { TermFont.font(bold: true) }

    /// The one mark a command row carries, in the design's priority: gate, key, tty, parameters.
    func mark(for c: Command) -> (symbol: String, text: String, color: Color)? {
        if c.gate { return ("lock.fill", "Touch ID", warn) }
        if !c.secretNames.isEmpty { return ("key.fill", "secret", accent) }
        if c.interactive { return ("terminal.fill", "terminal", muted) }
        if !c.params.isEmpty { return ("slider.horizontal.3", "\(c.params.count) parameter\(c.params.count == 1 ? "" : "s")", muted) }
        return nil
    }
}

/// The theme's button. Paper and Ink's call to action is a square ink field with paper text (--color-cta-bg),
/// teal with ink text in the dark section; ds-next's is the same shape with rounded corners, in steel.
/// `quiet` is the second button: a surface with a hairline.
struct InkButtonStyle: ButtonStyle {
    let palette: Palette
    var quiet = false
    @Environment(\.isEnabled) private var enabled

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: palette.paper ? 0 : 7, style: .continuous) }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundStyle(quiet ? palette.codeText : palette.ground)
            .background(quiet ? (palette.paper ? palette.card : palette.theme.surface) : palette.theme.brand, in: shape)
            .overlay { if quiet { shape.strokeBorder(palette.paper ? palette.codeText : palette.rule, lineWidth: 1) } }
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

extension View {
    /// The one button a panel or sheet is for, in the theme.
    func primaryButton(_ palette: Palette) -> some View { buttonStyle(InkButtonStyle(palette: palette)) }

    /// A second button beside it: the outlined one.
    func secondaryButton(_ palette: Palette) -> some View { buttonStyle(InkButtonStyle(palette: palette, quiet: true)) }

    /// A screen or sheet title in the theme's heading face.
    func heading(_ palette: Palette, _ size: CGFloat = 28) -> some View {
        font(palette.title(size)).tracking(palette.tracking(size))
    }

    /// A small heading over a block ("Runs", "Parameters"): Paper and Ink's mono uppercase label, or the
    /// system's small caps line.
    @ViewBuilder func sectionLabel(_ palette: Palette) -> some View {
        if palette.paper {
            font(.system(size: PaperInkTokens.labelSize, weight: .bold, design: .monospaced))
                .tracking(PaperInkTokens.labelSize * PaperInkTokens.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(palette.accent)
        } else {
            font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
        }
    }

    /// A panel that stands off the page: in Paper and Ink a white square card with a hairline; in ds-next a
    /// rounded surface with one.
    @ViewBuilder func panel(_ palette: Palette) -> some View {
        if palette.paper {
            background(palette.card).overlay { Rectangle().strokeBorder(palette.rule, lineWidth: 1) }
        } else {
            background(palette.theme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.rule, lineWidth: 1) }
        }
    }

    /// A code block or output pane's field: square with a hairline in Paper and Ink.
    @ViewBuilder func codeBlock(_ palette: Palette) -> some View {
        if palette.paper {
            background(palette.card).overlay { Rectangle().strokeBorder(palette.rule, lineWidth: 1) }
        } else {
            background(palette.codeSurface, in: palette.block)
        }
    }

    /// A small tag: Paper and Ink's mono uppercase tag on a grey field, or a tinted capsule.
    @ViewBuilder func pill(_ fill: Color, _ palette: Palette) -> some View {
        if palette.paper {
            font(.system(size: PaperInkTokens.labelSize, weight: .bold, design: .monospaced))
                .tracking(PaperInkTokens.labelSize * PaperInkTokens.labelTracking)
                .textCase(.uppercase)
                .background(palette.tag, in: RoundedRectangle(cornerRadius: 2))
        } else {
            background(fill, in: Capsule())
        }
    }

    /// The page ground behind a column, in Paper and Ink only; ds-next leaves the system's.
    @ViewBuilder func ground(_ palette: Palette) -> some View {
        if palette.paper { scrollContentBackground(.hidden).background(palette.ground) } else { self }
    }
}
