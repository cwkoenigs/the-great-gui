import Registry
import SwiftUI
import TerminalDesign

/// ⌘N and ⌘E: the command as a form in a sheet, with direction on the way. A new command can start from
/// an example; every field says what it is for; an env file and a secret are picked from what is stored,
/// not typed; and the block that will be written is shown as the form fills in. Add appends one block and
/// Save rewrites the edited command's block, through the writer the command line uses.
struct NewCommandSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focus: String?

    var body: some View {
        @Bindable var model = model
        let palette = Palette(scheme: scheme)
        let preview = model.draftPreview
        SheetFrame(palette: palette, title: title, footnote: footer, width: 680, height: 640) {
            if !model.isEditing, model.copyOf == nil {
                Menu {
                    ForEach(AppModel.commandExamples) { example in
                        Button { model.use(example); focus = "name" } label: { Label(example.title, systemImage: example.symbol) }
                    }
                } label: {
                    Label("Start from an example", systemImage: "wand.and.stars")
                }
                .menuStyle(.borderlessButton).fixedSize().foregroundStyle(palette.accent)
                .help("Fill the form with a working example, then change it")
            }
        } content: {
            if let teaches = model.exampleNote {
                Label(teaches, systemImage: "lightbulb.fill").font(.callout).foregroundStyle(palette.muted)
            }
            VStack(alignment: .leading, spacing: 12) {
                LabeledField(palette: palette, label: "Name", hint: "How you find it: lowercase letters, digits and dashes.") {
                    TextField("Name", text: $model.draft.name, prompt: Text("brew-outdated")).font(Palette.mono).fieldBox(palette).focused($focus, equals: "name")
                }
                LabeledField(palette: palette, label: "Run", hint: "Exactly what you would type in a terminal.") {
                    TextField("Run", text: $model.draft.run, prompt: Text("brew outdated --verbose"), axis: .vertical).font(Palette.mono).fieldBox(palette)
                }
                LabeledField(palette: palette, label: "Description") {
                    TextField("Description", text: $model.draft.desc, prompt: Text("what Homebrew would upgrade")).fieldBox(palette)
                }
                LabeledField(palette: palette, label: "Group", hint: "The sidebar heading it sits under" + (model.groups.isEmpty ? "." : ": yours are " + model.groups.joined(separator: ", ") + ".")) {
                    TextField("Group", text: $model.draft.group, prompt: Text(model.groups.first ?? "mac")).fieldBox(palette)
                }
            }
            .formSection("1 · What it is", palette)
            VStack(alignment: .leading, spacing: 12) {
                LabeledField(palette: palette, label: "Parameters", hint: "To ask for a value each run, write {formula} in the run line and describe it here as name:description. Add =default for a default, ! to require it, and ; between several.") {
                    TextField("Parameters", text: $model.draft.params, prompt: Text("formula:the formula to upgrade!")).font(Palette.mono).fieldBox(palette)
                }
                LabeledField(palette: palette, label: "Working directory") {
                    TextField("Working directory", text: $model.draft.cwd, prompt: Text("~/Developer/my-project")).font(Palette.mono).fieldBox(palette)
                }
            }
            .formSection("2 · What it asks for, and where it runs (optional)", palette)
            VStack(alignment: .leading, spacing: 12) {
                if !model.credentialProfiles.entries.isEmpty {
                    Menu("Use Credential Profile") {
                        ForEach(model.credentialProfiles.entries) { profile in
                            Button(profile.label + " · " + profile.destination) { model.useCredentialProfileInDraft(profile) }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
                LabeledField(palette: palette, label: "Environment", hint: "KEY=value, with ; between several. Insert secret adds one whose value is read from the Keychain when it runs, so it is never written here.") {
                    HStack {
                        TextField("Environment", text: $model.draft.env, prompt: Text("TOKEN=keychain:gitlab-token; PAGER=cat")).font(Palette.mono).fieldBox(palette)
                        Menu("Insert secret") {
                            if model.formSecretNames.isEmpty {
                                Text("No secrets stored yet")
                            } else {
                                ForEach(model.formSecretNames, id: \.self) { name in Button(name) { model.insertSecret(name) } }
                            }
                            Divider()
                            Button("Add a secret in Secrets…") { model.leaveFormForSecrets(file: false) }
                        }
                        .menuStyle(.borderlessButton).fixedSize().foregroundStyle(palette.accent)
                    }
                }
                LabeledField(palette: palette, label: "Env file", hint: "Every entry of a whole .env stored in Secrets, without the file touching the disk.") {
                    HStack {
                        Picker("Env file", selection: $model.draft.envFile) {
                            ForEach(model.envFileChoices, id: \.tag) { choice in Text(choice.label).tag(choice.tag) }
                        }
                        .labelsHidden().fixedSize()
                        if model.envFileChoices.count == 1 {
                            Button("No .env stored yet: add one in Secrets…") { model.leaveFormForSecrets(file: true) }.rowAction(palette)
                        }
                    }
                }
            }
            .formSection("3 · Secrets and settings it needs (optional)", palette)
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Needs a terminal: it draws a screen or asks questions", isOn: bool("interactive"))
                Toggle("Ask for Touch ID or the password before it runs", isOn: bool("gate"))
                if let suggested = model.suggestedSchedule {
                    // A copy of a team command: its schedule is the team's suggestion, off until the person says so.
                    Toggle("Also run it by itself on this Mac, \(suggested.english)", isOn: suggestedOn(suggested))
                    Text("The team suggests this schedule. Off: your copy runs only when you run it. On: launchd runs it on this Mac from the moment you press Add, with this window closed.")
                        .font(.caption).foregroundStyle(palette.muted)
                }
                LabeledField(palette: palette, label: "Schedule", hint: "Runs it by itself, even with this window closed. A scheduled command cannot also need a terminal or Touch ID.") {
                    HStack {
                        TextField("Schedule", text: $model.draft.schedule, prompt: Text("empty: only when you run it")).fieldBox(palette)
                        Menu("Examples") {
                            ForEach(AppModel.scheduleExamples, id: \.phrase) { ex in
                                Button("\(ex.phrase)  ·  \(ex.means)") { model.draft.schedule = ex.phrase }
                            }
                            Divider()
                            Button("Only when I run it") { model.draft.schedule = "" }
                        }
                        .menuStyle(.borderlessButton).fixedSize().foregroundStyle(palette.accent)
                    }
                    if !model.draft.schedule.trimmingCharacters(in: .whitespaces).isEmpty {
                        Label("Saving arms it: launchd will run this command on this Mac on that schedule.", systemImage: "clock")
                            .font(.caption).foregroundStyle(palette.warn)
                    }
                }
                LabeledField(palette: palette, label: "Tags") {
                    TextField("Tags", text: $model.draft.tags, prompt: Text("a, b")).fieldBox(palette)
                }
            }
            .formSection("4 · How it behaves (optional)", palette)
            VStack(alignment: .leading, spacing: 8) {
                Label(preview.ok ? "Ready: this is what will be written" : "Not ready yet", systemImage: preview.ok ? "checkmark.circle.fill" : "pencil.circle")
                    .font(.callout.weight(.medium)).foregroundStyle(preview.ok ? palette.ok : palette.muted)
                Text(preview.text)
                    .font(preview.ok ? Palette.mono : .callout)
                    .foregroundStyle(preview.ok ? palette.codeText : palette.muted)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .codeBlock(palette)
                if !preview.fix.isEmpty { Text(preview.fix).font(.callout).foregroundStyle(palette.warn) }
            }
            if let note = model.registryNote { NoteLine(note: note, palette: palette) }
        } actions: {
            Button("Cancel") { model.closeNewCommand() }.secondaryButton(palette).keyboardShortcut(.cancelAction)
            Button(model.isEditing ? "Save" : "Add") { model.saveDraft() }.primaryButton(palette).keyboardShortcut(.defaultAction)
        }
        .onAppear { focus = "name" }
    }

    private var title: String {
        if model.isEditing { return "Edit \(model.editingName ?? "")" }
        if let name = model.copyOf { return "Your Copy of \(name)" }
        return "New Command"
    }

    private var footer: String {
        let file = model.registryURL.lastPathComponent
        let verb = model.isEditing ? "Rewrites the block for \(model.editingName ?? "") in \(file)" : "Appends one block to \(file)"
        return verb + (model.registryIsRepository ? " and commits it." : ".")
    }

    private func bool(_ field: String) -> Binding<Bool> {
        Binding(get: { (try? RegistryWriter.parseBool(model.draft[field], name: field)) ?? false },
                set: { model.draft[field] = $0 ? "yes" : "no" })
    }

    private func suggestedOn(_ suggested: Schedule) -> Binding<Bool> {
        Binding(get: { model.draft.schedule == suggested.text }, set: { model.draft.schedule = $0 ? suggested.text : "" })
    }
}

/// The app menu's Update…: `make update` in the checkout this bundle was built in, in an embedded terminal.
/// A sheet, so nothing can tear the terminal down mid-build; when the script succeeds it quits and reopens
/// the app, and the sheet goes with it. Close is only offered once the shell has ended.
struct UpdateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        let run = model.run.flatMap { $0.name == AppModel.updateName ? $0 : nil }
        let running = run?.status == .running
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Updating the-great-gui").heading(palette, 22)
                Spacer()
                if let run { StatusChip(run: run, palette: palette) }
            }
            Text("Pulls the checkout, rebuilds the app and relinks the command and the skills. When it finishes, the window closes and comes back on the new build.")
                .font(.callout).foregroundStyle(palette.muted)
            if let run, run.interactive, running || run.isDone {
                TerminalPane(run: run, theme: palette.theme) { code in model.finishInteractive(code: code) }
                    .frame(height: 16 * TermFont.line + 16)
                    .padding(8)
                    .codeBlock(palette)
            } else if let run, case .failed(let what, let fix) = run.status {
                NoteLine(note: AppModel.Note(ok: false, text: what, fix: fix), palette: palette)
            }
            HStack {
                if let root = AppModel.checkoutURL {
                    Text(root.path).font(.caption).foregroundStyle(palette.muted).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if model.relaunching {
                    Text("Reopening…").font(.callout).foregroundStyle(palette.muted)
                } else {
                    Button("Close") { model.closeUpdate() }.secondaryButton(palette).disabled(running).keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(20)
        .frame(width: 720)
        .foregroundStyle(palette.ink)
        .background(palette.ground)
        .interactiveDismissDisabled(true)
    }
}
