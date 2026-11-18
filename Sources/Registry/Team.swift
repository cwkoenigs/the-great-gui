import Foundation

/// Whose a command is.
public enum Origin: String, Sendable {
    case personal, team
}

/// The team's registry, as the last load found it.
public struct TeamState: Equatable, Sendable {
    /// The team's commands.toml.
    public var url: URL
    /// How many commands it holds, shadowed ones included.
    public var commands: Int
    /// The team commands a personal command of the same name hides.
    public var overridden: [String]
    /// Why the team's file could not be used. The person's own commands load regardless.
    public var problem: RegistryError?
    /// How many tools it lists, shadowed ones included.
    public var tools = 0

    public init(url: URL, commands: Int = 0, overridden: [String] = [], problem: RegistryError? = nil, tools: Int = 0) {
        self.url = url; self.commands = commands; self.overridden = overridden; self.problem = problem; self.tools = tools
    }
}

/// The team's registry: a second commands.toml, in a folder beside the person's own, that the team maintains
/// and every install receives (docs/team-tooling.md). It is the same format and is never written here. A
/// personal command wins a clash of names. A team schedule is held back, so nothing the team sends runs by
/// itself. A team `[[file]]` and the secrets its commands name are a checklist: names only, never a value.
extension Registry {
    /// The folder the team's repository is cloned into: `GREAT_GUI_TEAM`, else the registry's folder with
    /// `-team` added (`~/.great-gui` gives `~/.great-gui-team`), so a test instance has its own.
    public static func teamDirectory(for registry: URL = defaultURL()) -> URL {
        if let p = ProcessInfo.processInfo.environment["GREAT_GUI_TEAM"], !p.isEmpty {
            return URL(fileURLWithPath: NSString(string: p).expandingTildeInPath)
        }
        let folder = registry.deletingLastPathComponent()
        return folder.deletingLastPathComponent().appendingPathComponent(folder.lastPathComponent + "-team")
    }

    public static func teamURL(for registry: URL = defaultURL()) -> URL {
        teamDirectory(for: registry).appendingPathComponent("commands.toml")
    }

    /// The person's commands, the ones this Mac may edit, in file order.
    public var personal: [Command] { commands.filter { $0.origin == .personal } }
    public var teamCommands: [Command] { commands.filter { $0.origin == .team } }

    /// This registry with the team's behind it: the person's commands first, then the team's that no
    /// personal command shadows, marked and with their schedules held back.
    public func merging(team: Registry) -> Registry {
        let mine = Set(commands.map(\.name))
        let theirs = Set(team.commands.map(\.name))
        var all = commands.map { c -> Command in
            var c = c
            c.overridesTeam = theirs.contains(c.name)
            return c
        }
        for var c in team.commands where !mine.contains(c.name) {
            c.origin = .team
            c.teamSchedule = c.schedule
            c.schedule = nil
            all.append(c)
        }
        let myFiles = Set(files.map(\.name))
        let pointers = team.files.filter { !myFiles.contains($0.name) }.map { f -> SecretFile in
            var f = f
            f.team = true
            return f
        }
        // Tools follow the same rule as commands: the person's own entry wins, and the team's is marked.
        let myTools = Set(tools.map(\.name))
        let theirTools = Set(team.tools.map(\.name))
        var allTools = tools.map { t -> Tool in
            var t = t
            t.overridesTeam = theirTools.contains(t.name)
            return t
        }
        for var t in team.tools where !myTools.contains(t.name) {
            t.origin = .team
            allTools.append(t)
        }
        var out = Registry(url: url, commands: all, files: files + pointers, tools: allTools)
        out.team = TeamState(url: team.url, commands: team.commands.count, overridden: team.commands.map(\.name).filter(mine.contains),
                             tools: team.tools.count)
        return out
    }

    /// The person's registry with the team's merged in when this Mac has one. A team file that cannot be
    /// read never costs the person their own commands: it is reported in `team.problem`.
    public static func loadAll(from url: URL = defaultURL(), team: URL? = nil) throws -> Registry {
        var mine = try load(from: url)
        let teamURL = team ?? self.teamURL(for: url)
        guard FileManager.default.fileExists(atPath: teamURL.path) else { return mine }
        do {
            return mine.merging(team: try load(from: teamURL))
        } catch let e as RegistryError {
            mine.team = TeamState(url: teamURL, problem: RegistryError("the team's registry: " + e.what, fix: e.fix))
            return mine
        }
    }
}
