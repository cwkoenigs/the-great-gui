import Registry
import SwiftUI
import TerminalDesign

struct CredentialProfileRows: View {
    @Environment(AppModel.self) private var model
    let palette: Palette

    var body: some View {
        let profiles = model.credentialProfiles
        VStack(spacing: 0) {
            HeaderRow(palette: palette, columns: [("Credential profile", nil), ("Last check", 230), ("", 170)])
            ForEach(profiles.entries) { profile in
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.label).font(.callout.weight(.medium))
                        Text(profile.destination).font(.caption).foregroundStyle(palette.muted).lineLimit(1)
                    }
                    .cell(nil)
                    Group {
                        if profiles.checking == profile.id {
                            Text("Checking…").foregroundStyle(palette.muted)
                        } else if let result = profiles.results[profile.id] {
                            NoteLine(note: result, palette: palette)
                        } else {
                            Text("Unchecked").foregroundStyle(palette.muted)
                        }
                    }
                    .cell(230)
                    HStack(spacing: 10) {
                        Button("Check") {
                            profiles.check(profile, files: model.registry?.files ?? [], secrets: model.secrets)
                        }
                        .rowAction(palette)
                        .disabled(profiles.checking != nil)
                        Button("Edit") { profiles.open(profile) }.rowAction(palette).disabled(profiles.checking != nil)
                    }
                    .cell(170)
                }
                .font(.callout)
                .tableRow(palette)
            }
        }
    }
}

struct CredentialProfileSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var profiles = model.credentialProfiles
        let palette = Palette(scheme: scheme)
        let existing = profiles.entries.first { $0.id == profiles.draft.id }
        let files = (model.registry?.files ?? []).map(\.name)
        SheetFrame(palette: palette, title: existing == nil ? "Add Credential Profile" : "Edit Credential Profile",
                   footnote: "Profiles store Keychain references. Add or rotate values in Secrets.", width: 650, height: 570) {
            EmptyView()
        } content: {
            LabeledField(palette: palette, label: "Label") {
                TextField("Label", text: $profiles.draft.label, prompt: Text("Reporting API")).fieldBox(palette)
            }
            LabeledField(palette: palette, label: "Destination", hint: "A service or host label for you to review when selecting the profile.") {
                TextField("Destination", text: $profiles.draft.destination, prompt: Text("api.example.com")).fieldBox(palette)
            }
            LabeledField(palette: palette, label: "Environment bindings", hint: "Use VARIABLE=keychain:name. Separate entries with semicolons.") {
                HStack {
                    TextField("Environment bindings", text: $profiles.draft.bindings, prompt: Text("API_TOKEN=keychain:example-token"))
                        .font(Palette.mono).fieldBox(palette)
                    Menu("Insert secret") {
                        ForEach(model.secretRows.filter(\.inKeychain), id: \.name) { row in
                            Button(row.name) { insert(row.name) }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .disabled(!model.secretRows.contains(where: \.inKeychain))
                }
            }
            LabeledField(palette: palette, label: "Credential file") {
                Picker("Credential file", selection: $profiles.draft.file) {
                    Text("None").tag("")
                    ForEach(files, id: \.self) { Text($0).tag($0) }
                    if !profiles.draft.file.isEmpty, !files.contains(profiles.draft.file) {
                        Text(profiles.draft.file + " (missing)").tag(profiles.draft.file)
                    }
                }
                .labelsHidden()
                if !profiles.draft.file.isEmpty {
                    Picker("File use", selection: $profiles.draft.fileUse) {
                        Text("Load .env into the process").tag(CredentialProfile.FileUse.environment)
                        Text("Client needs a local file").tag(CredentialProfile.FileUse.localFile)
                    }
                    if profiles.draft.fileUse == .localFile {
                        Text("Restore the registered file when the client needs it. Check verifies the existing copy.")
                            .font(.caption).foregroundStyle(palette.muted)
                    }
                }
            }
            LabeledField(palette: palette, label: "Read-only check (optional)",
                         hint: "Enter a command you trust to check this credential. Check runs it on demand and shows only the exit result.") {
                TextField("Read-only check", text: $profiles.draft.checkCommand, prompt: Text("example-cli auth status"))
                    .font(Palette.mono).fieldBox(palette)
            }
            if let note = profiles.note { NoteLine(note: note, palette: palette) }
        } actions: {
            if let existing {
                Button("Remove Profile") {
                    profiles.remove(existing)
                    if profiles.note == nil { profiles.editorOpen = false }
                }
                .rowAction(palette, destructive: true)
                .help("Remove this profile from the picker. Keychain items and saved commands remain available.")
            }
            Button("Cancel") { profiles.editorOpen = false }.secondaryButton(palette).keyboardShortcut(.cancelAction)
            Button("Save Profile") { profiles.save() }.primaryButton(palette).keyboardShortcut(.defaultAction)
        }
    }

    private func insert(_ name: String) {
        let profiles = model.credentialProfiles
        let variable = String(name.uppercased().map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "_" })
        let key = variable.first?.isNumber == true ? "_" + variable : variable
        let entry = "\(key)=keychain:\(name)"
        let existing = profiles.draft.bindings.trimmingCharacters(in: .whitespaces)
        profiles.draft.bindings = existing.isEmpty ? entry : existing + (existing.hasSuffix(";") ? " " : "; ") + entry
    }
}
