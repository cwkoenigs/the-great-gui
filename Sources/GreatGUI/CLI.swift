import Foundation
import Registry
import Runner
import Scheduler
import Secrets

/// `great-gui add|edit|remove|list|check|path|run|version|help`: the same registry, the same validation, no window.
/// The shim in bin/ runs this binary from the app bundle, so Keychain sees the same signed app.
enum CLI {
    static let subcommands: Set<String> = ["add", "edit", "remove", "rm", "list", "check", "path", "run", "schedule", "pause", "resume", "file", "files", "secrets", "secret", "exec", "update-check", "show", "history", "team", "tools", "tool",
                                           "version", "--version", "help", "--help", "-h"]

    @MainActor
    static func runIfRequested() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let first = args.first else { return }
        if subcommands.contains(first) { exit(main(args)) }
        // A word that is not a command must fail, not open a window: an agent with a typo would wait forever.
        // Arguments that start with a dash are the system's own (and --snapshot), and pass through.
        if !first.hasPrefix("-") {
            json = args.contains("--json")
            fail("unknown command \(first)", fix: "great-gui help lists the commands")
            exit(2)
        }
    }

    /// Set by `--json` on the commands that only report: their answer, and any error, is then one JSON object
    /// on stdout, for an agent to parse.
    nonisolated(unsafe) static var json = false
    /// Set by `--capture`: what the command printed, masked, stdout and stderr in the order they arrived.
    /// The newest `limit` bytes are kept (DECISIONS local-038).
    final class Capture: @unchecked Sendable {
        static let limit = 64 * 1024
        private let lock = NSLock()
        private var data = Data()
        private(set) var truncated = false

        func append(_ text: String) {
            lock.lock(); defer { lock.unlock() }
            data.append(Data(text.utf8))
            if data.count > Self.limit {
                data.removeFirst(data.count - Self.limit)
                truncated = true
            }
        }

        /// The kept text. When the front was cut it starts at a line, never in the middle of a character.
        var text: String {
            lock.lock(); defer { lock.unlock() }
            var kept = data
            if truncated, let nl = kept.firstIndex(of: 0x0A) { kept = kept.subdata(in: kept.index(after: nl)..<kept.endIndex) }
            return String(decoding: kept, as: UTF8.self)
        }

        /// The keys a result object gains.
        var fields: [String: Any] { ["output": text, "output_truncated": truncated] }
    }

    nonisolated(unsafe) static var capture: Capture?

    static let reporting: Set<String> = ["add", "edit", "remove", "rm", "run", "pause", "resume", "list", "check", "show", "file", "files", "schedule", "history", "secrets", "secret", "update-check", "team", "tools", "tool"]

    static func main(_ input: [String]) -> Int32 {
        var args = input
        if reporting.contains(args[0]), args.contains("--json") {
            json = true
            if args[0] != "secrets" && args[0] != "secret" { args.removeAll { $0 == "--json" } }
        }
        // exec carries someone else's command after --: only a --json before it is ours.
        if args[0] == "exec", let i = args.firstIndex(of: "--json"), i < (args.firstIndex(of: "--") ?? 0) {
            json = true
            args.remove(at: i)
        }
        // --capture (run, and exec before its --): the result object also carries what the command printed.
        if args[0] == "run" || args[0] == "exec", let i = args.firstIndex(of: "--capture"),
           args[0] == "run" || i < (args.firstIndex(of: "--") ?? 0) {
            args.remove(at: i)
            guard json else { fail("--capture goes with --json", fix: "great-gui \(args[0]) --json --capture …: the output is then in the result object as well as on stderr"); return 2 }
            capture = Capture()
        }
        switch args[0] {
        case "add": return add(Array(args.dropFirst()))
        case "edit": return edit(Array(args.dropFirst()))
        case "remove", "rm": return remove(Array(args.dropFirst()))
        case "schedule": return schedule(Array(args.dropFirst()))
        case "file", "files": return file(Array(args.dropFirst()))
        case "secrets", "secret": return secrets(Array(args.dropFirst()))
        case "exec": return exec(Array(args.dropFirst()))
        case "update-check": return updateCheck(Array(args.dropFirst()))
        case "show": return show(Array(args.dropFirst()))
        case "history": return history(Array(args.dropFirst()))
        case "team": return team(Array(args.dropFirst()))
        case "tools", "tool": return tools(Array(args.dropFirst()))
        case "pause": return pause(Array(args.dropFirst()), resume: false)
        case "resume": return pause(Array(args.dropFirst()), resume: true)
        case "list": return list()
        case "check": return check()
        case "path": print(Registry.defaultURL().path); return 0
        case "run": return run(Array(args.dropFirst()))
        case "version", "--version": print(Version.full); return 0
        default: print(help); return 0
        }
    }

    static let help = """
    great-gui · your commands, from the terminal

      great-gui add NAME --run "…" [--desc …] [--group …] [--cwd …] [--interactive] [--gate] [--schedule "weekdays 08:30"]
                   [--tag T]… [--env KEY=value | KEY=keychain:NAME]… [--env-file keychain:NAME]
                   [--param name:desc=default!]… [--no-commit]
      great-gui edit NAME [--name NEW] [the flags of add: one given replaces that field, the rest stays]
                   [--no-interactive] [--no-gate] [--clear-tags] [--clear-env] [--clear-env-file] [--clear-params] [--clear-schedule]
      great-gui remove NAME          take a command out (its block only; the rest of the file stays)
      great-gui list                 the registry, by group
      great-gui show NAME            one command in full: its run line, parameters, environment (names only), schedule
      great-gui history [NAME] [-n N]  what ran, newest first: when, how (window, shell, scheduled, exec), exit code
      great-gui check                is the registry file valid
      great-gui path                 where the registry file is
      great-gui run NAME [-P k=v]…   run one command here (gated commands run from the window)
                                     with --json, --capture also puts what it printed in the result
      great-gui schedule [sync]      the scheduled commands and their launchd agents · sync makes the agents match the file
      great-gui pause NAME · resume NAME
      great-gui secrets [--json]     the names of the secrets and files in the Keychain, and who uses them. Never a value
      great-gui exec [--env KEY=keychain:NAME]… [--env-file keychain:NAME] [--cwd DIR] -- COMMAND…
                                     run one command with secrets in its environment; their values are masked in the output
      great-gui file                 the credential files kept whole in the Keychain, and how each compares with its path
      great-gui file add NAME --path ~/x/.env [--mode 600] [--desc …] [--no-store]   point at a file and store it
      great-gui file store [NAME]…   the file's contents into the Keychain (all of them when no name is given)
      great-gui file restore [NAME]… [--force]   the Keychain copy onto its path, private; --force overwrites a file that differs
      great-gui file remove NAME [--purge]       drop the pointer; --purge also deletes the Keychain copy. The file stays
      great-gui update-check         is there a newer version to pull (it only looks; make update installs)
      great-gui team                 the team's registry on this Mac: where it is, what it follows, what it holds
      great-gui team join ADDRESS    clone the team's repository (any git address) · team sync follows it now
      great-gui team init DIR        start a team repository in DIR: commands.toml, skills/, a README · you push it
      great-gui team leave           take it off this Mac (the folder goes to the Trash; your commands and secrets stay)
      great-gui tools [--check]      the programs this Mac should have: installed, missing, and with --check what is behind
      great-gui tools install [NAME]…   install what is missing, or the named ones · tools update [NAME]… brings them current
      great-gui tools add NAME --method METHOD [--pkg P] [--bin B] [--desc …] [--install "…"] [--update "…"] [--requires R]…
      great-gui tools methods        brew, cask, uv, pipx, pip, npm, cargo, go and script, with the lines each derives
      great-gui tools remove NAME    drop it from your registry (nothing is uninstalled)
      great-gui version · help

    The team's commands and tools are listed with yours, marked team, and are read-only here: add NAME with the same
    name makes your own version, which wins. A team schedule is never armed by itself, and a team tool is never
    installed by itself: tools install runs when you, or your agent, ask.

    For agents: every command but path, version and help takes --json and then prints one JSON object on stdout, errors included
    ({"ok": false, "error": …, "fix": …}). run and exec (--json before the --) and tools install|update send the
    command's own output to stderr and print {"ok", "code", "seconds", …} when it ends; run and exec take
    --capture (exec: before the --) to also get it as "output" (masked, stdout and stderr in order, the
    newest 64 KB, "output_truncated" when the front was cut). Exit codes: 0 fine · 1 something is
    not as it should be (a file out of sync, an invalid registry) · 2 the request was wrong or refused ·
    10 an update is waiting · run and exec return the command's own.

    The window: open the-great-gui.app. ⌘N adds a command there, ⌘E edits the selected one, ⌘⌫ removes it; ⌘K manages secrets.
    """

    // MARK: add · edit · remove

    /// What add and edit accept. A flag given sets its field; edit keeps every field not given.
    struct Fields {
        var name: String?
        var newName: String?
        var run: String?, desc: String?, group: String?, cwd: String?
        var interactive: Bool?, gate: Bool?
        var tags: [String]?, env: [String: EnvValue]?, params: [Param]?
        var schedule: String?
        var envFile: String?
        var commit = true
    }

    /// The flags shared by add and edit. Nil after an error has been printed (exit 2).
    static func parseFields(_ args: [String]) throws -> Fields? {
        var f = Fields()
        var i = 0
        func value(_ flag: String) -> String? {
            guard i + 1 < args.count else { fail("\(flag) needs a value", fix: help); return nil }
            i += 1
            return args[i]
        }
        while i < args.count {
            let a = args[i]
            switch a {
            case "--name": guard let v = value(a) else { return nil }; f.newName = v
            case "--run": guard let v = value(a) else { return nil }; f.run = v
            case "--desc", "--description": guard let v = value(a) else { return nil }; f.desc = v
            case "--group": guard let v = value(a) else { return nil }; f.group = v
            case "--cwd": guard let v = value(a) else { return nil }; f.cwd = v
            case "--tag", "--tags": guard let v = value(a) else { return nil }; f.tags = (f.tags ?? []) + RegistryWriter.parseTags(v)
            case "--env":
                guard let v = value(a) else { return nil }
                let (k, e) = try RegistryWriter.parseEnv(v)
                var env = f.env ?? [:]
                env[k] = e
                f.env = env
            case "--param": guard let v = value(a) else { return nil }; f.params = (f.params ?? []) + [try RegistryWriter.parseParam(v)]
            case "--interactive", "--tty": f.interactive = true
            case "--no-interactive": f.interactive = false
            case "--gate": f.gate = true
            case "--no-gate": f.gate = false
            case "--clear-tags": f.tags = []
            case "--clear-env": f.env = [:]
            case "--clear-params": f.params = []
            case "--schedule": guard let v = value(a) else { return nil }; f.schedule = v
            case "--clear-schedule": f.schedule = ""
            case "--env-file": guard let v = value(a) else { return nil }; f.envFile = v
            case "--clear-env-file": f.envFile = ""
            case "--no-commit": f.commit = false
            default:
                if a.hasPrefix("-") { fail("unknown flag \(a)", fix: help); return nil }
                if f.name == nil { f.name = a } else { fail("one name only; \(a) is extra", fix: "quote the run line: --run \"…\""); return nil }
            }
            i += 1
        }
        return f
    }

    static func add(_ args: [String]) -> Int32 {
        if args.contains("-h") || args.contains("--help") { print(help); return 0 }
        do {
            guard let f = try parseFields(args) else { return 2 }
            guard let name = f.name else { fail("add needs a name", fix: "great-gui add NAME --run \"…\""); return 2 }
            if f.newName != nil { fail("--name is for edit", fix: "great-gui add NAME --run \"…\""); return 2 }
            let command = try RegistryWriter.build(name: name, run: f.run ?? "", desc: f.desc ?? "", group: f.group ?? "", cwd: f.cwd ?? "",
                                                   interactive: f.interactive ?? false, gate: f.gate ?? false, tags: f.tags ?? [],
                                                   env: f.env ?? [:], params: f.params ?? [], schedule: f.schedule ?? "",
                                                   envFile: f.envFile ?? "")
            let url = Registry.defaultURL()
            let registry = try RegistryWriter.append(command, to: url)
            var facts = [count(registry.commands.count, "command"), url.path]
            if f.commit, RegistryWriter.autoCommit(url, message: "add \(command.name)") { facts.append("committed") }
            if let s = syncAgents(registry) { facts.append(s) }
            let known = Set((try? SecretStore().names()) ?? [])
            let plain = command.secretNames.filter { $0 != command.envFile && !known.contains($0) }
            if json {
                emit(["ok": true, "action": "added", "command": describe(command), "path": url.path, "committed": facts.contains("committed"),
                      "secrets_missing": command.secretNames.filter { !known.contains($0) }])
                return 0
            }
            print("✓ added \(command.name) · " + facts.joined(separator: " · "))
            if !plain.isEmpty {
                print("  not in the Keychain yet: " + plain.joined(separator: ", ") + " · add the values with ⌘K in the window; never on the command line")
            }
            if let f = command.envFile, !SecretStore().exists(f) {
                print("  env file: \(f) is not in the Keychain yet · great-gui file add \(f) --path /path/to/.env stores it")
            }
            return 0
        } catch let e as RegistryError {
            fail(e.what, fix: e.fix)
            return 2
        } catch {
            fail("\(error)")
            return 2
        }
    }

    /// The command as it is, with the fields given replaced; the block is rewritten in place.
    static func edit(_ args: [String]) -> Int32 {
        if args.contains("-h") || args.contains("--help") { print(help); return 0 }
        do {
            guard let f = try parseFields(args) else { return 2 }
            guard let name = f.name else { fail("edit needs a name", fix: "great-gui edit NAME --desc \"…\""); return 2 }
            let url = Registry.defaultURL()
            let reg = try Registry.load(from: url)
            guard let old = reg.command(named: name) else { failMissing(name); return 2 }
            let command = try RegistryWriter.build(name: f.newName ?? old.name, run: f.run ?? old.run, desc: f.desc ?? old.desc,
                                                   group: f.group ?? old.group, cwd: f.cwd ?? old.cwd ?? "",
                                                   interactive: f.interactive ?? old.interactive, gate: f.gate ?? old.gate,
                                                   tags: f.tags ?? old.tags, env: f.env ?? old.env, params: f.params ?? old.params,
                                                   schedule: f.schedule ?? old.schedule?.text ?? "",
                                                   envFile: f.envFile ?? old.envFile ?? "")
            guard command != old else {
                if json { emit(["ok": true, "action": "unchanged", "command": describe(old), "path": url.path]) } else { print("✓ \(name) unchanged · nothing given to change") }
                return 0
            }
            let registry = try RegistryWriter.replace(name, with: command, in: url)
            let message = command.name == name ? "edit \(name)" : "rename \(name) to \(command.name)"
            var facts = [count(registry.commands.count, "command"), url.path]
            if f.commit, RegistryWriter.autoCommit(url, message: message) { facts.append("committed") }
            if let s = syncAgents(registry) { facts.append(s) }
            if json {
                let known = Set((try? SecretStore().names()) ?? [])
                emit(["ok": true, "action": command.name == name ? "edited" : "renamed", "was": name, "command": describe(command), "path": url.path,
                      "committed": facts.contains("committed"), "secrets_missing": command.secretNames.filter { !known.contains($0) }])
                return 0
            }
            print("✓ \(message) · " + facts.joined(separator: " · "))
            if let f = command.envFile, f != old.envFile, !SecretStore().exists(f) {
                print("  env file: \(f) is not in the Keychain yet · great-gui file add \(f) --path /path/to/.env stores it")
            }
            let missing = command.secretNames.filter { !old.secretNames.contains($0) && $0 != command.envFile }
            if !missing.isEmpty {
                print("  secrets: " + missing.joined(separator: ", ") + " · add the values with ⌘K in the window; never on the command line")
            }
            return 0
        } catch let e as RegistryError {
            fail(e.what, fix: e.fix)
            return 2
        } catch {
            fail("\(error)")
            return 2
        }
    }

    static func remove(_ args: [String]) -> Int32 {
        if args.contains("-h") || args.contains("--help") { print(help); return 0 }
        var name: String?
        var commit = true
        for a in args {
            switch a {
            case "--no-commit": commit = false
            default:
                if a.hasPrefix("-") { fail("unknown flag \(a)", fix: help); return 2 }
                if name == nil { name = a } else { fail("one name only; \(a) is extra", fix: "great-gui remove NAME"); return 2 }
            }
        }
        guard let name else { fail("remove needs a name", fix: "great-gui remove NAME"); return 2 }
        do {
            let url = Registry.defaultURL()
            if try Registry.load(from: url).command(named: name) == nil { failMissing(name); return 2 }
            let registry = try RegistryWriter.remove(name, from: url)
            var facts = [count(registry.commands.count, "command"), url.path]
            if commit, RegistryWriter.autoCommit(url, message: "remove \(name)") { facts.append("committed") }
            if let s = syncAgents(registry) { facts.append(s) }
            if json { emit(["ok": true, "action": "removed", "name": name, "path": url.path, "committed": facts.contains("committed"), "commands": registry.commands.count]); return 0 }
            print("✓ removed \(name) · " + facts.joined(separator: " · "))
            return 0
        } catch let e as RegistryError {
            fail(e.what, fix: e.fix)
            return 2
        } catch {
            fail("\(error)")
            return 2
        }
    }

    /// A name that is not in the person's file: the team's is read-only and says how to take it over.
    static func failMissing(_ name: String) {
        if (try? Registry.loadAll())?.command(named: name)?.origin == .team {
            fail("\(name) is the team's and is read-only here", fix: "great-gui add \(name) --run \"…\" makes your own version, which wins over theirs")
        } else {
            fail("no command named \(name)", fix: "great-gui list")
        }
    }

    // MARK: the team's registry

    static func team(_ args: [String]) -> Int32 {
        if args.contains("-h") || args.contains("--help") { print(help); return 0 }
        let dir = Registry.teamDirectory()
        func report(_ outcome: TeamSync.Outcome, done: String) -> Int32 {
            switch outcome {
            case .notJoined:
                if json { emit(["ok": true, "status": "not_joined", "directory": dir.path]) } else { print("✓ no team registry on this Mac · great-gui team join ADDRESS") }
                return 0
            case .current:
                if json { emit(["ok": true, "status": done == "left" ? "left" : "current", "directory": dir.path]) } else { print("✓ \(done) · \(dir.path)") }
                return 0
            case .updated(let c):
                if json {
                    emit(["ok": true, "status": "updated", "directory": dir.path, "added": c.added, "changed": c.changed, "removed": c.removed, "skills": c.skills, "tools": c.tools, "details": c.details])
                } else {
                    print("✓ team · " + c.words + (c.skills.isEmpty ? "" : " · skills: " + c.skills.joined(separator: ", ")))
                    for line in c.details { print("    " + line) }
                }
                return 0
            case .failed(let what, let fix):
                fail(what, fix: fix)
                return 1
            }
        }
        switch args.first {
        case "join":
            guard args.count == 2 else { fail("team join needs one address", fix: "great-gui team join https://host/team/tooling.git"); return 2 }
            return report(TeamSync.join(args[1], into: dir), done: "joined")
        case "sync":
            return report(TeamSync.sync(dir), done: "up to date")
        case "leave":
            return report(TeamSync.leave(dir), done: "left")
        case "init":
            guard args.count == 2 else { fail("team init needs a folder", fix: "great-gui team init ~/Developer/team-tooling"); return 2 }
            let target = URL(fileURLWithPath: NSString(string: args[1]).expandingTildeInPath)
            do {
                let made = try TeamSync.scaffold(target)
                if json { emit(["ok": true, "directory": target.path, "written": made]) } else {
                    print("✓ team repository started in \(target.path) · wrote " + (made.isEmpty ? "nothing: it was all there" : made.joined(separator: ", ")))
                    print("  next: put it on your git host, then on each Mac: great-gui team join ADDRESS")
                }
                return 0
            } catch {
                fail("could not write to \(target.path)", fix: error.localizedDescription)
                return 2
            }
        case nil, "status":
            let st = TeamSync.status(dir)
            let reg = try? Registry.loadAll()
            let state = reg?.team
            let teamOnes = reg?.teamCommands ?? []
            let stored = Set((try? SecretStore().names()) ?? [])
            let needs = Array(Set(teamOnes.flatMap(\.secretNames) + (reg?.files.filter(\.team).map(\.name) ?? []))).sorted()
            let missing = needs.filter { !stored.contains($0) }
            // The team's tools are a checklist too: which are here is asked of the package managers and PATH only.
            let teamTools = reg?.teamTools ?? []
            let toolStatus = ToolRunner.status(teamTools, versions: false, outdated: false)
            let toolsMissing = teamTools.filter { toolStatus[$0.name]?.installed != true }.map(\.name)
            if json {
                var d: [String: Any] = ["ok": state?.problem == nil, "joined": st.joined, "directory": dir.path, "repository": st.repository,
                                        "commands": teamOnes.map(\.name), "overridden": state?.overridden ?? [],
                                        "secrets_needed": needs, "secrets_missing": missing,
                                        "tools": teamTools.map(\.name), "tools_missing": toolsMissing]
                if let r = st.remote { d["remote"] = r }
                if let h = st.head { d["head"] = h }
                if let at = st.syncedAt { d["synced_at"] = iso(at) }
                if let p = state?.problem { d["error"] = p.what; d["fix"] = p.fix }
                emit(d)
                return state?.problem == nil ? 0 : 1
            }
            guard st.joined else { print("✓ no team registry on this Mac · great-gui team join ADDRESS"); return 0 }
            if let p = state?.problem { fail(p.what, fix: p.fix); return 1 }
            var facts = [count(state?.commands ?? 0, "command")] + ((state?.tools ?? 0) > 0 ? [count(state?.tools ?? 0, "tool")] : []) + [dir.path]
            if let r = st.remote { facts.append("follows " + r) } else { facts.append("a plain folder: it follows no remote") }
            if let at = st.syncedAt, st.repository { facts.append("synced " + HistoryStore.relative(at)) }
            print("✓ team · " + facts.joined(separator: " · "))
            for c in teamOnes { print("    " + c.name.padding(toLength: 24, withPad: " ", startingAt: 0) + c.desc) }
            if let o = state?.overridden, !o.isEmpty { print("  yours win over the team's: " + o.joined(separator: ", ")) }
            if !teamTools.isEmpty { print("  tools: " + teamTools.map(\.name).joined(separator: ", ")) }
            if !toolsMissing.isEmpty { print("  not installed yet: " + toolsMissing.joined(separator: ", ") + " · great-gui tools install") }
            if !missing.isEmpty { print("  not in the Keychain yet: " + missing.joined(separator: ", ") + " · add the values with ⌘K in the window; never on the command line") }
            return 0
        default:
            fail("unknown team command \(args[0])", fix: "great-gui team [join ADDRESS|sync|leave|init DIR]")
            return 2
        }
    }

    // MARK: secrets for agents: names to choose from, and a run that is handed the values

    /// The names an agent may refer to, and whether each is there. No flag makes this print a value.
    static func secrets(_ args: [String]) -> Int32 {
        if args.contains("-h") || args.contains("--help") { print(help); return 0 }
        if let extra = args.first(where: { $0 != "--json" && $0 != "list" }) {
            fail("unknown argument \(extra)", fix: "great-gui secrets [--json] lists names; values are added in the window (⌘K) and never printed")
            return 2
        }
        let store = SecretStore()
        let reg = try? Registry.loadAll()
        let stored: Set<String>
        do { stored = Set(try store.names()) } catch { fail("\(error)"); return 1 }
        let fileNames = Set(reg?.files.map(\.name) ?? [])
        let referenced = Set((reg?.commands ?? []).flatMap(\.secretNames))
        func users(_ n: String) -> [String] { (reg?.commands ?? []).filter { $0.secretNames.contains(n) }.map(\.name) }
        let names = stored.union(referenced).subtracting(fileNames).sorted()
        if args.contains("--json") {
            var items: [[String: Any]] = names.map { ["name": $0, "kind": "secret", "stored": stored.contains($0), "used_by": users($0)] }
            for f in reg?.files ?? [] {
                items.append(["name": f.name, "kind": "file", "stored": stored.contains(f.name), "path": f.path, "used_by": users(f.name)])
            }
            let data = (try? JSONSerialization.data(withJSONObject: ["service": store.service, "secrets": items], options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
            print(String(decoding: data, as: UTF8.self))
            return 0
        }
        guard !names.isEmpty || !fileNames.isEmpty else { print("✓ no secrets yet · add one in the window (⌘K); a value is never typed on the command line"); return 0 }
        print("✓ \(count(names.count, "secret")) · \(count(fileNames.count, "file")) · Keychain service \(store.service) · names only")
        func line(_ n: String, _ kind: String) {
            let u = users(n)
            print("    " + n.padding(toLength: 28, withPad: " ", startingAt: 0) + kind.padding(toLength: 8, withPad: " ", startingAt: 0)
                + (stored.contains(n) ? "in Keychain" : "missing    ") + (u.isEmpty ? "" : "  · used by " + u.joined(separator: ", ")))
        }
        for n in names { line(n, "secret") }
        for f in reg?.files ?? [] { line(f.name, "file") }
        print("  use one: great-gui exec --env KEY=keychain:NAME -- COMMAND   ·   a whole .env: --env-file keychain:NAME")
        return 0
    }

    /// One command, not in the registry, run with secrets in its environment. The caller names the secrets and
    /// never holds their values: they go from the Keychain to the child, and are masked in what it prints.
    static func exec(_ args: [String]) -> Int32 {
        let usage = "great-gui exec [--env KEY=keychain:NAME]… [--env-file keychain:NAME] [--cwd DIR] -- COMMAND…"
        if args.first == "-h" || args.first == "--help" { print(help); return 0 }
        guard let dashes = args.firstIndex(of: "--") else { fail("exec needs -- before the command", fix: usage); return 2 }
        let command = Array(args[(dashes + 1)...])
        guard !command.isEmpty else { fail("exec needs a command after --", fix: usage); return 2 }
        var env: [String: EnvValue] = [:]
        var envFile: String?
        var cwd: String?
        var i = 0
        do {
            while i < dashes {
                let a = args[i]
                guard ["--env", "--env-file", "--cwd"].contains(a) else { fail("unknown argument \(a)", fix: usage); return 2 }
                guard i + 1 < dashes else { fail("\(a) needs a value", fix: usage); return 2 }
                i += 1
                switch a {
                case "--env":
                    let (k, v) = try RegistryWriter.parseEnv(args[i])
                    env[k] = v
                case "--env-file": envFile = try RegistryWriter.parseEnvFile(args[i])
                default: cwd = NSString(string: args[i]).expandingTildeInPath
                }
                i += 1
            }
        } catch let e as RegistryError {
            fail(e.what, fix: e.fix)
            return 2
        } catch {
            fail("\(error)")
            return 2
        }
        // One argument is a shell line as written; several are words, quoted so the shell passes them on unchanged.
        let line = command.count == 1 ? command[0] : command.map(Registry.shellQuote).joined(separator: " ")
        let r = Resolved(name: "exec", run: line, cwd: cwd, env: env, envFile: envFile)
        do {
            let built = try RunEnvironment.build(r, secrets: SecretStore())
            var environment = ProcessInfo.processInfo.environment
            environment.merge(built.env) { _, new in new }
            let started = Date()
            let code = try runMasked(shellArguments: ["-lc", line], cwd: cwd, environment: environment, redact: built.redact)
            let seconds = (Date().timeIntervalSince(started) * 10).rounded() / 10
            // The history shows that it ran and with which secrets, by name: an agent's use leaves a trace.
            let with = r.secretNames.isEmpty ? "" : "  # with " + r.secretNames.joined(separator: ", ")
            HistoryStore().append(HistoryEntry(name: "exec", run: line + with, cwd: cwd, mode: "exec", code: code, seconds: seconds, startedAt: started))
            if json { emit(["ok": code == 0, "name": "exec", "code": Int(code), "seconds": seconds, "secrets": r.secretNames, "masked": built.redact.count].merging(capture?.fields ?? [:]) { a, _ in a }) }
            return code
        } catch let e as RunEnvironment.Refusal {
            fail(e.what, fix: e.fix)
            return 2
        } catch {
            fail("could not start: \(error.localizedDescription)", fix: cwd.map { "does \($0) exist?" } ?? "")
            return 2
        }
    }

    /// Runs the shell with its output passed through the redactor, line by line, stdout to stdout and stderr
    /// to stderr. With nothing to mask the child keeps this terminal as it is, so nothing about a plain run changes.
    /// With `--json` the command's stdout goes to stderr, so stdout carries nothing but the result object.
    static func runMasked(shellArguments: [String], cwd: String?, environment: [String: String], redact: [String]) throws -> Int32 {
        fflush(stdout)
        let ours: FileHandle = json ? .standardError : .standardOutput
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ProcessRun.defaultShell())
        p.arguments = shellArguments
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        p.environment = environment
        // A value of several lines (a key file) is also masked line by line, since output arrives that way.
        let values = redact + redact.flatMap { v in v.contains("\n") ? v.split(separator: "\n").map(String.init).filter { $0.count >= RunEnvironment.minRedactedLength } : [] }
        guard !values.isEmpty || capture != nil else {
            if json { p.standardOutput = FileHandle.standardError }
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        }
        let redactor = Redactor(values: values)
        let capture = Self.capture
        let done = DispatchGroup()
        let lock = NSLock()
        func pump(_ pipe: Pipe, to out: FileHandle) {
            done.enter()
            var buffer = Data()
            func emit(_ raw: Data, newline: Bool) {
                let text = redactor.redact(String(decoding: raw, as: UTF8.self)) + (newline ? "\n" : "")
                lock.lock(); out.write(Data(text.utf8)); capture?.append(text); lock.unlock()
            }
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    if !buffer.isEmpty { emit(buffer, newline: false) }
                    done.leave()
                    return
                }
                buffer.append(data)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    emit(buffer.subdata(in: buffer.startIndex..<nl), newline: true)
                    buffer.removeSubrange(buffer.startIndex...nl)
                }
            }
        }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        pump(out, to: ours)
        pump(err, to: .standardError)
        do {
            try p.run()
        } catch {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            throw error
        }
        p.waitUntilExit()
        done.wait()
        return p.terminationStatus
    }

    // MARK: updates

    /// The same look the window takes once a day. Exit 0 when current, 10 when something is waiting, 1 when it could not tell.
    static func updateCheck(_ args: [String]) -> Int32 {
        let root = args.first.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) } ?? MainActor.assumeIsolated { AppModel.checkoutURL }
        guard let root else { fail("this build is not running from its checkout", fix: "run it through great-gui, or give the checkout: great-gui update-check ~/Developer/the-great-gui"); return 1 }
        let outcome = UpdateCheck.run(in: root)
        if json {
            switch outcome {
            case .current: emit(["ok": true, "status": "current", "checkout": root.path]); return 0
            case .behind(let info): emit(["ok": true, "status": "behind", "count": info.count, "subjects": info.subjects, "checkout": root.path, "install": "make update"]); return 10
            case .unknown(let why): emit(["ok": false, "status": "unknown", "error": why]); return 1
            }
        }
        switch outcome {
        case .current:
            print("✓ up to date · \(root.path)")
            return 0
        case .behind(let info):
            print("▲ update available · \(info.words) · the-great-gui › Update…, or make update in \(root.path)")
            for s in info.subjects { print("    " + s) }
            if info.count > info.subjects.count { print("    … and \(info.count - info.subjects.count) more") }
            return 10
        case .unknown(let why):
            fail(why, fix: "check the network and your access to the repository; git -C \(root.path) fetch shows the reason")
            return 1
        }
    }

    // MARK: files

    /// `great-gui file …`: pointers in the registry, bytes in the Keychain. No subcommand prints a value,
    /// and none takes one: a file's contents come from the file.
    static func file(_ args: [String]) -> Int32 {
        if args.contains("-h") || args.contains("--help") { print(help); return 0 }
        let rest = Array(args.dropFirst())
        do {
            switch args.first {
            case nil, "list", "status": return try fileList()
            case "add": return try fileAdd(rest)
            case "store", "put": return try fileStore(rest)
            case "restore", "apply": return try fileRestore(rest)
            case "remove", "rm": return try fileRemove(rest)
            default:
                fail("unknown file command \(args[0])", fix: "great-gui file [add|store|restore|remove]")
                return 2
            }
        } catch let e as RegistryError {
            fail(e.what, fix: e.fix)
            return 2
        } catch let e as FileSecretError {
            fail(e.what, fix: e.fix)
            return 2
        } catch {
            fail("\(error)")
            return 2
        }
    }

    static func fileList() throws -> Int32 {
        let reg = try Registry.loadAll()
        let files = FileSecrets()
        var rows: [(file: SecretFile, state: FileSecrets.State?, words: String, users: [String])] = []
        for f in reg.files {
            let users = reg.commands.filter { $0.secretNames.contains(f.name) }.map(\.name)
            do {
                let st = try files.state(name: f.name, path: f.expandedPath, mode: f.modeBits)
                rows.append((f, st, st.words, users))
            } catch {
                rows.append((f, nil, "\(error)".components(separatedBy: "\n")[0], users))
            }
        }
        let wrong = rows.filter { $0.state != .inSync }.count
        if json {
            emit(["ok": wrong == 0, "service": files.store.service, "files": rows.map { r -> [String: Any] in
                var d: [String: Any] = ["name": r.file.name, "path": r.file.path, "mode": r.file.mode, "in_sync": r.state == .inSync, "used_by": r.users]
                if let st = r.state { d["state"] = st.rawValue; d["advice"] = st.advice } else { d["state"] = "unreadable"; d["advice"] = r.words }
                return d
            }])
            return wrong == 0 ? 0 : 1
        }
        guard !reg.files.isEmpty else { print("✓ no files yet · great-gui file add NAME --path ~/project/.env"); return 0 }
        print("✓ \(count(reg.files.count, "file")) · Keychain service \(files.store.service)")
        for r in rows {
            print("    " + r.file.name.padding(toLength: 24, withPad: " ", startingAt: 0) + r.words.padding(toLength: 17, withPad: " ", startingAt: 0)
                + r.file.path + (r.users.isEmpty ? "" : "  · used by " + r.users.joined(separator: ", ")))
        }
        return wrong == 0 ? 0 : 1
    }

    static func fileAdd(_ args: [String]) throws -> Int32 {
        var name: String?, path: String?, mode = "", desc = "", store = true, commit = true
        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--path", "--mode", "--desc", "--description":
                guard i + 1 < args.count else { fail("\(a) needs a value", fix: "great-gui file add NAME --path ~/project/.env"); return 2 }
                i += 1
                if a == "--path" { path = args[i] } else if a == "--mode" { mode = args[i] } else { desc = args[i] }
            case "--no-store": store = false
            case "--no-commit": commit = false
            default:
                if a.hasPrefix("-") { fail("unknown flag \(a)", fix: "great-gui file add NAME --path ~/project/.env"); return 2 }
                if name == nil { name = a } else { fail("one name only; \(a) is extra", fix: "great-gui file add NAME --path ~/project/.env"); return 2 }
            }
            i += 1
        }
        guard let name, let path else { fail("file add needs a name and --path", fix: "great-gui file add NAME --path ~/project/.env"); return 2 }
        // The shell expands an unquoted ~; the registry gets it back, so the entry carries nobody's home folder.
        let absolute = path.hasPrefix("~") || path.hasPrefix("/") ? path : FileManager.default.currentDirectoryPath + "/" + path
        let entry = try RegistryWriter.buildFile(name: name, path: RegistryWriter.portable(absolute), mode: mode, desc: desc)
        let url = Registry.defaultURL()
        let registry = try RegistryWriter.appendFile(entry, to: url)
        var facts = [entry.path, count(registry.files.count, "file")]
        if commit, RegistryWriter.autoCommit(url, message: "add file \(entry.name)") { facts.append("committed") }
        let there = FileManager.default.fileExists(atPath: entry.expandedPath)
        if json {
            var d: [String: Any] = ["ok": true, "action": "added", "name": entry.name, "path": entry.path, "mode": entry.mode,
                                    "committed": facts.contains("committed"), "stored": false]
            if store, there {
                do {
                    d["bytes"] = try FileSecrets().keep(name: entry.name, from: entry.expandedPath).bytes
                    d["stored"] = true
                } catch let e as FileSecretError {
                    d["ok"] = false; d["error"] = "\(entry.name): \(e.what)"; d["fix"] = e.fix
                }
            }
            emit(d)
            return d["ok"] as? Bool == true ? 0 : 1
        }
        print("✓ added the file \(entry.name) · " + facts.joined(separator: " · "))
        guard store else { print("  not stored: great-gui file store \(entry.name) when the file is there"); return 0 }
        guard there else {
            print("  nothing at \(entry.path) yet: great-gui file store \(entry.name) once it exists")
            return 0
        }
        return try fileStore([entry.name])
    }

    /// The names given, or every file when none is; an unknown name is an error before anything is touched.
    static func files(named names: [String], in reg: Registry) throws -> [SecretFile] {
        if names.isEmpty { return reg.files }
        return try names.map { n in
            guard let f = reg.file(named: n) else { throw RegistryError("no file named \(n)", fix: "great-gui file lists them") }
            return f
        }
    }

    static func fileStore(_ args: [String]) throws -> Int32 {
        if let flag = args.first(where: { $0.hasPrefix("-") }) { fail("unknown flag \(flag)", fix: "great-gui file store [NAME]…"); return 2 }
        let reg = try Registry.loadAll()
        let files = FileSecrets()
        var failed = false
        var results: [[String: Any]] = []
        for f in try Self.files(named: args, in: reg) {
            do {
                let r = try files.keep(name: f.name, from: f.expandedPath)
                results.append(["name": f.name, "ok": true, "action": r.replaced ? "replaced" : "stored", "bytes": r.bytes, "path": f.path])
                if !json { print("✓ \(f.name) \(r.replaced ? "replaced" : "stored") · \(r.bytes) bytes from \(f.path)") }
            } catch let e as FileSecretError {
                results.append(["name": f.name, "ok": false, "error": e.what, "fix": e.fix])
                if !json { fail("\(f.name): \(e.what)", fix: e.fix) }
                failed = true
            }
        }
        if json { emit(["ok": !failed, "results": results]) }
        return failed ? 1 : 0
    }

    static func fileRestore(_ args: [String]) throws -> Int32 {
        let force = args.contains("--force") || args.contains("-f")
        let names = args.filter { $0 != "--force" && $0 != "-f" }
        if let flag = names.first(where: { $0.hasPrefix("-") }) { fail("unknown flag \(flag)", fix: "great-gui file restore [NAME]… [--force]"); return 2 }
        let reg = try Registry.loadAll()
        let files = FileSecrets()
        var failed = false
        var results: [[String: Any]] = []
        func problem(_ f: SecretFile, _ what: String, _ fix: String) {
            results.append(["name": f.name, "ok": false, "error": what, "fix": fix])
            if !json { fail(what, fix: fix) }
            failed = true
        }
        for f in try Self.files(named: names, in: reg) {
            do {
                let action: String, words: String
                switch try files.restore(name: f.name, to: f.expandedPath, mode: f.modeBits, force: force) {
                case .written(let bytes): action = "written"; words = "written · \(bytes) bytes to \(f.path) · mode \(f.mode)"
                case .modeFixed: action = "mode_fixed"; words = "unchanged · mode set to \(f.mode)"
                case .unchanged: action = "in_sync"; words = "in sync"
                }
                results.append(["name": f.name, "ok": true, "action": action, "path": f.path, "mode": f.mode])
                if !json { print("✓ \(f.name) " + words) }
            } catch SecretStore.Failure.notFound {
                problem(f, "\(f.name) is not in the Keychain on this Mac", "great-gui file store \(f.name) keeps the file at \(f.path); a value never comes from another Mac")
            } catch let e as FileSecretError {
                problem(f, "\(f.name): \(e.what)", e.fix)
            }
        }
        if json { emit(["ok": !failed, "results": results]) }
        return failed ? 1 : 0
    }

    static func fileRemove(_ args: [String]) throws -> Int32 {
        let purge = args.contains("--purge"), commit = !args.contains("--no-commit")
        let names = args.filter { $0 != "--purge" && $0 != "--no-commit" }
        if let flag = names.first(where: { $0.hasPrefix("-") }) { fail("unknown flag \(flag)", fix: "great-gui file remove NAME [--purge]"); return 2 }
        guard names.count == 1 else { fail("file remove needs one name", fix: "great-gui file remove NAME [--purge]"); return 2 }
        let name = names[0], url = Registry.defaultURL()
        let users = try Registry.load(from: url).commands.filter { $0.envFile == name }.map(\.name)
        let registry = try RegistryWriter.removeFile(name, from: url)
        var facts = [count(registry.files.count, "file")]
        if commit, RegistryWriter.autoCommit(url, message: "remove file \(name)") { facts.append("committed") }
        if purge {
            do {
                try SecretStore().delete(name)
                facts.append("Keychain copy deleted")
            } catch SecretStore.Failure.notFound {
                facts.append("nothing in the Keychain")
            }
        } else {
            facts.append("the Keychain copy stays (--purge deletes it)")
        }
        if json { emit(["ok": true, "action": "removed", "name": name, "committed": facts.contains("committed"), "purged": facts.contains("Keychain copy deleted"), "still_env_file_of": users]); return 0 }
        print("✓ removed the file \(name) · " + facts.joined(separator: " · ") + " · the file on disk is untouched")
        if !users.isEmpty, purge { print("  still the env file of " + users.joined(separator: ", ") + ": those runs will be refused") }
        return 0
    }

    // MARK: schedules

    static func scheduler() -> Scheduler {
        Scheduler(program: Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
    }

    /// After a write, the agents follow the file. Problems are printed, never fatal to the write.
    static func syncAgents(_ registry: Registry) -> String? {
        let r = scheduler().sync(registry)
        // Under --json the answer is one object: a scheduler problem is left to great-gui schedule to report.
        if !json { for p in r.problems { fail(p) } }
        return r.changed ? "agents synced" : nil
    }

    static func describe(_ r: Scheduler.Report) -> String {
        var parts: [String] = []
        if !r.written.isEmpty { parts.append("written " + r.written.joined(separator: ", ")) }
        if !r.removed.isEmpty { parts.append("removed " + r.removed.joined(separator: ", ")) }
        if !r.loaded.isEmpty { parts.append("loaded " + r.loaded.joined(separator: ", ")) }
        if !r.unloaded.isEmpty { parts.append("unloaded " + r.unloaded.joined(separator: ", ")) }
        return parts.isEmpty ? "nothing to change" : parts.joined(separator: " · ")
    }

    static func schedule(_ args: [String]) -> Int32 {
        do {
            let reg = try Registry.loadAll()
            let s = scheduler()
            if args.first == "sync" {
                let r = s.sync(reg)
                if json {
                    emit(["ok": r.problems.isEmpty, "written": r.written, "removed": r.removed, "loaded": r.loaded, "unloaded": r.unloaded, "problems": r.problems])
                    return r.problems.isEmpty ? 0 : 1
                }
                print("✓ agents · " + describe(r))
                for p in r.problems { fail(p) }
                return r.problems.isEmpty ? 0 : 1
            }
            let list = reg.commands.filter { $0.schedule != nil }
            if json {
                let paused = s.paused()
                let history = HistoryStore().load()
                emit(["ok": true, "agents_dir": s.agentsDir.path, "logs_dir": s.logsDir.path, "scheduled": list.map { c -> [String: Any] in
                    let st = s.status(c.name)
                    let last = history.first { $0.name == c.name }
                    var d: [String: Any] = ["name": c.name, "schedule": c.schedule!.text, "means": c.schedule!.english,
                                            "paused": paused.contains(c.name), "loaded": st.loaded, "log": s.logURL(for: c.name).path]
                    if !paused.contains(c.name), let n = s.nextRun(for: c, lastRun: last?.startedAt) { d["next_run"] = iso(n) }
                    if let last { d["last_run"] = ["started_at": iso(last.startedAt), "exit": Int(last.code)] }
                    return d
                }])
                return 0
            }
            guard !list.isEmpty else { print("✓ nothing is scheduled · great-gui edit NAME --schedule \"weekdays 08:30\""); return 0 }
            let paused = s.paused()
            let history = HistoryStore().load()
            print("✓ \(count(list.count, "scheduled command")) · agents in \(s.agentsDir.path) · logs in \(s.logsDir.path)")
            for c in list {
                let st = s.status(c.name)
                let last = history.first { $0.name == c.name }
                var facts = [c.schedule!.english, paused.contains(c.name) ? "paused" : (st.loaded ? "loaded" : "not loaded")]
                if !paused.contains(c.name), let n = s.nextRun(for: c, lastRun: last?.startedAt) { facts.append("next " + Scheduler.when(n)) }
                if let last { facts.append("last \(HistoryStore.relative(last.startedAt)), exit \(last.code)") }
                print("    " + c.name.padding(toLength: 24, withPad: " ", startingAt: 0) + facts.joined(separator: " · "))
            }
            return 0
        } catch let e as RegistryError {
            fail(e.what, fix: e.fix)
            return 1
        } catch {
            fail("\(error)")
            return 1
        }
    }

    static func pause(_ args: [String], resume: Bool) -> Int32 {
        let verb = resume ? "resume" : "pause"
        guard let name = args.first else { fail("\(verb) needs a name", fix: "great-gui \(verb) NAME"); return 2 }
        do {
            let reg = try Registry.loadAll()
            let s = scheduler()
            if resume { try s.resume(name, in: reg) } else { try s.pause(name, in: reg) }
            if json { emit(["ok": true, "name": name, "paused": !resume]) } else { print("✓ \(name) \(resume ? "resumed" : "paused")") }
            return 0
        } catch let e as RegistryError {
            fail(e.what, fix: e.fix)
            return 2
        } catch {
            fail("\(error)")
            return 2
        }
    }

    // MARK: list · check · run

    // MARK: one JSON object for an agent

    static func emit(_ object: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        print(String(decoding: data, as: UTF8.self))
    }

    static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    /// A command as data. The environment shows where a value comes from (`keychain:NAME`), never the value.
    static func describe(_ c: Command) -> [String: Any] {
        var d: [String: Any] = [
            "name": c.name, "group": c.group, "desc": c.desc, "run": c.run, "interactive": c.interactive, "gate": c.gate,
            "tags": c.tags, "secrets": c.secretNames, "env": c.env.mapValues(\.display),
            "params": c.params.map { p -> [String: Any] in
                var e: [String: Any] = ["name": p.name, "desc": p.desc, "required": p.required]
                if let v = p.defaultValue { e["default"] = v }
                return e
            },
            // What an agent needs to know before `great-gui run`: can it, and with which -P.
            "runnable_from_cli": !c.gate,
        ]
        if let cwd = c.cwd { d["cwd"] = cwd }
        if let s = c.schedule { d["schedule"] = s.text }
        if let f = c.envFile { d["env_file"] = EnvValue.keychainPrefix + f }
        // Whose it is. The team's are read-only here, and their schedule is held back until the person copies it.
        d["origin"] = c.origin.rawValue
        if c.overridesTeam { d["overrides_team"] = true }
        if let s = c.teamSchedule { d["team_schedule"] = s.text }
        return d
    }

    static func show(_ args: [String]) -> Int32 {
        guard let name = args.first, args.count == 1 else { fail("show needs one name", fix: "great-gui show NAME · great-gui list has the names"); return 2 }
        do {
            let reg = try Registry.loadAll()
            guard let c = reg.command(named: name) else { fail("no command named \(name)", fix: "great-gui list"); return 2 }
            if json {
                var d = describe(c)
                d["ok"] = true
                emit(d)
                return 0
            }
            func row(_ label: String, _ value: String) { print("  " + label.padding(toLength: 12, withPad: " ", startingAt: 0) + value) }
            print("✓ \(c.name) · \(c.group)" + (c.desc.isEmpty ? "" : " · \(c.desc)"))
            row("run", c.run)
            if let cwd = c.cwd { row("cwd", cwd) }
            for p in c.params {
                row("param", p.name + (p.desc.isEmpty ? "" : " · \(p.desc)") + (p.defaultValue.map { " · default \($0)" } ?? "") + (p.required ? " · required" : ""))
            }
            for (k, v) in c.env.sorted(by: { $0.key < $1.key }) { row("env", "\(k) = \(v.display)") }
            if let f = c.envFile { row("env file", EnvValue.keychainPrefix + f) }
            if let sch = c.schedule { row("schedule", sch.english) }
            if c.origin == .team { row("from", "the team · read-only here · great-gui add \(c.name) … makes your own version") }
            if c.overridesTeam { row("from", "yours · it wins over the team's \(c.name)") }
            if let sch = c.teamSchedule { row("schedule", "the team suggests \(sch.english) · not armed: schedule your own copy") }
            if c.interactive { row("terminal", "needs one") }
            if c.gate { row("gate", "Touch ID: runs from the window only") }
            if !c.tags.isEmpty { row("tags", c.tags.joined(separator: ", ")) }
            let flags = c.params.map { "-P \($0.name)=…" }.joined(separator: " ")
            if !c.gate { row("run it", "great-gui run \(c.name)" + (flags.isEmpty ? "" : " " + flags)) }
            return 0
        } catch let e as RegistryError {
            fail(e.what, fix: e.fix)
            return 1
        } catch {
            fail("\(error)")
            return 1
        }
    }

    /// What ran, newest first. `exec` entries name the secrets used, so this is also the record of what agents did.
    static func history(_ args: [String]) -> Int32 {
        var limit = 20
        var name: String?
        var i = 0
        while i < args.count {
            if args[i] == "-n" || args[i] == "--limit" {
                guard i + 1 < args.count, let n = Int(args[i + 1]), n > 0 else { fail("-n needs a number", fix: "great-gui history [NAME] [-n 20]"); return 2 }
                limit = n
                i += 2
            } else if args[i].hasPrefix("-") {
                fail("unknown flag \(args[i])", fix: "great-gui history [NAME] [-n 20]")
                return 2
            } else {
                name = args[i]
                i += 1
            }
        }
        let all = HistoryStore().load().filter { name == nil || $0.name == name }
        let shown = Array(all.prefix(limit))
        if json {
            emit(["ok": true, "total": all.count, "runs": shown.map { e -> [String: Any] in
                var d: [String: Any] = ["name": e.name, "run": e.run, "mode": e.mode, "exit": Int(e.code), "seconds": e.seconds, "started_at": iso(e.startedAt)]
                if let cwd = e.cwd { d["cwd"] = cwd }
                return d
            }])
            return 0
        }
        guard !shown.isEmpty else { print("✓ nothing has run yet" + (name.map { " under the name \($0)" } ?? "")); return 0 }
        print("✓ \(count(shown.count, "run")) of \(all.count), newest first")
        for e in shown {
            let mode = e.mode == "exec" ? "exec" : HistoryStore.modeName(e.mode)
            print("    " + HistoryStore.relative(e.startedAt).padding(toLength: 12, withPad: " ", startingAt: 0) + mode.padding(toLength: 10, withPad: " ", startingAt: 0)
                + "exit \(e.code)".padding(toLength: 9, withPad: " ", startingAt: 0) + (e.name == "exec" || e.name == "tools" ? e.run : e.name))
        }
        return 0
    }

    static func list() -> Int32 {
        do {
            let reg = try Registry.loadAll()
            if json {
                emit(["ok": true, "path": reg.url.path, "groups": reg.groups, "commands": reg.commands.map(describe),
                      "files": reg.files.map { ["name": $0.name, "path": $0.path, "mode": $0.mode] },
                      "tools": reg.tools.map { describe($0, nil) }])
                return 0
            }
            print("✓ \(count(reg.commands.count, "command")) · \(count(reg.groups.count, "group")) · \(reg.url.path)")
            for group in reg.groups {
                print("  \(group)")
                for c in reg.commands where c.group == group {
                    let kind = c.gate ? "gate" : (!c.secretNames.isEmpty ? "key" : (c.interactive ? "tty" : (c.params.isEmpty ? "" : "{\(c.params.count)}")))
                    print("    " + c.name.padding(toLength: 24, withPad: " ", startingAt: 0) + c.desc + (kind.isEmpty ? "" : "  · \(kind)") + (c.origin == .team ? "  · team" : ""))
                }
            }
            if let p = reg.team?.problem { fail(p.what, fix: p.fix) }
            if !reg.tools.isEmpty { print("  \(count(reg.tools.count, "tool")): " + reg.tools.map(\.name).joined(separator: ", ") + " · great-gui tools") }
            if !reg.files.isEmpty { print("  \(count(reg.files.count, "file")) in the Keychain: " + reg.files.map(\.name).joined(separator: ", ") + " · great-gui file") }
            return 0
        } catch let e as RegistryError {
            fail(e.what, fix: e.fix)
            return 1
        } catch {
            fail("\(error)")
            return 1
        }
    }

    static func check() -> Int32 {
        do {
            let reg = try Registry.loadAll()
            // The team's file is checked with the person's own: a bad one costs no commands, but it is said.
            if let p = reg.team?.problem { fail(p.what, fix: p.fix); return 1 }
            if json {
                emit(["ok": true, "path": reg.url.path, "commands": reg.commands.count, "groups": reg.groups.count, "files": reg.files.count,
                      "team_commands": reg.teamCommands.count, "tools": reg.tools.count])
                return 0
            }
            print("✓ \(reg.url.lastPathComponent) · \(count(reg.commands.count, "command")) · \(count(reg.groups.count, "group"))"
                + (reg.files.isEmpty ? "" : " · \(count(reg.files.count, "file"))") + (reg.tools.isEmpty ? "" : " · \(count(reg.tools.count, "tool"))"))
            return 0
        } catch let e as RegistryError {
            fail(e.what, fix: e.fix)
            return 1
        } catch {
            fail("\(error)")
            return 1
        }
    }

    /// Runs one command in this terminal, plain or interactive, with its secrets, and records it in the history.
    /// A gated command is refused: Touch ID belongs to the window. Under launchd (GREAT_GUI_SCHEDULED=1) the
    /// output is the command's log, framed by a header and a footer, and a failure posts a notification.
    static func run(_ args: [String]) -> Int32 {
        guard let name = args.first else { fail("run needs a name", fix: "great-gui run NAME [-P key=value]…"); return 2 }
        var params: [String: String] = [:]
        var i = 1
        while i < args.count {
            if args[i] == "-P" || args[i] == "--param", i + 1 < args.count, let eq = args[i + 1].firstIndex(of: "=") {
                params[String(args[i + 1][..<eq])] = String(args[i + 1][args[i + 1].index(after: eq)...])
                i += 2
            } else {
                fail("unknown argument \(args[i])", fix: "great-gui run NAME [-P key=value]…")
                return 2
            }
        }
        do {
            let reg = try Registry.loadAll()
            guard let c = reg.command(named: name) else { fail("no command named \(name)", fix: "great-gui list"); return 2 }
            let r = try reg.resolve(c, params: params)
            if r.gate { fail("\(name) is gated: run it from the window, where Touch ID is", fix: "or set gate = false"); return 2 }
            if r.interactive, capture != nil { fail("\(name) needs a terminal, so its output cannot be captured", fix: "run it without --capture") ; return 2 }
            var env = ProcessInfo.processInfo.environment
            let redact: [String]
            do {
                let built = try RunEnvironment.build(r, secrets: SecretStore())
                env.merge(built.env) { _, new in new }
                redact = built.redact
            } catch let e as RunEnvironment.Refusal {
                fail(e.what, fix: e.fix)
                return 2
            }
            if !r.interactive { env.merge(["NO_COLOR": "1", "CLICOLOR": "0"]) { _, new in new } }
            let scheduled = ProcessInfo.processInfo.environment["GREAT_GUI_SCHEDULED"] == "1"
            let out = FileHandle.standardOutput
            if scheduled {
                scheduler().trimLog(for: c.name)
                out.write(Data((Scheduler.header(name: c.name) + "\n").utf8))
            }
            let started = Date()
            // A program that needs the terminal keeps it; anything else has its secrets masked, in a log too.
            let code = try runMasked(shellArguments: [r.interactive ? "-lic" : "-lc", r.run], cwd: r.cwd, environment: env,
                                     redact: r.interactive ? [] : redact)
            let seconds = (Date().timeIntervalSince(started) * 10).rounded() / 10
            HistoryStore().append(HistoryEntry(name: c.name, run: r.run, cwd: r.cwd, mode: scheduled ? "sched" : "cli", code: code, seconds: seconds, startedAt: started))
            if json { emit(["ok": code == 0, "name": c.name, "code": Int(code), "seconds": seconds, "run": r.run, "secrets": r.secretNames, "origin": c.origin.rawValue].merging(capture?.fields ?? [:]) { a, _ in a }) }
            if scheduled {
                out.write(Data((Scheduler.footer(code: code, seconds: seconds) + "\n").utf8))
                if code != 0 { Notifier.post(title: "\(c.name) failed", body: "exit \(code) on its scheduled run · the log is in the window") }
            }
            return code
        } catch let e as RegistryError {
            fail(e.what, fix: e.fix)
            return 2
        } catch {
            fail("\(error)")
            return 2
        }
    }

    static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    static func fail(_ what: String, fix: String = "") {
        if json {
            emit(fix.isEmpty ? ["ok": false, "error": what] : ["ok": false, "error": what, "fix": fix])
            return
        }
        FileHandle.standardError.write(Data(("✗ \(what)\n" + (fix.isEmpty ? "" : "  \(fix)\n")).utf8))
    }
}
