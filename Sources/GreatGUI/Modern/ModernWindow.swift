import Registry
import SwiftUI
import TerminalDesign

/// The window: a sidebar of groups and the library, and beside it either the commands with the selected
/// one's detail, or one full-width screen (Tools, Secrets, History). Everything it draws takes its shape
/// and colour from `Palette` through `Kit.swift` (DECISIONS local-036); the system keeps the window frame,
/// the sidebar's material and the search field.
struct ModernWindow: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Palette.appearanceKey) private var appearance = Palette.defaultAppearance
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var model = model
        let palette = Palette(scheme: scheme)
        NavigationSplitView {
            Sidebar()
        } detail: {
            MainColumn()
        }
        .searchable(text: $model.filter, placement: .toolbar, prompt: "Filter commands")
        .onSubmit(of: .search) { model.runSelected() }
        .sheet(isPresented: newCommandOpen) { NewCommandSheet() }
        .sheet(isPresented: $model.secretSheetOpen) { SecretSheet() }
        .sheet(isPresented: $model.fileSheetOpen) { FileSheet() }
        .sheet(isPresented: updateOpen) { UpdateSheet() }
        .sheet(isPresented: toolRunOpen) { ToolRunSheet() }
        .sheet(isPresented: $model.toolSheetOpen) { ToolSheet() }
        .sheet(isPresented: $model.aboutOpen) { AboutSheet() }
        .confirmationDialog("Delete \(model.pendingDelete ?? "")?", isPresented: deletePending, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { model.confirmDelete() }
            Button("Cancel", role: .cancel) { model.cancelDelete() }
        } message: {
            Text("Its block is removed from \(model.registryURL.lastPathComponent)" + (model.registryIsRepository ? " and the change is committed." : "."))
        }
        .alert("Registry", isPresented: errorShown, presenting: model.registryNote) { _ in
            Button("OK") { model.clearRegistryNote() }
        } message: { note in
            Text(note.fix.isEmpty ? note.text : note.text + "\n" + note.fix)
        }
        .tint(palette.tint)
        .preferredColorScheme(Palette.colorScheme(appearance))
        .onChange(of: model.filter) { model.clampSelection() }
    }

    private var newCommandOpen: Binding<Bool> {
        Binding(get: { model.newCommandOpen }, set: { if $0 { model.openNewCommand() } else { model.closeNewCommand() } })
    }

    private var updateOpen: Binding<Bool> {
        Binding(get: { model.updateOpen }, set: { if !$0 { model.closeUpdate() } })
    }

    private var toolRunOpen: Binding<Bool> {
        Binding(get: { model.toolRunOpen && model.run?.name == AppModel.toolsRunName }, set: { if !$0 { model.closeToolRun() } })
    }

    private var deletePending: Binding<Bool> {
        Binding(get: { model.pendingDelete != nil }, set: { if !$0 { model.cancelDelete() } })
    }

    /// A failed write outside the sheet (a delete, a reorder) is an alert; the sheet shows its own errors.
    private var errorShown: Binding<Bool> {
        Binding(get: { !model.newCommandOpen && model.registryNote?.ok == false }, set: { if !$0 { model.clearRegistryNote() } })
    }
}

extension Palette {
    /// Where Settings keeps the appearance, and what a Mac starts with until one is chosen: dark
    /// (DECISIONS local-040).
    static let appearanceKey = "appearance"
    static let defaultAppearance = "dark"

    /// The scheme Settings asks for. Paper and Ink is a light theme, so "system" means light there.
    static func colorScheme(_ appearance: String) -> ColorScheme? {
        appearance == "dark" ? .dark : appearance == "light" || TermPalette.current == .paperInk ? .light : nil
    }
}

// MARK: the sidebar

private struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                heading("Commands", palette)
                row(.all, "All", "square.grid.2x2", model.registry?.commands.count ?? 0, palette)
                ForEach(model.groups, id: \.self) { group in
                    row(.group(group), group, "folder", model.count(in: group), palette)
                }
                heading("Library", palette).padding(.top, 14)
                row(.scheduled, "Scheduled", "calendar.badge.clock", model.scheduled.count, palette)
                if model.teamStatus.joined { row(.team, "Team", "person.2", model.teamCommandCount, palette) }
                row(.tools, "Tools", "shippingbox", model.toolsAttention, palette, attention: model.toolsAttention > 0)
                row(.docs, "Docs", "book", 0, palette)
                row(.secrets, "Secrets", "key", 0, palette)
                row(.history, "History", "clock", model.history.count, palette)
            }
            .padding(.horizontal, 10).padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { foot(palette) }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        .onChange(of: model.destination) { _, d in
            model.helpOpen = false
            if d == .secrets { model.refreshSecrets() }
            if d == .tools { model.refreshTools() }
            if d != .secrets, d != .tools, d != .docs, d != .history { model.clampSelection() }
        }
    }

    private func heading(_ text: String, _ palette: Palette) -> some View {
        Text(text).sectionLabel(palette).foregroundStyle(palette.muted)
            .padding(.horizontal, 10).padding(.bottom, 4)
    }

    private func row(_ destination: AppModel.Destination, _ title: String, _ symbol: String, _ count: Int, _ palette: Palette, attention: Bool = false) -> some View {
        let on = model.destination == destination
        return Button { model.destination = destination } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol).frame(width: 18).foregroundStyle(on ? palette.accent : palette.muted)
                Text(title).fontWeight(on ? .semibold : .regular).lineLimit(1)
                Spacer(minLength: 4)
                if count > 0 {
                    Text("\(count)").font(.caption.monospacedDigit().weight(attention ? .bold : .regular))
                        .foregroundStyle(attention ? palette.warn : palette.muted)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .selected(on, palette)
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.ink)
    }

    @ViewBuilder private func foot(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let change = model.teamChange {
                // The daily look brought something from the team: say what, until it is clicked away.
                notice("From the team", change.words, "person.2.fill", palette) { model.destination = .team; model.dismissTeamChange() }
                    .help((change.details.isEmpty ? "" : change.details.joined(separator: "\n") + "\n\n") + "Shows the team's commands and dismisses this note.")
            }
            if let info = model.updateAvailable {
                // A newer version is on the remote. Pressing this is the same as the-great-gui › Update….
                notice("Update available", info.words + " · click to install", "arrow.down.circle.fill", palette) { model.update() }
                    .help("What is new:\n" + info.subjects.map { "• " + $0 }.joined(separator: "\n") + "\n\nPulls, rebuilds and reopens the app.")
            }
            // The dog and the cat live here, in every theme: press them for About.
            Button { model.aboutOpen = true } label: {
                HStack(alignment: .bottom, spacing: 10) {
                    Mascots(palette: palette, height: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("the-great-gui").font(palette.title(13)).tracking(palette.tracking(13))
                        Text(Version.string).font(.caption2.monospacedDigit()).foregroundStyle(palette.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.top, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.ink)
            .help("About the-great-gui")
            Button { model.openNewCommand() } label: {
                Label("New Command", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .secondaryButton(palette)
            .padding(.horizontal, 12).padding(.vertical, 12)
            .help("New command (⌘N)")
        }
    }

    private func notice(_ title: String, _ text: String, _ symbol: String, _ palette: Palette, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol).foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).fontWeight(.semibold)
                    Text(text).font(.caption).foregroundStyle(palette.muted).lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.top, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.ink)
    }
}

// MARK: beside the sidebar

/// The commands with their detail, or one of the full-width screens.
private struct MainColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        Group {
            switch model.destination {
            case .secrets: SecretsScreen()
            case .tools: ToolsScreen()
            case .docs: DocsScreen()
            case .history: HistoryScreen()
            default:
                HStack(spacing: 0) {
                    CommandList().frame(width: 320)
                    Rectangle().fill(palette.hairline).frame(width: 1)
                    if let c = model.selectedCommand {
                        CommandDetail(command: c)
                    } else {
                        EmptyState(palette: palette, title: model.registry?.commands.isEmpty == false ? "No command selected" : "No commands yet",
                                   text: model.registry?.commands.isEmpty == false ? "Pick one in the list." : "A command is a line you would type in a terminal, kept here with a name. Add your first one.") {
                            Button("New Command") { model.openNewCommand() }.primaryButton(palette)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(palette.ink)
        .background(palette.ground)
        .navigationTitle(title)
    }

    private var title: String {
        switch model.destination {
        case .group(let g): g
        case .scheduled: "Scheduled"
        case .team: "Team"
        case .tools: "Tools"
        case .docs: "Docs"
        case .secrets: "Secrets"
        case .history: "History"
        case .all: "Commands"
        }
    }
}

private struct CommandList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let commands = model.commands(in: model.destination)
        let palette = Palette(scheme: scheme)
        Group {
            if commands.isEmpty, !model.filter.isEmpty {
                note("Nothing matches “\(model.filter)”", "Clear the filter to see every command.", palette)
            } else if commands.isEmpty, model.destination == .scheduled {
                note("Nothing scheduled", "Give a command a schedule in its form (⌘E): weekdays 08:30, every 15m, daily 09:00…", palette)
            } else if commands.isEmpty, model.destination == .team {
                note("Nothing from the team", "Every team command is overridden by one of yours, or the team's registry is empty.", palette)
            } else if commands.isEmpty {
                note("No commands", "⌘N adds one, or edit commands.toml (⌥⌘E).", palette)
            } else {
                List {
                    ForEach(commands, id: \.name) { c in
                        CommandRow(command: c, palette: palette, paused: model.isPaused(c.name), last: model.lastRun(of: c.name)?.code)
                            .selected(model.selected == c.name, palette)
                            .onTapGesture(count: 2) { model.select(c.name); model.runSelected() }
                            .onTapGesture { model.select(c.name) }
                            .contextMenu {
                                Button("Run") { model.select(c.name); model.runSelected() }
                                Button(c.origin == .team ? "Make My Own Copy…" : "Edit…") { model.openEditCommand(c) }
                                Divider()
                                Button("Delete…", role: .destructive) { model.askDelete(c.name) }.disabled(c.origin == .team)
                            }
                            .moveDisabled(!model.filter.isEmpty || c.origin == .team)
                            .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove { source, target in model.moveCommands(from: source, to: target) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onKeyPress(.downArrow) { model.moveSelection(1); return .handled }
                .onKeyPress(.upArrow) { model.moveSelection(-1); return .handled }
                .onKeyPress(.return) { model.runSelected(); return .handled }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(palette.ground)
    }

    private func note(_ title: String, _ text: String, _ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(palette.title(16)).tracking(palette.tracking(16))
            Text(text).font(.callout).foregroundStyle(palette.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CommandRow: View {
    let command: Command
    let palette: Palette
    var paused = false
    /// The exit code of its last run, when it has run.
    var last: Int32?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(command.name).font(.body.weight(.medium))
                if !command.desc.isEmpty {
                    Text(command.desc).font(.callout).foregroundStyle(palette.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if command.origin == .team || command.overridesTeam {
                Image(systemName: command.origin == .team ? "person.2" : "person.crop.circle.badge.checkmark")
                    .foregroundStyle(palette.muted)
                    .help(command.origin == .team ? "From the team · read-only here" : "Yours · it wins over the team's command of the same name")
            }
            if let s = command.schedule {
                Image(systemName: paused ? "pause.circle" : "clock")
                    .foregroundStyle(paused ? palette.warn : palette.accent)
                    .help(s.english + (paused ? " · paused" : ""))
            }
            if let mark = palette.mark(for: command) {
                Image(systemName: mark.symbol).foregroundStyle(mark.color).help(mark.text)
            }
            if let last {
                Image(systemName: last == 0 ? "checkmark" : "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(last == 0 ? palette.ok : palette.err)
                    .help(last == 0 ? "Its last run ended well" : "Its last run ended with exit \(last)")
            }
        }
        .font(.caption)
        .padding(.horizontal, 10).padding(.vertical, 7)
    }
}

/// the-great-gui › About: the two animals, the version and the commit this copy was built from.
struct AboutSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        VStack(spacing: 12) {
            Mascots(palette: palette, height: 150)
            Text("the-great-gui").heading(palette, 26)
            Text(Version.full).font(Palette.mono).foregroundStyle(palette.muted).textSelection(.enabled)
            Text("Your commands, your secrets and the tools this Mac should have.")
                .font(.callout).foregroundStyle(palette.muted).multilineTextAlignment(.center)
            Button("Close") { model.aboutOpen = false }.secondaryButton(palette).keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .frame(width: 380)
        .foregroundStyle(palette.ink)
        .background(palette.ground)
    }
}
