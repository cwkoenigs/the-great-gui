import Foundation
import Registry
import Secrets

/// The direction the forms give: examples that fill a form in one click, what each file state means and
/// what to press next, and the values the pick-lists offer. Both looks read it from here, so an example is
/// written once. Nothing in this file holds or reads a secret's value.
extension AppModel {
    // MARK: files

    /// A credential file people commonly keep: a name for its Keychain item and where the tool expects it.
    struct FileExample: Identifiable, Equatable {
        var title: String
        var name: String
        /// Empty when there is no usual place: the example then opens the file chooser.
        var path: String
        var symbol: String
        var id: String { title }
    }

    static let fileExamples: [FileExample] = [
        FileExample(title: "Snowflake connections", name: "snowflake-connections", path: "~/.snowflake/connections.toml", symbol: "snowflake"),
        FileExample(title: "A project's .env", name: "", path: "", symbol: "doc.text"),
        FileExample(title: "AWS credentials", name: "aws-credentials", path: "~/.aws/credentials", symbol: "cloud"),
        FileExample(title: "SSH private key", name: "ssh-key", path: "~/.ssh/id_ed25519", symbol: "key.horizontal"),
        FileExample(title: "npm token (.npmrc)", name: "npmrc", path: "~/.npmrc", symbol: "shippingbox"),
    ]

    /// Fills the Add file form.
    func use(_ example: FileExample) {
        secretsNote = nil
        newFilePath = example.path
        newFileName = example.name
    }

    /// The path a chooser returned, as the registry would carry it, with a name suggested when none is typed.
    func chose(path: String) {
        newFilePath = RegistryWriter.portable(path)
        if newFileName.trimmingCharacters(in: .whitespaces).isEmpty { newFileName = Self.suggestedName(for: path) }
    }

    /// `~/proj/.env` → `proj-env`; `~/.snowflake/connections.toml` → `snowflake-connections`; `~/.npmrc` → `npmrc`.
    static func suggestedName(for path: String) -> String {
        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        func clean(_ s: String) -> String {
            let mapped = s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
            return String(mapped).split(separator: "-").joined(separator: "-")
        }
        let file = clean(url.deletingPathExtension().lastPathComponent.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent)
        let folder = clean(url.deletingLastPathComponent().lastPathComponent)
        let home = clean(FileManager.default.homeDirectoryForCurrentUser.lastPathComponent)
        if folder.isEmpty || folder == home { return file.isEmpty ? "file" : file }
        if file.isEmpty { return folder }
        return "\(folder)-\(file)"
    }

    /// What the Add file form says under the path as it is typed: is a file there, and what Add will do.
    struct PathCheck: Equatable {
        enum Kind {
            case empty, found, absent, folder, tooBig, relative
            /// Whether Add can go ahead: a file that is there, or one that is not there yet.
            var canAdd: Bool { self == .found || self == .absent }
        }
        var kind: Kind
        var text: String
    }

    func checkNewFilePath() -> PathCheck {
        let raw = newFilePath.trimmingCharacters(in: .whitespaces)
        if raw.isEmpty { return PathCheck(kind: .empty, text: "Type a path, press Choose…, or start from an example above.") }
        guard raw.hasPrefix("~") || raw.hasPrefix("/") else {
            return PathCheck(kind: .relative, text: "Start the path with ~ or /, as in ~/project/.env.")
        }
        let path = NSString(string: raw).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            return PathCheck(kind: .absent, text: "Nothing is there yet. Add saves the pointer; press Store once the file exists.")
        }
        if isDir.boolValue { return PathCheck(kind: .folder, text: "That is a folder. Pick the one file inside it.") }
        let size = ((try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber)?.intValue ?? 0
        if size > FileSecrets.maxBytes { return PathCheck(kind: .tooBig, text: "That file is \(size) bytes; a credential file is at most \(FileSecrets.maxBytes).") }
        return PathCheck(kind: .found, text: "Found, \(size) bytes. Add stores its contents in your Keychain now.")
    }

    /// What a state means and what to press, in one line each: the legend of the files list.
    static func advice(for state: FileSecrets.State?) -> String {
        guard let state else { return "The Keychain copy could not be read." }
        switch state {
        case .wrongMode: return "Contents match, but other users could read the file. Press Fix mode."
        case .differs: return "The file changed since it was stored. Store keeps the file's version; Restore puts the Keychain's back."
        case .notOnDisk: return "Stored in the Keychain, but the file is not at its path. Press Restore to write it."
        case .notStored: return "The file exists but is not in the Keychain yet. Press Store."
        default: return state.advice
        }
    }

    static let fileStates: [FileSecrets.State] = [.inSync, .notStored, .notOnDisk, .differs, .wrongMode, .missing]

    /// What can be done to a credential file in each state: the one place that rule lives.
    enum FileAction: Hashable {
        case store, restore, fixMode
        var title: String {
            switch self {
            case .store: "Store"
            case .restore: "Restore"
            case .fixMode: "Fix mode"
            }
        }
    }

    static func fileActions(for state: FileSecrets.State?) -> [FileAction] {
        switch state {
        case .notStored: [.store]
        case .notOnDisk: [.restore]
        case .differs: [.store, .restore]
        case .wrongMode: [.fixMode]
        default: []
        }
    }

    func perform(_ action: FileAction, on name: String) {
        switch action {
        case .store: storeFile(name)
        case .restore, .fixMode: restoreFile(name)
        }
    }

    // MARK: the secret and file sheets

    func openSecretSheet(named name: String = "") {
        newSecretName = name
        newSecretValue = ""
        secretSheetOpen = true
    }

    /// Cancel: the typed value goes with the sheet.
    func closeSecretSheet() {
        newSecretValue = ""
        secretSheetOpen = false
    }

    /// Save, and close when it went in.
    func saveSecretFromSheet() {
        saveSecret()
        if secretsNote?.ok == true { secretSheetOpen = false }
    }

    func openFileSheet() {
        newFileName = ""
        newFilePath = ""
        fileSheetOpen = true
    }

    /// "12 runs · 10 ok · 2 failed"
    var historySummary: String {
        guard !history.isEmpty else { return "" }
        let ok = history.filter { $0.code == 0 }.count
        return "\(history.count) run\(history.count == 1 ? "" : "s") · \(ok) ok · \(history.count - ok) failed"
    }

    // MARK: commands

    /// A command to start from: the form filled in, to change rather than to invent.
    struct CommandExample: Identifiable {
        var title: String
        var teaches: String
        var symbol: String
        var draft: Draft
        var id: String { title }
    }

    private static func draft(_ fill: (inout Draft) -> Void) -> Draft {
        var d = Draft()
        fill(&d)
        return d
    }

    static let commandExamples: [CommandExample] = [
        CommandExample(title: "A plain command", teaches: "Just a name and a shell line.", symbol: "play", draft: draft {
            $0.name = "brew-outdated"; $0.run = "brew outdated --verbose"; $0.desc = "what Homebrew would upgrade"; $0.group = "mac"
        }),
        CommandExample(title: "Asks for a value", teaches: "{formula} in the run line becomes a field; ! makes it required.", symbol: "slider.horizontal.3", draft: draft {
            $0.name = "brew-upgrade"; $0.run = "brew upgrade {formula}"; $0.desc = "upgrade one formula"; $0.group = "mac"
            $0.params = "formula:the formula to upgrade!"
        }),
        CommandExample(title: "Runs in a folder", teaches: "Working directory is where it runs; a parameter can have a default.", symbol: "folder", draft: draft {
            $0.name = "git-log"; $0.run = "git log --oneline -n {count}"; $0.desc = "the last commits of a repository"; $0.group = "git"
            $0.cwd = "~/Developer/my-project"; $0.params = "count:how many=10"
        }),
        CommandExample(title: "Needs a terminal", teaches: "Turn on Needs a terminal for a program that draws a screen or asks questions.", symbol: "terminal", draft: draft {
            $0.name = "top-cpu"; $0.run = "top -o cpu"; $0.desc = "what is using the processor"; $0.group = "mac"; $0.interactive = "yes"
        }),
        CommandExample(title: "Uses a secret token", teaches: "TOKEN=keychain:gitlab-token reads the value from the Keychain at run time. Add the value in Secrets.", symbol: "key", draft: draft {
            $0.name = "gitlab-pipelines"; $0.run = "curl -s -H \"PRIVATE-TOKEN: $TOKEN\" https://gitlab.com/api/v4/projects/{project}/pipelines"
            $0.desc = "a project's pipelines, through the API"; $0.group = "work"
            $0.params = "project:the project id!"; $0.env = "TOKEN=keychain:gitlab-token"
        }),
        CommandExample(title: "Uses a whole .env", teaches: "Env file names a .env stored in Secrets › Add file. Its entries become the environment; the file is never written to disk.", symbol: "doc.text", draft: draft {
            $0.name = "run-report"; $0.run = "uv run report.py"; $0.desc = "the report, with the project's settings"; $0.group = "work"
            $0.cwd = "~/Developer/my-project"; $0.envFile = "keychain:my-project-env"
        }),
        CommandExample(title: "Runs on a schedule", teaches: "Schedule is a phrase: weekdays 08:30, every 15m, daily 09:00. It runs with the window closed.", symbol: "clock", draft: draft {
            $0.name = "morning-sync"; $0.run = "git pull --ff-only"; $0.desc = "pull the project every weekday morning"; $0.group = "git"
            $0.cwd = "~/Developer/my-project"; $0.schedule = "weekdays 08:30"
        }),
        CommandExample(title: "Asks before it runs", teaches: "Touch ID or your password before every run: for deploys and deletes.", symbol: "lock", draft: draft {
            $0.name = "deploy-production"; $0.run = "make deploy"; $0.desc = "ship to production"; $0.group = "work"
            $0.cwd = "~/Developer/my-project"; $0.gate = "yes"
        }),
    ]

    func use(_ example: CommandExample) {
        clearRegistryNote()
        draft = example.draft
        exampleNote = example.teaches
    }

    static let scheduleExamples: [(phrase: String, means: String)] = [
        ("every 15m", "every fifteen minutes"), ("hourly", "on the hour"), ("daily 09:00", "every day at nine"),
        ("weekdays 08:30", "Monday to Friday"), ("weekends 10:00", "Saturday and Sunday"),
        ("mon,thu 18:00", "the days named"), ("monthly 1 07:00", "the first of the month"),
    ]

    /// The `.env` files a command's Env file can pick: the registry's files, and the draft's own choice when
    /// it names something else, so an existing value is never dropped by opening the form.
    var envFileChoices: [(tag: String, label: String)] {
        var out = [(tag: "", label: "None")]
        let names = registry?.files.map(\.name) ?? []
        for n in names { out.append((EnvValue.keychainPrefix + n, n)) }
        let current = draft.envFile.trimmingCharacters(in: .whitespaces)
        if !current.isEmpty, !out.contains(where: { $0.tag == current }) {
            let bare = current.hasPrefix(EnvValue.keychainPrefix) ? String(current.dropFirst(EnvValue.keychainPrefix.count)) : current
            out.append((current, bare + (formSecretNames.contains(bare) ? " (a secret, not a file)" : " (not stored yet)")))
        }
        return out
    }

    /// Adds `NAME=keychain:name` to the draft's environment: `gitlab-token` becomes `GITLAB_TOKEN`.
    func insertSecret(_ name: String) {
        let key = String(name.uppercased().map { $0.isLetter || $0.isNumber ? $0 : "_" })
        let entry = "\(key.first?.isNumber == true ? "_" + key : key)=\(EnvValue.keychainPrefix)\(name)"
        let existing = draft.env.trimmingCharacters(in: .whitespaces)
        draft.env = existing.isEmpty ? entry : existing + (existing.hasSuffix(";") ? " " : "; ") + entry
    }

    /// The block the form would write, or what is wrong with it, as the form is filled in. Never saved from here.
    struct DraftPreview: Equatable {
        var ok: Bool
        var text: String
        var fix: String = ""
    }

    var draftPreview: DraftPreview {
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty && draft.run.trimmingCharacters(in: .whitespaces).isEmpty {
            return DraftPreview(ok: false, text: "Give it a name and a run line, or start from an example.")
        }
        do {
            let c = try RegistryWriter.build(
                name: draft.name, run: draft.run, desc: draft.desc, group: draft.group, cwd: draft.cwd,
                interactive: try RegistryWriter.parseBool(draft.interactive, name: "interactive"),
                gate: try RegistryWriter.parseBool(draft.gate, name: "gate"),
                tags: RegistryWriter.parseTags(draft.tags), env: try RegistryWriter.parseEnvs(draft.env),
                params: try RegistryWriter.parseParams(draft.params), schedule: draft.schedule, envFile: draft.envFile)
            return DraftPreview(ok: true, text: RegistryWriter.render(c).trimmingCharacters(in: .newlines))
        } catch let e as RegistryError {
            return DraftPreview(ok: false, text: e.what, fix: e.fix)
        } catch {
            return DraftPreview(ok: false, text: "\(error)")
        }
    }
}
