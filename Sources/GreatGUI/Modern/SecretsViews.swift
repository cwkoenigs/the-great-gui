import Registry
import Secrets
import SwiftUI
import TerminalDesign

/// The secrets by name: in the Keychain or only named by the registry, and who uses them; then the
/// credential files kept whole, each with where it belongs and how its Keychain copy compares. Never a
/// value. The rows take the screen's width; how it all works is behind the "?".
struct SecretsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        let pending = Binding(get: { model.pendingRestore != nil }, set: { if !$0 { model.cancelRestore() } })
        Screen(palette: palette, kicker: "Keychain · this Mac only", title: "Secrets", summary: summary) {
            Button { model.openSecretSheet() } label: { Label("Add secret", systemImage: "plus") }
                .primaryButton(palette).help("Add or replace a secret")
            Button { model.openFileSheet() } label: { Label("Add file", systemImage: "doc.badge.plus") }
                .secondaryButton(palette).help("Keep a whole credential file (.env, connections.toml) in the Keychain")
        } help: {
            SecretsHelp(palette: palette)
        } content: {
            if model.secretRows.isEmpty && model.fileRows.isEmpty {
                EmptyState(palette: palette, title: "No secrets yet",
                           text: "A secret is one value, such as a token. A file is a whole credential file, such as a .env or Snowflake's connections.toml. Both are kept in your Keychain, on this Mac only.") {
                    Button("Add a secret") { model.openSecretSheet() }.primaryButton(palette)
                    Button("Add a file") { model.openFileSheet() }.secondaryButton(palette)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let note = model.secretsNote { NoteLine(note: note, palette: palette).padding(.horizontal, 24).padding(.vertical, 12) }
                        if !model.secretRows.isEmpty { secrets(palette) }
                        if !model.fileRows.isEmpty { files(palette).padding(.top, model.secretRows.isEmpty ? 0 : 22) }
                    }
                }
            }
        }
        .confirmationDialog("Overwrite \(model.fileRows.first { $0.name == model.pendingRestore }?.path ?? "the file")?", isPresented: pending, titleVisibility: .visible) {
            Button("Overwrite with the Keychain copy", role: .destructive) { model.confirmRestore() }
            Button("Cancel", role: .cancel) { model.cancelRestore() }
        } message: {
            Text("The file on disk differs from the copy in the Keychain. Restoring replaces the file; Store would keep the file's version instead.")
        }
        .onAppear { model.refreshSecrets() }
    }

    private var summary: String {
        let s = model.secretRows.count, f = model.fileRows.count
        let missing = model.secretRows.filter { !$0.inKeychain }.count
        if s == 0 && f == 0 { return "" }
        return "\(s) secret\(s == 1 ? "" : "s") · \(f) file\(f == 1 ? "" : "s")" + (missing > 0 ? " · \(missing) not stored yet" : "")
    }

    private func secrets(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            HeaderRow(palette: palette, columns: [("Secret", 260), ("Keychain", 150), ("Used by", nil), ("", 70)])
            ForEach(model.secretRows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(row.name).font(Palette.mono).lineLimit(1).truncationMode(.middle).help(row.name).cell(260)
                    Label(row.inKeychain ? "in Keychain" : "missing", systemImage: row.inKeychain ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(row.inKeychain ? palette.ok : palette.warn).cell(150)
                    Text(row.usedBy.isEmpty ? "no command" : row.usedBy.joined(separator: ", "))
                        .foregroundStyle(row.usedBy.isEmpty ? palette.muted : palette.ink).lineLimit(2).cell(nil)
                    Group {
                        if row.inKeychain {
                            Button("Delete") { model.deleteSecret(row.name) }.rowAction(palette, destructive: true)
                        } else {
                            Button("Add") { model.openSecretSheet(named: row.name) }.rowAction(palette)
                        }
                    }
                    .cell(70)
                }
                .font(.callout)
                .tableRow(palette)
            }
        }
    }

    private func files(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            HeaderRow(palette: palette, columns: [("File", 230), ("Keychain copy", 140), ("What to do", nil), ("", 200)])
            ForEach(model.fileRows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name).font(Palette.mono).lineLimit(1)
                        Text(row.path).font(.caption).foregroundStyle(palette.muted).lineLimit(1).truncationMode(.middle).help(row.path)
                    }
                    .cell(230)
                    Label(row.state?.words ?? "unreadable", systemImage: icon(row)).foregroundStyle(color(row, palette)).cell(140)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.problem.isEmpty ? AppModel.advice(for: row.state) : row.problem).fixedSize(horizontal: false, vertical: true)
                        if !row.usedBy.isEmpty { Text("Used by " + row.usedBy.joined(separator: ", ")).font(.caption) }
                    }
                    .foregroundStyle(palette.muted).cell(nil)
                    HStack(spacing: 14) {
                        Spacer(minLength: 0)
                        ForEach(AppModel.fileActions(for: row.state), id: \.self) { action in
                            Button(action.title) { model.perform(action, on: row.name) }.rowAction(palette)
                        }
                        Button("Remove") { model.removeFile(row.name) }.rowAction(palette, destructive: true)
                            .help("Drop the pointer. The file stays, and so does its Keychain copy until you delete it above.")
                    }
                    .cell(200)
                }
                .font(.callout)
                .tableRow(palette)
            }
        }
    }

    private func icon(_ row: AppModel.FileRow) -> String {
        switch row.state {
        case .inSync: "checkmark.circle.fill"
        case .notOnDisk: "arrow.down.circle"
        case .notStored: "arrow.up.circle"
        default: "exclamationmark.triangle.fill"
        }
    }

    private func color(_ row: AppModel.FileRow, _ palette: Palette) -> Color {
        switch row.state {
        case .inSync: palette.ok
        case .none: palette.err
        default: palette.warn
        }
    }
}

/// Behind the "?": what each kind is for, how to add one step by step, and what every file state means.
private struct SecretsHelp: View {
    @Environment(AppModel.self) private var model
    let palette: Palette

    var body: some View {
        guide("A secret: one value", "A token or a password a command needs.", [
            "Press Add secret, give it a name such as gitlab-token, and paste the value. It is never shown again.",
            "In a command, open Edit and use Insert secret under Environment. That writes TOKEN=keychain:gitlab-token.",
            "When the command runs, the value is read from the Keychain into its environment and hidden in the output.",
        ])
        guide("A file: a whole credential file", "A project's .env, or ~/.snowflake/connections.toml.", [
            "Press Add file and pick an example or choose the file. Its contents are stored in the Keychain; the registry keeps only the name and the path.",
            "To put it back where a tool expects it, press Restore in the list. It is written so only you can read it.",
            "To give a .env to one command without it touching the disk, open that command's Edit and pick it under Env file.",
        ])
        VStack(alignment: .leading, spacing: 6) {
            Text("What a file's status means").font(palette.title(15))
            ForEach(AppModel.fileStates, id: \.self) { state in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(state.words).font(.callout.weight(.medium)).foregroundStyle(state == .inSync ? palette.ok : palette.warn)
                        .frame(width: 110, alignment: .leading)
                    Text(AppModel.advice(for: state)).font(.callout).foregroundStyle(palette.muted)
                }
            }
        }
        Text("Everything here is in your login keychain under \(model.secrets.service) and stays on this Mac: nothing exports or syncs a value. A teammate stores their own.")
            .font(.callout).foregroundStyle(palette.muted)
    }

    private func guide(_ title: String, _ example: String, _ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(palette.title(15))
            Text(example).font(.callout).foregroundStyle(palette.muted)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(i + 1).").font(.callout.monospacedDigit()).foregroundStyle(palette.muted)
                    Text(step).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Add or replace one secret: the name, and a value field that never shows what you type.
struct SecretSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focus: Field?
    enum Field { case name, value }

    var body: some View {
        @Bindable var model = model
        let palette = Palette(scheme: scheme)
        SheetFrame(palette: palette, title: "Add a Secret", footnote: "Saved in your login keychain under \(model.secrets.service). It stays on this Mac.",
                   width: 520, height: 330) {
            EmptyView()
        } content: {
            LabeledField(palette: palette, label: "Name", hint: "How commands refer to it: letters, digits, dots and dashes.") {
                TextField("Name", text: $model.newSecretName, prompt: Text("gitlab-token"))
                    .font(Palette.mono).fieldBox(palette)
                    .focused($focus, equals: .name)
                    .onSubmit { focus = .value }
            }
            LabeledField(palette: palette, label: "Value", hint: "Paste or type it. It is never shown again, here or anywhere.") {
                SecureField("Value", text: $model.newSecretValue, prompt: Text("the token or password"))
                    .fieldBox(palette)
                    .focused($focus, equals: .value)
                    .onSubmit { model.saveSecretFromSheet() }
            }
            if let note = model.secretsNote, !note.ok { NoteLine(note: note, palette: palette) }
        } actions: {
            Button("Cancel") { model.closeSecretSheet() }.secondaryButton(palette).keyboardShortcut(.cancelAction)
            Button("Save") { model.saveSecretFromSheet() }.primaryButton(palette).keyboardShortcut(.defaultAction)
        }
        .onAppear { model.clearSecretsNote(); focus = model.newSecretName.isEmpty ? .name : .value }
    }
}

/// Add a credential file: start from an example or choose the file, see at once whether it is there, and
/// read what happens next. Its contents are read from the file; this sheet never shows or takes them.
struct FileSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focus: Field?
    enum Field { case name, path }

    var body: some View {
        @Bindable var model = model
        let palette = Palette(scheme: scheme)
        let check = model.checkNewFilePath()
        SheetFrame(palette: palette, title: "Add a File", footnote: "It stays on this Mac, under \(model.secrets.service).", width: 620, height: 560) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                FlowButtons(items: AppModel.fileExamples) { example in
                    Button {
                        if example.path.isEmpty { choose() } else { model.use(example); focus = .path }
                    } label: { Label(example.title, systemImage: example.symbol) }
                    .secondaryButton(palette)
                }
                Text("An example fills in the two fields below with the usual name and place. Change either one.")
                    .font(.caption).foregroundStyle(palette.muted)
            }
            .formSection("1 · Start from an example", palette)
            VStack(alignment: .leading, spacing: 12) {
                LabeledField(palette: palette, label: "Path", hint: "Where the file belongs.") {
                    HStack {
                        TextField("Path", text: $model.newFilePath, prompt: Text("~/.snowflake/connections.toml"))
                            .font(Palette.mono).fieldBox(palette)
                            .focused($focus, equals: .path)
                            .onSubmit { focus = .name }
                        Button("Choose…", action: choose).secondaryButton(palette)
                    }
                    Label(check.text, systemImage: symbol(check.kind)).font(.callout).foregroundStyle(color(check.kind, palette))
                }
                LabeledField(palette: palette, label: "Name", hint: "How you refer to it later: letters, digits, dots and dashes.") {
                    TextField("Name", text: $model.newFileName, prompt: Text("snowflake-connections"))
                        .font(Palette.mono).fieldBox(palette)
                        .focused($focus, equals: .name)
                        .onSubmit { model.addFile() }
                }
            }
            .formSection("2 · Where the file is, and a name for it", palette)
            VStack(alignment: .leading, spacing: 6) {
                Label("Add stores the file's contents in your login keychain. The registry gets only the name and the path.", systemImage: "lock.fill")
                Label("Restore, in the list, writes it back to its path so only you can read it.", systemImage: "arrow.down.doc")
                Label("A command can take a stored .env directly: Edit the command and pick it under Env file.", systemImage: "terminal")
            }
            .font(.callout).foregroundStyle(palette.muted)
            .formSection("3 · What happens next", palette)
            if let note = model.secretsNote, !note.ok { NoteLine(note: note, palette: palette) }
        } actions: {
            Button("Cancel") { model.fileSheetOpen = false }.secondaryButton(palette).keyboardShortcut(.cancelAction)
            Button(check.kind == .found ? "Add and Store" : "Add") { model.addFile() }
                .primaryButton(palette).keyboardShortcut(.defaultAction)
                .disabled(!check.kind.canAdd)
        }
        .onAppear { model.clearSecretsNote(); focus = .path }
    }

    private func symbol(_ kind: AppModel.PathCheck.Kind) -> String {
        switch kind {
        case .found: "checkmark.circle.fill"
        case .empty: "arrow.up"
        case .absent: "questionmark.circle"
        default: "exclamationmark.triangle.fill"
        }
    }

    private func color(_ kind: AppModel.PathCheck.Kind, _ palette: Palette) -> Color {
        switch kind {
        case .found: palette.ok
        case .empty, .absent: palette.muted
        default: palette.warn
        }
    }

    /// The open panel, hidden files shown: credential files usually start with a dot.
    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Choose the credential file to keep in your Keychain"
        panel.prompt = "Choose"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.chose(path: url.path)
        focus = .name
    }
}

/// A row of buttons that wraps onto more lines when the sheet is narrow.
struct FlowButtons<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { ForEach(items) { content($0) } }
            VStack(alignment: .leading, spacing: 6) {
                let half = (items.count + 1) / 2
                HStack(spacing: 8) { ForEach(items.prefix(half)) { content($0) } }
                HStack(spacing: 8) { ForEach(items.dropFirst(half)) { content($0) } }
            }
            VStack(alignment: .leading, spacing: 6) { ForEach(items) { content($0) } }
        }
    }
}

/// Every run, newest first, across the screen's width.
struct HistoryScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        Screen(palette: palette, kicker: "Runs", title: "History", summary: model.historySummary) {
            EmptyView()
        } help: {
            Text("What is recorded").font(palette.title(15))
            Text("Every run, from this window, from great-gui in a terminal, from an agent and from a schedule: when it started, how it was started, its exit code, how long it took and the line that ran.")
                .font(.callout)
            Text("A secret's value is never recorded: secrets travel in the run's environment, not in its line. A parameter's value is part of the line, so it is recorded.")
                .font(.callout).foregroundStyle(palette.muted)
            Text("The newest \(500) runs are kept, in Application Support. great-gui history --json gives the same list to an agent.")
                .font(.callout).foregroundStyle(palette.muted)
        } content: {
            if model.history.isEmpty {
                EmptyState(palette: palette, title: "No runs yet", text: "Run a command and it is recorded here: when, how, its exit code and how long it took.") { EmptyView() }
            } else {
                ScrollView { HistoryRows(rows: model.history, showName: true, palette: palette) }
            }
        }
    }
}
