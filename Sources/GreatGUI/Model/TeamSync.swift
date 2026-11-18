import Foundation
import Registry

/// The team's repository on this Mac: cloned once from an address the person gives, then fast-forwarded by
/// the daily look. Nothing is ever pushed, and the folder is read-only as far as the app goes. The address is
/// kept nowhere but the clone's own remote, so any git host works: GitHub at home, the company's at work.
/// What arrives is text: commands, `[[file]]` pointers and agent skills. Never a secret's value.
enum TeamSync {
    struct Status: Equatable {
        var directory: URL
        /// The folder is there.
        var joined: Bool
        /// It is a git clone, so it can follow a remote. A plain folder is used as it is.
        var repository: Bool
        var remote: String?
        var head: String?
        /// When the remote was last asked, from the clone's own record of it.
        var syncedAt: Date?
    }

    /// What a sync brought, by name.
    struct Change: Equatable {
        var added: [String] = []
        var changed: [String] = []
        var removed: [String] = []
        var skills: [String] = []
        /// Tools the team now lists that it did not before. They are listed, not installed.
        var tools: [String] = []
        /// For each changed command, what changed, in a line: a command people trust by name can change under it.
        var details: [String] = []
        var isEmpty: Bool { added.isEmpty && changed.isEmpty && removed.isEmpty && tools.isEmpty }

        var words: String {
            var parts: [String] = []
            if !added.isEmpty { parts.append("\(added.count) new (\(added.joined(separator: ", ")))") }
            if !changed.isEmpty { parts.append("\(changed.count) changed (\(changed.joined(separator: ", ")))") }
            if !removed.isEmpty { parts.append("\(removed.count) removed (\(removed.joined(separator: ", ")))") }
            if !tools.isEmpty { parts.append("\(tools.count) tool\(tools.count == 1 ? "" : "s") to install (\(tools.joined(separator: ", ")))") }
            return parts.isEmpty ? "nothing new" : parts.joined(separator: " · ")
        }
    }

    enum Outcome: Equatable {
        case notJoined
        case current
        case updated(Change)
        case failed(String, fix: String)
    }

    static func status(_ dir: URL) -> Status {
        let fm = FileManager.default
        var s = Status(directory: dir, joined: fm.fileExists(atPath: dir.path), repository: false)
        guard s.joined, fm.fileExists(atPath: dir.appendingPathComponent(".git").path) else { return s }
        s.repository = true
        let remote = UpdateCheck.git(["remote", "get-url", "origin"], in: dir, timeout: 10)
        if remote.status == 0 { s.remote = remote.output.trimmingCharacters(in: .whitespacesAndNewlines) }
        let head = UpdateCheck.git(["rev-parse", "--short", "HEAD"], in: dir, timeout: 10)
        if head.status == 0 { s.head = head.output.trimmingCharacters(in: .whitespacesAndNewlines) }
        for name in ["FETCH_HEAD", "HEAD"] {
            let attrs = try? fm.attributesOfItem(atPath: dir.appendingPathComponent(".git/\(name)").path)
            if let d = attrs?[.modificationDate] as? Date { s.syncedAt = d; break }
        }
        return s
    }

    /// Clones the team's repository into `dir`. Blocking: call it off the main thread.
    static func join(_ address: String, into dir: URL) -> Outcome {
        let remote = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remote.isEmpty, !remote.hasPrefix("-") else {
            return .failed("join needs the team repository's address", fix: "as git clones it: https://host/team/tooling.git, or git@host:team/tooling.git")
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.path) {
            return .failed("this Mac already has a team registry at \(dir.path)", fix: "great-gui team shows it; great-gui team leave removes it first")
        }
        let parent = dir.deletingLastPathComponent()
        try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let clone = UpdateCheck.git(["clone", "--quiet", "--", remote, dir.path], in: parent, timeout: 120)
        guard clone.status == 0 else {
            try? fm.removeItem(at: dir)   // only ever what a failed clone left behind: the folder did not exist before
            return .failed("could not clone \(remote)", fix: "check the address and that this Mac can reach it without a password prompt: git ls-remote \(remote)")
        }
        let file = dir.appendingPathComponent("commands.toml")
        var change = Change()
        if fm.fileExists(atPath: file.path) {
            do {
                let theirs = try Registry.load(from: file)
                change.added = theirs.commands.map(\.name)
                change.tools = theirs.tools.map(\.name)
            } catch let e as RegistryError {
                return .failed("joined, but the team's commands.toml is not valid: \(e.what)", fix: e.fix)
            } catch {
                return .failed("joined, but the team's commands.toml could not be read", fix: "\(error)")
            }
        }
        change.skills = linkSkills(dir)
        return .updated(change)
    }

    /// Asks the remote, checks what it has before taking it, and fast-forwards. A file that would not load is
    /// left on the remote and the last good one stays. Blocking: call it off the main thread.
    static func sync(_ dir: URL) -> Outcome {
        let s = status(dir)
        guard s.joined else { return .notJoined }
        guard s.repository else { _ = linkSkills(dir); return .current }
        guard UpdateCheck.git(["fetch", "--quiet"], in: dir, timeout: 45).status == 0 else {
            return .failed("could not reach the team repository (offline, or no access)", fix: "git -C \(dir.path) fetch shows the reason")
        }
        let behind = UpdateCheck.git(["rev-list", "--count", "HEAD..@{u}"], in: dir, timeout: 15)
        guard behind.status == 0, let count = Int(behind.output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .failed("the team folder's branch does not track a remote branch", fix: "git -C \(dir.path) status")
        }
        guard count > 0 else { _ = linkSkills(dir); return .current }
        let file = dir.appendingPathComponent("commands.toml")
        let incoming = UpdateCheck.git(["show", "@{u}:commands.toml"], in: dir, timeout: 15)
        var next = Registry(url: file, commands: [])
        if incoming.status == 0 {
            do {
                next = try Registry.parse(incoming.output, url: file)
            } catch let e as RegistryError {
                return .failed("the team pushed a commands.toml that is not valid, so the last good one stays: \(e.what)", fix: "tell whoever pushed it: \(e.fix)")
            } catch {
                return .failed("the team's new commands.toml could not be read", fix: "\(error)")
            }
        }
        let was = try? Registry.load(from: file)
        let before = was?.commands ?? []
        let toolsBefore = Set(was?.tools.map(\.name) ?? [])
        guard UpdateCheck.git(["merge", "--ff-only", "--quiet", "@{u}"], in: dir, timeout: 30).status == 0 else {
            return .failed("the team folder has changes of its own and cannot follow the remote", fix: "it is read-only here: git -C \(dir.path) status shows what changed")
        }
        var change = diff(before, next.commands)
        change.tools = next.tools.map(\.name).filter { !toolsBefore.contains($0) }
        change.skills = linkSkills(dir)
        return .updated(change)
    }

    static func diff(_ before: [Command], _ after: [Command]) -> Change {
        let old = Dictionary(before.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let new = Dictionary(after.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        var change = Change(added: after.map(\.name).filter { old[$0] == nil },
                            changed: after.map(\.name).filter { old[$0] != nil && old[$0] != new[$0] },
                            removed: before.map(\.name).filter { new[$0] == nil })
        for name in change.changed {
            guard let was = old[name], let now = new[name] else { continue }
            change.details.append(name + ": " + what(was, now).joined(separator: " · "))
        }
        return change
    }

    /// What differs between two versions of a command. The run line is shown both ways; a secret is named.
    static func what(_ was: Command, _ now: Command) -> [String] {
        var out: [String] = []
        if was.run != now.run { out.append("runs  \(now.run)  (was  \(was.run))") }
        if was.cwd != now.cwd { out.append("in \(now.cwd ?? "no folder") (was \(was.cwd ?? "no folder"))") }
        let gained = now.secretNames.filter { !was.secretNames.contains($0) }, lost = was.secretNames.filter { !now.secretNames.contains($0) }
        if !gained.isEmpty { out.append("now uses the secret\(gained.count == 1 ? "" : "s") " + gained.joined(separator: ", ")) }
        if !lost.isEmpty { out.append("no longer uses " + lost.joined(separator: ", ")) }
        if was.env != now.env, gained.isEmpty, lost.isEmpty { out.append("environment changed") }
        if was.schedule != now.schedule { out.append("suggested schedule: " + (now.schedule?.text ?? "none")) }
        if was.params != now.params { out.append("parameters changed") }
        if was.gate != now.gate { out.append(now.gate ? "now asks for Touch ID" : "no longer asks for Touch ID") }
        if was.interactive != now.interactive { out.append(now.interactive ? "now needs a terminal" : "no longer needs a terminal") }
        if was.desc != now.desc || was.group != now.group || was.tags != now.tags, out.isEmpty { out.append("description or group") }
        return out.isEmpty ? ["changed"] : out
    }

    /// Takes the team registry off this Mac: its skill links are removed and the folder goes to the Trash.
    /// The person's own registry and every stored secret stay as they are.
    static func leave(_ dir: URL) -> Outcome {
        guard FileManager.default.fileExists(atPath: dir.path) else { return .notJoined }
        unlinkSkills(dir)
        do {
            try FileManager.default.trashItem(at: dir, resultingItemURL: nil)
            return .current
        } catch {
            return .failed("could not move \(dir.path) to the Trash", fix: error.localizedDescription)
        }
    }

    // MARK: starting a team repository

    static let exampleRegistry = """
    # The team's commands.toml: the same format as each person's own (the-great-gui's README has it).
    # Everyone who joins this repository gets these commands, read-only, about once a day.
    #
    # - A person's own command with the same name wins over one here.
    # - A schedule here is a suggestion: it is not armed on anyone's Mac until they copy the command.
    # - Never a secret's value. Name the secret (keychain:NAME) and each person stores their own.
    # - Paths start with ~ so they carry nobody's home folder.
    # - A [[tool]] here is a listing: it shows as missing until the person, or their agent, installs it.

    [[command]]
    name = "team-hello"
    group = "team"
    desc = "proves the team registry reached this Mac"
    run = "echo hello from the team registry"

    # A command that needs a secret: each person adds team-example-token in their own window (⌘K).
    # [[command]]
    # name = "team-api-check"
    # group = "team"
    # desc = "call the API with your own token"
    # run = "curl -sS -H \"Authorization: Bearer $TOKEN\" https://example.com/health"
    # env = { TOKEN = "keychain:team-example-token" }

    # A credential file the team's commands expect: a pointer only. Each person stores their own copy.
    # [[file]]
    # name = "snowflake-connections"
    # path = "~/.snowflake/connections.toml"

    # A program everyone should have. method is brew, cask, uv or script; script carries its own install line.
    # [[tool]]
    # name = "ripgrep"
    # desc = "fast search"
    # method = "brew"
    # bin = "rg"

    """

    static let exampleReadme = """
    # Team tooling

    The shared registry for the-great-gui. Each Mac joins once:

        great-gui team join ADDRESS-OF-THIS-REPOSITORY

    or Settings › Team in the window. After that the app follows this repository about once a day.

    - `commands.toml`: the team's commands, and `[[file]]` pointers to the credential files they expect.
    - `skills/NAME/SKILL.md`: agent skills, linked into Claude Code, Codex, Hermes and Cortex Code.

    Rules: never commit a secret's value; write paths with `~`; check a change with
    `GREAT_GUI_REGISTRY=commands.toml great-gui check` before pushing. A file that does not load is not
    taken by anyone's Mac: they keep the last good one.

    """

    /// Writes the starting files of a team repository into `dir`, never over one that is there, and makes
    /// it a git repository. Returns what it wrote. Publishing it is the person's step.
    static func scaffold(_ dir: URL) throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("skills"), withIntermediateDirectories: true)
        var made: [String] = []
        for (name, text) in [("commands.toml", exampleRegistry), ("README.md", exampleReadme), ("skills/.gitkeep", "")] {
            let url = dir.appendingPathComponent(name)
            guard !fm.fileExists(atPath: url.path) else { continue }
            try text.write(to: url, atomically: true, encoding: .utf8)
            made.append(name)
        }
        if !fm.fileExists(atPath: dir.appendingPathComponent(".git").path), UpdateCheck.git(["init", "--quiet"], in: dir, timeout: 15).status == 0 {
            made.append(".git")
        }
        return made
    }

    // MARK: skills

    /// The agents' skill folders on this Mac. `GREAT_GUI_SKILL_DIRS` (colon-separated) points a test elsewhere.
    static var skillDirectories: [URL] {
        if let p = ProcessInfo.processInfo.environment["GREAT_GUI_SKILL_DIRS"] {
            return p.split(separator: ":").map { URL(fileURLWithPath: NSString(string: String($0)).expandingTildeInPath) }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [".claude/skills", ".codex/skills", ".hermes/skills", ".snowflake/cortex/skills"].map(home.appendingPathComponent)
    }

    /// Where a symbolic link points, when it points into this team folder's skills.
    private static func teamTarget(of link: URL, in dir: URL) -> String? {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return nil }
        return target.hasPrefix(dir.appendingPathComponent("skills").path + "/") ? target : nil
    }

    /// Links each `skills/NAME/` of the team folder into the agents that are here, beside the app's own.
    /// A skill the person or the app already has under that name is left alone: theirs wins, as with commands.
    /// Links to team skills that are gone are removed. Returns the names linked.
    @discardableResult
    static func linkSkills(_ dir: URL, into agents: [URL] = skillDirectories) -> [String] {
        let fm = FileManager.default
        let root = dir.appendingPathComponent("skills")
        let names = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).sorted().filter {
            fm.fileExists(atPath: root.appendingPathComponent($0).appendingPathComponent("SKILL.md").path)
        }
        var linked: Set<String> = []
        for agent in agents where fm.fileExists(atPath: agent.path) {
            for entry in (try? fm.contentsOfDirectory(atPath: agent.path)) ?? [] {
                let link = agent.appendingPathComponent(entry)
                if let target = teamTarget(of: link, in: dir), !fm.fileExists(atPath: target) { try? fm.removeItem(at: link) }
            }
            for name in names {
                let link = agent.appendingPathComponent(name)
                let target = root.appendingPathComponent(name).path
                if teamTarget(of: link, in: dir) == target { linked.insert(name); continue }
                // Anything else under that name is not ours to replace. attributesOfItem does not follow a link.
                guard (try? fm.attributesOfItem(atPath: link.path)) == nil else { continue }
                if (try? fm.createSymbolicLink(atPath: link.path, withDestinationPath: target)) != nil { linked.insert(name) }
            }
        }
        return linked.sorted()
    }

    static func unlinkSkills(_ dir: URL, from agents: [URL] = skillDirectories) {
        let fm = FileManager.default
        for agent in agents {
            for entry in (try? fm.contentsOfDirectory(atPath: agent.path)) ?? [] {
                let link = agent.appendingPathComponent(entry)
                if teamTarget(of: link, in: dir) != nil { try? fm.removeItem(at: link) }
            }
        }
    }
}
