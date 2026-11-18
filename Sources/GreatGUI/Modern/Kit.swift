import Registry
import SwiftUI
import TerminalDesign

// The window's own building blocks (DECISIONS local-036). Every shape, selection, field, tab, chip and
// table row is drawn here from `Palette`, so a screen never reaches for the system's blue selection, a
// glass effect or a grouped form: Paper and Ink is square, ink and teal throughout, ds-next rounded and steel.

extension Palette {
    /// The field behind a selected row.
    var selection: Color { paper ? theme.hl : theme.brand.opacity(scheme == .dark ? 0.32 : 0.16) }
    /// A hovered row, one step quieter.
    var hover: Color { paper ? theme.surface.opacity(0.7) : theme.surface.opacity(0.5) }
    /// Corner radius of a row, a field or a chip: none in Paper and Ink.
    var corner: CGFloat { paper ? 0 : 7 }
    /// The line under headers and between rows.
    var hairline: Color { rule }
    /// Text on the page.
    var ink: Color { theme.text }
    /// A field's surface.
    var fieldFill: Color { paper ? card : theme.surface.opacity(scheme == .dark ? 0.6 : 0.5) }
}

// MARK: rows and selection

/// A row that can be the selected one: the theme's field behind it, and in Paper and Ink a teal bar at its
/// leading edge. Used by the sidebar and the command list in place of the system's selection.
struct SelectedBackground: ViewModifier {
    let on: Bool
    let palette: Palette

    func body(content: Content) -> some View {
        content
            .background {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: palette.corner, style: .continuous).fill(on ? palette.selection : .clear)
                    if on, palette.paper { Rectangle().fill(palette.accent).frame(width: 3) }
                }
            }
            .contentShape(Rectangle())
    }
}

extension View {
    func selected(_ on: Bool, _ palette: Palette) -> some View { modifier(SelectedBackground(on: on, palette: palette)) }
}

// MARK: fields and forms

/// A labelled field in a sheet: the label above in the theme's small caps, the control, and a line that
/// says what goes in it. Left-aligned throughout, so an empty field never reads as a filled one.
struct LabeledField<Control: View>: View {
    let palette: Palette
    let label: String
    var hint: String = ""
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).sectionLabel(palette)
            control()
            if !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// A text field's box: the card surface with a hairline, square in Paper and Ink.
    func fieldBox(_ palette: Palette) -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(palette.fieldFill, in: RoundedRectangle(cornerRadius: palette.corner, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: palette.corner, style: .continuous).strokeBorder(palette.hairline, lineWidth: 1) }
    }

    /// A group of fields under a numbered heading.
    func formSection(_ title: String, _ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(palette.title(15)).tracking(palette.tracking(15)).foregroundStyle(palette.ink)
            self
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(palette)
    }

    /// A small action in a table row or beside a field: the theme's link colour, no chrome.
    func rowAction(_ palette: Palette, destructive: Bool = false) -> some View {
        buttonStyle(.plain)
            .font(.callout.weight(.medium))
            .foregroundStyle(destructive ? palette.err : palette.accent)
    }

    /// A status chip's field: a tag with a hairline in Paper and Ink, a tinted capsule in ds-next.
    @ViewBuilder func chip(_ palette: Palette) -> some View {
        if palette.paper {
            background(palette.card).overlay { Rectangle().strokeBorder(palette.hairline, lineWidth: 1) }
        } else {
            background(palette.theme.surface.opacity(0.7), in: Capsule())
        }
    }
}

/// A sheet's frame: the title in the heading face, the body in a scroll view on the page ground, and a
/// bar of actions that stays in view however tall the body is.
struct SheetFrame<Trailing: View, Body: View, Actions: View>: View {
    let palette: Palette
    let title: String
    var footnote: String = ""
    var width: CGFloat = 600
    var height: CGFloat = 520
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Body
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).heading(palette, 22)
                Spacer()
                trailing()
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
            Rectangle().fill(palette.hairline).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content() }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(palette.hairline).frame(height: 1)
            HStack(spacing: 10) {
                Text(footnote).font(.caption).foregroundStyle(palette.muted).lineLimit(2)
                Spacer()
                actions()
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .foregroundStyle(palette.ink)
        .background(palette.ground)
        .frame(width: width)
        .frame(minHeight: 260, idealHeight: height, maxHeight: height)
    }
}

/// What a write or a look said: a mark and one or two lines. The same block wherever a note is shown.
struct NoteLine: View {
    let note: AppModel.Note
    let palette: Palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: note.ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(note.ok ? palette.ok : palette.err)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.text).textSelection(.enabled)
                if !note.fix.isEmpty { Text(note.fix).foregroundStyle(palette.muted).textSelection(.enabled) }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: tabs

/// A row of tabs in the theme: small caps with a teal rule under the chosen one in Paper and Ink, filled
/// rounded tabs in ds-next. In place of the system's segmented control.
struct Tabs<Value: Hashable & Identifiable>: View {
    let palette: Palette
    let values: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: palette.paper ? 22 : 4) {
            ForEach(values) { value in
                let on = value == selection
                Button { selection = value } label: {
                    if palette.paper {
                        VStack(spacing: 5) {
                            Text(title(value))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .tracking(1.2).textCase(.uppercase)
                                .foregroundStyle(on ? palette.ink : palette.muted)
                            Rectangle().fill(on ? palette.accent : .clear).frame(height: 2)
                        }
                        .fixedSize()
                    } else {
                        Text(title(value)).font(.callout.weight(on ? .semibold : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(on ? palette.selection : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) { if palette.paper { Rectangle().fill(palette.hairline).frame(height: 1) } }
    }
}

// MARK: a screen and its table

/// A full-width screen beside the sidebar: a kicker, a title, a line that says where things stand, the
/// actions, a "?" that holds the how-to, and below it the screen's rows.
struct Screen<Actions: View, Help: View, Body: View>: View {
    let palette: Palette
    let kicker: String
    let title: String
    var summary: String = ""
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var help: () -> Help
    @ViewBuilder var content: () -> Body
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                palette.kicker(kicker)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title).heading(palette)
                    if !summary.isEmpty { Text(summary).font(.callout).foregroundStyle(palette.muted) }
                    Spacer()
                    actions()
                    Button { model.helpOpen.toggle() } label: { Image(systemName: "questionmark.circle") }
                        .buttonStyle(.plain).font(.title3).foregroundStyle(palette.muted)
                        .help("How this screen works")
                        .popover(isPresented: $model.helpOpen, arrowEdge: .bottom) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 14) { help() }
                                    .padding(18).frame(width: 460, alignment: .leading)
                            }
                            .frame(maxHeight: 520)
                            .foregroundStyle(palette.ink)
                            .background(palette.ground)
                        }
                }
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 14)
            Rectangle().fill(palette.hairline).frame(height: 1)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(palette.ink)
        .background(palette.ground)
    }
}

/// A table's header line: small caps over a hairline.
struct HeaderRow: View {
    let palette: Palette
    let columns: [(title: String, width: CGFloat?)]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, c in
                Text(c.title).sectionLabel(palette).foregroundStyle(palette.muted)
                    .frame(width: c.width, alignment: .leading)
                    .frame(maxWidth: c.width == nil ? .infinity : nil, alignment: .leading)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.hairline).frame(height: 1) }
    }
}

extension View {
    /// One row of a screen's table: the same gutters as the header, a hairline under it.
    func tableRow(_ palette: Palette) -> some View {
        padding(.horizontal, 24).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.hairline.opacity(0.6)).frame(height: 1) }
    }

    /// A cell of a fixed width, or the one that takes what is left.
    func cell(_ width: CGFloat?) -> some View {
        frame(width: width, alignment: .leading).frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// The dog and the cat from the design system, at any height, in the theme's colours. The design's view is
/// drawn at its own size and scaled, so its pixels stay whole.
struct Mascots: View {
    let palette: Palette
    let height: CGFloat

    var body: some View {
        let natural = CGSize(width: TermFont.cellWidth * CGFloat(Tokens.Mascot.width), height: TermFont.line / 2 * CGFloat(Tokens.Mascot.height))
        let scale = height / natural.height
        Mascot().environment(\.termTheme, palette.theme)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: natural.width * scale, height: height, alignment: .topLeading)
            .accessibilityLabel("A dog and a cat, arms around each other")
    }
}

/// An empty screen: the two pixel animals from the design system, a line, and what to do.
struct EmptyState<Actions: View>: View {
    let palette: Palette
    let title: String
    let text: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 14) {
            Mascots(palette: palette, height: 130)
            Text(title).font(palette.title(20)).tracking(palette.tracking(20))
            Text(text).font(.callout).foregroundStyle(palette.muted).multilineTextAlignment(.center).frame(maxWidth: 440)
            HStack(spacing: 10) { actions() }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
