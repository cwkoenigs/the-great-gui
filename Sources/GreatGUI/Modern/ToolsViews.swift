import Registry
import SwiftUI
import TerminalDesign

/// The tools the registry lists, yours and the team's: what this Mac has of each, the line an install or an
/// update would run, and a button that runs it. Nothing here runs by itself; the list is a look at the
/// package managers and PATH. The rows take the screen's width; how it works is behind the "?".
struct ToolsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        Screen(palette: palette, kicker: "This Mac", title: "Tools", summary: model.tools.isEmpty ? "" : model.toolsSummary) {
            Button { model.installTools() } label: { Label("Install Missing", systemImage: "arrow.down.circle") }
                .primaryButton(palette)
                .disabled(model.toolsMissing.isEmpty || model.toolsRunning)
                .help("Install the \(model.toolsMissing.count) that are missing")
            Button { model.updateTools() } label: { Label("Update All", systemImage: "arrow.up.circle") }
                .secondaryButton(palette)
                .disabled(model.toolsOutdated.isEmpty || model.toolsRunning)
                .help("Update the \(model.toolsOutdated.count) that are behind")
            Button { model.refreshTools(outdated: true) } label: { Label("Check", systemImage: "arrow.clockwise") }
                .secondaryButton(palette)
                .disabled(model.toolsBusy || model.tools.isEmpty)
                .help("Ask the package managers what is behind. It only looks.")
            Button { model.openToolForm() } label: { Label("Add Tool", systemImage: "plus") }
                .secondaryButton(palette)
                .help("List a program this Mac should have")
        } help: {
            ToolsHelp(palette: palette)
        } content: {
            if model.tools.isEmpty {
                EmptyState(palette: palette, title: "No tools listed",
                           text: "A tool is a program this Mac should have: a Homebrew formula or app, a Python or npm package, or anything with its own installer. Listing one installs nothing.") {
                    Button("Add a tool") { model.openToolForm() }.primaryButton(palette)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let note = model.toolNote { NoteLine(note: note, palette: palette).padding(.horizontal, 24).padding(.vertical, 12) }
                        HeaderRow(palette: palette, columns: [("Tool", 230), ("On this Mac", 210), ("What a press would run", nil), ("", 150)])
                        ForEach(model.tools, id: \.name) { tool in row(tool, palette) }
                    }
                }
                .disabled(model.toolsRunning)
            }
        }
        .onAppear { model.refreshTools() }
    }

    private func row(_ tool: Tool, _ palette: Palette) -> some View {
        let status = model.toolStatus[tool.name]
        let installed = status?.installed == true
        return HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tool.name).font(Palette.mono).lineLimit(1)
                    if tool.origin == .team {
                        Image(systemName: "person.2").font(.caption).foregroundStyle(palette.muted).help("From the team · read-only here")
                    }
                }
                if !tool.desc.isEmpty { Text(tool.desc).font(.caption).foregroundStyle(palette.muted).lineLimit(2) }
            }
            .cell(230)
            Label(status?.words ?? "looking…", systemImage: icon(status)).foregroundStyle(color(status, palette))
                .help(status?.managerMissing.map { "\($0) is not installed on this Mac" } ?? "")
                .cell(210)
            VStack(alignment: .leading, spacing: 2) {
                Text(installed ? tool.updateLine : tool.installLine)
                    .font(Palette.mono).lineLimit(3).textSelection(.enabled)
                    .help(installed ? tool.updateLine : tool.installLine)
                Text(tool.method.rawValue + (tool.origin == .team ? " · the team's line" : "")).font(.caption).foregroundStyle(palette.muted)
            }
            .cell(nil)
            HStack(spacing: 14) {
                Spacer(minLength: 0)
                if let status {
                    if !status.installed {
                        Button("Install") { model.installTools([tool.name]) }.rowAction(palette)
                    } else if !status.elsewhere, status.outdated == true || !tool.knowsOutdated {
                        Button("Update") { model.updateTools([tool.name]) }.rowAction(palette)
                    }
                }
                if tool.origin == .personal {
                    Button("Remove") { model.removeTool(tool.name) }.rowAction(palette, destructive: true)
                        .help("Take \(tool.name) off your list. Nothing is uninstalled.")
                }
            }
            .cell(150)
        }
        .font(.callout)
        .tableRow(palette)
    }

    private func icon(_ s: ToolStatus?) -> String {
        guard let s else { return "ellipsis.circle" }
        if !s.installed { return "arrow.down.circle" }
        return s.outdated == true ? "arrow.up.circle" : "checkmark.circle.fill"
    }

    private func color(_ s: ToolStatus?, _ palette: Palette) -> Color {
        guard let s else { return palette.muted }
        if !s.installed || s.outdated == true { return palette.warn }
        return palette.ok
    }
}

/// Behind the "?": where the list comes from, that nothing installs by itself, and the methods.
private struct ToolsHelp: View {
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing installs by itself").font(palette.title(15))
            Text("The list comes from your commands.toml and, when you have joined one, the team's. A tool the team adds shows here as missing until you press Install, or your agent runs great-gui tools install. The app looks at what is behind for the package managers that can say (Homebrew, uv, npm), and only reports it.")
                .font(.callout).foregroundStyle(palette.muted)
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Adding a tool").font(palette.title(15))
            Text("Add Tool, or from a terminal:").font(.callout).foregroundStyle(palette.muted)
            Text("great-gui tools add ripgrep --method brew --bin rg").font(Palette.mono).textSelection(.enabled)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading).codeBlock(palette)
            ForEach(Tool.Method.allCases, id: \.rawValue) { method in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(method.rawValue).font(Palette.mono).frame(width: 60, alignment: .leading)
                    Text(method.words).font(.callout).foregroundStyle(palette.muted)
                }
            }
            Text("Or write a [[tool]] entry in commands.toml (⌥⌘E). Removing an entry uninstalls nothing.")
                .font(.callout).foregroundStyle(palette.muted)
        }
    }
}

/// Lists a tool in your registry: the name, the method, and what that method needs. Nothing is installed.
struct ToolSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var model = model
        let palette = Palette(scheme: scheme)
        let method = Tool.Method(rawValue: model.toolDraft.method) ?? .brew
        SheetFrame(palette: palette, title: "Add a Tool", footnote: "Adds a [[tool]] entry to your commands.toml. Nothing is installed until you press Install.",
                   width: 560, height: 560) {
            EmptyView()
        } content: {
            LabeledField(palette: palette, label: "Name") {
                TextField("Name", text: $model.toolDraft.name, prompt: Text("ripgrep")).font(Palette.mono).fieldBox(palette)
            }
            LabeledField(palette: palette, label: "Description") {
                TextField("Description", text: $model.toolDraft.desc, prompt: Text("fast search")).fieldBox(palette)
            }
            LabeledField(palette: palette, label: "Method", hint: method.words) {
                Picker("Method", selection: $model.toolDraft.method) {
                    ForEach(Tool.Method.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                }
                .labelsHidden().fixedSize()
            }
            if method == .script {
                LabeledField(palette: palette, label: "Install line", hint: "The shell line that installs it. It runs only when Install is pressed.") {
                    TextField("Install", text: $model.toolDraft.install, prompt: Text("curl -LsSf https://astral.sh/uv/install.sh | sh"), axis: .vertical)
                        .font(Palette.mono).fieldBox(palette)
                }
                LabeledField(palette: palette, label: "Update line", hint: "Optional; the install line is used when empty.") {
                    TextField("Update", text: $model.toolDraft.update, prompt: Text("uv self update")).font(Palette.mono).fieldBox(palette)
                }
            } else {
                LabeledField(palette: palette, label: "Package", hint: method == .go ? "The module path." : "Only when \(method.manager ?? "the package manager") calls it something other than the name.") {
                    TextField("Package", text: $model.toolDraft.pkg, prompt: Text(method == .go ? "golang.org/x/tools/gopls" : "ripgrep")).font(Palette.mono).fieldBox(palette)
                }
            }
            LabeledField(palette: palette, label: "Program", hint: "Optional: what it puts on PATH, when that differs from the name.") {
                TextField("Program", text: $model.toolDraft.bin, prompt: Text("rg")).font(Palette.mono).fieldBox(palette)
            }
            LabeledField(palette: palette, label: "Requires", hint: "Optional: other tools or programs it needs first.") {
                TextField("Requires", text: $model.toolDraft.requires, prompt: Text("uv")).font(Palette.mono).fieldBox(palette)
            }
            if let note = model.toolNote, !note.ok { NoteLine(note: note, palette: palette) }
        } actions: {
            Button("Cancel") { model.toolSheetOpen = false }.secondaryButton(palette).keyboardShortcut(.cancelAction)
            Button("Add") { model.saveTool() }.primaryButton(palette).keyboardShortcut(.defaultAction)
        }
    }
}

/// An install or update run, in an embedded terminal so an installer that asks for a password can be
/// answered. A sheet, so nothing tears the terminal down mid-install; Close is offered once the shell ends.
struct ToolRunSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        let run = model.run.flatMap { $0.name == AppModel.toolsRunName ? $0 : nil }
        let running = run?.status == .running
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tools").heading(palette, 22)
                Spacer()
                if let run { StatusChip(run: run, palette: palette) }
            }
            Text(model.toolsRunSummary).font(.callout).foregroundStyle(palette.muted).lineLimit(2)
            if let run, run.interactive, running || run.isDone {
                TerminalPane(run: run, theme: palette.theme) { code in model.finishInteractive(code: code) }
                    .frame(height: 16 * TermFont.line + 16)
                    .padding(8)
                    .codeBlock(palette)
            } else if let run, case .failed(let what, let fix) = run.status {
                NoteLine(note: AppModel.Note(ok: false, text: what, fix: fix), palette: palette)
            }
            HStack {
                Text("Each tool's own installer runs here, one after another. A failure is counted and the rest still run.")
                    .font(.caption).foregroundStyle(palette.muted)
                Spacer()
                Button("Close") { model.closeToolRun() }.secondaryButton(palette).disabled(running).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 720)
        .foregroundStyle(palette.ink)
        .background(palette.ground)
        .interactiveDismissDisabled(true)
    }
}
