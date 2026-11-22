import AppKit
import Foundation
import Observation
import Registry
import Runner
import Scheduler
import Secrets

/// Everything the window shows: the registry and its error, the filter and selection, the current run
/// and its lines, the history, the secrets screen. One instance, injected into the
/// environment; no `@State`.
@MainActor
@Observable
final class AppModel {
    // MARK: registry
    let registryURL: URL
    /// The team's commands.toml, merged in behind the person's own when it is there (Registry/Team.swift).
    let teamURL: URL
    var teamDirectory: URL { teamURL.deletingLastPathComponent() }
    private(set) var registry: Registry?
    private(set) var loadError: RegistryError?

    // MARK: picking
    var filter = ""
    private(set) var selected: String?

    // MARK: a run, the history
    private(set) var run: RunState?
    private(set) var history: [HistoryEntry]
    private var historyWatcher: FileWatcher?

    // MARK: schedules: launchd agents kept in step with the registry
    let scheduler: Scheduler
    private(set) var pausedNames: Set<String> = []
    private(set) var agentStatus: [String: Scheduler.Status] = [:]
    private(set) var schedulerNote: Note?

    // MARK: the window
    /// What the sidebar shows: every command, one group, the secrets, or the history.
    enum Destination: Hashable {
        case all
        case group(String)
        case scheduled
        case team
        case tools
        case secrets
        case history
    }
    var destination: Destination = .all

    enum DetailTab: String, CaseIterable, Identifiable {
        case output = "Output", terminal = "Terminal", history = "History", log = "Log"
        var id: String { rawValue }
    }
    var detailTab: DetailTab = .output

    /// The selected command's parameter values as the detail's form holds them; reset on selection.
    var paramValues: [String: String] = [:]
    var secretSheetOpen = false
    /// The "?" popover of the screen that is showing (Tools, Secrets, History).
    var helpOpen = false
    var aboutOpen = false

    func commands(in destination: Destination) -> [Command] {
        let base = registry?.filtered(filter) ?? []
        if case .group(let g) = destination { return base.filter { $0.group == g } }
        if destination == .scheduled { return base.filter { $0.schedule != nil } }
        if destination == .team { return base.filter { $0.origin == .team } }
        return base
    }

    func count(in group: String) -> Int { registry?.commands.filter { $0.group == group }.count ?? 0 }

    func history(for name: String) -> [HistoryEntry] { history.filter { $0.name == name } }

    func resetParams() {
        paramValues = [:]
        for p in selectedCommand?.params ?? [] { paramValues[p.name] = p.defaultValue ?? "" }
    }

    /// Run the selected command with the detail's parameter values (Run, ⌘↩).
    func runSelected() {
        guard let c = selectedCommand else { return }
        registryNote = nil
        start(c, params: c.params.isEmpty ? [:] : paramValues)
        detailTab = c.interactive ? .terminal : .output
    }

    // MARK: a new or edited command (⌘N, ⌘E), a delete (⌘⌫)
    private(set) var newCommandOpen = false
    /// The command the open form edits; nil when the form adds.
    private(set) var editingName: String?
    var isEditing: Bool { editingName != nil }
    /// The command a delete confirmation is open for.
    private(set) var pendingDelete: String?
    var draft = Draft()
    /// Whether the registry's folder is a git repository, asked once when the form opens (never from a view).
    private(set) var registryIsRepository = false
    private(set) var registryNote: Note?
    /// What the example just loaded into the form teaches; cleared when the form opens or closes.
    var exampleNote: String?
    /// The team command the open form is a copy of; nil for a new command or an edit.
    private(set) var copyOf: String?
    /// That team command's schedule: a suggestion the form offers as a switch that starts off
    /// (DECISIONS local-037). Copying never arms a schedule by itself.
    private(set) var suggestedSchedule: Schedule?
    /// The secret names in the Keychain when the form opened (attributes only), for its Insert secret menu.
    private(set) var formSecretNames: [String] = []

    /// What the ⌘N form holds: text, parsed and validated only when saved, by the same writer the CLI uses.
    struct Draft: Equatable {
        var name = "", run = "", desc = "", group = "", cwd = "", params = "", env = "", envFile = "", tags = "", interactive = "no", gate = "no", schedule = ""
        init() {}
        /// The form's text for an existing command, in the same notation the fields take.
        init(_ c: Command) {
            name = c.name
            run = c.run
            desc = c.desc
            group = c.group
            cwd = c.cwd ?? ""
            params = RegistryWriter.paramsSpec(c.params)
            env = RegistryWriter.envSpec(c.env)
            envFile = c.envFile.map { EnvValue.keychainPrefix + $0 } ?? ""
            tags = c.tags.joined(separator: ", ")
            interactive = c.interactive ? "yes" : "no"
            gate = c.gate ? "yes" : "no"
            // A team command's schedule is not copied: the form offers it as a switch that starts off.
            schedule = c.schedule?.text ?? ""
        }
        static let fields = ["name", "run", "desc", "group", "cwd", "params", "env", "env_file", "tags", "interactive", "gate", "schedule"]
        static let hints: [String: String] = [
            "name": "caffeinate", "run": "caffeinate -dimsu", "desc": "what it does, in a few words", "group": "mac",
            "cwd": "~ or a path; {param} allowed", "params": "seconds:how long=3600!  ·  more separated by ;",
            "env": "TOKEN=keychain:name; PAGER=cat", "env_file": "keychain:name · a whole .env from the Keychain, never on disk", "tags": "a, b", "interactive": "yes if it needs a terminal", "gate": "yes to ask for Touch ID",
            "schedule": "weekdays 08:30 · every 15m · daily 09:00 · empty: only when asked",
        ]
        subscript(field: String) -> String {
            get {
                switch field {
                case "name": name
                case "run": run
                case "desc": desc
                case "group": group
                case "cwd": cwd
                case "params": params
                case "env": env
                case "env_file": envFile
                case "tags": tags
                case "interactive": interactive
                case "gate": gate
                default: schedule
                }
            }
            set {
                switch field {
                case "name": name = newValue
                case "run": run = newValue
                case "desc": desc = newValue
                case "group": group = newValue
                case "cwd": cwd = newValue
                case "params": params = newValue
                case "env": env = newValue
                case "env_file": envFile = newValue
                case "tags": tags = newValue
                case "interactive": interactive = newValue
                case "gate": gate = newValue
                default: schedule = newValue
                }
            }
        }
    }

    // MARK: tools (AppModel+Tools.swift): what the registry lists, and what the last look found of each
    var toolStatus: [String: ToolStatus] = [:]
    /// When the package managers were last asked what is behind; nil until someone looks.
    var toolsCheckedAt: Date?
    var toolsBusy = false
    /// The sheet over an install or update run.
    var toolRunOpen = false
    /// What the current or last tools run is doing, for the history: "install ripgrep, jq".
    var toolsRunSummary = ""
    /// The add-a-tool form, a sheet.
    var toolDraft = ToolDraft()
    var toolSheetOpen = false
    /// What the last add or remove of a tool said.
    var toolNote: Note?

    struct ToolDraft: Equatable {
        var name = "", method = "brew", pkg = "", bin = "", desc = "", install = "", update = "", requires = ""
    }

    // MARK: secrets
    let secrets: SecretStore
    let credentialProfiles: CredentialProfiles
    private(set) var secretRows: [SecretRow] = []
    var secretsNote: Note?
    var newSecretName = ""
    var newSecretValue = ""
    var rotatingSecret = false

    // MARK: credential files, kept whole in the Keychain
    private(set) var fileRows: [FileRow] = []
    var newFileName = ""
    var newFilePath = ""
    var fileSheetOpen = false
    /// The file a restore would overwrite, while the window asks first.
    private(set) var pendingRestore: String?
    var files: FileSecrets { FileSecrets(store: secrets) }

    private let store: HistoryStore
    private var watcher: FileWatcher?
    private var process: ProcessRun?

    enum RunStatus: Equatable {
        case gating
        /// Waiting on the Keychain for the run's secrets: macOS may be asking the person to allow it.
        case unlocking
        case running
        case done(code: Int32, seconds: Double)
        case failed(what: String, fix: String)
    }

    struct RunState: Equatable {
        /// Which run this is: an answer that arrives late (the Keychain, the process) is matched against it.
        var id = UUID()
        var name: String
        var run: String
        var cwd: String?
        var interactive: Bool
        var env: [String: String] = [:]
        var redact: [String] = []
        var lines: [String] = []
        var status: RunStatus = .running
        var startedAt = Date()
        var isDone: Bool { if case .done = status { true } else { false } }
    }

    /// A secret as the screen lists it: in the Keychain, named by the registry, or both.
    struct SecretRow: Equatable, Identifiable {
        var name: String
        var inKeychain: Bool
        var usedBy: [String]
        var id: String { name }
    }

    /// A `[[file]]` entry as the screen lists it: where it belongs and how the Keychain copy compares. Never its contents.
    struct FileRow: Equatable, Identifiable {
        var name: String
        var path: String
        var mode: String
        var state: FileSecrets.State?
        /// Why the state could not be read, when it could not.
        var problem: String = ""
        var usedBy: [String]
        var id: String { name }
    }

    struct Note: Equatable {
        var ok: Bool
        var text: String
        var fix: String = ""
    }

    init(registryURL: URL = Registry.defaultURL(), teamURL: URL? = nil, store: HistoryStore = HistoryStore(),
         secrets: SecretStore = SecretStore(), scheduler: Scheduler? = nil, watch: Bool = true,
         preferences: UserDefaults = .standard) {
        self.registryURL = registryURL
        self.teamURL = teamURL ?? Registry.teamURL(for: registryURL)
        self.watching = watch
        self.store = store
        self.secrets = secrets
        credentialProfiles = CredentialProfiles(registryURL: registryURL, service: secrets.service, preferences: preferences)
        self.scheduler = scheduler ?? Scheduler(program: Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
        self.history = store.load()
        reload()
        if watch {
            watcher = FileWatcher(path: registryURL.path) { [weak self] in self?.reload() }
            historyWatcher = FileWatcher(path: store.url.path) { [weak self] in self?.reloadHistory() }
            teamStatus = TeamSync.status(teamDirectory)
            watchTeam()
            startUpdateChecks()
            refreshTools()
        }
    }

    /// Fixed state for `--snapshot` and tests: rows and a run as if a look and a run had happened.
    /// The window never calls it.
    func stage(secretRows: [SecretRow]? = nil, fileRows: [FileRow]? = nil, run: RunState? = nil) {
        if let secretRows { self.secretRows = secretRows; staged = true }
        if let fileRows { self.fileRows = fileRows; staged = true }
        if let run { self.run = run; selected = run.name; resetParams() }
    }

    // MARK: derived

    var commands: [Command] { registry?.filtered(filter) ?? [] }
    var selectedCommand: Command? { selected.flatMap { name in registry?.command(named: name) } }
    var groups: [String] { registry?.groups ?? [] }
    var shellName: String { URL(fileURLWithPath: ProcessRun.defaultShell()).lastPathComponent }

    /// The commands whose environment names this secret.
    func users(of secret: String) -> [String] {
        registry?.commands.filter { $0.secretNames.contains(secret) }.map(\.name) ?? []
    }

    // MARK: registry

    func reload() {
        do {
            try ensureRegistryFile()
            registry = try Registry.loadAll(from: registryURL, team: teamURL)
            loadError = nil
            syncSchedules()
        } catch let e as RegistryError {
            loadError = e            // the last good registry stays on screen under the error
        } catch {
            loadError = RegistryError("could not read \(registryURL.path): \(error.localizedDescription)")
        }
        clampSelection()
        if destination == .secrets { refreshSecrets() }
        // A tool that just arrived, from the file or the team, has no status yet: look.
        if watching, Set(registry?.tools.map(\.name) ?? []) != Set(toolStatus.keys) { refreshTools() }
    }

    /// After a write: the person's file as the writer left it, with the team's behind it again.
    private func adopt(_ personal: Registry) {
        registry = (try? Registry.loadAll(from: registryURL, team: teamURL)) ?? personal
        loadError = nil
    }

    /// A fresh install starts from the example that ships with the app.
    private func ensureRegistryFile() throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: registryURL.path) else { return }
        try fm.createDirectory(at: registryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Registry.exampleTOML().write(to: registryURL, atomically: true, encoding: .utf8)
    }

    // MARK: picking

    func clampSelection() {
        let names = commands(in: destination).map(\.name)
        if let s = selected, names.contains(s) { return }
        selected = names.first
        resetParams()
    }

    func select(_ name: String) {
        guard selected != name else { return }
        selected = name
        resetParams()
    }

    /// ↑ and ↓ in the list: the selection moves within what is shown.
    func moveSelection(_ delta: Int) {
        let names = commands(in: destination).map(\.name)
        guard !names.isEmpty else { return }
        let i = selected.flatMap { names.firstIndex(of: $0) } ?? 0
        select(names[min(max(i + delta, 0), names.count - 1)])
    }

    // MARK: running

    func start(_ c: Command, params: [String: String]) {
        let registry = self.registry ?? Registry(url: registryURL, commands: [])   // resolving needs no registry
        let resolved: Resolved
        do {
            resolved = try registry.resolve(c, params: params)
        } catch let e as RegistryError {
            run = RunState(name: c.name, run: "", cwd: nil, interactive: false, status: .failed(what: e.what, fix: e.fix))
            return
        } catch {
            run = RunState(name: c.name, run: "", cwd: nil, interactive: false, status: .failed(what: "\(error)", fix: ""))
            return
        }
        run = RunState(name: c.name, run: resolved.run, cwd: resolved.cwd, interactive: resolved.interactive,
                       status: resolved.gate ? .gating : .running)
        guard resolved.gate else {
            launch(c, resolved)
            return
        }
        Task { @MainActor [weak self] in
            let outcome = await Gate.ask("run \(c.name)")
            guard let self, let r = self.run, r.name == c.name, r.status == .gating else { return }
            switch outcome {
            case .allowed:
                self.launch(c, resolved)
            case .cancelled:
                self.run?.status = .failed(what: "\(c.name) did not run: Touch ID was cancelled", fix: "")
            case .failed(let why):
                self.run?.status = .failed(what: "\(c.name) did not run: \(why)", fix: "")
            }
        }
    }

    /// A run whose line is taken as it is, with no `{parameter}` to fill: a tool's installer may hold any braces.
    func startAsIs(name: String, run line: String, interactive: Bool) {
        run = RunState(name: name, run: line, cwd: nil, interactive: interactive, status: .running)
        launch(Command(name: name, group: "the-great-gui", run: line, interactive: interactive), Resolved(name: name, run: line, interactive: interactive))
    }

    /// Secrets into the environment, then the process. Any secret value is also what the output redacts.
    /// The Keychain is read off the main thread (DECISIONS local-035): macOS may put up a dialog and wait
    /// for the person, and the window must stay live while it does.
    private func launch(_ c: Command, _ resolved: Resolved) {
        guard !resolved.secretNames.isEmpty else {
            begin(resolved, RunEnvironment.Built(env: resolved.env.compactMapValues { if case .literal(let s) = $0 { s } else { nil } }))
            return
        }
        guard let id = run?.id else { return }
        run?.status = .unlocking
        let secrets = self.secrets
        Task.detached(priority: .userInitiated) { [weak self] in
            let outcome: Result<RunEnvironment.Built, RunEnvironment.Refusal>
            do {
                outcome = .success(try RunEnvironment.build(resolved, secrets: secrets))
            } catch let e as RunEnvironment.Refusal {
                outcome = .failure(e)
            } catch {
                outcome = .failure(RunEnvironment.Refusal(what: "\(error)", fix: ""))
            }
            await self?.unlocked(id, resolved, outcome)
        }
    }

    /// The Keychain answered. A run that was replaced or dismissed meanwhile is left alone.
    private func unlocked(_ id: UUID, _ resolved: Resolved, _ outcome: Result<RunEnvironment.Built, RunEnvironment.Refusal>) {
        guard run?.id == id, run?.status == .unlocking else { return }
        switch outcome {
        case .success(let built): begin(resolved, built)
        case .failure(let e): run?.status = .failed(what: e.what, fix: e.fix)
        }
    }

    private func begin(_ resolved: Resolved, _ built: RunEnvironment.Built) {
        let env = built.env
        let redact = built.redact
        run?.env = env
        run?.redact = redact
        run?.startedAt = Date()
        run?.status = .running
        if resolved.interactive { return }   // the terminal pane starts the process when it appears
        let p = ProcessRun(run: resolved.run, cwd: resolved.cwd, env: env, redact: redact) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        do {
            try p.start()
            process = p
        } catch {
            run?.status = .failed(what: "could not start: \(error.localizedDescription)", fix: "does \(resolved.cwd ?? "the directory") exist?")
        }
    }

    private func handle(_ event: ProcessRun.Event) {
        switch event {
        case .started:
            break
        case .line(let line):
            run?.lines.append(line)
        case .exited(let code, let seconds):
            finish(code: code, seconds: seconds, mode: "run")
        }
    }

    /// The terminal pane reports the shell's exit.
    func finishInteractive(code: Int32?) {
        guard let r = run, r.interactive, r.status == .running else { return }
        finish(code: code ?? -1, seconds: (Date().timeIntervalSince(r.startedAt) * 10).rounded() / 10, mode: "tty")
        if r.name == Self.updateName, code == 0 { relaunch() }
    }

    private func finish(code: Int32, seconds: Double, mode: String) {
        guard var r = run else { return }
        r.status = .done(code: code, seconds: seconds)
        run = r
        process = nil
        let ranTools = r.name == Self.toolsRunName
        history = store.append(HistoryEntry(name: r.name, run: ranTools ? toolsRunSummary : r.run, cwd: r.cwd, mode: mode, code: code, seconds: seconds, startedAt: r.startedAt))
        if ranTools { refreshTools(outdated: toolsCheckedAt != nil) }
    }

    /// A scheduled run, or a shell run, landed in the history file.
    func reloadHistory() { history = store.load() }

    // MARK: schedules

    /// The agents follow the registry: written, loaded, unloaded or removed as needed; paused ones stay unloaded.
    func syncSchedules() {
        guard let registry else { return }
        let report = scheduler.sync(registry)
        pausedNames = scheduler.paused()
        var status: [String: Scheduler.Status] = [:]
        for c in registry.commands where c.schedule != nil { status[c.name] = scheduler.status(c.name) }
        agentStatus = status
        schedulerNote = report.problems.isEmpty ? nil : Note(ok: false, text: report.problems.joined(separator: " · "), fix: "great-gui schedule shows the agents")
        if !status.isEmpty { Notifier.requestAuthorizationIfNeeded() }
    }

    var scheduled: [Command] { registry?.commands.filter { $0.schedule != nil } ?? [] }
    func isPaused(_ name: String) -> Bool { pausedNames.contains(name) }
    func lastRun(of name: String) -> HistoryEntry? { history.first { $0.name == name } }
    func nextRun(of c: Command) -> Date? { scheduler.nextRun(for: c, lastRun: lastRun(of: c.name)?.startedAt) }
    func lastLog(of name: String) -> String? { scheduler.lastLog(for: name) }
    func revealLog(of name: String) { NSWorkspace.shared.activateFileViewerSelecting([scheduler.logURL(for: name)]) }

    /// "weekdays at 08:30 · next Tue 08:30 · last 2h ago, exit 0", or "… · paused".
    func scheduleLine(for c: Command) -> String? {
        guard let s = c.schedule else { return nil }
        var parts = [s.english]
        if isPaused(c.name) {
            parts.append("paused")
        } else if let n = nextRun(of: c) {
            parts.append("next " + Scheduler.when(n))
        } else if case .interval = s.kind {
            let span = String(s.english.dropFirst("every ".count))
            parts.append("first run within " + (span == "minute" ? "a minute" : span == "hour" ? "an hour" : span))
        }
        if let last = lastRun(of: c.name) { parts.append("last \(HistoryStore.relative(last.startedAt)), exit \(last.code)") }
        if let st = agentStatus[c.name], !st.loaded, !isPaused(c.name) { parts.append("agent not loaded") }
        return parts.joined(separator: " · ")
    }

    func togglePause(_ name: String) {
        guard let registry else { return }
        do {
            if isPaused(name) { try scheduler.resume(name, in: registry) } else { try scheduler.pause(name, in: registry) }
            pausedNames = scheduler.paused()
            agentStatus[name] = scheduler.status(name)
            registryNote = Note(ok: true, text: "\(name) \(isPaused(name) ? "paused" : "resumed")")
        } catch let e as RegistryError {
            registryNote = Note(ok: false, text: e.what, fix: e.fix)
        } catch {
            registryNote = Note(ok: false, text: "\(error)")
        }
    }

    func togglePauseSelected() {
        if let s = selected { togglePause(s) }
    }

    func terminate() { process?.terminate() }

    func dismissRun() { run = nil }

    // MARK: the new-command form

    func openNewCommand() {
        registryNote = nil
        pendingDelete = nil
        editingName = nil
        copyOf = nil
        suggestedSchedule = nil
        draft = Draft()
        if let g = selectedCommand?.group { draft.group = g }
        registryIsRepository = RegistryWriter.isRepository(registryURL)
        prepareForm()
        newCommandOpen = true
    }

    func useCredentialProfileInDraft(_ profile: CredentialProfile) {
        do {
            var environment = try RegistryWriter.parseEnvs(draft.env)
            for (key, value) in try profile.environment() {
                if let current = environment[key], current != value {
                    throw RegistryError("The command already sets \(key)", fix: "Clear or reconcile it before applying this profile.")
                }
                environment[key] = value
            }
            let file = profile.envFile.map { EnvValue.keychainPrefix + $0 }
            if let file, !draft.envFile.isEmpty, draft.envFile != file {
                throw RegistryError("The command already uses a different env file", fix: "Select the env file you want before saving.")
            }
            draft.env = RegistryWriter.envSpec(environment)
            if let file { draft.envFile = file }
            registryNote = profile.requiredLocalFile.map { name in
                Note(ok: true, text: "This client needs the \(name) file at its configured path", fix: "Use Check in Secrets to verify the local copy.")
            }
        } catch let error as RegistryError {
            registryNote = Note(ok: false, text: error.what, fix: error.fix)
        } catch {
            registryNote = Note(ok: false, text: "Could not apply the credential profile")
        }
    }

    /// The same form, filled from the command; Save rewrites its block.
    func openEditCommand(_ c: Command) {
        registryNote = nil
        pendingDelete = nil
        draft = Draft(c)
        // The team's command is read-only here: its form adds a copy to the person's own file, which wins.
        editingName = c.origin == .team ? nil : c.name
        registryIsRepository = RegistryWriter.isRepository(registryURL)
        prepareForm()
        copyOf = c.origin == .team ? c.name : nil
        suggestedSchedule = c.origin == .team ? c.teamSchedule : nil
        if c.origin == .team {
            exampleNote = "Your own copy of the team's \(c.name): it wins over theirs and no longer follows their changes."
        }
        newCommandOpen = true
    }

    func editSelected() {
        if let c = selectedCommand { openEditCommand(c) }
    }

    func closeNewCommand() {
        newCommandOpen = false
        editingName = nil
        exampleNote = nil
        copyOf = nil
        suggestedSchedule = nil
    }

    /// From the form to the Secrets screen with the right sheet open: the command form closes.
    func leaveFormForSecrets(file: Bool) {
        closeNewCommand()
        destination = .secrets
        if file { openFileSheet() } else { openSecretSheet() }
    }

    /// What the form's pick-lists offer, read once as it opens: names only, never a value.
    private func prepareForm() {
        exampleNote = nil
        let files = Set(registry?.files.map(\.name) ?? [])
        formSecretNames = ((try? secrets.names()) ?? []).filter { !files.contains($0) }
    }

    /// Validates the draft exactly as the loader would, then appends it to the file or rewrites the block
    /// it edits, commits when the folder is a repository, and selects the command. Errors stay in the form.
    func saveDraft() {
        do {
            let command = try RegistryWriter.build(
                name: draft.name, run: draft.run, desc: draft.desc, group: draft.group, cwd: draft.cwd,
                interactive: try RegistryWriter.parseBool(draft.interactive, name: "interactive"),
                gate: try RegistryWriter.parseBool(draft.gate, name: "gate"),
                tags: RegistryWriter.parseTags(draft.tags),
                env: try RegistryWriter.parseEnvs(draft.env),
                params: try RegistryWriter.parseParams(draft.params),
                schedule: draft.schedule,
                envFile: draft.envFile)
            let registry: Registry
            let message: String
            if let old = editingName {
                registry = try RegistryWriter.replace(old, with: command, in: registryURL)
                message = old == command.name ? "edit \(command.name)" : "rename \(old) to \(command.name)"
            } else {
                registry = try RegistryWriter.append(command, to: registryURL)
                message = "add \(command.name)"
                filter = ""
            }
            let committed = RegistryWriter.autoCommit(registryURL, message: message)
            let edited = editingName != nil
            adopt(registry)
            newCommandOpen = false
            editingName = nil
            copyOf = nil
            suggestedSchedule = nil
            if case .group(let g) = destination, g != command.group { destination = .group(command.group) }
            selected = command.name
            resetParams()
            var text = edited ? "\(command.name) saved" : "\(command.name) added · \(registry.commands.count) commands"
            if committed { text += " · committed" }
            if !command.secretNames.isEmpty { text += " · ⌘K adds " + command.secretNames.joined(separator: ", ") }
            registryNote = Note(ok: true, text: text)
        } catch let e as RegistryError {
            registryNote = Note(ok: false, text: e.what, fix: e.fix)
        } catch {
            registryNote = Note(ok: false, text: "\(error)")
        }
    }

    // MARK: updating the app (the app menu's Update…)

    static let updateName = "update-the-great-gui"

    /// The checkout this bundle was built in: build/the-great-gui.app sits two levels below its root.
    static var checkoutURL: URL? {
        let root = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.appendingPathComponent("Makefile").path),
              fm.fileExists(atPath: root.appendingPathComponent("scripts/update.sh").path) else { return nil }
        return root
    }

    private(set) var updateOpen = false

    // MARK: is there a newer version (looked for once a day; nothing installs until Update… is pressed)
    private(set) var updateAvailable: UpdateInfo?
    private(set) var updateCheckedAt: Date?
    /// Why the last look could not tell, when it could not.
    private(set) var updateCheckProblem: String?
    private(set) var checkingForUpdate = false
    private var activeObserver: NSObjectProtocol?

    /// A look now, and again whenever the app comes forward and the last look is a day old.
    private func startUpdateChecks() {
        checkForUpdateIfDue()
        activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkForUpdateIfDue() }
        }
    }

    private func checkForUpdateIfDue() {
        guard UpdateCheck.enabled else { return }
        if teamCheckedAt.map({ Date().timeIntervalSince($0) >= UpdateCheck.interval }) ?? true { syncTeam(quiet: true) }
        // The daily look also asks the package managers what is behind. It runs nothing the registry names.
        if toolsCheckedAt.map({ Date().timeIntervalSince($0) >= UpdateCheck.interval }) ?? true { refreshTools(outdated: true, versions: false) }
        if let last = updateCheckedAt, Date().timeIntervalSince(last) < UpdateCheck.interval { return }
        checkForUpdate()
    }

    /// Asks the remote whether it has moved, in the background. Settings and the app menu call it directly.
    func checkForUpdate() {
        guard let root = Self.checkoutURL, !checkingForUpdate else { return }
        checkingForUpdate = true
        updateCheckedAt = Date()
        Task.detached(priority: .utility) { [weak self] in
            let outcome = UpdateCheck.run(in: root)
            await self?.finishUpdateCheck(outcome)
        }
    }

    private func finishUpdateCheck(_ outcome: UpdateCheck.Outcome) {
        checkingForUpdate = false
        switch outcome {
        case .current: updateAvailable = nil; updateCheckProblem = nil
        case .behind(let info): updateAvailable = info; updateCheckProblem = nil
        case .unknown(let why): updateCheckProblem = why
        }
    }

    /// "up to date · checked 2h ago", for Settings.
    var updateStatus: String {
        if checkingForUpdate { return "checking…" }
        if Self.checkoutURL == nil { return "this build is not running from its checkout" }
        guard let at = updateCheckedAt else { return UpdateCheck.enabled ? "not checked yet" : "checks are off" }
        let when = "checked " + HistoryStore.relative(at)
        if let info = updateAvailable { return "\(info.words) available · \(when)" }
        if let why = updateCheckProblem { return "\(why) · \(when)" }
        return "up to date · \(when)"
    }
    /// True from the moment a successful update run ends until the app is gone.
    private(set) var relaunching = false

    /// `make update` in the checkout, as an interactive run: pull, rebuild, relink, then the script quits and
    /// reopens the app. The window holds it in a sheet.
    func update() {
        guard let root = Self.checkoutURL else {
            registryNote = Note(ok: false, text: "this build is not running from its checkout",
                                fix: "update where it was built: make update in the-great-gui, then open build/the-great-gui.app")
            return
        }
        if let r = run, r.status == .running {
            registryNote = Note(ok: false, text: "\(r.name) is running", fix: "let it finish or stop it (⌘.) before updating")
            return
        }
        newCommandOpen = false
        editingName = nil
        pendingDelete = nil
        registryNote = nil
        let c = Command(name: Self.updateName, group: "the-great-gui", desc: "pull, rebuild, reopen", run: "make update",
                        cwd: root.path, interactive: true, env: ["GREAT_GUI_UPDATE_FROM_APP": .literal("1")])
        start(c, params: [:])
        updateOpen = true
    }

    /// After a successful update run: a detached shell opens the rebuilt bundle a second from now, the sheet
    /// comes down, the app asks itself to quit, and exits outright if that is refused. The history is saved.
    private func relaunch() {
        relaunching = true
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1.5; open \"$0\"", Bundle.main.bundleURL.path]
        try? p.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.updateOpen = false
            NSApp.terminate(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { exit(0) }
    }

    func closeUpdate() {
        updateOpen = false
        if let r = run, r.name == Self.updateName, r.status != .running { run = nil }
    }

    // MARK: the team's registry (joined in Settings or with great-gui team join; followed by the daily look)

    let watching: Bool
    private var teamWatcher: FileWatcher?
    private var teamCheckedAt: Date?
    private(set) var teamStatus = TeamSync.Status(directory: URL(fileURLWithPath: "/"), joined: false, repository: false)
    private(set) var teamBusy = false
    /// What the last sync or join said, for Settings.
    private(set) var teamNote: Note?
    /// What the last sync brought, until it is dismissed: the window says what changed.
    private(set) var teamChange: TeamSync.Change?
    /// The address typed in Settings.
    var teamAddress = ""
    var leaveTeamAsked = false

    var teamCommandCount: Int { registry?.teamCommands.count ?? 0 }

    /// "12 commands · 2 overridden by yours · synced 3h ago", for Settings and the banner.
    var teamSummary: String {
        if teamBusy { return "working…" }
        guard teamStatus.joined else { return "not joined" }
        var parts = ["\(registry?.team?.commands ?? 0) commands"]
        if let n = registry?.team?.overridden.count, n > 0 { parts.append("\(n) overridden by yours") }
        if !teamStatus.repository { parts.append("a plain folder: it does not follow a remote") }
        else if let at = teamStatus.syncedAt { parts.append("synced " + HistoryStore.relative(at)) }
        return parts.joined(separator: " · ")
    }

    /// The team file is watched only once it exists, so a Mac with no team has no timer looking for it.
    private func watchTeam() {
        guard watching, teamWatcher == nil, FileManager.default.fileExists(atPath: teamURL.path) else { return }
        teamWatcher = FileWatcher(path: teamURL.path) { [weak self] in self?.reload() }
    }

    func dismissTeamChange() { teamChange = nil }

    func joinTeam() {
        let address = teamAddress
        teamWork { dir in TeamSync.join(address, into: dir) }
    }

    /// Follows the remote now. `quiet` is the daily look: it speaks only when something arrived.
    func syncTeam(quiet: Bool = false) {
        guard FileManager.default.fileExists(atPath: teamDirectory.path) else { return }
        teamWork(quiet: quiet) { dir in TeamSync.sync(dir) }
    }

    func leaveTeam() {
        leaveTeamAsked = false
        teamWatcher = nil
        teamWork { dir in TeamSync.leave(dir) }
    }

    private func teamWork(quiet: Bool = false, _ work: @escaping @Sendable (URL) -> TeamSync.Outcome) {
        guard !teamBusy else { return }
        teamBusy = true
        teamCheckedAt = Date()
        let dir = teamDirectory
        Task.detached(priority: .utility) { [weak self] in
            let outcome = work(dir)
            await self?.finishTeamWork(outcome, quiet: quiet)
        }
    }

    private func finishTeamWork(_ outcome: TeamSync.Outcome, quiet: Bool) {
        teamBusy = false
        teamStatus = TeamSync.status(teamDirectory)
        reload()
        watchTeam()
        switch outcome {
        case .notJoined:
            teamNote = nil
        case .current:
            teamNote = quiet ? teamNote : Note(ok: true, text: teamStatus.joined ? "up to date" : "left the team registry · the folder is in the Trash")
        case .updated(let change):
            if !change.isEmpty { teamChange = change }
            teamAddress = ""
            teamNote = Note(ok: true, text: change.words + (change.skills.isEmpty ? "" : " · skills: " + change.skills.joined(separator: ", ")),
                            fix: change.details.joined(separator: "\n"))
        case .failed(let what, let fix):
            teamNote = Note(ok: false, text: what, fix: fix)
        }
        if let problem = registry?.team?.problem { teamNote = Note(ok: false, text: problem.what, fix: problem.fix) }
    }

    // MARK: deleting (⌘⌫, asked first)

    func askDelete(_ name: String) {
        guard let c = registry?.command(named: name) else { return }
        guard c.origin == .personal else {
            registryNote = Note(ok: false, text: "\(name) is the team's and cannot be deleted here",
                                fix: "⌘E makes your own copy, which wins; Settings › Team leaves the team registry")
            return
        }
        registryNote = nil
        registryIsRepository = RegistryWriter.isRepository(registryURL)
        pendingDelete = name
    }

    func clearRegistryNote() { registryNote = nil }
    /// Says why something asked for outside a form did not happen: the window's alert.
    func refuse(_ what: String, fix: String) { registryNote = Note(ok: false, text: what, fix: fix) }

    func deleteSelected() {
        if let s = selected { askDelete(s) }
    }

    func cancelDelete() {
        pendingDelete = nil
    }

    /// Removes the block, commits, and selects the command that took its place in the list.
    func confirmDelete() {
        guard let name = pendingDelete else { return }
        pendingDelete = nil
        let shownBefore = commands(in: destination).map(\.name)
        let index = shownBefore.firstIndex(of: name) ?? 0
        do {
            let registry = try RegistryWriter.remove(name, from: registryURL)
            let committed = RegistryWriter.autoCommit(registryURL, message: "remove \(name)")
            adopt(registry)
            if case .group(let g) = destination, !registry.groups.contains(g) { destination = .all }
            let shown = commands(in: destination).map(\.name)
            selected = shown.isEmpty ? nil : shown[min(index, shown.count - 1)]
            resetParams()
            registryNote = Note(ok: true, text: "\(name) removed · \(registry.commands.count) commands" + (committed ? " · committed" : ""))
        } catch let e as RegistryError {
            registryNote = Note(ok: false, text: e.what, fix: e.fix)
        } catch {
            registryNote = Note(ok: false, text: "\(error)")
        }
    }

    // MARK: reordering (drag in the list)

    /// The shown commands move; everything else keeps its place in the file. Not while a filter hides rows.
    func moveCommands(from source: IndexSet, to target: Int) {
        guard filter.isEmpty else { return }
        let shown = commands(in: destination)
        let own = Set(shown.filter { $0.origin == .personal }.map(\.name))
        var after = shown.map(\.name)
        after.move(fromOffsets: source, toOffset: target)
        // Only the person's own commands have a place in their file; the team's follow them in the list.
        reorder(after.filter(own.contains), replacing: shown.map(\.name).filter(own.contains))
    }

    /// Writes the file with `names` in the positions `before` held, in the new order.
    private func reorder(_ names: [String], replacing before: [String]) {
        guard let all = registry?.personal.map(\.name), names != before else { return }
        let slots = all.indices.filter { before.contains(all[$0]) }
        guard slots.count == names.count else { return }
        var full = all
        for (k, i) in slots.enumerated() { full[i] = names[k] }
        do {
            let registry = try RegistryWriter.reorder(full, in: registryURL)
            let committed = RegistryWriter.autoCommit(registryURL, message: "reorder commands")
            adopt(registry)
            registryNote = Note(ok: true, text: "order saved" + (committed ? " · committed" : ""))
        } catch let e as RegistryError {
            registryNote = Note(ok: false, text: e.what, fix: e.fix)
        } catch {
            registryNote = Note(ok: false, text: "\(error)")
        }
    }

    // MARK: secrets screen

    func clearSecretsNote() { secretsNote = nil }

    /// Names in the Keychain and names the registry refers to, merged; never a value. The Keychain is asked
    /// off the main thread (comparing a file reads its stored copy, and macOS may put up a dialog), so the
    /// rows arrive a moment later and the window stays live meanwhile.
    func refreshSecrets() {
        guard !staged else { return }
        let secrets = self.secrets
        let entries = registry?.files ?? []
        secretsLook += 1
        let look = secretsLook
        Task.detached(priority: .userInitiated) { [weak self] in
            var names: Set<String> = []
            var problem: String?
            do { names = Set(try secrets.names()) } catch { problem = "\(error)" }
            let files = FileSecrets(store: secrets)
            var states: [String: Result<FileSecrets.State, SecretsLookFailure>] = [:]
            for f in entries {
                do {
                    states[f.name] = .success(try files.state(name: f.name, path: f.expandedPath, mode: f.modeBits))
                } catch {
                    states[f.name] = .failure(SecretsLookFailure(text: "\(error)".components(separatedBy: "\n")[0]))
                }
            }
            await self?.finishSecretsLook(look, names: names, problem: problem, states: states)
        }
    }

    struct SecretsLookFailure: Error, Sendable { var text: String }
    private var secretsLook = 0
    /// True once `stage` has given the rows: a snapshot or a test then never asks the Keychain.
    private var staged = false

    /// Only the newest look is taken: an older one that answers late is dropped.
    private func finishSecretsLook(_ look: Int, names inKeychain: Set<String>, problem: String?,
                                   states: [String: Result<FileSecrets.State, SecretsLookFailure>]) {
        guard look == secretsLook else { return }
        if let problem { secretsNote = Note(ok: false, text: problem) }
        let profileReferences = credentialProfiles.entries.flatMap { profile -> [String] in
            let environment = (try? profile.environment()) ?? [:]
            return environment.values.compactMap { value -> String? in
                if case .keychain(let name) = value { return name }
                return nil
            }
        }
        let referenced = Set((registry?.commands ?? []).flatMap(\.secretNames) + profileReferences)
        let entries = registry?.files ?? []
        let fileNames = Set(entries.map(\.name))
        // A file's Keychain item is listed with the files, not twice.
        secretRows = (inKeychain.union(referenced)).subtracting(fileNames).sorted().map { name in
            SecretRow(name: name, inKeychain: inKeychain.contains(name), usedBy: users(of: name))
        }
        fileRows = entries.map { f in
            var row = FileRow(name: f.name, path: f.path, mode: f.mode, usedBy: users(of: f.name))
            switch states[f.name] {
            case .success(let s): row.state = s
            case .failure(let e): row.problem = e.text
            case nil: break
            }
            return row
        }
    }

    // MARK: files

    private func fileNote(_ error: Error) {
        if let e = error as? RegistryError {
            secretsNote = Note(ok: false, text: e.what, fix: e.fix)
        } else if let e = error as? FileSecretError {
            secretsNote = Note(ok: false, text: e.what, fix: e.fix)
        } else {
            secretsNote = Note(ok: false, text: "\(error)")
        }
    }

    /// Adds the pointer to the registry (one block, committed like a command) and, when the file is there,
    /// stores its contents.
    func addFile() {
        let name = newFileName.trimmingCharacters(in: .whitespaces)
        do {
            let entry = try RegistryWriter.buildFile(name: name, path: RegistryWriter.portable(NSString(string: newFilePath.trimmingCharacters(in: .whitespaces)).expandingTildeInPath))
            let registry = try RegistryWriter.appendFile(entry, to: registryURL)
            let committed = RegistryWriter.autoCommit(registryURL, message: "add file \(entry.name)")
            adopt(registry)
            var text = "\(entry.name) added · \(entry.path)" + (committed ? " · committed" : "")
            if FileManager.default.fileExists(atPath: entry.expandedPath) {
                let kept = try files.keep(name: entry.name, from: entry.expandedPath)
                text += " · \(kept.bytes) bytes \(kept.replaced ? "replaced" : "stored") in the Keychain"
            } else {
                text += " · nothing at that path yet: Store once the file exists"
            }
            secretsNote = Note(ok: true, text: text)
            newFileName = ""
            newFilePath = ""
            newSecretName = ""
            fileSheetOpen = false
        } catch {
            fileNote(error)
        }
        refreshSecrets()
    }

    /// The file's contents into the Keychain, replacing the copy there.
    func storeFile(_ name: String) {
        guard let f = registry?.file(named: name) else { return }
        pendingRestore = nil
        do {
            let kept = try files.keep(name: f.name, from: f.expandedPath)
            secretsNote = Note(ok: true, text: "\(f.name) \(kept.replaced ? "replaced" : "stored") · \(kept.bytes) bytes from \(f.path)")
        } catch {
            fileNote(error)
        }
        refreshSecrets()
    }

    /// The Keychain copy onto its path. A file that differs is asked about first.
    func restoreFile(_ name: String) {
        guard let f = registry?.file(named: name) else { return }
        if fileRows.first(where: { $0.name == name })?.state == .differs {
            secretsNote = nil
            pendingRestore = name
            return
        }
        restore(f, force: false)
    }

    func confirmRestore() {
        guard let name = pendingRestore, let f = registry?.file(named: name) else { return }
        pendingRestore = nil
        restore(f, force: true)
    }

    func cancelRestore() { pendingRestore = nil }

    private func restore(_ f: SecretFile, force: Bool) {
        do {
            switch try files.restore(name: f.name, to: f.expandedPath, mode: f.modeBits, force: force) {
            case .written(let bytes): secretsNote = Note(ok: true, text: "\(f.name) written · \(bytes) bytes to \(f.path) · mode \(f.mode)")
            case .modeFixed: secretsNote = Note(ok: true, text: "\(f.name) unchanged · mode set to \(f.mode)")
            case .unchanged: secretsNote = Note(ok: true, text: "\(f.name) in sync")
            }
        } catch SecretStore.Failure.notFound {
            secretsNote = Note(ok: false, text: "\(f.name) is not in the Keychain on this Mac", fix: "Store keeps the file at \(f.path); a value never comes from another Mac")
        } catch {
            fileNote(error)
        }
        refreshSecrets()
    }

    /// Drops the pointer. The Keychain copy stays, listed as a plain secret, where Delete removes it; the file on disk is never touched.
    func removeFile(_ name: String) {
        pendingRestore = nil
        if registry?.file(named: name)?.team == true {
            secretsNote = Note(ok: false, text: "\(name) is on the team's checklist and cannot be removed here", fix: "Store keeps your copy of the file; the pointer follows the team")
            return
        }
        do {
            let registry = try RegistryWriter.removeFile(name, from: registryURL)
            let committed = RegistryWriter.autoCommit(registryURL, message: "remove file \(name)")
            adopt(registry)
            secretsNote = Note(ok: true, text: "\(name) is no longer a file here" + (committed ? " · committed" : "") + " · the file is untouched; its Keychain copy is listed with the secrets")
        } catch {
            fileNote(error)
        }
        refreshSecrets()
    }

    func saveSecret() {
        let name = newSecretName.trimmingCharacters(in: .whitespaces)
        guard SecretStore.isValidName(name) else {
            secretsNote = Note(ok: false, text: "'\(name)' is not a valid secret name", fix: "letters, digits, . _ and -")
            return
        }
        guard !newSecretValue.isEmpty else {
            secretsNote = Note(ok: false, text: "\(name) has no value", fix: "paste or type it in the value field")
            return
        }
        do {
            let replaced = try secrets.set(name, value: newSecretValue)
            let used = users(of: name)
            let usage = used.isEmpty ? "no command uses it yet" : "used by " + used.joined(separator: ", ")
            secretsNote = Note(ok: true, text: "\(name) \(replaced ? "replaced" : "saved") · \(usage)")
            newSecretName = ""
            newSecretValue = ""
            credentialProfiles.invalidateChecks()
            refreshSecrets()
        } catch {
            secretsNote = Note(ok: false, text: "\(error)")
        }
    }

    func deleteSecret(_ name: String) {
        do {
            try secrets.delete(name)
            credentialProfiles.invalidateChecks()
            secretsNote = Note(ok: true, text: "\(name) deleted")
            refreshSecrets()
        } catch {
            secretsNote = Note(ok: false, text: "\(error)")
        }
    }
}
